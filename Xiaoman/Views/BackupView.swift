import SwiftUI
import Foundation
import UniformTypeIdentifiers

/// 备份与恢复：整份账本导出成一个 JSON，换机、重签之前先存一份
struct BackupView: View {

    @EnvironmentObject private var store: LedgerStore

    @State private var sharePayload: SharePayload?
    @State private var showingImporter = false
    @State private var showingRestoreConfirm = false
    @State private var pendingData: Data?
    @State private var pendingSummary = ""
    @State private var message: String?
    @State private var status: String?

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
        .sheet(isPresented: $showingImporter) {
            DocumentPicker(contentTypes: [.item]) { urls in
                showingImporter = false
                handleImport(urls)
            }
            .ignoresSafeArea()
        }
        .alert("用备份覆盖当前账本？", isPresented: $showingRestoreConfirm) {
            Button("取消", role: .cancel) { pendingData = nil }
            Button("覆盖恢复", role: .destructive) { performRestore() }
        } message: {
            Text(pendingSummary.isEmpty
                 ? "现在的账目、资产、预算和自定义分类都会被备份文件里的内容替换。"
                 : pendingSummary)
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
                Text("将 \(store.transactions.count) 笔账目、\(store.assets.count) 个资产、预算与分类导出为一个 JSON 文件；续签或更换设备前导出，恢复时直接导入。")
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
                Text("选择此前导出的 xiaoman-backup-*.json，将覆盖当前数据。")
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

                if let status {
                    Text(status)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var noteCard: some View {
        Text("提示：免费证书 7 天过期。续签时使用同一 Bundle ID 覆盖安装不会丢失数据；仅卸载重装会清空数据，建议在卸载前先导出备份。")
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

    private func handleImport(_ urls: [URL]) {
        guard let url = urls.first else {
            status = nil
            return
        }

        status = "已选择：\(url.lastPathComponent)，正在读取…"
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard !data.isEmpty else {
                status = "备份文件为空（0 字节）。"
                message = "备份文件为空（0 字节），可能尚未从 iCloud 下载完成。"
                return
            }
            pendingData = data
            pendingSummary = "即将用「\(url.lastPathComponent)」（\(byteText(data.count))）覆盖当前账本，里面的账目、资产、预算和自定义分类都会被替换。"
            status = "已读取：\(url.lastPathComponent)（\(byteText(data.count))）"
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(320))
                showingRestoreConfirm = true
            }
        } catch {
            status = "读取失败：\(error.localizedDescription)"
            message = "读不到这个文件：\(error.localizedDescription)"
        }
    }

    private func performRestore() {
        guard let data = pendingData else { return }
        pendingData = nil
        pendingSummary = ""
        do {
            let count = try store.restoreBackup(from: data)
            message = "恢复完成，共 \(count) 笔账。"
        } catch {
            message = error.localizedDescription
        }
    }

    private func byteText(_ count: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(count))
    }
}
