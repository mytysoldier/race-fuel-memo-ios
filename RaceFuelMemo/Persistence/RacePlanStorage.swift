import Foundation

protocol RacePlanStorage {
    func loadRacePlans() -> [RacePlan]
    func saveRacePlans(_ racePlans: [RacePlan])
}

struct UserDefaultsRacePlanStorage: RacePlanStorage {
    private enum StorageKey {
        static let racePlans = "racePlans"
    }

    private let userDefaults: UserDefaults
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(
        userDefaults: UserDefaults = .standard,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.userDefaults = userDefaults
        self.decoder = decoder
        self.encoder = encoder
    }

    func loadRacePlans() -> [RacePlan] {
        guard let data = userDefaults.data(forKey: StorageKey.racePlans) else {
            return []
        }

        do {
            return try decoder.decode([RacePlan].self, from: data)
        } catch {
            return []
        }
    }

    func saveRacePlans(_ racePlans: [RacePlan]) {
        do {
            let data = try encoder.encode(racePlans)
            userDefaults.set(data, forKey: StorageKey.racePlans)
        } catch {
            return
        }
    }
}
