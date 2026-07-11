import Foundation
import UserNotifications

enum RaceReminderScheduler {
    private static let notificationCenter = UNUserNotificationCenter.current()
    private static let registrationLock = NSLock()
    private static var activeRegistrationTokens: [RacePlan.ID: UUID] = [:]

    static func requestAuthorizationAndSchedule(for racePlan: RacePlan) async throws -> Int {
        let registrationToken = beginRegistration(for: racePlan.id)
        let reminderIdentifiers = notificationIdentifiers(for: racePlan.id)
        let existingRequests = await notificationCenter.pendingNotificationRequests()
            .filter { reminderIdentifiers.contains($0.identifier) }

        do {
            let settings = await notificationCenter.notificationSettings()
            try validateRegistration(for: racePlan.id, token: registrationToken)
            try Task.checkCancellation()

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
                try validateRegistration(for: racePlan.id, token: registrationToken)
                try Task.checkCancellation()
                try await notificationCenter.add(request)
                try validateRegistration(for: racePlan.id, token: registrationToken)
                try Task.checkCancellation()
            }

            try validateRegistration(for: racePlan.id, token: registrationToken)
            try Task.checkCancellation()
            let requestIdentifiers = Set(requests.map(\.identifier))
            let staleIdentifiers = reminderIdentifiers.filter { !requestIdentifiers.contains($0) }
            notificationCenter.removePendingNotificationRequests(withIdentifiers: staleIdentifiers)

            guard finishRegistration(for: racePlan.id, token: registrationToken) else {
                throw CancellationError()
            }
            return requests.count
        } catch {
            await rollbackRegistration(
                for: racePlan.id,
                token: registrationToken,
                existingRequests: existingRequests
            )
            throw error
        }
    }

    static func cancelReminders(for racePlanID: RacePlan.ID) {
        registrationLock.lock()
        activeRegistrationTokens[racePlanID] = nil
        registrationLock.unlock()
        notificationCenter.removePendingNotificationRequests(withIdentifiers: notificationIdentifiers(for: racePlanID))
    }

    private static func beginRegistration(for racePlanID: RacePlan.ID) -> UUID {
        let token = UUID()
        registrationLock.lock()
        activeRegistrationTokens[racePlanID] = token
        registrationLock.unlock()
        return token
    }

    private static func finishRegistration(for racePlanID: RacePlan.ID, token: UUID) -> Bool {
        registrationLock.lock()
        defer { registrationLock.unlock() }

        guard activeRegistrationTokens[racePlanID] == token else {
            return false
        }

        activeRegistrationTokens[racePlanID] = nil
        return true
    }

    private static func rollbackRegistration(
        for racePlanID: RacePlan.ID,
        token: UUID,
        existingRequests: [UNNotificationRequest]
    ) async {
        registrationLock.lock()
        let shouldRollback = activeRegistrationTokens[racePlanID] == token
        if shouldRollback {
            activeRegistrationTokens[racePlanID] = nil
        }
        registrationLock.unlock()

        guard shouldRollback else {
            return
        }

        notificationCenter.removePendingNotificationRequests(withIdentifiers: notificationIdentifiers(for: racePlanID))
        for request in existingRequests {
            try? await notificationCenter.add(request)
        }
    }

    private static func validateRegistration(for racePlanID: RacePlan.ID, token: UUID) throws {
        registrationLock.lock()
        let activeToken = activeRegistrationTokens[racePlanID]
        registrationLock.unlock()

        guard activeToken == token else {
            if activeToken == nil {
                notificationCenter.removePendingNotificationRequests(withIdentifiers: notificationIdentifiers(for: racePlanID))
            }

            throw CancellationError()
        }
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
