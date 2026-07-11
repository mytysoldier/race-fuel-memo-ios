import Foundation
import UserNotifications

enum RaceReminderScheduler {
    private static let notificationCenter = UNUserNotificationCenter.current()
    private static let registrationLock = NSLock()
    private static var activeRegistrationTokens: [RacePlan.ID: UUID] = [:]
    private static var cancelledRegistrationTokens: Set<UUID> = []

    static func requestAuthorizationAndSchedule(
        for racePlan: RacePlan,
        timings: Set<RaceReminderTiming> = Set(RaceReminderTiming.allCases)
    ) async throws -> Int {
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

            let requests = notificationRequests(for: racePlan, timings: timings)

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
            try validateRegistration(for: racePlan.id, token: registrationToken)
            try Task.checkCancellation()

            guard finishRegistration(for: racePlan.id, token: registrationToken) else {
                throw CancellationError()
            }
            return requests.count
        } catch RaceReminderSchedulerError.permissionDenied {
            finishRegistration(for: racePlan.id, token: registrationToken)
            throw RaceReminderSchedulerError.permissionDenied
        } catch {
            await rollbackRegistration(
                for: racePlan.id,
                token: registrationToken,
                existingRequests: existingRequests
            )
            throw error
        }
    }

    static func pendingReminderDates(for racePlanID: RacePlan.ID) async -> [Date] {
        await notificationCenter.pendingNotificationRequests()
            .filter { notificationIdentifiers(for: racePlanID).contains($0.identifier) }
            .compactMap { ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() }
            .sorted()
    }

    static func pendingReminderTimings(for racePlanID: RacePlan.ID) async -> Set<RaceReminderTiming> {
        let pendingIdentifiers = Set(
            await notificationCenter.pendingNotificationRequests().map(\.identifier)
        )

        return Set(RaceReminderTiming.allCases.filter { timing in
            pendingIdentifiers.contains(
                notificationIdentifier(for: racePlanID, suffix: timing.notificationIdentifierSuffix)
            )
        })
    }

    static func cancelReminders(for racePlanID: RacePlan.ID) {
        registrationLock.lock()
        if let activeRegistrationToken = activeRegistrationTokens[racePlanID] {
            cancelledRegistrationTokens.insert(activeRegistrationToken)
        }
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
        let wasExplicitlyCancelled = activeToken != token && cancelledRegistrationTokens.remove(token) != nil
        registrationLock.unlock()

        guard activeToken == token else {
            if wasExplicitlyCancelled {
                notificationCenter.removePendingNotificationRequests(withIdentifiers: notificationIdentifiers(for: racePlanID))
            }

            throw CancellationError()
        }
    }

    private static func notificationRequests(
        for racePlan: RacePlan,
        timings: Set<RaceReminderTiming>,
        now: Date = .now
    ) -> [UNNotificationRequest] {
        reminderDates(for: racePlan, timings: timings)
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

    private static func reminderDates(
        for racePlan: RacePlan,
        timings: Set<RaceReminderTiming>
    ) -> [(identifier: String, date: Date, body: String)] {
        let calendar = Calendar.current
        let startDate = racePlan.startTime
        let dayBefore = calendar.date(byAdding: .day, value: -1, to: startDate)
            .flatMap { calendar.date(bySettingHour: 20, minute: 0, second: 0, of: $0) }

        let reminders: [(RaceReminderTiming, String, Date?, String)] = [
            (.dayBefore, "day-before", dayBefore, String(localized: "notification.body.day_before")),
            (.twoHoursBefore, "two-hours-before", calendar.date(byAdding: .hour, value: -2, to: startDate), String(localized: "notification.body.two_hours_before")),
            (.thirtyMinutesBefore, "thirty-minutes-before", calendar.date(byAdding: .minute, value: -30, to: startDate), String(localized: "notification.body.thirty_minutes_before"))
        ]

        return reminders.filter { timings.contains($0.0) }.compactMap { _, suffix, date, body in
            let identifier = notificationIdentifier(for: racePlan.id, suffix: suffix)
            return date.map { (identifier, $0, body) }
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

enum RaceReminderTiming: String, CaseIterable, Identifiable {
    case dayBefore
    case twoHoursBefore
    case thirtyMinutesBefore

    var id: String { rawValue }

    fileprivate var notificationIdentifierSuffix: String {
        switch self {
        case .dayBefore: "day-before"
        case .twoHoursBefore: "two-hours-before"
        case .thirtyMinutesBefore: "thirty-minutes-before"
        }
    }

    var label: String {
        switch self {
        case .dayBefore: "前日 20:00"
        case .twoHoursBefore: "スタート2時間前"
        case .thirtyMinutesBefore: "スタート30分前"
        }
    }
}

enum RaceReminderSchedulerError: LocalizedError {
    case permissionDenied

    var errorDescription: String? {
        String(localized: "notification.error.permission_denied")
    }
}
