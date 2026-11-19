import SwiftUI

struct ImportReviewView: View {

    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                List {
                    Section {
                        ForEach(store.pendingDrafts) { draft in
                            NavigationLink {
                                DraftEditorView(draft: draft)
                                    .environmentObject(store)
                            } label: {
                                DraftRow(draft: draft)
                            }
                        }
                    } footer: {
                        Text("识别结果仅供参考，保存前请核对金额。原始文本将随账目一并存档，便于日后追溯。")
                    }
                    .listRowBackground(Theme.cardFill)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("确认识别结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("全部丢弃") {
                        store.discardAllDrafts()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存全部") {
                        store.commitAllDrafts()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct DraftRow: View {

    let draft: ImportDraft

    private var amountColor: Color {
        draft.isValid ? .primary : Color.red
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.amountCents.map { Money.display($0) } ?? "金额未识别")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(amountColor)

                Text(draft.merchant.isEmpty ? "商户未识别，请手动填写" : draft.merchant)
                    .font(.subheadline)
                    .foregroundStyle(draft.merchant.isEmpty ? .secondary : .primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    badge(draft.source.title)
                    badge(draft.category)
                    if !draft.assetName.isEmpty {
                        badge(draft.assetName)
                    }
                    badge("把握度 \(draft.confidenceText)")
                    if draft.isDuplicate {
                        badge("疑似重复")
                    }
                }
            }

            Spacer(minLength: 4)

            Text(DateFormatter.clock.string(from: draft.occurredAt))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12), in: Capsule())
            .foregroundStyle(.secondary)
    }
}

struct DraftEditorView: View {

    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss

    private let originalID: UUID
    private let rawText: String

    @State private var amountText: String
    @State private var direction: Direction
    @State private var merchant: String
    @State private var category: String
    @State private var source: BillSource
    @State private var occurredAt: Date
    @State private var note: String
    @State private var showRawText = false
    @State private var assetID: UUID?

    init(draft: ImportDraft) {
        originalID = draft.id
        rawText = draft.rawText
        _amountText = State(initialValue: draft.amountText)
        _direction = State(initialValue: draft.direction)
        _merchant = State(initialValue: draft.merchant)
        _category = State(initialValue: draft.category)
        _source = State(initialValue: draft.source)
        _occurredAt = State(initialValue: draft.occurredAt)
        _note = State(initialValue: draft.note)
        _assetID = State(initialValue: draft.assetID)
    }

    private var categoryNames: [String] {
        var names = store.categories.filter { $0.kind == direction }.map(\.name)
        if !names.contains(category) {
            names.append(category)
        }
        return names
    }

    private var amountCents: Int? {
        Money.cents(from: amountText)
    }

    private var isValid: Bool {
        guard let cents = amountCents else { return false }
        return cents > 0
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 6) {
                    Text("¥")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                }
            }

            Section {
                Picker("方向", selection: $direction) {
                    ForEach(Direction.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                TextField("商户", text: $merchant)

                Picker("分类", selection: $category) {
                    ForEach(categoryNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }

                Picker("资产", selection: $assetID) {
                    Text("不绑定").tag(UUID?.none)
                    ForEach(store.assets.filter { !$0.isArchived }) { asset in
                        Text(asset.name).tag(UUID?.some(asset.id))
                    }
                }

                Picker("来源", selection: $source) {
                    ForEach(BillSource.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }

                DatePicker("时间", selection: $occurredAt, displayedComponents: [.date, .hourAndMinute])
            }

            Section("备注") {
                TextField("可选", text: $note, axis: .vertical)
                    .lineLimit(1...3)
            }

            Section {
                Button {
                    showRawText.toggle()
                } label: {
                    HStack {
                        Text("原始识别文本")
                        Spacer()
                        Image(systemName: showRawText ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if showRawText {
                    Text(rawText.isEmpty ? "（空）" : rawText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("确认这一条")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .disabled(!isValid)
            }
        }
    }

    private func save() {
        guard let cents = amountCents, cents > 0 else { return }
        var draft = ImportDraft()
        draft.id = originalID
        draft.amountText = Money.plain(cents)
        draft.direction = direction
        draft.merchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.category = category
        draft.source = source
        draft.occurredAt = occurredAt
        draft.note = note
        draft.rawText = rawText
        draft.assetID = assetID
        draft.assetName = store.asset(for: assetID)?.name ?? ""

        store.commit(draft)
        store.removeDraft(originalID)
        dismiss()
    }
}
