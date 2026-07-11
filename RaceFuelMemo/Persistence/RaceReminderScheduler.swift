import Foundation
import UserNotifications

enum RaceReminderScheduler {
    private static let notificationCenter = UNUserNotificationCenter.current()

    static func requestAuthorizationAndSchedule(for racePlan: RacePlan) async throws -> Int {
        let settings = await notificationCenter.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        case .notDetermined:
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else {
                throw RaceReminderSchedulerError.permissionDenied
            }
        case .denied:
            throw RaceReminderSchedulerError.permissionDenied
        @unknown default:
            throw RaceReminderSchedulerError.permissionDenied
        }

        let requests = notificationRequests(for: racePlan)

        for request in requests {
            try await notificationCenter.add(request)
        }

        let requestIdentifiers = Set(requests.map(\.identifier))
        let staleIdentifiers = notificationIdentifiers(for: racePlan.id)
            .filter { !requestIdentifiers.contains($0) }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: staleIdentifiers)

        return requests.count
    }

    static func cancelReminders(for racePlanID: RacePlan.ID) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: notificationIdentifiers(for: racePlanID))
    }

    private static func notificationRequests(for racePlan: RacePlan, now: Date = .now) -> [UNNotificationRequest] {
        reminderDates(for: racePlan)
            .filter { $0.date > now }
            .map { reminder in
                let content = UNMutableNotificationContent()
                content.title = String(localized: "notification.title")
                content.body = reminder.body
                content.sound = .default

                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: Calendar.current.dateComponents(
                        [.year, .month, .day, .hour, .minute],
                        from: reminder.date
                    ),
                    repeats: false
                )

                return UNNotificationRequest(
                    identifier: reminder.identifier,
                    content: content,
                    trigger: trigger
                )
            }
    }

    private static func reminderDates(for racePlan: RacePlan) -> [(identifier: String, date: Date, body: String)] {
        let calendar = Calendar.current
        let startDate = racePlan.startTime
        let dayBefore = calendar.date(byAdding: .day, value: -1, to: startDate)
            .flatMap { calendar.date(bySettingHour: 20, minute: 0, second: 0, of: $0) }

        return [
            (identifier: notificationIdentifier(for: racePlan.id, suffix: "day-before"), date: dayBefore, body: String(localized: "notification.body.day_before")),
            (identifier: notificationIdentifier(for: racePlan.id, suffix: "two-hours-before"), date: calendar.date(byAdding: .hour, value: -2, to: startDate), body: String(localized: "notification.body.two_hours_before")),
            (identifier: notificationIdentifier(for: racePlan.id, suffix: "thirty-minutes-before"), date: calendar.date(byAdding: .minute, value: -30, to: startDate), body: String(localized: "notification.body.thirty_minutes_before"))
        ].compactMap { identifier, date, body in
            date.map { (identifier, $0, body) }
        }
    }

    private static func notificationIdentifiers(for racePlanID: RacePlan.ID) -> [String] {
        ["day-before", "two-hours-before", "thirty-minutes-before"].map {
            notificationIdentifier(for: racePlanID, suffix: $0)
        }
    }

    private static func notificationIdentifier(for racePlanID: RacePlan.ID, suffix: String) -> String {
        "race-reminder.\(racePlanID.uuidString).\(suffix)"
    }
}

enum RaceReminderSchedulerError: LocalizedError {
    case permissionDenied

    var errorDescription: String? {
        String(localized: "notification.error.permission_denied")
    }
}
