import SwiftUI

struct LedgerListView: View {

    @EnvironmentObject private var store: LedgerStore

    @State private var query: String = ""
    @State private var editingItem: Transaction?
    @State private var showingNew = false

    private struct DaySection: Identifiable {
        let id: Date
        let items: [Transaction]
    }

    private var filtered: [Transaction] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return store.transactions }
        return store.transactions.filter { item in
            item.merchant.contains(keyword)
                || item.category.contains(keyword)
                || item.note.contains(keyword)
                || item.source.title.contains(keyword)
                || item.rawText.contains(keyword)
        }
    }

    private var sections: [DaySection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.occurredAt) }
        return grouped.keys.sorted(by: >).map { day in
            DaySection(
                id: day,
                items: (grouped[day] ?? []).sorted { $0.occurredAt > $1.occurredAt }
            )
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                ScrollView {
                    LazyVStack(spacing: 14, pinnedViews: []) {
                        MonthSummaryCard()

                        if filtered.isEmpty {
                            emptyHint
                        } else {
                            ForEach(sections) { section in
                                dayBlock(section)
                            }
                        }
                    }
                    .padding(16)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("账单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .searchable(text: $query, prompt: "搜商户 / 分类 / 备注")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        HeatmapView()
                            .environmentObject(store)
                    } label: {
                        Image(systemName: "calendar")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        MonthReportView()
                            .environmentObject(store)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNew = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editingItem) { item in
                TransactionEditorView(transaction: item)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showingNew) {
                TransactionEditorView(transaction: Transaction(amountCents: 0), isNew: true)
                    .environmentObject(store)
            }
        }
    }

    private func dayBlock(_ section: DaySection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Fmt.day.string(from: section.id))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                let total = section.items
                    .filter { $0.direction == .expense }
                    .reduce(0) { $0 + $1.amountCents }
                Text("-" + Money.plain(total))
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 6)

            VStack(spacing: 0) {
                ForEach(section.items) { item in
                    Button {
                        editingItem = item
                    } label: {
                        HomeRow(transaction: item, asset: store.asset(for: item.assetID))
                            .padding(.horizontal, 14)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            store.delete(item)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }

                    if item.id != section.items.last?.id {
                        Divider()
                            .opacity(0.12)
                            .padding(.leading, 60)
                    }
                }
            }
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(store.transactions.isEmpty ? "还没有记录" : "没有匹配的记录")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            Text(store.transactions.isEmpty
                 ? "到「设置 → 用快捷指令 + 双击背面记账」按教程配一次；之后截图交给 App 就能自动入账。"
                 : "换个关键词试试。")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}
