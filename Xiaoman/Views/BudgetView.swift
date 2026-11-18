import SwiftUI
import UIKit
import UserNotifications

struct BudgetView: View {

    @EnvironmentObject private var store: LedgerStore

    @State private var monthlyText: String = ""
    @State private var reminderEnabled = false
    @State private var reminderTime = Date()
    @State private var authDenied = false
    @State private var fillBeforeToday = true
    @FocusState private var budgetFieldFocused: Bool

    private var plan: BudgetPlan { store.budgetPlan }
    private var days: [DailyBudget] { store.dailyBudgets() }
    private var today: DailyBudget? { store.todayBudget }

    private var baseDaily: Int {
        BudgetEngine.baseDailyCents(monthlyCents: plan.monthlyCents, month: Date())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        setupCard
                        if plan.isConfigured {
                            overviewCard
                            reminderCard
                            daysCard
                        } else {
                            hintCard
                        }
                    }
                    .padding(16)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("预算")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { dismissKeyboard() }
                }
            }
        }
        .onAppear(perform: loadFromStore)
        .task {
            authDenied = await BudgetNotifier.authorizationStatus() == .denied
        }
    }

    // MARK: - 设置

    private var setupCard: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text("每月预算")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("¥")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    TextField("例如 6000", text: $monthlyText)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .keyboardType(.decimalPad)
                        .monospacedDigit()
                        .focused($budgetFieldFocused)
                }
                Text("按 \(BudgetEngine.daysInMonth(of: Date())) 天均分，每天 \(Money.display(baseDaily))，花不完自动留到第二天。")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)

                Toggle(isOn: $fillBeforeToday) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("从今日起")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                        Text("打开的当天开始算预算，之前的日期不再占用额度，今日额度就是每天均分的 \(Money.display(baseDaily))。")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(Theme.accent)
                .onChange(of: fillBeforeToday) { _ in savePlan() }

                HStack {
                    Spacer()
                    Button {
                        dismissKeyboard()
                        savePlan()
                    } label: {
                        Text("保存预算")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.glassProminent)
                }
            }
        }
    }

    private var hintCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("先设一个月度预算")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("设好之后，首页会显示今天还能花多少；超支的部分会自动从明天的额度里扣。")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 本月概览

    private var overviewCard: some View {
        let summary = store.monthSummary()
        let remaining = plan.monthlyCents - summary.expense
        let progress = plan.monthlyCents > 0
            ? min(1, Double(summary.expense) / Double(plan.monthlyCents))
            : 0

        return GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("本月已花")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Money.plain(summary.expense) + " / " + Money.plain(plan.monthlyCents))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                ProgressBar(progress: progress, isOverspent: remaining < 0)
                    .frame(height: 8)
                HStack {
                    Text(remaining >= 0 ? "本月还能花" : "本月已超支")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Money.display(abs(remaining)))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(remaining >= 0 ? Theme.income : Theme.expense)
                }
                if let today = today {
                    Divider().opacity(0.25)
                    HStack(spacing: 16) {
                        ZStack {
                            RingGauge(
                                progress: today.progress,
                                lineWidth: 9,
                                colors: today.isOverspent
                                    ? [Color(hex: "FF453A"), Color(hex: "FF9F0A")]
                                    : [Color(hex: "4C7DFF"), Color(hex: "8B5CF6")]
                            )
                            .frame(width: 58, height: 58)
                            Text("\(Int(today.progress * 100))%")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .monospacedDigit()
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("今天")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                            Text("已花 \(Money.plain(today.spentCents)) · 可用 \(Money.plain(today.availableCents))")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(.secondary)
                            Text(today.isOverspent
                                 ? "超支 \(Money.plain(-today.remainingCents))，明天额度先扣"
                                 : "还剩 \(Money.plain(today.remainingCents))")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(today.isOverspent ? Theme.expense : Theme.income)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    // MARK: - 提醒

    private var reminderCard: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $reminderEnabled) {
                    Text("每天提醒剩余额度")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                }
                .onChange(of: reminderEnabled) { _ in savePlan() }

                if reminderEnabled {
                    DatePicker(
                        "提醒时间",
                        selection: $reminderTime,
                        displayedComponents: .hourAndMinute
                    )
                    .font(.system(size: 14, design: .rounded))
                    .onChange(of: reminderTime) { _ in savePlan() }
                }

                if authDenied {
                    HStack(spacing: 6) {
                        Image(systemName: "bell.slash")
                        Text("通知被关闭了，去系统设置里打开「小满」的通知。")
                            .font(.system(size: 12, design: .rounded))
                        Spacer()
                        Button("去设置") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(Theme.warn)
                }
            }
        }
    }

    // MARK: - 每日列表

    private var daysCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "每日预算", trailing: "红色 = 超支")
            VStack(spacing: 0) {
                ForEach(days) { day in
                    HStack(spacing: 12) {
                        Text("\(Calendar.current.component(.day, from: day.date))")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .frame(width: 26)
                            .foregroundStyle(Calendar.current.isDateInToday(day.date) ? Theme.accent : .primary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(Money.plain(day.spentCents) + " / " + Money.plain(day.availableCents))
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .monospacedDigit()
                            if day.carryInCents != 0 {
                                Text((day.carryInCents > 0 ? "结转 +" : "结转 ") + Money.plain(day.carryInCents))
                                    .font(.system(size: 10, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer(minLength: 4)

                        Text(day.isOverspent
                             ? "-" + Money.plain(-day.remainingCents)
                             : Money.plain(day.remainingCents))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(day.isOverspent ? Theme.expense : Theme.income)
                    }
                    .padding(.vertical, 8)

                    if day.id != days.last?.id {
                        Divider().opacity(0.12)
                    }
                }
            }
            .padding(.horizontal, 14)
            .glassEffect(.regular, in: .rect(cornerRadius: 26))
        }
    }

    // MARK: - 存取

    private func dismissKeyboard() {
        budgetFieldFocused = false
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func loadFromStore() {
        monthlyText = plan.monthlyCents == 0 ? "" : Money.plain(plan.monthlyCents)
        reminderEnabled = plan.reminderEnabled
        fillBeforeToday = plan.fillBeforeToday
        var components = DateComponents()
        components.hour = plan.reminderHour
        components.minute = plan.reminderMinute
        reminderTime = Calendar.current.date(from: components) ?? Date()
    }

    private func savePlan() {
        var plan = store.budgetPlan
        plan.monthlyCents = Money.cents(from: monthlyText) ?? 0
        plan.reminderEnabled = reminderEnabled
        plan.fillBeforeToday = fillBeforeToday
        let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        plan.reminderHour = components.hour ?? 21
        plan.reminderMinute = components.minute ?? 0

        if plan.reminderEnabled {
            Task {
                let granted = await BudgetNotifier.requestAuthorization()
                authDenied = !granted
                await BudgetNotifier.refresh(plan: plan, today: store.todayBudget)
            }
        } else {
            BudgetNotifier.clearAll()
        }
        store.updateBudget(plan)
    }
}

struct ProgressBar: View {
    var progress: Double
    var isOverspent: Bool = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.track)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: isOverspent
                                ? [Color(hex: "FF453A"), Color(hex: "FF9F0A")]
                                : [Color(hex: "4C7DFF"), Color(hex: "8B5CF6")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(4, geometry.size.width * min(1, max(0, progress))))
            }
        }
    }
}
