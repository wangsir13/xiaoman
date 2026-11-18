import SwiftUI

struct HomeView: View {

    @EnvironmentObject private var store: LedgerStore

    @State private var statsExpanded = false
    @State private var assetsExpanded = false

    private var summary: (expense: Int, income: Int) { store.monthSummary() }
    private var totals: [CategoryTotal] { store.expenseByCategory() }

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        heroCard
                        quickStats
                        budgetCard
                        categoryCard
                        assetsCard
                        recentCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    // MARK: - 顶部

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Fmt.day.string(from: Date()))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Text("小满")
                .font(.system(size: 34, weight: .bold, design: .rounded))
        }
        .padding(.top, 8)
    }

    // MARK: - 主卡：本月支出

    private var heroCard: some View {
        let parts = Fmt.amountParts(summary.expense)
        return GlassCard(padding: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(Fmt.month.string(from: Date()) + " 支出")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    GlassPill(
                        text: store.budgetPlan.isConfigured ? "预算 " + Money.plain(store.budgetPlan.monthlyCents) : "未设预算",
                        systemImage: "target"
                    )
                }
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("¥")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(parts.integer)
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("." + parts.fraction)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if store.budgetPlan.isConfigured {
                    let remaining = store.monthRemainingCents
                    HStack(spacing: 6) {
                        Image(systemName: remaining >= 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                        Text(remaining >= 0
                             ? "还能花 " + Money.display(remaining)
                             : "已超支 " + Money.display(-remaining))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(remaining >= 0 ? Theme.income : Theme.expense)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottomTrailing) {
                Text("小满胜万全")
                    .font(.system(size: 12, weight: .medium, design: .serif))
                    .tracking(2.5)
                    .foregroundStyle(Theme.accent.opacity(0.5))
                    .padding(.trailing, 2)
                    .padding(.bottom, 2)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - 概览小卡（两列，可折叠展开）

    private struct StatItem {
        let title: String
        let value: String
        let symbol: String
        let tint: Color
    }

    private var statItems: [StatItem] {
        [
            StatItem(title: "今日支出", value: Money.display(store.spentToday()), symbol: "sun.max", tint: Theme.expense),
            StatItem(title: "本月收入", value: Money.display(summary.income), symbol: "arrow.down.circle", tint: Theme.income),
            StatItem(title: "本月结余", value: Money.display(summary.income - summary.expense), symbol: "equal.circle", tint: Color(hex: "8B5CF6")),
            StatItem(title: "净资产", value: Money.display(store.totalBalanceCents), symbol: "chart.pie", tint: Color(hex: "0EA5A5"))
        ]
    }

    private var quickStats: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(Array(statItems.prefix(statsExpanded ? statItems.count : 2).enumerated()), id: \.offset) { _, item in
                    miniStat(title: item.title, value: item.value, symbol: item.symbol, tint: item.tint)
                }
            }
            if statItems.count > 2 {
                expandButton(isExpanded: statsExpanded, title: statsExpanded ? "收起" : "展开更多") {
                    withAnimation(.snappy(duration: 0.26)) { statsExpanded.toggle() }
                }
            }
        }
    }

    private func expandButton(isExpanded: Bool, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
            .padding(.horizontal, 14)
            .glassEffect(.clear, in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private func miniStat(title: String, value: String, symbol: String, tint: Color) -> some View {
        GlassCard(padding: 14, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                    Text(title)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
                .foregroundStyle(tint)
                Text(value)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        }
    }

    // MARK: - 今日预算

    @ViewBuilder
    private var budgetCard: some View {
        if let today = store.todayBudget {
            GlassCard(padding: 18) {
                HStack(spacing: 16) {
                    ZStack {
                        RingGauge(
                            progress: today.progress,
                            lineWidth: 11,
                            colors: today.isOverspent
                                ? [Color(hex: "FF453A"), Color(hex: "FF9F0A")]
                                : [Color(hex: "4C7DFF"), Color(hex: "8B5CF6")]
                        )
                        .frame(width: 78, height: 78)
                        VStack(spacing: 0) {
                            Text("\(Int(today.progress * 100))%")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .monospacedDigit()
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("今日预算")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Text("已花 " + Money.display(today.spentCents) + " / " + Money.display(today.availableCents))
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            if today.carryInCents != 0 {
                                GlassPill(
                                    text: (today.carryInCents > 0 ? "昨日结转 +" : "昨日超支 ") + Money.plain(today.carryInCents),
                                    tint: today.carryInCents > 0 ? Theme.income : Theme.expense
                                )
                            }
                            GlassPill(
                                text: today.isOverspent
                                    ? "超支 " + Money.display(-today.remainingCents)
                                    : "剩余 " + Money.display(today.remainingCents),
                                tint: today.isOverspent ? Theme.expense : .primary
                            )
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - 分类分布

    private var categoryCard: some View {
        NavigationLink {
            SpendingChartsView()
                .environmentObject(store)
        } label: {
            GlassCard(padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("本月支出分布")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 18) {
                        ZStack {
                            CategoryDonut(totals: totals, lineWidth: 14)
                                .frame(width: 96, height: 96)
                            VStack(spacing: 0) {
                                Text("\(totals.count)")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                Text("类")
                                    .font(.system(size: 10, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        CategoryLegend(totals: totals, limit: 4)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 资产

    private var assetsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "资产", trailing: Money.display(store.totalBalanceCents))
            if store.assets.isEmpty {
                GlassCard {
                    Text("还没有资产，去「资产」页添加银行卡、支付宝余额或借款。")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            } else {
                if assetsExpanded {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(store.assets) { asset in
                            assetChip(asset)
                        }
                    }
                }
                // 折叠按钮居中，和上面「概览小卡」的展开按钮对齐
                HStack {
                    Spacer(minLength: 0)
                    expandButton(isExpanded: assetsExpanded, title: assetsExpanded ? "收起" : "展开资产") {
                        withAnimation(.snappy(duration: 0.26)) { assetsExpanded.toggle() }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func assetChip(_ asset: Asset) -> some View {
        let balance = store.balanceCents(of: asset)
        return GlassCard(padding: 14, cornerRadius: 22, tint: Color(hex: asset.colorHex)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: asset.symbol)
                        .font(.system(size: 12, weight: .semibold))
                    Text(asset.name)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundStyle(Color(hex: asset.colorHex))
                Text(Money.display(balance))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(balance < 0 ? Theme.expense : .primary)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        }
    }

    // MARK: - 最近账目

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "最近记录")
            if store.transactions.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("还没有记录")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text("快捷指令里加一个动作：「小满记账」→ 识别截图，双击手机背面就能自动入账；也可以点右上角 + 手动记一笔。")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(store.recentTransactions(limit: 6)) { item in
                        NavigationLink {
                            TransactionEditorView(transaction: item)
                                .environmentObject(store)
                        } label: {
                            HomeRow(transaction: item, asset: store.asset(for: item.assetID))
                        }
                        .buttonStyle(.plain)
                        if item.id != store.recentTransactions(limit: 6).last?.id {
                            Divider().opacity(0.15).padding(.leading, 46)
                        }
                    }
                }
                .padding(14)
                .glassEffect(.regular, in: .rect(cornerRadius: 26, style: .continuous))
            }
        }
    }
}

/// 首页里的账目行
struct HomeRow: View {
    let transaction: Transaction
    let asset: Asset?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: CategoryCatalog.builtin.first { $0.name == transaction.category }?.colorHex ?? "90A4AE").opacity(0.22))
                Image(systemName: CategoryCatalog.builtin.first { $0.name == transaction.category }?.symbol ?? "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: CategoryCatalog.builtin.first { $0.name == transaction.category }?.colorHex ?? "90A4AE"))
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.title)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(transaction.category)
                    Text("·")
                    Text(Fmt.clock.string(from: transaction.occurredAt))
                    if let asset = asset {
                        Text("·")
                        Text(asset.name)
                    }
                }
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 6)

            Text(transaction.displayAmount)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(transaction.direction == .income ? Theme.income : .primary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
