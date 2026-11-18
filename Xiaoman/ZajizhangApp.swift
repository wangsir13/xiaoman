import SwiftUI

@main
struct XiaomanApp: App {

    @StateObject private var store = LedgerStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .onOpenURL { url in
                    DeepLink.handle(url, store: store)
                }
        }
    }
}
