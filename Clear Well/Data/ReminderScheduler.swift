import Foundation
import UserNotifications

/// Schedules local "time to retest" reminders on this phone. Nothing is sent to a server.
enum ReminderScheduler {
    private static let prefix = "clearwell.retest."

    /// Asks permission the first time. Returns true if reminders are allowed.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Replaces all retest reminders with fresh ones based on the saved tests.
    static func reschedule(tests: [WaterTest], enabled: Bool, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })

        guard enabled, !tests.isEmpty else { return }

        for due in TestingSchedule.upcoming(tests: tests, now: now) where due.date > now {
            let content = UNMutableNotificationContent()
            content.title = "Time to test your well"
            content.body = "Your next \(due.contaminant.name.lowercased()) test is due. \(due.contaminant.limit.retest.description) keeps your family's water safe."
            content.sound = .default

            var when = Calendar.current.dateComponents([.year, .month, .day], from: due.date)
            when.hour = 9
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: prefix + due.contaminant.rawValue, content: content, trigger: trigger))
        }
    }

    /// Sends a sample reminder in a few seconds — handy for showing reminders in the demo.
    static func sendSampleReminder(after seconds: TimeInterval = 5) async {
        let content = UNMutableNotificationContent()
        content.title = "Time to test your well"
        content.body = "Your next nitrate test is due. Testing every other year keeps your family's water safe."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: prefix + "sample", content: content, trigger: trigger))
    }
}

/// Shows reminders even while ClearWell is open (useful for the demo).
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
