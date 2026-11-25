import Foundation
import UserNotifications

public enum NotificationManager {
    private static let dailyGreetingId = "com.chlorme.daily.greeting"

    public static func configureDailyGreeting(
        enabled: Bool,
        characterName: String,
        hour: Int,
        minute: Int
    ) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [dailyGreetingId])
        guard enabled else { return }

        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = characterName
        content.body = "今天过得怎么样？忙完的话，来和我说说话呀。"
        content.sound = .default

        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: dailyGreetingId, content: content, trigger: trigger)
        try? await center.add(request)
    }
}
