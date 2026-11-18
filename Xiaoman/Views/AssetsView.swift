import SwiftUI

struct AssetsView: View {

    @EnvironmentObject private var store: LedgerStore
    @State private var editingAsset: Asset?
    @State private var showingNew = false
    @State private var isSorting = false

    private var visibleAssets: [Asset] {
        store.assets.filter { !$0.isArchived }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                if isSorting {
                    sortingList
                } else {
                ScrollView {
                    VStack(spacing: 14) {
                        totalCard

                        ForEach(visibleAssets) { asset in
                            Button {
                                editingAsset = asset
                            } label: {
                                assetRow(asset)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    store.deleteAsset(asset)
                                } label: {
                                    Label("删除资产", systemImage: "trash")
                                }
                            }
                        }

                        if visibleAssets.isEmpty {
                            GlassCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("还没有资产")
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    Text("添加银行卡、信用卡、微信/支付宝余额或借款，之后每笔记账都会自动扣减对应资产。")
                                        .font(.system(size: 13, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
                .scrollIndicators(.hidden)
                }
            }
            .navigationTitle("资产")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isSorting ? "完成" : "排序") {
                        withAnimation(.snappy(duration: 0.22)) { isSorting.toggle() }
                    }
                    .disabled(visibleAssets.count < 2)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNew = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editingAsset) { asset in
                AssetEditorView(asset: asset)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showingNew) {
                AssetEditorView(asset: Asset(), isNew: true)
                    .environmentObject(store)
            }
        }
    }

    private var sortingList: some View {
        List {
            Section {
                ForEach(visibleAssets) { asset in
                    HStack(spacing: 12) {
                        Image(systemName: asset.symbol)
                            .foregroundStyle(Color(hex: asset.colorHex))
                            .frame(width: 22)
                        Text(asset.name.isEmpty ? "未命名" : asset.name)
                        Spacer(minLength: 8)
                        Text(store.balanceText(of: asset))
                            .font(.system(size: 13, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Theme.cardFill)
                }
                .onMove { indices, newOffset in
                    if let from = indices.first {
                        store.moveAssets(from: from, to: newOffset)
                    }
                }
            } header: {
                Text("拖动右侧把手调整顺序")
            } footer: {
                Text("顺序会同步到首页的资产卡片。")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(.active))
    }

    private var totalCard: some View {
        GlassCard(padding: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("净资产")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(Money.display(store.totalBalanceCents))
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(store.totalBalanceCents < 0 ? Theme.expense : .primary)
                HStack(spacing: 8) {
                    GlassPill(text: "\(visibleAssets.count) 个账户", systemImage: "square.stack.3d.up")
                    if store.assets.contains(where: { $0.kind.isLiability }) {
                        GlassPill(text: "含负债", systemImage: "exclamationmark.circle")
                    }
                }
            }
        }
    }

    private func assetRow(_ asset: Asset) -> some View {
        let balance = store.balanceCents(of: asset)
        return GlassCard(padding: 16, tint: Color(hex: asset.colorHex)) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color(hex: asset.colorHex).opacity(0.22))
                    Image(systemName: asset.symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: asset.colorHex))
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text(asset.name.isEmpty ? "未命名资产" : asset.name)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text(asset.kind.title + " · 期初 " + Money.plain(asset.openingBalanceCents))
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                Text(Money.display(balance))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(balance < 0 ? Theme.expense : .primary)
            }
        }
    }
}

struct AssetEditorView: View {

    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss

    private let originalID: UUID
    private let isNew: Bool

    @State private var name: String
    @State private var kind: AssetKind
    @State private var openingText: String
    @State private var keywordText: String
    @State private var note: String
    @State private var colorHex: String

    private let originalOpening: Int

    init(asset: Asset, isNew: Bool = false) {
        self.originalID = asset.id
        self.isNew = isNew
        self.originalOpening = asset.openingBalanceCents
        _name = State(initialValue: asset.name)
        _kind = State(initialValue: asset.kind)
        _openingText = State(initialValue: asset.openingBalanceCents == 0 ? "" : Money.plain(asset.openingBalanceCents))
        _keywordText = State(initialValue: asset.keywords.joined(separator: ","))
        _note = State(initialValue: asset.note)
        _colorHex = State(initialValue: asset.colorHex)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称，例如 招商银行储蓄卡", text: $name)
                    Picker("类型", selection: $kind) {
                        ForEach(AssetKind.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    TextField(kind.isLiability ? "已欠金额，例如 -1500" : "当前余额，例如 3250.80", text: $openingText)
                        .keyboardType(.numbersAndPunctuation)
                        .onChange(of: kind) { newKind in
                            // 只有信用卡默认按「欠多少」记，切成信用卡时把已填的正数翻成负数
                            guard newKind == .creditCard else { return }
                            let trimmed = openingText.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            let hasSign = trimmed.contains("-") || trimmed.contains("−") || trimmed.contains("－")
                            if !hasSign, let cents = Money.cents(from: trimmed), cents > 0 {
                                openingText = Money.plain(-cents)
                            }
                        }
                } header: {
                    Text("基本信息")
                } footer: {
                    Text(openingHint)
                }

                Section {
                    TextField("用逗号分隔，例如 招商,尾号1234", text: $keywordText)
                } header: {
                    Text("识别关键词")
                } footer: {
                    Text("截图里出现这些词时，这笔账会自动绑到这个资产上。")
                }

                Section("颜色") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(Asset.palette, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(height: 30)
                                .overlay {
                                    if hex == colorHex {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture { colorHex = hex }
                        }
                    }
                }

                Section("备注") {
                    TextField("可选", text: $note, axis: .vertical)
                }

                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            if let asset = store.assets.first(where: { $0.id == originalID }) {
                                store.deleteAsset(asset)
                            }
                            dismiss()
                        } label: {
                            Text("删除这个资产")
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "新增资产" : "编辑资产")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var openingHint: String {
        switch kind {
        case .creditCard:
            return "信用卡按「欠多少」记：填正数会自动存成负数（填 1500 就是 -1500），净资产里自动减掉。"
        case .loan:
            return "借款：别人欠你的（你借出去的）填正数，你欠别人的填负数，两种都允许。"
        default:
            return "期初余额可以是负数，例如储蓄卡透支；键盘上的减号可以直接输入。"
        }
    }

    private func save() {
        var asset = store.assets.first { $0.id == originalID } ?? Asset()
        asset.id = originalID
        asset.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.kind = kind
        let typed = openingText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasSign = typed.contains("-") || typed.contains("−") || typed.contains("－")
        let parsed = Money.cents(from: typed) ?? 0
        // 只有信用卡按「欠多少」自动取负；借款两种方向都合法，不动符号
        let newOpening = (kind == .creditCard && !hasSign) ? -abs(parsed) : parsed
        // 期初余额一改，就从现在开始生效：之前的账单不再跟着扣减，只有之后的新账会动这个数
        if newOpening != originalOpening {
            asset.openingBalanceCents = newOpening
            asset.openingAt = Date()
        }
        asset.note = note
        asset.colorHex = colorHex
        asset.keywords = keywordText
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == " " })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if isNew {
            store.addAsset(asset)
        } else {
            store.updateAsset(asset)
        }
        dismiss()
    }
}
