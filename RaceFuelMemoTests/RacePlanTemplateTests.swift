import Foundation
import Testing
@testable import RaceFuelMemo

@Test func duplicateRemapsEveryIdentityAndKeepsSourceIndependent() throws {
    let source = reusableRaceFixture()
    let originalFirstSegment = source.pacePlans[0].segments[0]
    var duplicate = source.duplicated()
    let second = source.duplicated()
    #expect(duplicate.id != source.id)
    #expect(duplicate.id != second.id)
    #expect(Set(allReuseIDs(duplicate)).isDisjoint(with: allReuseIDs(source)))
    #expect(Set(allReuseIDs(duplicate)).isDisjoint(with: allReuseIDs(second)))
    #expect(duplicate.selectedPacePlanID == duplicate.pacePlans[0].id)
    #expect(duplicate.fuelingEvents[0].checkpointID == duplicate.checkpoints[0].id)
    #expect(!duplicate.checklistItems[0].isChecked)
    #expect(!duplicate.checklistNotificationsEnabled)
    #expect(duplicate.checklistItems[1].dueDate == source.checklistItems[1].dueDate)
    #expect(duplicate.checkpoints[0].cutoffTime == source.checkpoints[0].cutoffTime)
    #expect(duplicate.raceDate == source.raceDate)
    #expect(duplicate.memo == source.memo)
    #expect(RaceCheckpointValidator.error(for: duplicate) == nil)

    duplicate.checkpoints[0].name = "別の給水所"
    duplicate.pacePlans[0].segments[0].targetSeconds += 20
    duplicate.fuelingEvents[0].name = "新しいジェル"
    duplicate.checklistItems[0].title = "別の持ち物"
    #expect(source.checkpoints[0].name == "固有の給水所")
    #expect(source.pacePlans[0].segments[0] == originalFirstSegment)
    #expect(source.fuelingEvents[0].name == "ジェル")
    #expect(source.checklistItems[0].title == "シューズ")
}

@Test func duplicateEditsPersistWithoutChangingOriginalRace() throws {
    let suite = "plan-duplicate-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let storage = UserDefaultsRacePlanStorage(userDefaults: defaults)
    let store = RacePlanStore(storage: storage)
    let source = reusableRaceFixture()
    #expect(store.addRacePlan(source))
    let savedSource = try #require(store.racePlans.first)
    var duplicate = savedSource.duplicated()
    #expect(store.addRacePlan(duplicate))
    duplicate.memo = "複製後のメモ"
    duplicate.checklistItems[0].isChecked = true
    #expect(store.updateRacePlan(duplicate))
    let reloaded = try storage.loadRacePlans()
    #expect(reloaded.count == 2)
    #expect(reloaded[0] == savedSource)
    #expect(reloaded[1] == duplicate)
}

@Test func templateOmitsRaceSpecificInformationAndConvertsCheckpointFueling() throws {
    let source = reusableRaceFixture()
    let template = RacePlanTemplate(name: "10km設定", source: source)
    let encoded = try JSONEncoder().encode(template)
    let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    for key in ["raceDate", "startTime", "memo", "checkpoints", "checklistNotificationsEnabled"] {
        #expect(json[key] == nil)
    }
    let text = try #require(String(data: encoded, encoding: .utf8))
    #expect(!text.contains(source.name))
    #expect(!text.contains("固有の給水所"))
    #expect(!text.contains("dueDate"))
    #expect(!text.contains("isChecked"))
    #expect(template.fuelingEvents[0].checkpointID == nil)
    #expect(template.fuelingEvents[0].distanceKm == 5)
    #expect(template.fuelingEvents[0].elapsedSeconds == nil)

    let destination = basicReuseDestination(distance: 10)
    let applied = try template.applying(to: destination, components: Set(RacePlanReuseComponent.allCases))
    let another = try template.applying(to: destination, components: Set(RacePlanReuseComponent.allCases))
    #expect(applied.id == destination.id)
    #expect(applied.name == destination.name)
    #expect(applied.raceDate == destination.raceDate)
    #expect(applied.startTime == destination.startTime)
    #expect(applied.memo == destination.memo)
    #expect(applied.checkpoints == destination.checkpoints)
    #expect(applied.selectedPacePlanID == applied.pacePlans[0].id)
    #expect(!applied.checklistItems[0].isChecked)
    #expect(applied.checklistItems[0].dueTiming == .dayBefore)
    #expect(applied.checklistItems[1].dueDate == nil)
    #expect(!applied.checklistNotificationsEnabled)
    #expect(Set(allReuseIDs(applied).dropFirst()).isDisjoint(with: allReuseIDs(source)))
    #expect(applied.pacePlans[0].id != another.pacePlans[0].id)
    #expect(applied.checklistItems[0].id != another.checklistItems[0].id)
    #expect(RaceFuelingPlanCalculator.schedule(for: applied).first?.distanceKm == 5)
}

@Test func partialReusePreservesUnselectedSettingsAndRejectsIncompatibleDistance() throws {
    let source = reusableRaceFixture()
    let template = RacePlanTemplate(name: "設定", source: source)
    let destination = basicReuseDestination(distance: 21.0975)
    let itemsOnly = try template.applying(to: destination, components: [.checklist])
    #expect(itemsOnly.distanceKm == destination.distanceKm)
    #expect(itemsOnly.targetHours == destination.targetHours)
    #expect(itemsOnly.pacePlans == destination.pacePlans)
    #expect(itemsOnly.fuelingEvents == destination.fuelingEvents)
    #expect(itemsOnly.gelNames == destination.gelNames)
    #expect(itemsOnly.checkpoints == destination.checkpoints)
    #expect(throws: RacePlanReuseError.self) {
        try template.applying(to: destination, components: [.pace])
    }
    #expect(throws: RacePlanReuseError.self) {
        try template.applying(to: destination, components: [.fueling])
    }
    let matching = basicReuseDestination(distance: 10)
    let paceOnly = try template.applying(to: matching, components: [.pace])
    #expect(paceOnly.checklistItems == matching.checklistItems)
    #expect(paceOnly.gelNames == matching.gelNames)
    let fuelOnly = try template.applying(to: matching, components: [.fueling])
    #expect(fuelOnly.pacePlans == matching.pacePlans)
    #expect(fuelOnly.checklistItems == matching.checklistItems)
    #expect(fuelOnly.fuelingEvents[0].checkpointID == nil)
}

@Test func planTemplateStorePersistsCreationRenameApplicationAndDeletion() throws {
    let suite = "plan-templates-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = RacePlanTemplateStore(defaults: defaults)
    #expect(!store.save(name: "  ", source: reusableRaceFixture()))
    #expect(store.save(name: " マイ10km ", source: reusableRaceFixture()))
    let saved = try #require(store.templates.first)
    #expect(saved.name == "マイ10km")
    #expect(!store.rename(id: saved.id, to: "\n"))
    #expect(store.rename(id: saved.id, to: " 当日用 "))
    let reloaded = RacePlanTemplateStore(defaults: defaults)
    let template = try #require(reloaded.templates.first)
    #expect(template.id == saved.id)
    #expect(template.name == "当日用")
    let applied = try template.applying(to: basicReuseDestination(distance: 10), components: [.fueling, .checklist])
    #expect(applied.fuelingEvents.count == 1)
    #expect(applied.checklistItems.count == 2)
    #expect(reloaded.delete(id: template.id))
    #expect(RacePlanTemplateStore(defaults: defaults).templates.isEmpty)
}

@Test func corruptPlanTemplateDataIsNotOverwritten() throws {
    let suite = "bad-plan-templates-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let original = Data("broken".utf8)
    defaults.set(original, forKey: RacePlanTemplateStore.storageKey)
    let store = RacePlanTemplateStore(defaults: defaults)
    #expect(store.error != nil)
    #expect(!store.save(name: "新規", source: reusableRaceFixture()))
    #expect(defaults.data(forKey: RacePlanTemplateStore.storageKey) == original)
}

private func reusableRaceFixture() -> RacePlan {
    let start = Date(timeIntervalSince1970: 1_900_000_000)
    let checkpoint = RaceCheckpoint(order: 0, name: "固有の給水所", distanceKm: 5,
                                    cutoffTime: start.addingTimeInterval(3_000), kind: .aidStation)
    let pace = RacePacePlanCalculator.normalized(
        RacePacePlan(order: 0, name: "A目標", targetSeconds: 3_600,
                     strategy: .negative, halfDifferenceSeconds: 120),
        raceDistanceKm: 10, checkpoints: [checkpoint])
    return RacePlan(name: "固有の大会名", raceDate: start, startTime: start,
                    distanceKm: 10, targetHours: 1, targetMinutes: 0,
                    gelCount: 1, gelNames: ["旧ジェル"], memo: "大会固有メモ",
                    checklistItems: [
                        ChecklistItem(title: "シューズ", isChecked: true, order: 0,
                                      isRequired: true, dueTiming: .dayBefore),
                        ChecklistItem(title: "受付", isChecked: true, order: 1,
                                      dueDate: start.addingTimeInterval(-86_400))
                    ], checklistNotificationsEnabled: true,
                    checkpoints: [checkpoint], pacePlans: [pace], selectedPacePlanID: pace.id,
                    fuelingEvents: [RaceFuelingEvent(order: 0, name: "ジェル", quantity: 2,
                                                     elapsedSeconds: 100, checkpointID: checkpoint.id)])
}

private func basicReuseDestination(distance: Double) -> RacePlan {
    RacePlan(name: "次回レース", raceDate: .distantFuture, startTime: .distantFuture,
             distanceKm: distance, targetHours: 2, targetMinutes: 0,
             gelCount: 2, gelNames: ["新ジェル1", "新ジェル2"], memo: "次回メモ")
}

private func allReuseIDs(_ plan: RacePlan) -> [UUID] {
    [plan.id] + plan.checkpoints.map(\.id) + plan.pacePlans.map(\.id)
        + plan.pacePlans.flatMap { $0.segments.map(\.id) }
        + plan.fuelingEvents.map(\.id) + plan.checklistItems.map(\.id)
}
