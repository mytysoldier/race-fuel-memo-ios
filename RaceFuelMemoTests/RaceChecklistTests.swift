import Foundation
import Testing
@testable import RaceFuelMemo

@Test func checklistTemplateCreatesIndependentUncheckedItems() {
    let source = ChecklistItem(title: "ゼッケン", isChecked: true, order: 0,
                               category: ChecklistCategory.registration.rawValue,
                               isRequired: true, dueTiming: .dayBefore)
    let template = ChecklistTemplate(name: "大会準備", items: [source])
    let first = template.checklistItems()
    let second = template.checklistItems()

    #expect(first[0].id != source.id)
    #expect(first[0].id != second[0].id)
    #expect(!first[0].isChecked)
    #expect(first[0].isRequired)
    #expect(first[0].dueTiming == .dayBefore)
}

@Test func checklistTemplateStorePersistsRenameAndDelete() throws {
    let suite = "checklist-template-tests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = ChecklistTemplateStore(defaults: defaults)

    #expect(store.templates.first?.items.count == 10)
    #expect(store.save(name: " マイ準備 ", items: [ChecklistItem(title: "受付")]))
    let id = try #require(store.templates.last?.id)
    #expect(store.rename(id: id, to: "当日用"))
    #expect(ChecklistTemplateStore(defaults: defaults).templates.last?.name == "当日用")
    #expect(store.delete(id: id))
    #expect(ChecklistTemplateStore(defaults: defaults).templates.count == 1)
    #expect(!store.delete(id: ChecklistTemplate.standardID))
}

@Test func checklistReminderPlannerRecalculatesAndSkipsCompletedItems() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 8)))
    var plan = RacePlan(name: "マラソン", raceDate: start, startTime: start,
                        distanceKm: 42.195, targetHours: 4, targetMinutes: 0,
                        gelCount: 0, checklistItems: [
                            ChecklistItem(title: "ゼッケン", isRequired: true, dueTiming: .dayBefore),
                            ChecklistItem(title: "ウォッチ", isRequired: true, dueTiming: .raceMorning),
                            ChecklistItem(title: "任意", isRequired: false, dueTiming: .dayBefore)
                        ], checklistNotificationsEnabled: true)
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 6)))
    let original = ChecklistReminderPlanner.reminders(for: plan, now: now, calendar: calendar)
    #expect(original.map(\.title) == ["ゼッケン", "ウォッチ"])
    #expect(original[0].date == calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 20)))

    plan.checklistItems[0].isChecked = true
    plan.startTime = try #require(calendar.date(byAdding: .day, value: 1, to: start))
    let updated = ChecklistReminderPlanner.reminders(for: plan, now: now, calendar: calendar)
    #expect(updated.count == 1)
    #expect(updated[0].identifier == original[1].identifier)
    #expect(updated[0].date == calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 6)))

    plan.checklistNotificationsEnabled = false
    #expect(ChecklistReminderPlanner.reminders(for: plan, now: now, calendar: calendar).isEmpty)
}

@Test func startupReconciliationRemovesDeletedAndDisabledPlanReminders() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 8)))
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 6)))
    let active = RacePlan(name: "有効", raceDate: start, startTime: start,
                          distanceKm: 10, targetHours: 1, targetMinutes: 0, gelCount: 0,
                          checklistItems: [ChecklistItem(title: "ゼッケン", isRequired: true, dueTiming: .dayBefore)],
                          checklistNotificationsEnabled: true)
    var disabled = active
    disabled.checklistNotificationsEnabled = false
    let activeID = try #require(ChecklistReminderPlanner.reminders(for: active, now: now, calendar: calendar).first?.identifier)
    let disabledID = "checklist-reminder.\(disabled.id.uuidString).\(UUID().uuidString)"
    let deletedID = "checklist-reminder.\(UUID().uuidString).\(UUID().uuidString)"

    let removals = ChecklistReminderPlanner.identifiersToRemove(
        existing: [activeID, disabledID, deletedID], plans: [active, disabled], now: now, calendar: calendar
    )
    #expect(removals == [disabledID, deletedID])
}

@Test func oldChecklistItemKeepsCheckedStateAndUsesSafeDefaults() throws {
    let id = UUID()
    let data = Data("""
    {"id":"\(id.uuidString)","title":"シューズ","isChecked":true,"order":3}
    """.utf8)
    let item = try JSONDecoder().decode(ChecklistItem.self, from: data)
    #expect(item.id == id)
    #expect(item.isChecked)
    #expect(!item.isRequired)
    #expect(item.dueTiming == nil)
}
