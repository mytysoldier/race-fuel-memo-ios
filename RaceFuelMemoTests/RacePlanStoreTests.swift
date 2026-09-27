import Testing
@testable import RaceFuelMemo

@Test func addUpdateAndDeletePersistRacePlans() {
    let storage = InMemoryRacePlanStorage()
    let store = RacePlanStore(storage: storage)
    var racePlan = makeStoreRacePlan(name: "春レース")

    store.addRacePlan(racePlan)
    #expect(store.racePlans == [racePlan])

    racePlan.memo = "更新後"
    store.updateRacePlan(racePlan)
    #expect(store.racePlans == [racePlan])

    store.deleteRacePlan(id: racePlan.id)
    #expect(store.racePlans.isEmpty)
    #expect(storage.racePlans.isEmpty)
}

@Test func checklistChangeOnlyUpdatesTargetRacePlan() {
    let firstRacePlan = makeStoreRacePlan(name: "春レース")
    let secondRacePlan = makeStoreRacePlan(name: "秋レース")
    let store = RacePlanStore(storage: InMemoryRacePlanStorage(racePlans: [firstRacePlan, secondRacePlan]))

    store.setChecklistItemChecked(
        racePlanID: firstRacePlan.id,
        checklistItemID: firstRacePlan.checklistItems[0].id,
        isChecked: true
    )

    #expect(store.racePlans[0].checklistItems[0].isChecked)
    #expect(!store.racePlans[1].checklistItems[0].isChecked)
}

@Test func updatingUnknownRacePlanDoesNotChangeStoredPlans() {
    let racePlan = makeStoreRacePlan(name: "春レース")
    let store = RacePlanStore(storage: InMemoryRacePlanStorage(racePlans: [racePlan]))

    store.updateRacePlan(makeStoreRacePlan(name: "存在しないレース"))

    #expect(store.racePlans == [racePlan])
}

@Test func failedSaveDoesNotExposeUnsavedChanges() {
    let original = makeStoreRacePlan(name: "保存済み")
    let storage = InMemoryRacePlanStorage(racePlans: [original])
    let store = RacePlanStore(storage: storage)
    storage.shouldFailSave = true

    #expect(!store.addRacePlan(makeStoreRacePlan(name: "未保存")))
    #expect(store.racePlans == [original])
    #expect(storage.racePlans == [original])
    #expect(store.storageError != nil)
}

@Test func failedLoadBlocksNewWrites() {
    let storage = InMemoryRacePlanStorage()
    storage.shouldFailLoad = true
    let store = RacePlanStore(storage: storage)

    #expect(store.racePlans.isEmpty)
    #expect(store.storageError != nil)
    #expect(!store.addRacePlan(makeStoreRacePlan(name: "上書き禁止")))
    #expect(storage.racePlans.isEmpty)
}

@Test func newRacesHaveIndependentChecklistIDs() {
    let first = makeStoreRacePlan(name: "春レース")
    let second = makeStoreRacePlan(name: "秋レース")

    #expect(first.checklistItems.map(\.order) == Array(0..<10))
    #expect(first.checklistItems[0].id != second.checklistItems[0].id)
}

private func makeStoreRacePlan(name: String) -> RacePlan {
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

private final class InMemoryRacePlanStorage: RacePlanStorage {
    var racePlans: [RacePlan]
    var shouldFailLoad = false
    var shouldFailSave = false

    init(racePlans: [RacePlan] = []) {
        self.racePlans = racePlans
    }

    func loadRacePlans() throws -> [RacePlan] {
        if shouldFailLoad { throw RacePlanStorageError.unreadableData }
        return racePlans
    }

    func saveRacePlans(_ racePlans: [RacePlan]) throws {
        if shouldFailSave { throw RacePlanStorageError.unreadableData }
        self.racePlans = racePlans
    }
}
