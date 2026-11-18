import Foundation

/// 处理 xiaoman:// 深链接。
///
/// 约定：
///   xiaoman://record?text=<经过 URL 编码的 OCR 全文>&src=wechat&ts=1700000000
///   xiaoman://record?amount=12.34&merchant=星巴克&src=alipay&ts=1700000000
///
/// text 是主通道；amount / merchant / ts 是可选的显式覆盖值。
enum DeepLink {

    static let scheme = "xiaoman"

    /// 由 SwiftUI 在主线程调用，内部会直接改 store，所以标 @MainActor
    @MainActor
    static func handle(_ url: URL, store: LedgerStore) {
        guard url.scheme?.lowercased() == scheme else { return }

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        func value(_ names: [String]) -> String? {
            for name in names {
                if let item = items.first(where: { $0.name.lowercased() == name.lowercased() }),
                   let raw = item.value,
                   !raw.isEmpty {
                    return raw
                }
            }
            return nil
        }

        var text = value(["text", "t", "content", "ocr"]) ?? ""
        // 少数工具会把百分号编码原样塞进来，这里兜底解一次
        if text.contains("%"), let decoded = text.removingPercentEncoding, decoded != text {
            text = decoded
        }

        let sourceHint = BillSource.named(value(["src", "source"]))
        var draft: ImportDraft
        if text.isEmpty {
            draft = ImportDraft()
            draft.confidence = 0.4
        } else {
            draft = BillParser.parse(text: text, sourceHint: sourceHint)
        }

        if let amountText = value(["amount", "amt", "a"]) {
            draft.amountText = amountText
            draft.confidence = max(draft.confidence, 0.75)
        }
        if let merchant = value(["merchant", "m", "shop", "payee"]) {
            draft.merchant = merchant
            draft.confidence = max(draft.confidence, 0.75)
        }
        if let category = value(["cat", "category"]) {
            draft.category = category
        } else if !draft.merchant.isEmpty {
            draft.category = CategoryCatalog.suggest(merchant: draft.merchant, source: draft.source)
        }
        if let raw = value(["ts", "time"]), let date = parseTimestamp(raw) {
            draft.occurredAt = date
        }
        if let note = value(["note", "remark"]) {
            draft.note = note
        }

        store.enqueue(draft: draft)
    }

    private static func parseTimestamp(_ raw: String) -> Date? {
        if let seconds = Double(raw) {
            // 秒级时间戳；大于 1e12 视作毫秒
            let value = seconds > 1_000_000_000_000 ? seconds / 1000 : seconds
            return Date(timeIntervalSince1970: value)
        }

        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: raw) { return date }

        let formatters = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy/MM/dd HH:mm"]
        for format in formatters {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }
}
