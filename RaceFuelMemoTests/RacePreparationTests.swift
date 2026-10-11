import XCTest

@testable import RaceFuelMemo

final class RacePreparationTests: XCTestCase {
    private func plan() -> RacePlan {
        RacePlan(
            name: "Race", raceDate: Date(), startTime: Date(timeIntervalSince1970: 100000),
            distanceKm: 20, targetHours: 2, targetMinutes: 0, gelCount: 1)
    }

    private func draft() -> RaceCreationDraft {
        let race = plan()
        return RaceCreationDraft(
            id: race.id, name: "  unfinished  ", raceDate: race.raceDate,
            startTime: race.startTime, distanceKm: 20, usesCustomDistance: true,
            customDistanceKm: -3,
            targetHours: 0, targetMinutes: 0, gelNames: ["  "], memo: " raw memo ",
            checkpoints: [RaceCheckpoint(order: 0, name: "", distanceKm: -1)],
            pacePlans: [RacePacePlan(order: 0, name: "unfinished", targetSeconds: 0)],
            selectedPacePlanID: nil, fuelingEvents: [], checklistItems: race.checklistItems,
            checklistNotificationsEnabled: false, step: .fueling, isGuided: false)
    }

    func testBasicPlanCanOutputWithoutAdvancedFeatures() {
        let preparation = RacePreparation(plan: plan())
        XCTAssertEqual(preparation.statuses.map(\.step), RacePreparationStep.allCases)
        XCTAssertEqual(preparation.statuses.last?.state, .ready)
        XCTAssertEqual(preparation.nextStep, .output)
        XCTAssertEqual(preparation.statuses.first { $0.step == .checkpoints }?.state, .unset)
    }

    func testWarningsUseSelectedPaceAndDoNotBlockOutput() {
        var race = plan()
        let fast = RacePacePlan(order: 0, name: "Fast", targetSeconds: 3600)
        let slow = RacePacePlan(order: 1, name: "Slow", targetSeconds: 7200)
        race.pacePlans = [fast, slow]
        race.selectedPacePlanID = slow.id
        race.normalizePacePlans()
        race.checkpoints = [
            RaceCheckpoint(
                order: 0, name: "Gate", distanceKm: 10,
                cutoffTime: race.startTime.addingTimeInterval(2700), kind: .cutoff)
        ]
        race.gelCount = 0
        race.checklistItems = [ChecklistItem(title: "Shoes", isRequired: true)]
        var preparation = RacePreparation(plan: race)
        XCTAssertEqual(preparation.statuses.first { $0.step == .checkpoints }?.state, .attention)
        XCTAssertTrue(
            preparation.statuses.first { $0.step == .checkpoints }!.detail.contains("Gate"))
        XCTAssertEqual(preparation.statuses.first { $0.step == .fueling }?.state, .unset)
        XCTAssertEqual(preparation.statuses.first { $0.step == .checklist }?.state, .attention)
        XCTAssertEqual(preparation.statuses.last?.state, .ready)
        race.selectedPacePlanID = fast.id
        race.checklistItems[0].isChecked = true
        preparation = RacePreparation(plan: race)
        XCTAssertEqual(preparation.statuses.first { $0.step == .checkpoints }?.state, .ready)
        XCTAssertEqual(preparation.statuses.first { $0.step == .checklist }?.state, .ready)
    }

    func testFuelingErrorDoesNotHideCutoffWarning() {
        var race = plan()
        race.checkpoints = [
            RaceCheckpoint(
                order: 0, name: "Gate", distanceKm: 10,
                cutoffTime: race.startTime.addingTimeInterval(1800), kind: .cutoff)
        ]
        race.fuelingEvents = [RaceFuelingEvent(order: 0, name: "Gel", quantity: 1, distanceKm: 30)]
        let preparation = RacePreparation(plan: race)
        XCTAssertEqual(preparation.statuses.first { $0.step == .fueling }?.state, .attention)
        XCTAssertTrue(
            preparation.statuses.first { $0.step == .checkpoints }!.detail.contains("関門超過"))
        XCTAssertEqual(preparation.statuses.last?.state, .unset)
    }

    func testMissingNameOrInvalidDistanceCannotOutput() {
        var race = plan()
        race.name = " \n "
        XCTAssertEqual(RacePreparation(plan: race).nextStep, .basic)
        XCTAssertEqual(RacePreparation(plan: race).statuses.last?.state, .unset)
        race.name = "Race"
        race.distanceKm = .nan
        XCTAssertEqual(RacePreparation(plan: race).statuses.last?.state, .unset)
    }

    func testDraftRoundTripPreservesRawAndInvalidInput() {
        let suite = "RacePreparationTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let draft = draft()
        let store = RaceCreationDraftStore(defaults: defaults)
        store.save(draft)
        let restored = RaceCreationDraftStore(defaults: defaults)
        XCTAssertEqual(restored.draft, draft)
        restored.clear(savedID: UUID())
        XCTAssertEqual(restored.draft, draft)
        restored.clear(savedID: draft.id)
        XCTAssertNil(RaceCreationDraftStore(defaults: defaults).draft)
    }

    func testCorruptDraftIsNotOverwrittenOrCleared() {
        let suite = "RacePreparationTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let data = Data("unreadable".utf8)
        defaults.set(data, forKey: "raceCreationDraftV1")
        let store = RaceCreationDraftStore(defaults: defaults)
        XCTAssertNotNil(store.error)
        store.save(draft())
        XCTAssertNotNil(store.error)
        store.clear(savedID: UUID())
        XCTAssertEqual(defaults.data(forKey: "raceCreationDraftV1"), data)
    }

    func testNonFiniteDraftInputIsPreservedWithoutRepeatedWrites() {
        let suite = "RacePreparationTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var draft = draft()
        draft.customDistanceKm = .nan
        let store = RaceCreationDraftStore(defaults: defaults)
        store.save(draft)
        let original = defaults.data(forKey: "raceCreationDraftV1")
        store.save(draft)
        XCTAssertEqual(defaults.data(forKey: "raceCreationDraftV1"), original)
        XCTAssertTrue(
            RaceCreationDraftStore(defaults: defaults).draft?.customDistanceKm.isNaN == true)
        XCTAssertNil(store.error)
    }
}
