import Foundation
import Testing
@testable import RaceFuelMemo

private func fuelingRace() -> RacePlan {
    RacePlan(
        name: "補給テスト", raceDate: Date(timeIntervalSinceReferenceDate: 10_000),
        startTime: Date(timeIntervalSinceReferenceDate: 10_000),
        distanceKm: 20, targetHours: 2, targetMinutes: 0, gelCount: 0
    )
}

@Test func fuelingEventsFollowCheckpointScheduleAndElapsedTime() {
    var plan = fuelingRace()
    let checkpoint = RaceCheckpoint(order: 0, name: "10km給水", distanceKm: 10,
                                    plannedElapsedSeconds: 4_500, kind: .aidStation)
    plan.checkpoints = [checkpoint]
    plan.fuelingEvents = [
        RaceFuelingEvent(order: 0, name: "A", quantity: 1, distanceKm: 5),
        RaceFuelingEvent(order: 1, name: "B", quantity: 1, elapsedSeconds: 3_600),
        RaceFuelingEvent(order: 2, name: "C", quantity: 1,
                         distanceKm: 10, checkpointID: checkpoint.id)
    ]

    #expect(RaceCheckpointValidator.error(for: plan) == nil)
    let schedule = RaceFuelingPlanCalculator.schedule(for: plan)
    #expect(schedule.map(\.elapsedSeconds) == [2_250, 3_600, 4_500])
    #expect(abs(schedule[1].distanceKm - 8) < 0.001)
    #expect(schedule[2].checkpointName == "10km給水")
    #expect(schedule[2].passingTime == plan.startTime.addingTimeInterval(4_500))
}

@Test func fuelingDistanceFollowsSelectedPacePlan() {
    var plan = fuelingRace()
    let pace = RacePacePlan(order: 0, name: "後半加速", targetSeconds: 7_200,
                            strategy: .negative, halfDifferenceSeconds: 600)
    plan.pacePlans = [pace]
    plan.selectedPacePlanID = pace.id
    plan.normalizePacePlans()
    plan.fuelingEvents = [RaceFuelingEvent(order: 0, name: "ジェル", quantity: 1, distanceKm: 10)]

    #expect(RaceFuelingPlanCalculator.schedule(for: plan)[0].elapsedSeconds == 3_900)
}

@Test func removingOrMovingCheckpointKeepsFuelingLocationUsable() {
    var plan = fuelingRace()
    let checkpoint = RaceCheckpoint(order: 0, name: "給水所", distanceKm: 10, kind: .aidStation)
    plan.checkpoints = [checkpoint]
    plan.fuelingEvents = [RaceFuelingEvent(order: 0, name: "ドリンク", quantity: 1,
                                          checkpointID: checkpoint.id, kind: .drink)]

    plan.normalizeFuelingEvents()
    #expect(plan.fuelingEvents[0].distanceKm == 10)
    plan.checkpoints[0].distanceKm = 12
    plan.normalizeFuelingEvents()
    #expect(plan.fuelingEvents[0].distanceKm == 12)
    plan.checkpoints = []
    plan.normalizeFuelingEvents()
    #expect(plan.fuelingEvents[0].checkpointID == nil)
    #expect(plan.fuelingEvents[0].distanceKm == 12)
    #expect(RaceFuelingPlanCalculator.validationError(for: plan) == nil)
    #expect(RaceFuelingPlanCalculator.schedule(for: plan)[0].distanceKm == 12)
}

@Test func fuelingRequirementsAndValidation() {
    var plan = fuelingRace()
    plan.fuelingEvents = [
        RaceFuelingEvent(order: 0, name: " Gel A ", quantity: 2, distanceKm: 5,
                         carbohydrateGramsPerItem: 25),
        RaceFuelingEvent(order: 1, name: "gel a", quantity: 3, distanceKm: 10),
        RaceFuelingEvent(order: 2, name: "Gel A", quantity: 1, distanceKm: 15, kind: .drink)
    ]

    #expect(RaceFuelingPlanCalculator.validationError(for: plan) == nil)
    let requirements = RaceFuelingPlanCalculator.requirements(for: plan.fuelingEvents)
    #expect(requirements.count == 2)
    #expect(requirements.first(where: { $0.kind == .gel })?.quantity == 5)
    #expect(requirements.first(where: { $0.kind == .drink })?.quantity == 1)

    plan.fuelingEvents[0].quantity = 0
    #expect(RaceFuelingPlanCalculator.validationError(for: plan) != nil)
    plan.fuelingEvents[0].quantity = 2
    plan.fuelingEvents[0].carbohydrateGramsPerItem = .nan
    #expect(RaceFuelingPlanCalculator.validationError(for: plan) != nil)
    plan.fuelingEvents[0].carbohydrateGramsPerItem = 25
    plan.fuelingEvents[0].distanceKm = 21
    #expect(RaceFuelingPlanCalculator.validationError(for: plan) != nil)
}

@Test func legacyGelsCanBecomeIndependentFuelingEvents() {
    var plan = fuelingRace()
    plan.gelCount = 2
    plan.gelNames = ["A", "B"]

    let events = RaceFuelingPlanCalculator.initialEvents(for: plan)
    #expect(events.count == 2)
    #expect(events.map(\.name) == ["A", "B"])
    #expect(events.allSatisfy { $0.quantity == 1 && $0.distanceKm != nil })
    plan.fuelingEvents = events
    plan.gelCount = 0
    plan.gelNames = []
    #expect(RaceFuelingPlanCalculator.initialEvents(for: plan) == events)
}

@Test func presetAppliesToAnotherRaceAndKeepsOriginalIndependent() throws {
    var source = fuelingRace()
    let checkpoint = RaceCheckpoint(order: 0, name: "給水所", distanceKm: 10, kind: .aidStation)
    source.checkpoints = [checkpoint]
    source.fuelingEvents = [
        RaceFuelingEvent(order: 0, name: "ジェル", quantity: 2,
                         distanceKm: 10, checkpointID: checkpoint.id,
                         carbohydrateGramsPerItem: 20, containsCaffeine: true,
                         pickup: .dropBag),
        RaceFuelingEvent(order: 1, name: "ドリンク", quantity: 1,
                         elapsedSeconds: 3_600, kind: .drink)
    ]
    let preset = RaceFuelingPreset(name: "いつもの補給", plan: source)
    var destination = fuelingRace()
    destination.distanceKm = 10
    destination.targetHours = 1
    destination.fuelingEvents = preset.events(for: destination)

    #expect(destination.fuelingEvents.map(\.distanceKm).first! == 5)
    #expect(destination.fuelingEvents[0].checkpointID == nil)
    #expect(destination.fuelingEvents[1].elapsedSeconds == 1_800)
    #expect(destination.fuelingEvents[0].id != source.fuelingEvents[0].id)
    #expect(RaceFuelingPlanCalculator.validationError(for: destination) == nil)
    destination.fuelingEvents[0].name = "変更品"
    #expect(source.fuelingEvents[0].name == "ジェル")
    #expect(preset.events[0].name == "ジェル")

    let suite = "RaceFuelingPresetTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = RaceFuelingPresetStore(defaults: defaults)
    #expect(store.save(preset))
    #expect(RaceFuelingPresetStore(defaults: defaults).presets == [preset])
    #expect(store.delete(id: preset.id))
    #expect(store.presets.isEmpty)
    #expect(source.fuelingEvents[0].name == "ジェル")
}

@Test func earlierFuelingEventDecodesWithSafeDefaults() throws {
    let data = Data("""
        {"id":"00000000-0000-0000-0000-000000000001","order":0,
         "name":"旧ジェル","quantity":1,"distanceKm":5}
        """.utf8)
    let event = try JSONDecoder().decode(RaceFuelingEvent.self, from: data)
    #expect(event.kind == .gel)
    #expect(event.pickup == .carry)
    #expect(event.carbohydrateGramsPerItem == nil)
    #expect(!event.containsCaffeine)
}
