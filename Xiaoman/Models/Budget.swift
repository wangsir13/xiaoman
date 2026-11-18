import Foundation

/// 预算设置：一个月一个总预算，按天均分并滚动结转
struct BudgetPlan: Codable, Hashable {
    /// 月度总预算（分），0 表示还没设置
    var monthlyCents: Int = 0
    /// 每天几点提醒
    var reminderHour: Int = 21
    var reminderMinute: Int = 0
    var reminderEnabled: Bool = false
    /// 从今天开始记：今天之前的额度当作已经用完，不往今天结转。
    /// 这样第一次填预算时，今日额度不会因为「前面几天没花」而暴涨。
    var fillBeforeToday: Bool = true

    var isConfigured: Bool { monthlyCents > 0 }

    init(
        monthlyCents: Int = 0,
        reminderHour: Int = 21,
        reminderMinute: Int = 0,
        reminderEnabled: Bool = false,
        fillBeforeToday: Bool = true
    ) {
        self.monthlyCents = monthlyCents
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.reminderEnabled = reminderEnabled
        self.fillBeforeToday = fillBeforeToday
    }

    // 老版本的 budget.json 没有 fillBeforeToday，缺失时按默认值补，避免整份文件解码失败
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        monthlyCents = try container.decodeIfPresent(Int.self, forKey: .monthlyCents) ?? 0
        reminderHour = try container.decodeIfPresent(Int.self, forKey: .reminderHour) ?? 21
        reminderMinute = try container.decodeIfPresent(Int.self, forKey: .reminderMinute) ?? 0
        reminderEnabled = try container.decodeIfPresent(Bool.self, forKey: .reminderEnabled) ?? false
        fillBeforeToday = try container.decodeIfPresent(Bool.self, forKey: .fillBeforeToday) ?? true
    }
}

/// 某一天的预算快照
struct DailyBudget: Identifiable, Hashable {
    /// 当日 0 点，同时当 id
    var id: Date { date }
    let date: Date
    /// 月预算 ÷ 当月天数
    let baseCents: Int
    /// 前一天结转进来的金额，可为负（昨天超支了）
    let carryInCents: Int
    /// 当天已经花掉的金额
    let spentCents: Int

    /// 当天总共可花
    var availableCents: Int { baseCents + carryInCents }
    /// 还剩多少，负数代表超支
    var remainingCents: Int { availableCents - spentCents }
    var isOverspent: Bool { remainingCents < 0 }
    /// 0...1 的进度，超支后仍然封顶在 1
    var progress: Double {
        guard availableCents > 0 else { return spentCents > 0 ? 1 : 0 }
        return min(1, max(0, Double(spentCents) / Double(availableCents)))
    }
    /// 结转给明天的金额
    var carryOutCents: Int { availableCents - spentCents }
}

enum BudgetEngine {

    static func daysInMonth(of date: Date, calendar: Calendar = .current) -> Int {
        calendar.range(of: .day, in: .month, for: date)?.count ?? 30
    }

    /// 月预算按天数均分，四舍五入到分
    static func baseDailyCents(monthlyCents: Int, month: Date, calendar: Calendar = .current) -> Int {
        guard monthlyCents > 0 else { return 0 }
        let days = max(1, daysInMonth(of: month, calendar: calendar))
        return Int((Double(monthlyCents) / Double(days)).rounded())
    }

    /// 把某个月的每一天算成 DailyBudget。未来日子按「还没花」处理，carry 一直往前推。
    /// 当 plan.fillBeforeToday 为 true 时，今天之前的每一天都当作「额度已用完」，carry 归零。
    static func dailyBudgets(
        month: Date,
        plan: BudgetPlan,
        transactions: [Transaction],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DailyBudget] {
        guard plan.isConfigured else { return [] }
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let days = daysInMonth(of: month, calendar: calendar)
        let base = baseDailyCents(monthlyCents: plan.monthlyCents, month: month, calendar: calendar)
        let today = calendar.startOfDay(for: now)

        var spentByDay: [Date: Int] = [:]
        for item in transactions where item.direction == .expense && interval.contains(item.occurredAt) {
            let day = calendar.startOfDay(for: item.occurredAt)
            spentByDay[day, default: 0] += item.amountCents
        }

        var result: [DailyBudget] = []
        var carry = 0
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: interval.start) else { continue }
            let start = calendar.startOfDay(for: day)
            var spent = spentByDay[start] ?? 0
            if plan.fillBeforeToday && start < today {
                // 额度假装已经花完：结转 = 0，今日从「基准额度」重新开始
                spent = base + carry
            }
            let point = DailyBudget(date: start, baseCents: base, carryInCents: carry, spentCents: spent)
            result.append(point)
            carry = point.carryOutCents
        }
        return result
    }

    static func todayBudget(
        plan: BudgetPlan,
        transactions: [Transaction],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DailyBudget? {
        let all = dailyBudgets(month: now, plan: plan, transactions: transactions, now: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        return all.first { $0.date == today }
    }

    /// 本月还能花多少（剩余预算 − 未来日子的基础预算，负数说明已经透支到下个月）
    static func monthRemainingCents(
        plan: BudgetPlan,
        transactions: [Transaction],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        guard plan.isConfigured else { return 0 }
        let spent = transactions
            .filter { $0.direction == .expense && calendar.isDate($0.occurredAt, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.amountCents }
        return plan.monthlyCents - spent
    }
}
