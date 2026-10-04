import SwiftUI
import UserNotifications

@main
struct ClearWellApp: App {
    @State private var store: WaterStore
    @State private var router: AppRouter
    private let notificationPresenter = NotificationPresenter()

    init() {
        let store = WaterStore()
        let router = AppRouter()
        #if DEBUG
        LaunchOptions.apply(to: router, store: store)
        #endif
        _store = State(initialValue: store)
        _router = State(initialValue: router)
        UNUserNotificationCenter.current().delegate = notificationPresenter
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
        }
    }
}

enum AppTab: Hashable {
    case home, add, history, help
}

/// Shared navigation state, so one screen can send the user to another tab.
@Observable
final class AppRouter {
    var tab: AppTab = .home
    var addPath: [AddRoute] = []
}

struct RootView: View {
    @Environment(WaterStore.self) private var store

    var body: some View {
        Group {
            if store.profile == nil {
                OnboardingView()
                    .transition(.opacity)
            } else {
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: store.profile == nil)
        .task(id: store.tests) {
            await ReminderScheduler.reschedule(tests: store.tests, enabled: store.settings.remindersOn)
        }
    }
}

struct MainTabView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Home", systemImage: "drop.fill", value: AppTab.home) {
                HomeView()
            }
            Tab("Add Results", systemImage: "plus.circle.fill", value: AppTab.add) {
                AddResultsView()
            }
            Tab("History", systemImage: "chart.xyaxis.line", value: AppTab.history) {
                HistoryView()
            }
            Tab("Get Help", systemImage: "phone.fill", value: AppTab.help) {
                GetHelpView()
            }
        }
    }
}
