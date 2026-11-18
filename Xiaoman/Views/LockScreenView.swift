import SwiftUI

/// 锁屏：打开 App 或从后台回来时盖在最上面，验证通过才放行
struct LockScreenView: View {

    var isUnlocking: Bool
    var onUnlock: () -> Void

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "记账"
    }

    var body: some View {
        ZStack {
            AuroraBackground()
                .ignoresSafeArea()

            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 96, height: 96)
                    Image(systemName: "faceid")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.primary)
                }
                .glassEffect(.regular, in: .circle)

                VStack(spacing: 6) {
                    Text(appName)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("账本已锁定")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Button {
                    onUnlock()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.open.fill")
                        Text(isUnlocking ? "验证中…" : "用 Face ID 解锁")
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.glassProminent)
                .disabled(isUnlocking)

                Text("可以在「设置 → 安全」里关掉这个锁")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .padding(24)
        }
    }
}
