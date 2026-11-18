import SwiftUI

struct MonthSummaryCard: View {

    @EnvironmentObject private var store: LedgerStore

    var body: some View {
        let summary = store.monthSummary()
        let parts = Fmt.amountParts(summary.expense)

        GlassCard(padding: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(Fmt.month.string(from: Date()))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    GlassPill(text: "共 \(store.transactions.count) 笔", systemImage: "list.bullet")
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

                HStack(spacing: 16) {
                    Label {
                        Text("收入 " + Money.display(summary.income))
                    } icon: {
                        Image(systemName: "arrow.down.left")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Theme.income)

                    Label {
                        Text("结余 " + Money.display(summary.income - summary.expense))
                    } icon: {
                        Image(systemName: "equal")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                }
                .font(.system(size: 13, weight: .medium, design: .rounded))
            }
        }
    }
}

extension DateFormatter {
    static let monthTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy 年 M 月"
        return formatter
    }()

    static let dayTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M 月 d 日 EEEE"
        return formatter
    }()

    static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
