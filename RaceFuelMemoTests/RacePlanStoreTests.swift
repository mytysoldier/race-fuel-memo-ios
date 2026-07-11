import XCTest
@testable import RaceFuelMemo

final class RacePlanStoreTests: XCTestCase {
    func testAddUpdateAndDeletePersistRacePlans() {
        let storage = InMemoryRacePlanStorage()
        let store = RacePlanStore(storage: storage)
        var racePlan = makeRacePlan(name: "春レース")

        store.addRacePlan(racePlan)
        XCTAssertEqual(store.racePlans, [racePlan])

        racePlan.memo = "更新後"
        store.updateRacePlan(racePlan)
        XCTAssertEqual(store.racePlans, [racePlan])

        store.deleteRacePlan(id: racePlan.id)
        XCTAssertTrue(store.racePlans.isEmpty)
        XCTAssertTrue(storage.racePlans.isEmpty)
    }

    func testChecklistChangeOnlyUpdatesTargetRacePlan() {
        let firstRacePlan = makeRacePlan(name: "春レース")
        let secondRacePlan = makeRacePlan(name: "秋レース")
        let store = RacePlanStore(storage: InMemoryRacePlanStorage(racePlans: [firstRacePlan, secondRacePlan]))

        store.setChecklistItemChecked(
            racePlanID: firstRacePlan.id,
            checklistItemID: firstRacePlan.checklistItems[0].id,
            isChecked: true
        )

        XCTAssertTrue(store.racePlans[0].checklistItems[0].isChecked)
        XCTAssertFalse(store.racePlans[1].checklistItems[0].isChecked)
    }

    func testUpdatingUnknownRacePlanDoesNotChangeStoredPlans() {
        let racePlan = makeRacePlan(name: "春レース")
        let store = RacePlanStore(storage: InMemoryRacePlanStorage(racePlans: [racePlan]))

        store.updateRacePlan(makeRacePlan(name: "存在しないレース"))

        XCTAssertEqual(store.racePlans, [racePlan])
    }

    private func makeRacePlan(name: String) -> RacePlan {
        RacePlan(
            name: name,
            raceDate: .distantFuture,
            startTime: .distantFuture,
            distanceKm: DistanceOption.fullMarathon.distanceKm,
            targetHours: 4,
            targetMinutes: 0,
            gelCount: 3
        )
    }
}

private final class InMemoryRacePlanStorage: RacePlanStorage {
    var racePlans: [RacePlan]

    init(racePlans: [RacePlan] = []) {
        self.racePlans = racePlans
    }

    func loadRacePlans() -> [RacePlan] {
        racePlans
    }

    func saveRacePlans(_ racePlans: [RacePlan]) {
        self.racePlans = racePlans
    }
}
