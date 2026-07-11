import XCTest
@testable import RaceFuelMemo

final class RacePlanStorageTests: XCTestCase {
    private var userDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: "RacePlanStorageTests")!
        userDefaults.removePersistentDomain(forName: "RacePlanStorageTests")
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: "RacePlanStorageTests")
        userDefaults = nil
        super.tearDown()
    }

    func testSaveAndLoadPreservesRacePlanAndChecklist() {
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

        storage.saveRacePlans([racePlan])

        XCTAssertEqual(storage.loadRacePlans(), [racePlan])
    }

    func testLoadReturnsEmptyArrayForInvalidData() {
        userDefaults.set(Data("invalid".utf8), forKey: "racePlans")

        XCTAssertTrue(UserDefaultsRacePlanStorage(userDefaults: userDefaults).loadRacePlans().isEmpty)
    }
}
