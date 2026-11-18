import SwiftUI
import UniformTypeIdentifiers

/// 批量导入：选微信 / 支付宝导出的 CSV，预览后一次写入
struct CSVImportView: View {

    @EnvironmentObject private var store: LedgerStore

    @State private var showingImporter = false
    @State private var rows: [CSVImporter.Row] = []
    @State private var fileName = ""
    @State private var message: String?
    @State private var busy = false
    /// 行内状态：不依赖 alert，能确认「选择器回调到底有没有回来」
    @State private var status: String?

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(spacing: 16) {
                    pickCard
                    if !rows.isEmpty {
                        summaryCard
                        previewCard
                        importButton
                    }
                    noteCard
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("批量导入")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            handle(result)
        }
        .alert("提示", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private var pickCard: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("从微信 / 支付宝导出的账单")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("把以前记的账一次补齐。微信：「我 → 服务 → 钱包 → 账单 → 常见问题 → 下载账单」；支付宝：「我的 → 账单 → 右上角 → 开具交易流水」。导出后选那个 CSV / xlsx（或微信给的 zip）文件。")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)

                Button {
                    showingImporter = true
                } label: {
                    Label(busy ? "正在读取…" : "选择账单文件", systemImage: "doc.badge.plus")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.glassProminent)
                .disabled(busy)

                if let status {
                    Text(status)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var summaryCard: some View {
        GlassCard(padding: 16) {
            HStack(spacing: 16) {
                stat("\(rows.count)", "识别到")
                stat("\(rows.filter { $0.direction == .expense }.count)", "支出")
                stat("\(rows.filter { $0.direction == .income }.count)", "收入")
                Spacer(minLength: 0)
            }
        }
    }

    private func stat(_ value: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(title)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "预览", trailing: "最多显示 8 条")

            VStack(spacing: 0) {
                ForEach(Array(rows.prefix(8).enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.merchant)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .lineLimit(1)
                            Text(Fmt.day.string(from: row.date) + " " + Fmt.clock.string(from: row.date))
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 6)
                        Text((row.direction == .expense ? "-" : "+") + Money.plain(row.cents))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(row.direction == .expense ? Theme.expense : Theme.income)
                    }
                    .padding(.vertical, 8)

                    if row.merchant != rows.prefix(8).last?.merchant {
                        Divider().opacity(0.12)
                    }
                }
            }
            .padding(.horizontal, 14)
            .glassEffect(.regular, in: .rect(cornerRadius: 24, style: .continuous))
        }
    }

    private var importButton: some View {
        Button {
            importRows()
        } label: {
            Label("导入这 \(rows.count) 笔", systemImage: "tray.and.arrow.down.fill")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.glassProminent)
    }

    private var noteCard: some View {
        Text("支持 CSV、xlsx，以及微信导出的 zip。导入会按「来源 + 金额 + 商户 + 分钟」判重，重复的会自动跳过；已经手动记过的账单不会被覆盖。")
            .font(.system(size: 12, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }

    // MARK: - 动作

    private func handle(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            status = "选择器返回错误：\(error.localizedDescription)"
            message = "读取失败：\(error.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else {
                status = "选择器返回了空结果。"
                return
            }
            status = "已选择：\(url.lastPathComponent)，正在读取…"
            busy = true
            defer { busy = false }

            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }

            do {
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                guard !data.isEmpty else {
                    showLater("这个文件是空的（0 字节）。如果它在 iCloud 里，先点一下让它下载完再选。")
                    return
                }
                let parsed = try CSVImporter.parse(data: data, fileName: url.lastPathComponent)
                rows = parsed
                fileName = url.lastPathComponent
                status = "已读取：\(url.lastPathComponent)，识别到 \(parsed.count) 笔" + (parsed.isEmpty ? "（表头没认出来，换个文件试试）" : "")
            } catch {
                rows = []
                status = "读取失败：\(error.localizedDescription)"
                showLater(error.localizedDescription)
            }
        }
    }

    /// fileImporter 收起动画期间直接弹 alert 会被系统吞掉，稍等一下再弹
    private func showLater(_ text: String) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            message = text
        }
    }

    private func importRows() {
        let incoming = CSVImporter.transactions(from: rows, store: store)
        let result = store.importTransactions(incoming)
        rows = []
        fileName = ""
        message = "导入完成：新增 \(result.added) 笔，跳过重复 \(result.skipped) 笔。"
    }
}
