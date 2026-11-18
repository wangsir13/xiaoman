import SwiftUI

struct TransactionEditorView: View {

    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss

    private let base: Transaction
    private let isNew: Bool

    @State private var amountText: String
    @State private var direction: Direction
    @State private var merchant: String
    @State private var category: String
    @State private var source: BillSource
    @State private var occurredAt: Date
    @State private var note: String
    @State private var assetID: UUID?

    init(transaction: Transaction, isNew: Bool = false) {
        self.base = transaction
        self.isNew = isNew
        _amountText = State(initialValue: transaction.amountCents > 0 ? Money.plain(transaction.amountCents) : "")
        _direction = State(initialValue: transaction.direction)
        _merchant = State(initialValue: transaction.merchant)
        _category = State(initialValue: transaction.category)
        _source = State(initialValue: transaction.source)
        _occurredAt = State(initialValue: transaction.occurredAt)
        _note = State(initialValue: transaction.note)
        _assetID = State(initialValue: transaction.assetID)
    }

    private var isValid: Bool {
        guard let cents = Money.cents(from: amountText) else { return false }
        return cents > 0
    }

    private var categoryNames: [String] {
        let items = store.categories.filter { $0.kind == direction }
        var names = items.map(\.name)
        if !names.contains(category) {
            names.append(category)
        }
        return names
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 6) {
                        Text("¥")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                }

                Section {
                    Picker("方向", selection: $direction) {
                        ForEach(Direction.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: direction) { newValue in
                        if !categoryNames.contains(category) {
                            category = store.categories.first { $0.kind == newValue }?.name ?? category
                        }
                    }

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
                        .lineLimit(1...4)
                }

                if !base.rawText.isEmpty {
                    Section("原始识别文本") {
                        Text(base.rawText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            store.delete(base)
                            dismiss()
                        } label: {
                            Text("删除这笔记录")
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "新增一笔" : "编辑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!isValid)
                }
            }
        }
    }

    private func save() {
        guard let cents = Money.cents(from: amountText), cents > 0 else { return }
        var item = base
        item.amountCents = cents
        item.direction = direction
        item.merchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        item.category = category
        item.source = source
        item.occurredAt = occurredAt
        item.note = note
        item.assetID = assetID
        item.fingerprint = ""
        store.upsert(item)
        dismiss()
    }
}
