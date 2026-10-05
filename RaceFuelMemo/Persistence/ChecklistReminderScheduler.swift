import Foundation
import UserNotifications

struct ChecklistReminder: Equatable {
    let identifier: String
    let title: String
    let date: Date
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
        .prefix(50)
        .map { $0 }
    }
}

@MainActor enum ChecklistReminderScheduler {
    private static let center = UNUserNotificationCenter.current()
    private static var latestRevisions: [RacePlan.ID: Int] = [:]
    private static var queuedTasks: [RacePlan.ID: Task<Void, Never>] = [:]

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

    /// Serialize updates for a race so an older save cannot overwrite newer reminder requests.
    static func enqueue(_ plan: RacePlan?, id: RacePlan.ID, revision: Int) {
        guard revision > latestRevisions[id, default: 0] else { return }
        latestRevisions[id] = revision
        let previous = queuedTasks[id]
        queuedTasks[id] = Task {
            await previous?.value
            guard latestRevisions[id] == revision else { return }
            await reconcile(plan, id: id)
        }
    }

    private static func reconcile(_ plan: RacePlan?, id: RacePlan.ID) async {
        let prefix = "checklist-reminder.\(id.uuidString)."
        let existing = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }

        var reminders: [ChecklistReminder] = []
        if let plan, plan.checklistNotificationsEnabled {
            let status = await center.notificationSettings().authorizationStatus
            if status == .authorized || status == .provisional || status == .ephemeral {
                reminders = ChecklistReminderPlanner.reminders(for: plan)
            }
        }

        var scheduledIDs: Set<String> = []
        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = "\(plan?.name ?? "レース")の準備"
            content.body = "必須項目「\(reminder.title)」が未完了です。"
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: reminder.date
                ),
                repeats: false
            )
            do {
                try await center.add(UNNotificationRequest(
                    identifier: reminder.identifier, content: content, trigger: trigger
                ))
                scheduledIDs.insert(reminder.identifier)
            } catch {
                // Do not leave a pending request with stale content when replacement fails.
            }
        }

        center.removePendingNotificationRequests(withIdentifiers: existing.filter { !scheduledIDs.contains($0) })
    }
}
