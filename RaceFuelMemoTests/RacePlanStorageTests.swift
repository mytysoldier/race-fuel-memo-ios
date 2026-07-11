import Foundation
import Testing
@testable import RaceFuelMemo

@Test func saveAndLoadPreservesRacePlanAndChecklist() {
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

    storage.saveRacePlans([racePlan])

    #expect(storage.loadRacePlans() == [racePlan])
}

@Test func loadReturnsEmptyArrayForInvalidData() {
    let suiteName = "RacePlanStorageTests.\(UUID().uuidString)"
    let userDefaults = makeUserDefaults(suiteName: suiteName)
    defer { userDefaults.removePersistentDomain(forName: suiteName) }
    userDefaults.set(Data("invalid".utf8), forKey: "racePlans")

    #expect(UserDefaultsRacePlanStorage(userDefaults: userDefaults).loadRacePlans().isEmpty)
}

private func makeUserDefaults(suiteName: String) -> UserDefaults {
    UserDefaults(suiteName: suiteName)!
}
