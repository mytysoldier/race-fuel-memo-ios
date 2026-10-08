import Foundation
import UserNotifications

struct ChecklistReminder: Equatable {
    let identifier: String
    let title: String
    let date: Date
}

struct ChecklistReminderRequest: Equatable {
    let raceName: String
    let reminder: ChecklistReminder
}

enum ChecklistReminderPlanner {
    static func reminders(for plan: RacePlan, now: Date = .now, calendar: Calendar = .current) -> [ChecklistReminder] {
        guard plan.checklistNotificationsEnabled else { return [] }
        return plan.checklistItems.compactMap { item in
            guard item.isRequired, !item.isChecked,
                  let dueDate = item.resolvedDueDate(for: plan, calendar: calendar),
                  dueDate > now else { return nil }
            return ChecklistReminder(
                identifier: "checklist-reminder.\(plan.id.uuidString).\(item.id.uuidString)",
                title: item.title, date: dueDate
            )
        }
        .sorted { $0.date < $1.date }
    }

    static func reminderRequests(
        for plans: [RacePlan],
        maximumCount: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [ChecklistReminderRequest] {
        plans.flatMap { plan in
            reminders(for: plan, now: now, calendar: calendar).map {
                ChecklistReminderRequest(raceName: plan.name, reminder: $0)
            }
        }
        .sorted { $0.reminder.date < $1.reminder.date }
        .prefix(max(0, maximumCount))
        .map { $0 }
    }
}

@MainActor enum ChecklistReminderScheduler {
    private static let checklistIdentifierPrefix = "checklist-reminder."
    private static let maximumPendingNotificationCount = 64
    private static let maximumChecklistReminderCount = 50
    private static let center = UNUserNotificationCenter.current()
    private static var queuedTask: Task<Void, Never>?
    private static var queuedOperationID = 0

    static func requestAuthorization() async throws {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return
        case .notDetermined:
            guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                throw RaceReminderSchedulerError.permissionDenied
            }
        case .denied:
            throw RaceReminderSchedulerError.permissionDenied
        @unknown default:
            throw RaceReminderSchedulerError.permissionDenied
        }
    }

    /// Serialize startup and save-driven updates so the newest saved plans win.
    static func enqueueReconciliation(for plans: [RacePlan]) {
        _ = enqueueReconciliation(for: plans, reservingNotificationSlots: 0)
    }

    /// Reserve slots before another notification flow schedules its requests.
    static func reconcile(
        for plans: [RacePlan],
        reservingNotificationSlots: Int
    ) async {
        let task = enqueueReconciliation(
            for: plans,
            reservingNotificationSlots: reservingNotificationSlots
        )
        await task.value
    }

    @discardableResult
    private static func enqueueReconciliation(
        for plans: [RacePlan],
        reservingNotificationSlots: Int
    ) -> Task<Void, Never> {
        let previous = queuedTask
        queuedOperationID += 1
        let operationID = queuedOperationID
        let task = Task {
            await previous?.value
            await reconcileAll(plans, reservingNotificationSlots: reservingNotificationSlots)
            if queuedOperationID == operationID {
                queuedTask = nil
            }
        }
        queuedTask = task
        return task
    }

    /// Remove notifications for deleted or disabled plans that may have survived an app termination.
    private static func reconcileAll(
        _ plans: [RacePlan],
        reservingNotificationSlots: Int
    ) async {
        let pendingRequests = await center.pendingNotificationRequests()
        let existingChecklistRequests = pendingRequests.filter {
            $0.identifier.hasPrefix(checklistIdentifierPrefix)
        }
        let existingChecklistIDs = Set(existingChecklistRequests.map(\.identifier))
        let existingChecklistRequestsByID = Dictionary(
            uniqueKeysWithValues: existingChecklistRequests.map { ($0.identifier, $0) }
        )
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            center.removePendingNotificationRequests(withIdentifiers: Array(existingChecklistIDs))
            return
        }

        let nonChecklistCount = pendingRequests.count - existingChecklistIDs.count
        let availableCount = min(
            maximumChecklistReminderCount,
            maximumPendingNotificationCount - nonChecklistCount - max(0, reservingNotificationSlots)
        )
        let requests = ChecklistReminderPlanner.reminderRequests(
            for: plans, maximumCount: availableCount
        )

        // Remove current checklist requests first so a template replacement never exceeds iOS's 64-request limit.
        center.removePendingNotificationRequests(withIdentifiers: Array(existingChecklistIDs))
        for request in requests {
            let content = notificationContent(raceName: request.raceName, reminder: request.reminder)
            let trigger = notificationTrigger(for: request.reminder.date)
            do {
                try await center.add(UNNotificationRequest(
                    identifier: request.reminder.identifier, content: content, trigger: trigger
                ))
            } catch {
                // Keep a previously valid request if replacing it fails transiently.
                if let existingRequest = existingChecklistRequestsByID[request.reminder.identifier] {
                    try? await center.add(existingRequest)
                }
            }
        }
    }

    private static func notificationContent(raceName: String, reminder: ChecklistReminder) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "\(raceName)の準備"
        content.body = "必須項目「\(reminder.title)」が未完了です。"
        content.sound = .default
        return content
    }

    private static func notificationTrigger(for date: Date) -> UNCalendarNotificationTrigger {
        UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: date
            ),
            repeats: false
        )
    }
}
