import LocalAuthentication
import Foundation

/// Face ID / 设备密码锁：只在用户主动打开时生效
enum AppLock {

    static let enabledKey = "appLockEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// 设备有没有设置密码（没密码就没法锁）
    static var isAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    /// 弹系统验证框，成功返回 true
    static func authenticate(reason: String = "解锁你的记账本") async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "取消"
        context.localizedFallbackTitle = "输入密码"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // 没有密码/没开生物识别：直接放行，别把用户锁在外面
            return true
        }

        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}
