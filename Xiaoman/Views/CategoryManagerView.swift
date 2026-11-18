import SwiftUI

struct CategoryManagerView: View {

    @EnvironmentObject private var store: LedgerStore
    @State private var showingNew = false
    @State private var name = ""
    @State private var selectedSymbol = "tag.fill"
    @State private var selectedColor = "2F4EDE"
    @State private var kind: Direction = .expense

    private let symbols = [
        "tag.fill", "fork.knife", "car.fill", "bag.fill", "house.fill",
        "gamecontroller.fill", "cross.case.fill", "book.fill", "gift.fill",
        "pawprint.fill", "airplane", "wrench.and.screwdriver.fill", "yensign.circle.fill",
        "chart.line.uptrend.xyaxis", "heart.fill", "leaf.fill"
    ]

    private let colors = [
        "FF7043", "42A5F5", "AB47BC", "26A69A", "EC407A",
        "EF5350", "8D6E63", "5C6BC0", "7E57C2", "66BB6A",
        "9CCC65", "90A4AE", "E0A800", "0EA5A5", "2F4EDE"
    ]

    var body: some View {
        ZStack {
            AuroraBackground()
            List {
                Section("支出分类") {
                    ForEach(store.categories.filter { $0.kind == .expense }) { item in
                        row(item)
                    }
                }
                Section("收入分类") {
                    ForEach(store.categories.filter { $0.kind == .income }) { item in
                        row(item)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .listRowBackground(Theme.cardFillSoft)
        }
        .navigationTitle("分类")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingNew = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNew) {
            NavigationStack {
                Form {
                    Section("名称") {
                        TextField("例如 宠物", text: $name)
                    }
                    Section("类型") {
                        Picker("类型", selection: $kind) {
                            Text("支出").tag(Direction.expense)
                            Text("收入").tag(Direction.income)
                        }
                        .pickerStyle(.segmented)
                    }
                    Section("图标") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                            ForEach(symbols, id: \.self) { symbol in
                                Image(systemName: symbol)
                                    .font(.system(size: 17))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(symbol == selectedSymbol ? Theme.hairline : Theme.cardFillSoft)
                                    )
                                    .onTapGesture { selectedSymbol = symbol }
                            }
                        }
                    }
                    Section("颜色") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                            ForEach(colors, id: \.self) { hex in
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(height: 28)
                                    .overlay {
                                        if hex == selectedColor {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .onTapGesture { selectedColor = hex }
                            }
                        }
                    }
                }
                .navigationTitle("新增分类")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showingNew = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            store.addCategory(
                                CategoryItem(
                                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                    symbol: selectedSymbol,
                                    colorHex: selectedColor,
                                    kind: kind,
                                    isBuiltin: false
                                )
                            )
                            name = ""
                            showingNew = false
                        }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func row(_ item: CategoryItem) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: item.colorHex).opacity(0.22))
                Image(systemName: item.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: item.colorHex))
            }
            .frame(width: 32, height: 32)

            Text(item.name)
                .font(.system(size: 15, weight: .medium, design: .rounded))

            Spacer()

            if item.isBuiltin {
                Text("预置")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                Button(role: .destructive) {
                    store.deleteCategory(item)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
