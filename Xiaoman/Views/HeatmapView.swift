import SwiftUI

/// 记账热力图：一年 53 列 × 7 行，颜色越亮说明那天花得越多
struct HeatmapView: View {

    @EnvironmentObject private var store: LedgerStore

    @State private var year: Int = Calendar.current.component(.year, from: Date())

    private let calendar = Calendar.current

    private var currentYear: Int { calendar.component(.year, from: Date()) }

    /// 每一天的支出（分），只统计有记录的日期
    private var spendingByDay: [Date: Int] {
        var result: [Date: Int] = [:]
        for item in store.transactions where item.direction == .expense {
            let day = calendar.startOfDay(for: item.occurredAt)
            result[day, default: 0] += item.amountCents
        }
        return result
    }

    private var maxCents: Int {
        let values = spendingByDay.filter { calendar.component(.year, from: $0.key) == year }
        return max(1, values.values.max() ?? 1)
    }

    private var recordedDays: Int {
        spendingByDay.keys.filter { calendar.component(.year, from: $0) == year }.count
    }

    private var yearTotalCents: Int {
        spendingByDay
            .filter { calendar.component(.year, from: $0.key) == year }
            .reduce(0) { $0 + $1.value }
    }

    /// 当前连续记账天数（从今天往前数）
    private var currentStreak: Int {
        var streak = 0
        var day = calendar.startOfDay(for: Date())
        let days = spendingByDay
        while days[day] != nil {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    private var busiestDay: (date: Date, cents: Int)? {
        spendingByDay
            .filter { calendar.component(.year, from: $0.key) == year }
            .max { $0.value < $1.value }
            .map { (date: $0.key, cents: $0.value) }
    }

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(spacing: 16) {
                    yearSwitcher
                    heatCard
                    statCard
                    legend
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("记账日历")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var yearSwitcher: some View {
        HStack(spacing: 14) {
            Button {
                year -= 1
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .glassEffect(.regular.interactive(), in: .circle)

            Spacer()

            VStack(spacing: 2) {
                Text("\(String(year)) 年")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Text("\(recordedDays) 天记过账")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                year = min(currentYear, year + 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .disabled(year >= currentYear)
            .opacity(year >= currentYear ? 0.35 : 1)
        }
    }

    private var heatCard: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("每天的支出密度")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                Canvas { context, size in
                    draw(context: &context, size: size)
                }
                .frame(height: 132)
            }
        }
    }

    private func draw(context: inout GraphicsContext, size: CGSize) {
        let columns = 53
        let rows = 7
        let spacing: CGFloat = 2
        let cellWidth = (size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let cellHeight = (size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
        let side = min(cellWidth, cellHeight)

        guard let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) else { return }
        // 找到这一年第一天所在的周的第一天（按日历的每周首日）
        let weekday = calendar.component(.weekday, from: startOfYear)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -offset, to: startOfYear) else { return }

        let data = spendingByDay
        let peak = maxCents

        for index in 0..<(columns * rows) {
            guard let day = calendar.date(byAdding: .day, value: index, to: gridStart) else { continue }
            let column = index / rows
            let row = index % rows
            let x = CGFloat(column) * (side + spacing)
            let y = CGFloat(row) * (side + spacing)

            let isThisYear = calendar.component(.year, from: day) == year
            let cents = data[calendar.startOfDay(for: day)] ?? 0

            let color: Color
            if !isThisYear {
                color = Theme.trackSoft
            } else if cents == 0 {
                color = Theme.track
            } else {
                let ratio = min(1, Double(cents) / Double(peak))
                let stepped = max(0.25, (ratio * 4).rounded() / 4)
                color = Theme.accent.opacity(0.25 + stepped * 0.7)
            }

            let rect = CGRect(x: x, y: y, width: side, height: side)
            context.fill(Path(roundedRect: rect, cornerRadius: side * 0.25), with: .color(color))
        }
    }

    private var statCard: some View {
        GlassCard(padding: 16) {
            VStack(spacing: 12) {
                statRow("\(String(year)) 年支出", Money.display(yearTotalCents), Theme.expense)
                Divider().opacity(0.2)
                statRow("连续记账", "\(currentStreak) 天", Theme.income)
                Divider().opacity(0.2)
                if let busiest = busiestDay {
                    statRow("花得最多的一天", Fmt.day.string(from: busiest.date) + " · " + Money.display(busiest.cents), Theme.warn)
                } else {
                    statRow("花得最多的一天", "还没数据", .secondary)
                }
            }
        }
    }

    private func statRow(_ title: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Text("少")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
            ForEach(0..<5) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(index == 0 ? Theme.track : Theme.accent.opacity(0.25 + Double(index) * 0.18))
                    .frame(width: 12, height: 12)
            }
            Text("多")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
            Text("每天按总支出取色")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 4)
    }
}
