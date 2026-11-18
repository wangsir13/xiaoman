import SwiftUI

struct RootView: View {

    @EnvironmentObject private var store: LedgerStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @State private var selection: Tab = .home
    @State private var locked = AppLock.isEnabled
    @State private var unlocking = false

    enum Tab: Hashable {
        case home, ledger, assets, budget, settings
    }

    private var reviewBinding: Binding<Bool> {
        Binding(
            get: { !store.pendingDrafts.isEmpty },
            set: { shown in
                if !shown {
                    store.discardAllDrafts()
                }
            }
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selection) {
                HomeView()
                    .tabItem { Label("首页", systemImage: "house.fill") }
                    .tag(Tab.home)

                LedgerListView()
                    .tabItem { Label("账单", systemImage: "list.bullet.rectangle") }
                    .tag(Tab.ledger)

                AssetsView()
                    .tabItem { Label("资产", systemImage: "creditcard") }
                    .tag(Tab.assets)

                BudgetView()
                    .tabItem { Label("预算", systemImage: "target") }
                    .tag(Tab.budget)

                SettingsView()
                    .tabItem { Label("设置", systemImage: "gearshape") }
                    .tag(Tab.settings)
            }
            .tint(Theme.accent)

            if let banner = store.banner {
                Text(banner)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular.tint(Theme.accent.opacity(0.4)), in: .capsule)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .preferredColorScheme(Appearance(rawValue: appearanceRaw)?.colorScheme)
        .animation(.smooth(duration: 0.3), value: store.banner)
        .overlay {
            if locked {
                LockScreenView(isUnlocking: unlocking) {
                    Task { await unlock() }
                }
                .transition(.opacity)
            }
        }
        .sheet(isPresented: reviewBinding) {
            ImportReviewView()
                .environmentObject(store)
        }
        .task {
            await refreshNotifications()
            if locked {
                await unlock()
            }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                store.reloadIfChanged()
                Task {
                    await refreshNotifications()
                }
            case .background:
                if AppLock.isEnabled {
                    locked = true
                }
            default:
                break
            }
        }
        .onChange(of: store.transactions.count) { _ in
            Task {
                await refreshNotifications()
            }
        }
    }

    private func unlock() async {
        guard !unlocking else { return }
        unlocking = true
        let ok = await AppLock.authenticate()
        unlocking = false
        if ok {
            withAnimation(.smooth(duration: 0.25)) { locked = false }
        }
    }

    private func refreshNotifications() async {
        await BudgetNotifier.refresh(plan: store.budgetPlan, today: store.todayBudget)
    }
}
