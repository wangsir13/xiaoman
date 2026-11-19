import AppIntents
import UIKit
import UniformTypeIdentifiers

/// 快捷指令 / Siri 直接调用：把截图（或任何图片）交给 App，App 内部用 Vision 识别后落库。
/// 整个过程不需要把图片存成文件，也不需要用户先打开 App。
struct RecordFromScreenshotIntent: AppIntent {

    static var title: LocalizedStringResource = "小满记账"
    static var description: IntentDescription? = IntentDescription(
        "识别截图里的金额、商户和时间，自动记进账本。"
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "截图")
    var screenshot: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("识别 \(\.$screenshot) 并记账")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let loaded = await loadImage(from: screenshot)
        guard let image = loaded.image else {
            // 读不出来时把线索写进弹窗，方便定位是「没给文件」还是「给的是解不开的格式」
            return .result(dialog: IntentDialog(stringLiteral: "读不到截图：\(loaded.diagnostic)"))
        }

        let outcome = await recordImage(image)
        let message: String
        if !outcome.valid && !outcome.pending {
            message = "未能从截图中识别到金额，请在应用内手动记录。"
        } else if outcome.pending {
            if outcome.valid {
                message = "已识别 \(outcome.summary)，等待确认（置信度：\(outcome.confidence)）。"
            } else {
                message = "未能确认金额，已加入待确认列表，请在应用内补充。"
            }
        } else {
            let asset = outcome.assetName.isEmpty ? "未绑定资产" : "记在「\(outcome.assetName)」"
            message = "已记账 \(outcome.summary)，\(asset)。"
        }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }

    /// 读图失败的线索，直接给用户看，省得来回猜。
    struct LoadedImage {
        var image: UIImage?
        var diagnostic: String
    }

    /// 从「截屏」拿到的文件里取出图片。快捷指令给的可能是内存字节、临时文件、HEIC，
    /// 也可能是需要转换的「图像对象」，所以一路兜底。
    private func loadImage(from file: IntentFile) async -> LoadedImage {
        if let image = UIImage(data: file.data) {
            return LoadedImage(image: image, diagnostic: "")
        }

        if let url = file.fileURL {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            if let image = UIImage(contentsOfFile: url.path) {
                return LoadedImage(image: image, diagnostic: "")
            }
            if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                return LoadedImage(image: image, diagnostic: "")
            }
        }

        for type in [UTType.image, UTType.png, UTType.jpeg, UTType.heic] {
            if let data = try? await file.data(contentType: type),
               let image = UIImage(data: data) {
                return LoadedImage(image: image, diagnostic: "")
            }
        }

        if let result = try? await file.file(
            contentType: .png,
            destinationDirectory: FileManager.default.temporaryDirectory
        ), let image = UIImage(contentsOfFile: result.fileURL.path) {
            return LoadedImage(image: image, diagnostic: "")
        }

        let bytes = file.data.count
        let kind = file.type?.identifier ?? "未知"
        let where_ = file.fileURL == nil ? "没有文件地址" : "有文件地址但读不出图"
        let hint = bytes == 0
            ? "拿到的是空文件（\(kind)，0 字节，\(where_)）"
            : "拿到 \(bytes) 字节 \(kind)，\(where_)"
        return LoadedImage(image: nil, diagnostic: hint)
    }
}

/// 纯文字入账（从剪贴板 / 其他 App 传来的文本）
struct RecordFromTextIntent: AppIntent {

    static var title: LocalizedStringResource = "文本记账"
    static var description: IntentDescription? = IntentDescription("把一段账单文字解析成一条账目。")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "账单文字")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("解析 \(\.$text)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await record(text)
        let message: String
        if outcome.pending {
            message = "已识别 \(outcome.summary)，等待在应用内确认。"
        } else {
            message = "已记账 \(outcome.summary)。"
        }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

/// Intents 的结果摘要，跨 actor 传出去只带这几个值。
struct RecordOutcome: Sendable {
    var summary: String
    var valid: Bool
    var pending: Bool
    var assetName: String
    var confidence: String
}

/// LedgerStore 是 @MainActor，这里统一在主线程序列化地写一次。
@MainActor
private func record(_ text: String) async -> RecordOutcome {
    let store = LedgerStore()
    let draft = await store.enqueueSmart(text: text)
    return RecordOutcome(
        summary: draft.summaryLine,
        valid: draft.isValid,
        pending: store.pendingDrafts.contains { $0.id == draft.id },
        assetName: draft.assetName,
        confidence: draft.confidenceText
    )
}

/// 截图这条路：优先让多模态模型直接看图，不行再走 OCR。
@MainActor
private func recordImage(_ image: UIImage) async -> RecordOutcome {
    let store = LedgerStore()
    let draft = await store.enqueueVision(image)
    return RecordOutcome(
        summary: draft.summaryLine,
        valid: draft.isValid,
        pending: store.pendingDrafts.contains { $0.id == draft.id },
        assetName: draft.assetName,
        confidence: draft.confidenceText
    )
}

/// 查预算：不加小组件也能在桌面/锁屏看今日额度（快捷指令里「显示结果」就行）
struct CheckBudgetIntent: AppIntent {

    static var title: LocalizedStringResource = "查今日额度"
    static var description: IntentDescription? = IntentDescription("查询今日剩余额度与本月剩余预算。")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let line = await budgetLine()
        return .result(dialog: IntentDialog(stringLiteral: line))
    }
}

@MainActor
private func budgetLine() -> String {
    let store = LedgerStore()
    guard let today = store.todayBudget else {
        return "尚未设置月度预算，请在「预算」页配置。"
    }
    let left = today.remainingCents
    let monthLeft = store.monthRemainingCents
    if left < 0 {
        return "今天超支 \(Money.plain(-left))，本月还剩 \(Money.plain(abs(monthLeft)))。"
    }
    return "今天还能花 \(Money.plain(left))，本月还剩 \(Money.plain(abs(monthLeft)))。"
}

/// 让这几个动作出现在快捷指令 App 和建议里
struct XiaomanShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordFromScreenshotIntent(),
            phrases: [
                "用\(.applicationName)记一笔",
                "记账到\(.applicationName)",
                "让\(.applicationName)识别这张截图"
            ],
            shortTitle: "小满记账",
            systemImageName: "camera.viewfinder"
        )
        AppShortcut(
            intent: RecordFromTextIntent(),
            phrases: [
                "把这段账单记进\(.applicationName)"
            ],
            shortTitle: "文本记账",
            systemImageName: "text.viewfinder"
        )
        AppShortcut(
            intent: CheckBudgetIntent(),
            phrases: [
                "\(.applicationName)今天还能花多少"
            ],
            shortTitle: "查今日额度",
            systemImageName: "chart.pie.fill"
        )
    }
}
