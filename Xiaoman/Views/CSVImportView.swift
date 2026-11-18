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
            allowedContentTypes: [.commaSeparatedText, .plainText, .text],
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
                Text("从微信 / 支付宝导出的 CSV")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("把以前记的账一次补齐。微信：「我 → 服务 → 钱包 → 账单 → 常见问题 → 下载账单」；支付宝：「我的 → 账单 → 右上角 → 开具交易流水」。导出后选那个 CSV 文件。")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)

                Button {
                    showingImporter = true
                } label: {
                    Label(busy ? "正在读取…" : "选择 CSV 文件", systemImage: "doc.badge.plus")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.glassProminent)
                .disabled(busy)

                if !fileName.isEmpty {
                    Text("已读取：\(fileName)")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
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
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
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
        Text("导入会按「来源 + 金额 + 商户 + 分钟」判重，重复的会自动跳过；已经手动记过的账单不会被覆盖。")
            .font(.system(size: 12, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }

    // MARK: - 动作

    private func handle(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            message = "读取失败：\(error.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else { return }
            busy = true
            defer { busy = false }

            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }

            guard let data = try? Data(contentsOf: url) else {
                message = "读不到这个文件，换个位置再试。"
                return
            }
            guard let text = CSVImporter.decode(data) else {
                message = CSVImporter.CSVError.unsupportedEncoding.errorDescription
                return
            }

            do {
                rows = try CSVImporter.parse(text)
                fileName = url.lastPathComponent
            } catch {
                rows = []
                message = error.localizedDescription
            }
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
