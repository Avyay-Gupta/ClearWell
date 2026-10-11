import SwiftUI
import UserNotifications

@main
struct ClearWellApp: App {
    @State private var store: WaterStore
    @State private var router: AppRouter
    @State private var localWater = LocalWaterStore()
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
                .environment(localWater)
        }
    }
}

enum AppTab: Hashable {
    case home, quality, conserve, community, help
}

/// Shared navigation state, so one screen can send the user to another tab.
@Observable
final class AppRouter {
    var tab: AppTab = .home
    var qualityPath: [QualityRoute] = []

    /// Opens the Water Quality tab on the "Add a water test" screen.
    func showAddResults() {
        qualityPath = [.add]
        tab = .quality
    }
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
            // Retest reminders follow MDH's private-well schedule.
            let enabled = store.settings.remindersOn && store.currentProfile.hasPrivateWell
            await ReminderScheduler.reschedule(tests: store.tests, enabled: enabled)
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
            Tab("Water Quality", systemImage: "testtube.2", value: AppTab.quality) {
                WaterQualityView()
            }
            Tab("Conserve", systemImage: "gauge.with.dots.needle.33percent", value: AppTab.conserve) {
                ConserveView()
            }
            Tab("Community", systemImage: "person.3.fill", value: AppTab.community) {
                CommunityView()
            }
            Tab("Get Help", systemImage: "phone.fill", value: AppTab.help) {
                GetHelpView()
            }
        }
    }
}
