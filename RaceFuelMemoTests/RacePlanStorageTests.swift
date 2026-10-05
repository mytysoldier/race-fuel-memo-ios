import Foundation
import Testing
@testable import RaceFuelMemo

@Test func saveAndLoadPreservesRacePlanAndChecklist() throws {
    let suiteName = "RacePlanStorageTests.\(UUID().uuidString)"
    let userDefaults = makeUserDefaults(suiteName: suiteName)
    defer { userDefaults.removePersistentDomain(forName: suiteName) }

    let storage = UserDefaultsRacePlanStorage(userDefaults: userDefaults)
    let racePlan = RacePlan(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "テストレース",
        raceDate: Date(timeIntervalSinceReferenceDate: 1_000),
        startTime: Date(timeIntervalSinceReferenceDate: 2_000),
        distanceKm: 21.0975,
        targetHours: 2,
        targetMinutes: 0,
        gelCount: 2,
        memo: "テストメモ",
        checklistItems: [ChecklistItem(title: "ゼッケン", isChecked: true)]
    )

    try storage.saveRacePlans([racePlan])

    #expect((try? storage.loadRacePlans()) == [racePlan])
    let savedData = try #require(userDefaults.data(forKey: "racePlansV2"))
    let header = try JSONDecoder().decode(SavedHeader.self, from: savedData)
    #expect(header.schemaVersion == 2)
}

@Test func newInstallStartsEmptyWithoutWritingMigrationData() {
    let suiteName = "RacePlanStorageTests.\(UUID().uuidString)"
    let userDefaults = makeUserDefaults(suiteName: suiteName)
    defer { userDefaults.removePersistentDomain(forName: suiteName) }

    #expect((try? UserDefaultsRacePlanStorage(userDefaults: userDefaults).loadRacePlans()) == [])
    #expect(userDefaults.data(forKey: "racePlansV2") == nil)
}

@Test func legacyPlansMigrateOnceAndKeepOriginalData() throws {
    let suiteName = "RacePlanStorageTests.\(UUID().uuidString)"
    let userDefaults = makeUserDefaults(suiteName: suiteName)
    defer { userDefaults.removePersistentDomain(forName: suiteName) }
    let oldData = try JSONEncoder().encode([LegacyFixture(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "旧レース", raceDate: .distantPast, startTime: .distantFuture,
        distanceKm: 42.195, targetHours: 4, targetMinutes: 15,
        gelCount: 2, gelNames: ["A", "B"], memo: "元のメモ",
        checklistItems: [LegacyChecklistFixture(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            title: "ゼッケン", isChecked: true
        )]
    )])
    userDefaults.set(oldData, forKey: "racePlans")
    let storage = UserDefaultsRacePlanStorage(userDefaults: userDefaults)

    let migrated = try storage.loadRacePlans()
    #expect(migrated.count == 1)
    #expect(migrated[0].name == "旧レース")
    #expect(migrated[0].gelNames == ["A", "B"])
    #expect(migrated[0].checklistItems[0].isChecked)
    #expect(migrated[0].checklistItems[0].order == 0)
    #expect(migrated[0].checkpoints.isEmpty)
    #expect(userDefaults.data(forKey: "racePlans") == oldData)
    let firstV2Data = try #require(userDefaults.data(forKey: "racePlansV2"))

    #expect(try storage.loadRacePlans() == migrated)
    #expect(userDefaults.data(forKey: "racePlansV2") == firstV2Data)
}

@Test func partialLegacyRecordUsesSafeDefaults() throws {
    let suiteName = "RacePlanStorageTests.\(UUID().uuidString)"
    let userDefaults = makeUserDefaults(suiteName: suiteName)
    defer { userDefaults.removePersistentDomain(forName: suiteName) }
    let data = Data("""
        [{"id":"00000000-0000-0000-0000-000000000001","name":"一部欠損",
          "raceDate":1000,"startTime":2000,"distanceKm":10,
          "targetHours":1,"targetMinutes":0}]
        """.utf8)
    userDefaults.set(data, forKey: "racePlans")

    let plans = try UserDefaultsRacePlanStorage(userDefaults: userDefaults).loadRacePlans()
    #expect(plans.count == 1)
    #expect(plans[0].gelCount == 0)
    #expect(plans[0].memo.isEmpty)
    #expect(plans[0].checklistItems.isEmpty)
}

@Test func unreadableLegacyDataCannotBeOverwritten() throws {
    let suiteName = "RacePlanStorageTests.\(UUID().uuidString)"
    let userDefaults = makeUserDefaults(suiteName: suiteName)
    defer { userDefaults.removePersistentDomain(forName: suiteName) }
    let invalid = Data("invalid".utf8)
    userDefaults.set(invalid, forKey: "racePlans")
    let storage = UserDefaultsRacePlanStorage(userDefaults: userDefaults)

    #expect(throws: RacePlanStorageError.self) { try storage.loadRacePlans() }
    #expect(throws: RacePlanStorageError.self) { try storage.saveRacePlans([]) }
    #expect(userDefaults.data(forKey: "racePlans") == invalid)
    #expect(userDefaults.data(forKey: "racePlansV2") == nil)
}

@Test func unreadableOrFutureV2DataCannotBeOverwritten() throws {
    let suiteName = "RacePlanStorageTests.\(UUID().uuidString)"
    let userDefaults = makeUserDefaults(suiteName: suiteName)
    defer { userDefaults.removePersistentDomain(forName: suiteName) }
    let storage = UserDefaultsRacePlanStorage(userDefaults: userDefaults)

    for data in [Data("invalid".utf8), Data("{\"schemaVersion\":3,\"racePlans\":[]}".utf8)] {
        userDefaults.set(data, forKey: "racePlansV2")
        #expect(throws: RacePlanStorageError.self) { try storage.loadRacePlans() }
        #expect(throws: RacePlanStorageError.self) { try storage.saveRacePlans([]) }
        #expect(userDefaults.data(forKey: "racePlansV2") == data)
    }
}

@Test func v2ModelsRoundTripWithStableIDsAndOrdering() throws {
    let suiteName = "RacePlanStorageTests.\(UUID().uuidString)"
    let userDefaults = makeUserDefaults(suiteName: suiteName)
    defer { userDefaults.removePersistentDomain(forName: suiteName) }
    let storage = UserDefaultsRacePlanStorage(userDefaults: userDefaults)
    let checkpoint = RaceCheckpoint(order: 1, name: "20km給水", distanceKm: 20,
                                    plannedElapsedSeconds: 7200, hasAidStation: true,
                                    kind: .aidStation, segmentNote: "緩い上り", cautionNote: "足元に注意")
    let cutoff = RaceCheckpoint(order: 0, name: "10km関門", distanceKm: 10,
                                cutoffTime: .now.addingTimeInterval(4_000), kind: .cutoff)
    let segment = RacePaceSegment(order: 0, startDistanceKm: 0, endDistanceKm: 20, targetSeconds: 7200)
    let pacePlan = RacePacePlan(order: 0, name: "A", targetSeconds: 14400,
                                segments: [segment], strategy: .negative,
                                halfDifferenceSeconds: 600, kickDistanceKm: 5,
                                kickGainSecondsPerKm: 20)
    let event = RaceFuelingEvent(order: 0, name: "ジェル", quantity: 1,
                                 distanceKm: checkpoint.distanceKm, checkpointID: checkpoint.id,
                                 carbohydrateGramsPerItem: 25, containsCaffeine: true,
                                 note: "給水と一緒に", pickup: .support)
    var plan = RacePlan(name: "v2", raceDate: .now, startTime: .now, distanceKm: 42.195,
                        targetHours: 4, targetMinutes: 0, gelCount: 1,
                        checkpoints: [checkpoint, cutoff], pacePlans: [pacePlan],
                        selectedPacePlanID: pacePlan.id, fuelingEvents: [event])
    plan.normalizePacePlans()

    try storage.saveRacePlans([plan])
    #expect(try storage.loadRacePlans() == [plan])
    #expect(try storage.loadRacePlans()[0].pacePlans[0].strategy == .negative)
}

@Test func earlierV2CheckpointDecodesWithDefaults() throws {
    let data = Data("""
        {"id":"00000000-0000-0000-0000-000000000001","order":0,"name":"旧給水",
         "distanceKm":5,"plannedElapsedSeconds":1800,"hasAidStation":true}
        """.utf8)
    let checkpoint = try JSONDecoder().decode(RaceCheckpoint.self, from: data)
    #expect(checkpoint.kind == .aidStation)
    #expect(checkpoint.segmentNote.isEmpty)
    #expect(checkpoint.cautionNote.isEmpty)
}

@Test func earlierV2FinishCheckpointMigratesUsingRaceDistance() throws {
    let data = Data("""
        {"id":"00000000-0000-0000-0000-000000000001","name":"旧レース",
         "raceDate":1000,"startTime":2000,"distanceKm":42.195,
         "targetHours":4,"targetMinutes":0,"gelCount":0,"gelNames":[],"memo":"",
         "checklistItems":[],"pacePlans":[],"selectedPacePlanID":null,"fuelingEvents":[],
         "checkpoints":[{"id":"00000000-0000-0000-0000-000000000002","order":0,
         "name":"ゴール","distanceKm":42.195,"plannedElapsedSeconds":7200,
         "hasAidStation":true,"cutoffTime":3000}]}
        """.utf8)

    let plan = try JSONDecoder().decode(RacePlan.self, from: data)
    #expect(plan.checkpoints[0].kind == .finish)
    #expect(plan.checkpoints[0].plannedElapsedSeconds == 14_400)
    #expect(plan.checkpoints[0].hasAidStation)
    #expect(plan.checkpoints[0].cutoffTime == Date(timeIntervalSinceReferenceDate: 3_000))
    #expect(RaceCheckpointValidator.error(for: plan) == nil)
    #expect(RacePlanCalculator.checkpointSchedules(for: plan).count == 1)
}

@Test func legacyPacePlanWithSegmentsKeepsCustomAllocation() throws {
    let data = Data("""
        {"id":"00000000-0000-0000-0000-000000000001","order":0,"name":"旧A",
         "targetSeconds":7200,"segments":[
           {"id":"00000000-0000-0000-0000-000000000002","order":0,
            "startDistanceKm":0,"endDistanceKm":10,"targetSeconds":4000},
           {"id":"00000000-0000-0000-0000-000000000003","order":1,
            "startDistanceKm":10,"endDistanceKm":20,"targetSeconds":3200}]}
        """.utf8)

    let plan = try JSONDecoder().decode(RacePacePlan.self, from: data)
    #expect(plan.strategy == .custom)
    #expect(RacePacePlanCalculator.elapsedSeconds(at: 10, in: plan, raceDistanceKm: 20) == 4_000)
}

private func makeUserDefaults(suiteName: String) -> UserDefaults {
    UserDefaults(suiteName: suiteName)!
}

private struct SavedHeader: Decodable { let schemaVersion: Int }

private struct LegacyFixture: Encodable {
    let id: UUID
    let name: String
    let raceDate: Date
    let startTime: Date
    let distanceKm: Double
    let targetHours: Int
    let targetMinutes: Int
    let gelCount: Int
    let gelNames: [String]
    let memo: String
    let checklistItems: [LegacyChecklistFixture]
}

private struct LegacyChecklistFixture: Encodable {
    let id: UUID
    let title: String
    let isChecked: Bool
}
