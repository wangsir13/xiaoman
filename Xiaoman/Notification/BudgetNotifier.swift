import Foundation
import UserNotifications

/// 预算提醒：本地通知，不需要推送证书（免费自签环境下唯一能用的提醒方式）
enum BudgetNotifier {

    private static var center: UNUserNotificationCenter { .current() }

    static func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// 重新排今天剩下的那条提醒；已过今天的提醒时间就排到明天
    static func refresh(plan: BudgetPlan, today: DailyBudget?) async {
        center.removePendingNotificationRequests(withIdentifiers: ["budget.daily"])

        guard plan.isConfigured, plan.reminderEnabled, let today = today else { return }

        let content = UNMutableNotificationContent()
        content.title = today.isOverspent ? "今天超支了" : "今天还剩 " + Money.plain(today.remainingCents)
        if today.isOverspent {
            content.body = "已花 \(Money.plain(today.spentCents))，超出 \(Money.plain(-today.remainingCents))，明天的额度会先扣掉这部分。"
        } else {
            content.body = "已花 \(Money.plain(today.spentCents)) / \(Money.plain(today.availableCents))，还可以花 \(Money.plain(today.remainingCents))。"
        }
        content.sound = .default

        var components = DateComponents()
        components.hour = plan.reminderHour
        components.minute = plan.reminderMinute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let request = UNNotificationRequest(identifier: "budget.daily", content: content, trigger: trigger)
        try? await center.add(request)
    }

    /// 刚记完一笔账，如果直接把今天的额度花穿了，立刻提醒一次（当天只提醒一次）
    static func notifyOverspendIfNeeded(today: DailyBudget?) async {
        guard let today = today, today.isOverspent else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let identifier = "budget.overspend." + formatter.string(from: Date())

        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        if pending.contains(where: { $0.identifier == identifier })
            || delivered.contains(where: { $0.request.identifier == identifier }) {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "今天已超支 \(Money.plain(-today.remainingCents))"
        content.body = "今日额度 \(Money.plain(today.availableCents))，已花 \(Money.plain(today.spentCents))。"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        )
        try? await center.add(request)
    }

    static func clearAll() {
        center.removePendingNotificationRequests(withIdentifiers: ["budget.daily"])
    }
}
