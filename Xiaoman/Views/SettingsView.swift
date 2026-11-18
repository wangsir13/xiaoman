import SwiftUI
import UIKit
import Photos
import PhotosUI

struct SettingsView: View {

    @EnvironmentObject private var store: LedgerStore

    @AppStorage("autoCommit") private var autoCommit = true
    @AppStorage("aiEnabled") private var aiEnabled = false
    @AppStorage("aiKey") private var aiKey = ""
    @AppStorage("aiModel") private var aiModel = ""
    @AppStorage("aiProvider") private var aiProviderRaw = AIParser.Provider.deepseek.rawValue
    @AppStorage("aiEndpoint") private var aiEndpoint = ""
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue

    @State private var sharePayload: SharePayload?
    @State private var showingPaste = false
    @State private var showingClearConfirm = false
    @State private var exportedMessage: String?
    @State private var aiTesting = false
    @State private var aiMessage: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var photoBusy = false
    @FocusState private var aiFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                List {
                    dataSection
                    captureSection
                    aiSection
                    securitySection
                    appearanceSection
                    shortcutSection
                    aboutSection
                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { dismissKeyboard() }
                }
            }
        }
        .sheet(item: $sharePayload) { payload in
            ActivityView(items: [payload.url])
        }
        .sheet(isPresented: $showingPaste) {
            PasteImportView()
                .environmentObject(store)
        }
        .alert("清空所有账目？", isPresented: $showingClearConfirm) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                store.clearAll()
                store.flash("账目已清空")
            }
        } message: {
            Text("本地 JSON 里的记录会全部删除，资产和分类设置保留。建议先导出 CSV。")
        }
        .alert("导出完成", isPresented: Binding(
            get: { exportedMessage != nil },
            set: { if !$0 { exportedMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(exportedMessage ?? "")
        }
    }

    // MARK: - 数据

    private var dataSection: some View {
        Section("账本数据") {
            Button {
                exportCSV()
            } label: {
                Label("导出 CSV（Excel 可直接打开）", systemImage: "square.and.arrow.up")
            }

            NavigationLink {
                CategoryManagerView()
                    .environmentObject(store)
            } label: {
                Label("分类管理", systemImage: "tag")
            }

            NavigationLink {
                BackupView()
                    .environmentObject(store)
            } label: {
                Label("备份与恢复（换机 / 重签前必做）", systemImage: "externaldrive.badge.timemachine")
            }

            NavigationLink {
                CSVImportView()
                    .environmentObject(store)
            } label: {
                Label("批量导入微信 / 支付宝账单", systemImage: "tray.and.arrow.down")
            }

            Button(role: .destructive) {
                showingClearConfirm = true
            } label: {
                Label("清空所有账目", systemImage: "trash")
            }
        }
        .listRowBackground(Theme.cardFill)
    }

    // MARK: - 记账

    private var captureSection: some View {
        Section {
            Toggle(isOn: $autoCommit) {
                Label("高把握度自动入账", systemImage: "bolt.badge.checkmark")
            }
            Button {
                showingPaste = true
            } label: {
                Label("粘贴文本识别一笔", systemImage: "doc.on.clipboard")
            }

            PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                Label(photoBusy ? "正在识别…" : "从相册选一张账单图", systemImage: "photo.on.rectangle")
            }
            .disabled(photoBusy)
            .onChange(of: photoItem) { item in
                guard let item else { return }
                Task { await importPickedPhoto(item) }
            }
        } header: {
            Text("记账")
        } footer: {
            Text(autoCommit
                 ? "把握度 ≥ 80% 且不重复时直接入账，其余先进待确认列表。"
                 : "每次识别结果都会先放进待确认列表，由你核对后保存。")
        }
        .listRowBackground(Theme.cardFill)
    }

    // MARK: - AI 复核

    private var aiSection: some View {
        Section {
            Toggle(isOn: $aiEnabled) {
                Label("用大模型复核识别结果", systemImage: "sparkles")
            }

            if aiEnabled {
                Picker(selection: Binding(
                    get: { currentProvider },
                    set: { aiProviderRaw = $0.rawValue }
                )) {
                    ForEach(AIParser.Provider.allCases) { provider in
                        Text(provider.title).tag(provider)
                    }
                } label: {
                    Label("服务商", systemImage: "brain")
                }
                .onChange(of: aiProviderRaw) { _ in
                    aiModel = ""
                    aiEndpoint = ""
                    aiMessage = nil
                }

                SecureField(currentProvider.keyHint, text: $aiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 14, design: .monospaced))
                    .focused($aiFieldFocused)
                    .submitLabel(.done)
                    .onSubmit { dismissKeyboard() }

                TextField(currentProvider.modelHint, text: $aiModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 14, design: .monospaced))
                    .focused($aiFieldFocused)
                    .submitLabel(.done)
                    .onSubmit { dismissKeyboard() }

                if currentProvider == .custom {
                    TextField("接口地址 https://…/chat/completions", text: $aiEndpoint)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 13, design: .monospaced))
                        .focused($aiFieldFocused)
                        .submitLabel(.done)
                        .onSubmit { dismissKeyboard() }
                }

                Button {
                    dismissKeyboard()
                    testAI()
                } label: {
                    HStack {
                        Label(aiTesting ? "正在连接…" : "测试连接", systemImage: "network")
                        Spacer()
                        if aiTesting {
                            ProgressView()
                        }
                    }
                }
                .disabled(aiTesting || !canTestAI)

                if let aiMessage {
                    Text(aiMessage)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(aiMessage.hasPrefix("连接成功") ? Theme.income : Theme.warn)
                }
            }
        } header: {
            Text("AI 复核（可选）")
        } footer: {
            Text(aiFooter)
        }
        .listRowBackground(Theme.cardFill)
    }

    /// 当前选中的服务商（Picker 的 selection 用它，存的是 rawValue）
    private var currentProvider: AIParser.Provider {
        AIParser.Provider(rawValue: aiProviderRaw) ?? .deepseek
    }

    private var canTestAI: Bool {
        guard !aiKey.isEmpty else { return false }
        if currentProvider.requiresModel, aiModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        if currentProvider == .custom, aiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        return true
    }

    private var aiFooter: String {
        guard aiEnabled else {
            return "默认完全离线。打开后可以选 DeepSeek / GPT / Claude / 豆包，识别不准的账单会让模型再看一遍。"
        }
        let url = currentProvider.keyURL
        if currentProvider == .doubao {
            return "豆包要在火山方舟控制台建一个「推理接入点」，把 ep-xxxx 填到模型那一栏。Key 只存在本机，只发往 \(url)。"
        }
        if currentProvider == .custom {
            return "填一个 OpenAI 兼容接口即可（地址以 /chat/completions 结尾）。Key 只存在本机。"
        }
        return "Key 在 \(url) 申请，只存在本机，只发给这一家。识别时会发账单文字，不发图片。"
    }

    // MARK: - 安全

    private var securitySection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { appLockEnabled },
                set: { updateLock($0) }
            )) {
                Label("用 Face ID / 密码解锁", systemImage: "faceid")
            }
        } header: {
            Text("安全")
        } footer: {
            Text(AppLock.isAvailable
                 ? "打开后，每次从后台回到 App 都要验证一次；锁屏界面只显示一个解锁按钮，看不到任何账目。"
                 : "这台设备还没设置锁屏密码，所以暂时用不了；先去系统设置里加一个密码。")
        }
        .listRowBackground(Theme.cardFill)
    }

    // MARK: - 外观

    private var appearanceSection: some View {
        Section {
            Picker("外观", selection: Binding(
                get: { Appearance(rawValue: appearanceRaw) ?? .system },
                set: { appearanceRaw = $0.rawValue }
            )) {
                ForEach(Appearance.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("外观")
        } footer: {
            Text("跟随系统最省心；深色模式下玻璃和光斑的层次更明显。")
        }
        .listRowBackground(Theme.cardFill)
    }

    // MARK: - 快捷指令

    private var shortcutSection: some View {
        Section("自动化") {
            NavigationLink {
                ShortcutGuideView()
            } label: {
                Label("用快捷指令 + 双击背面记账", systemImage: "hand.tap")
            }
        }
        .listRowBackground(Theme.cardFill)
    }

    // MARK: - 关于

    private var aboutSection: some View {
        Section {
            NavigationLink {
                AboutView()
            } label: {
                Label("关于 · 制作人 · 打赏 · 反馈", systemImage: "info.circle")
            }
            HStack {
                Text("版本")
                Spacer()
                Text("1.0.0 (15)")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("关于")
        } footer: {
            Text("账目只存在这台手机上，没有账号。默认不联网；只有你自己打开上面的 AI 复核并填了 Key，才会把账单文字发给你选的那家大模型服务商。")
        }
        .listRowBackground(Theme.cardFill)
    }

    // MARK: - 动作

    private func dismissKeyboard() {
        aiFieldFocused = false
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func updateLock(_ enabled: Bool) {
        guard enabled else {
            appLockEnabled = false
            return
        }
        guard AppLock.isAvailable else {
            appLockEnabled = false
            store.flash("先给手机设置一个锁屏密码，才能开账本锁")
            return
        }
        Task {
            let ok = await AppLock.authenticate(reason: "打开账本锁")
            appLockEnabled = ok
            if ok {
                store.flash("已开启账本锁")
            }
        }
    }

    private func exportCSV() {
        guard let url = CSVExporter.writeTemporaryFile(from: store.transactions) else {
            exportedMessage = "导出失败：写临时文件出错。"
            return
        }
        sharePayload = SharePayload(url: url)
    }

    private func testAI() {
        dismissKeyboard()
        let model = aiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let provider = currentProvider
        let endpoint = aiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = AIParser.Config(
            enabled: true,
            provider: provider,
            apiKey: aiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            endpoint: endpoint.isEmpty ? provider.defaultEndpoint : endpoint,
            model: model.isEmpty ? provider.defaultModel : model
        )
        aiTesting = true
        aiMessage = nil
        Task {
            do {
                let summary = try await AIParser.test(config: config, sample: SampleData.wechat)
                await MainActor.run {
                    aiMessage = "连接成功：\(summary)"
                    aiTesting = false
                }
            } catch {
                await MainActor.run {
                    aiMessage = "失败：\(error.localizedDescription)"
                    aiTesting = false
                }
            }
        }
    }

    private func importPickedPhoto(_ item: PhotosPickerItem) async {
        photoBusy = true
        defer {
            photoBusy = false
            photoItem = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            store.flash("这张图读不出来，换一张试试")
            return
        }
        do {
            let text = try await ImageOCR.recognizeText(in: image)
            await store.enqueueSmart(text: text)
        } catch {
            store.flash("识别失败：\(error.localizedDescription)")
        }
    }

}
