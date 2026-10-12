import Testing
@testable import RaceFuelMemo

@Test func addUpdateAndDeletePersistRacePlans() {
    let storage = InMemoryRacePlanStorage()
    let store = RacePlanStore(storage: storage)
    var racePlan = makeStoreRacePlan(name: "春レース")

    #expect(store.addRacePlan(racePlan))
    #expect(store.racePlans == [racePlan])

    racePlan.memo = "更新後"
    #expect(store.updateRacePlan(racePlan))
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

    #expect(!store.updateRacePlan(makeStoreRacePlan(name: "存在しないレース")))

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

@Test func invalidCheckpointPlanCannotOverwriteSavedPlan() {
    let original = makeStoreRacePlan(name: "保存済み")
    let storage = InMemoryRacePlanStorage(racePlans: [original])
    let store = RacePlanStore(storage: storage)
    var invalid = original
    invalid.checkpoints = [RaceCheckpoint(order: 0, name: "超過", distanceKm: 300)]

    #expect(!store.updateRacePlan(invalid))
    #expect(store.validationError != nil)
    #expect(store.racePlans == [original])
    #expect(storage.racePlans == [original])
}

@Test func shorterBasicDistanceCanExplicitlyRemoveOnlyOutOfCourseAdvancedData() {
    var original = makeStoreRacePlan(name: "距離変更テスト")
    original.distanceKm = 10
    let kept = RaceCheckpoint(order: 0, name: "残す地点", distanceKm: 4)
    let removed = RaceCheckpoint(order: 1, name: "範囲外の地点", distanceKm: 8)
    let finish = RaceCheckpoint(order: 2, name: "ゴール", distanceKm: 10, kind: .finish)
    original.checkpoints = [kept, removed, finish]
    let keptFuel = RaceFuelingEvent(order: 0, name: "残す補給", quantity: 1, distanceKm: 3)
    let linkedFuel = RaceFuelingEvent(order: 1, name: "地点連動の補給", quantity: 1,
                                      checkpointID: removed.id)
    let distantFuel = RaceFuelingEvent(order: 2, name: "範囲外の補給", quantity: 1, distanceKm: 9)
    original.fuelingEvents = [keptFuel, linkedFuel, distantFuel]
    let store = RacePlanStore(storage: InMemoryRacePlanStorage(racePlans: [original]))

    var candidate = original
    candidate.distanceKm = 5
    candidate.normalizeFinishCheckpoints()
    candidate.normalizePacePlans()
    #expect(RaceCheckpointValidator.error(for: candidate) != nil)
    #expect(!store.updateRacePlan(candidate))
    #expect(store.racePlans == [original])

    let cleanup = RacePlanBasicEditCleanup(original: original, candidate: candidate)
    #expect(cleanup.removedCheckpoints.map(\.id) == [removed.id])
    #expect(Set(cleanup.removedFuelingEvents.map(\.id)) == [linkedFuel.id, distantFuel.id])
    let cleaned = cleanup.applying(to: candidate)
    #expect(cleaned.checkpoints.map(\.id) == [kept.id, finish.id])
    #expect(cleaned.checkpoints.last?.distanceKm == 5)
    #expect(cleaned.fuelingEvents.map(\.id) == [keptFuel.id])
    #expect(RaceCheckpointValidator.error(for: cleaned) == nil)
    #expect(store.updateRacePlan(cleaned))
    #expect(store.racePlans.first?.distanceKm == 5)
    #expect(original.checkpoints.count == 3)

    var longer = original
    longer.distanceKm = 12
    #expect(RacePlanBasicEditCleanup(original: original, candidate: longer).isEmpty)
}

@Test func shorterBasicTargetCanClearManualTimesWithoutRemovingSavedCheckpoint() {
    var original = makeStoreRacePlan(name: "目標タイム変更テスト")
    original.distanceKm = 10
    let checkpoint = RaceCheckpoint(order: 0, name: "残す地点", distanceKm: 4,
                                    plannedElapsedSeconds: 3_000)
    original.checkpoints = [checkpoint]
    let keptFuel = RaceFuelingEvent(order: 0, name: "残す補給", quantity: 1,
                                     elapsedSeconds: 1_200)
    let lateFuel = RaceFuelingEvent(order: 1, name: "目標超過の補給", quantity: 1,
                                     elapsedSeconds: 3_600)
    original.fuelingEvents = [keptFuel, lateFuel]
    let store = RacePlanStore(storage: InMemoryRacePlanStorage(racePlans: [original]))

    var candidate = original
    candidate.targetHours = 0
    candidate.targetMinutes = 40
    candidate.normalizeFinishCheckpoints()
    candidate.normalizePacePlans()
    #expect(RaceCheckpointValidator.error(for: candidate) != nil)
    #expect(store.racePlans == [original])

    let cleanup = RacePlanBasicEditCleanup(original: original, candidate: candidate)
    #expect(cleanup.removedCheckpoints.isEmpty)
    #expect(cleanup.clearedCheckpointTimes.map(\.id) == [checkpoint.id])
    #expect(cleanup.removedFuelingEvents.map(\.id) == [lateFuel.id])
    let cleaned = cleanup.applying(to: candidate)
    #expect(cleaned.checkpoints.map(\.id) == [checkpoint.id])
    #expect(cleaned.checkpoints[0].plannedElapsedSeconds == nil)
    #expect(cleaned.fuelingEvents.map(\.id) == [keptFuel.id])
    #expect(RaceCheckpointValidator.error(for: cleaned) == nil)
    #expect(store.updateRacePlan(cleaned))
    #expect(store.racePlans.first?.targetMinutes == 40)
    #expect(original.checkpoints[0].plannedElapsedSeconds == 3_000)
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
