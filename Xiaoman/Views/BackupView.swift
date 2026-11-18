import SwiftUI
import UniformTypeIdentifiers

/// 备份与恢复：整份账本导出成一个 JSON，换机、重签之前先存一份
struct BackupView: View {

    @EnvironmentObject private var store: LedgerStore

    @State private var sharePayload: SharePayload?
    @State private var showingImporter = false
    @State private var showingRestoreConfirm = false
    @State private var pendingData: Data?
    @State private var message: String?

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(spacing: 16) {
                    exportCard
                    restoreCard
                    noteCard
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("备份与恢复")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(item: $sharePayload) { payload in
            ActivityView(items: [payload.url])
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert("用备份覆盖当前账本？", isPresented: $showingRestoreConfirm) {
            Button("取消", role: .cancel) { pendingData = nil }
            Button("覆盖恢复", role: .destructive) { performRestore() }
        } message: {
            Text("现在的账目、资产、预算和自定义分类都会被备份文件里的内容替换。")
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

    private var exportCard: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("导出备份")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("把 \(store.transactions.count) 笔账、\(store.assets.count) 个资产、预算和分类打包成一个 JSON。续签或换手机前导一份，换回来时直接恢复。")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)

                Button {
                    exportBackup()
                } label: {
                    Label("导出到「文件」", systemImage: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.glassProminent)
            }
        }
    }

    private var restoreCard: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("从备份恢复")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("选一个之前导出的 xiaoman-backup-*.json，会覆盖当前数据。")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)

                Button {
                    showingImporter = true
                } label: {
                    Label("选择备份文件", systemImage: "folder")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.glass)
            }
        }
    }

    private var noteCard: some View {
        Text("提示：免费证书 7 天过期，续签时用同一个 Bundle ID 覆盖安装不会丢数据；只有卸载重装才会清空，所以「删 App 之前先备份」是最省心的习惯。")
            .font(.system(size: 12, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }

    // MARK: - 动作

    private func exportBackup() {
        guard let url = store.makeBackupFile() else {
            message = "导出失败：写临时文件出错。"
            return
        }
        sharePayload = SharePayload(url: url)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            message = "读取失败：\(error.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                message = "读不到这个文件，换个位置再试一次。"
                return
            }
            pendingData = data
            showingRestoreConfirm = true
        }
    }

    private func performRestore() {
        guard let data = pendingData else { return }
        pendingData = nil
        if let count = store.restoreBackup(from: data) {
            message = "恢复完成，共 \(count) 笔账。"
        } else {
            message = "这个文件不是小满的备份，或者已经损坏。"
        }
    }
}
