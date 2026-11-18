import SwiftUI

/// 环形饼图（纯 Canvas 绘制，不依赖 Charts）
struct CategoryDonut: View {
    var totals: [CategoryTotal]
    var lineWidth: CGFloat = 20

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = max(1, min(size.width, size.height) / 2 - lineWidth / 2)
            let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round)

            guard !totals.isEmpty else {
                var ring = Path()
                ring.addArc(
                    center: center,
                    radius: radius,
                    startAngle: .radians(-Double.pi / 2),
                    endAngle: .radians(Double.pi * 1.5),
                    clockwise: false
                )
                context.stroke(ring, with: .color(Theme.track), style: style)
                return
            }

            var start = -Double.pi / 2
            for total in totals {
                let sweep = max(0.03, total.share) * Double.pi * 2
                var path = Path()
                path.addArc(
                    center: center,
                    radius: radius,
                    startAngle: .radians(start + 0.02),
                    endAngle: .radians(start + sweep - 0.02),
                    clockwise: false
                )
                context.stroke(path, with: .color(Color(hex: total.category.colorHex)), style: style)
                start += sweep
            }
        }
    }
}

/// 分类图例
struct CategoryLegend: View {
    var totals: [CategoryTotal]
    var limit: Int = 6

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(totals.prefix(limit))) { total in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color(hex: total.category.colorHex))
                        .frame(width: 10, height: 10)
                    Text(total.category.name)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                    Spacer()
                    Text(String(format: "%.0f%%", total.share * 100))
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                    Text(Fmt.money(total.cents))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
            }
            if totals.isEmpty {
                Text("这个月还没有支出")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 每日支出柱状图，红色表示当天超支
struct DailyBars: View {
    var points: [DailyBudget]

    var body: some View {
        Canvas { context, size in
            guard !points.isEmpty else { return }
            let maxValue = max(1, points.map { max($0.spentCents, $0.availableCents) }.max() ?? 1)
            let count = points.count
            let gap: CGFloat = 2
            let barWidth = max(1, (size.width - gap * CGFloat(count - 1)) / CGFloat(count))
            let height = size.height

            for (index, point) in points.enumerated() {
                let ratio = CGFloat(point.spentCents) / CGFloat(maxValue)
                let barHeight = max(2, height * min(1, ratio))
                let x = CGFloat(index) * (barWidth + gap)
                let rect = CGRect(x: x, y: height - barHeight, width: barWidth, height: barHeight)
                let path = Path(roundedRect: rect, cornerRadius: min(2, barWidth / 2))
                let color: Color = point.isOverspent
                    ? Color(hex: "FF453A")
                    : Color(hex: "4C7DFF").opacity(point.date > Date() ? 0.35 : 0.9)
                context.fill(path, with: .color(color))
            }
        }
    }
}

/// 月度收支详情页
struct SpendingChartsView: View {

    @EnvironmentObject private var store: LedgerStore
    @State private var month = Date()

    private var summary: (expense: Int, income: Int) { store.monthSummary(for: month) }
    private var totals: [CategoryTotal] { store.expenseByCategory(in: month) }

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        monthSwitcher

                        GlassCard {
                            VStack(spacing: 16) {
                                HStack(alignment: .center, spacing: 16) {
                                    ZStack {
                                        CategoryDonut(totals: totals, lineWidth: 18)
                                            .frame(width: 130, height: 130)
                                        VStack(spacing: 2) {
                                            Text("支出")
                                                .font(.system(size: 12, design: .rounded))
                                                .foregroundStyle(.secondary)
                                            Text(Money.plain(summary.expense))
                                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                                .monospacedDigit()
                                        }
                                    }
                                    CategoryLegend(totals: totals, limit: 5)
                                }
                            }
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionTitle(title: "每日支出", trailing: store.budgetPlan.isConfigured ? "红色 = 超支" : nil)
                                DailyBars(points: store.dailyBudgets(in: month))
                                    .frame(height: 120)
                            }
                        }

                        GlassCard {
                            VStack(spacing: 12) {
                                HStack {
                                    Text("收入")
                                    Spacer()
                                    Text(Money.display(summary.income))
                                        .foregroundStyle(Theme.income)
                                        .monospacedDigit()
                                }
                                Divider().opacity(0.3)
                                HStack {
                                    Text("支出")
                                    Spacer()
                                    Text(Money.display(summary.expense))
                                        .foregroundStyle(Theme.expense)
                                        .monospacedDigit()
                                }
                                Divider().opacity(0.3)
                                HStack {
                                    Text("结余")
                                    Spacer()
                                    Text(Money.display(summary.income - summary.expense))
                                        .monospacedDigit()
                                }
                            }
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                        }
                    }
                    .padding(16)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("统计")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    private var monthSwitcher: some View {
        HStack {
            Button {
                shiftMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .padding(8)
            }
            .glassEffect(.regular.interactive(), in: .circle)

            Spacer()
            Text(Fmt.month.string(from: month))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            Spacer()

            Button {
                shiftMonth(1)
            } label: {
                Image(systemName: "chevron.right")
                    .padding(8)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .disabled(month >= Date())
            .opacity(month >= Date() ? 0.4 : 1)
        }
        .padding(.horizontal, 4)
    }

    private func shiftMonth(_ delta: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: delta, to: month) {
            month = min(next, Date())
        }
    }
}
