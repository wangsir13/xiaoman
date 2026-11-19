import SwiftUI

/// 月报：把本月收支、分类占比、每日支出排成一张竖图，可以直接分享出去
struct MonthReportView: View {

    @EnvironmentObject private var store: LedgerStore

    @State private var month: Date = Date()
    @State private var sharePayload: SharePayload?
    @State private var rendering = false
    @State private var failure: String?

    private let calendar = Calendar.current

    private var summary: (expense: Int, income: Int) { store.monthSummary(for: month) }
    private var totals: [CategoryTotal] { Array(store.expenseByCategory(in: month).prefix(5)) }
    private var days: [DailyBudget] { store.dailyBudgets(in: month) }
    private var count: Int { store.transactions(in: month).count }

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(spacing: 16) {
                    monthSwitcher
                    reportCard
                        .padding(.horizontal, 16)
                    Button {
                        export()
                    } label: {
                        Label(rendering ? "正在生成…" : "生成长图并分享", systemImage: "photo.badge.arrow.down")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.glassProminent)
                    .padding(.horizontal, 16)
                    .disabled(rendering)

                    if let failure {
                        Text(failure)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Theme.warn)
                    }

                    Text("图像仅在本机生成，不会上传。")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                }
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("月报")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(item: $sharePayload) { payload in
            ActivityView(items: [payload.url])
        }
    }

    private var monthSwitcher: some View {
        HStack(spacing: 14) {
            Button {
                shiftMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 34, height: 34)
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
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .disabled(calendar.isDate(month, equalTo: Date(), toGranularity: .month))
            .opacity(calendar.isDate(month, equalTo: Date(), toGranularity: .month) ? 0.35 : 1)
        }
        .padding(.horizontal, 16)
    }

    /// 这张卡片就是最终导出成图片的内容（刻意不用玻璃效果，离线渲染更稳）
    private var reportCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Fmt.month.string(from: month))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("月度账单")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(count) 笔")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("记账人")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }

            HStack(spacing: 10) {
                figureCard("支出", Money.plain(summary.expense), Color(hex: "FF453A"))
                figureCard("收入", Money.plain(summary.income), Color(hex: "34C759"))
                figureCard("结余", Money.plain(summary.income - summary.expense), Color(hex: "8B5CF6"))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("支出都花在哪")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))

                if totals.isEmpty {
                    Text("本月暂无支出记录。")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                } else {
                    ForEach(totals) { total in
                        categoryBar(total)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("每天花了多少")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                reportBars
                    .frame(height: 64)
            }

            Divider().overlay(Color.white.opacity(0.12))

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("小满")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("制作人 hy · 酷安 阿甘左一")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer()
                Text("本机生成 · 数据不上传")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "141B34"), Color(hex: "0B1020")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        }
    }

    private func figureCard(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
            Text("¥" + value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        }
    }

    private func categoryBar(_ total: CategoryTotal) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: total.category.colorHex))
                    .frame(width: 7, height: 7)
                Text(total.category.name)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text(Money.plain(total.cents))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.8))
                Text(String(format: "%.0f%%", total.share * 100))
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 34, alignment: .trailing)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(Color(hex: total.category.colorHex))
                        .frame(width: max(3, geometry.size.width * min(1, total.share)))
                }
            }
            .frame(height: 5)
        }
    }

    private var reportBars: some View {
        let peak = max(1, days.map { $0.spentCents }.max() ?? 1)
        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(days) { day in
                let isFuture = day.date > Date()
                let height = max(2, 64 * CGFloat(day.spentCents) / CGFloat(peak))
                RoundedRectangle(cornerRadius: 2)
                    .fill(day.spentCents == 0
                          ? Color.white.opacity(0.06)
                          : (day.isOverspent ? Color(hex: "FF453A") : Color(hex: "4C7DFF")).opacity(isFuture ? 0.35 : 1))
                    .frame(maxWidth: .infinity)
                    .frame(height: day.spentCents == 0 ? 2 : height)
            }
        }
    }

    // MARK: - 动作

    private func shiftMonth(_ delta: Int) {
        guard let next = calendar.date(byAdding: .month, value: delta, to: month) else { return }
        month = min(next, Date())
    }

    @MainActor
    private func export() {
        rendering = true
        failure = nil
        defer { rendering = false }

        let renderer = ImageRenderer(
            content: reportCard
                .frame(width: 390)
                .padding(20)
                .background(Color(hex: "0B1020"))
        )
        renderer.scale = 3

        guard let image = renderer.uiImage, let data = image.pngData() else {
            failure = "图像渲染失败，请更换内容后重试。"
            return
        }

        let name = "xiaoman-report-\(BackupEnvelope.stamp(month)).png"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            sharePayload = SharePayload(url: url)
        } catch {
            failure = "写临时文件失败：\(error.localizedDescription)"
        }
    }
}
