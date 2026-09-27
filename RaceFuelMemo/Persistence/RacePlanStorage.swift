import Foundation

protocol RacePlanStorage {
    func loadRacePlans() throws -> [RacePlan]
    func saveRacePlans(_ racePlans: [RacePlan]) throws
}

enum RacePlanStorageError: LocalizedError {
    case unreadableData
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unreadableData:
            return "保存済みレースを読み込めません。データを保護するため、変更を停止しました。"
        case .unsupportedVersion:
            return "新しい形式のレースデータが見つかりました。対応するアプリで開いてください。"
        }
    }
}

struct UserDefaultsRacePlanStorage: RacePlanStorage {
    private enum StorageKey {
        static let legacyRacePlans = "racePlans"
        static let racePlansV2 = "racePlansV2"
    }

    private struct V2Document: Codable {
        let schemaVersion: Int
        let racePlans: [RacePlan]
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

    func loadRacePlans() throws -> [RacePlan] {
        if let data = userDefaults.data(forKey: StorageKey.racePlansV2) {
            return try decodeV2(data).racePlans
        }

        guard let legacyData = userDefaults.data(forKey: StorageKey.legacyRacePlans) else {
            return []
        }

        let legacyPlans: [LegacyRacePlan]
        do {
            legacyPlans = try decoder.decode([LegacyRacePlan].self, from: legacyData)
        } catch {
            throw RacePlanStorageError.unreadableData
        }

        let migratedPlans = legacyPlans.map(\.racePlan)
        try saveRacePlans(migratedPlans)
        return migratedPlans
    }

    func saveRacePlans(_ racePlans: [RacePlan]) throws {
        // Never replace a document this app cannot read, including a future schema version.
        if let existing = userDefaults.data(forKey: StorageKey.racePlansV2) {
            _ = try decodeV2(existing)
        } else if let legacy = userDefaults.data(forKey: StorageKey.legacyRacePlans) {
            do {
                _ = try decoder.decode([LegacyRacePlan].self, from: legacy)
            } catch {
                throw RacePlanStorageError.unreadableData
            }
        }

        let document = V2Document(schemaVersion: 2, racePlans: racePlans)
        let encoded = try encoder.encode(document)
        userDefaults.set(encoded, forKey: StorageKey.racePlansV2)
    }

    private func decodeV2(_ data: Data) throws -> V2Document {
        // Read the version first, so future versions are not mistaken for corruption.
        struct Header: Decodable { let schemaVersion: Int }
        let header: Header
        do {
            header = try decoder.decode(Header.self, from: data)
        } catch {
            throw RacePlanStorageError.unreadableData
        }
        guard header.schemaVersion == 2 else {
            throw RacePlanStorageError.unsupportedVersion(header.schemaVersion)
        }
        do {
            return try decoder.decode(V2Document.self, from: data)
        } catch {
            throw RacePlanStorageError.unreadableData
        }
    }
}

/// Matches the original UserDefaults JSON independently of future RacePlan changes.
private struct LegacyRacePlan: Decodable {
    let id: UUID
    let name: String
    let raceDate: Date
    let startTime: Date
    let distanceKm: Double
    let targetHours: Int
    let targetMinutes: Int
    let gelCount: Int
    let gelNames: [String]?
    let memo: String
    let checklistItems: [LegacyChecklistItem]

    enum CodingKeys: String, CodingKey {
        case id, name, raceDate, startTime, distanceKm, targetHours, targetMinutes
        case gelCount, gelNames, memo, checklistItems
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        raceDate = try values.decode(Date.self, forKey: .raceDate)
        startTime = try values.decode(Date.self, forKey: .startTime)
        distanceKm = try values.decode(Double.self, forKey: .distanceKm)
        targetHours = try values.decode(Int.self, forKey: .targetHours)
        targetMinutes = try values.decode(Int.self, forKey: .targetMinutes)
        gelCount = try values.decodeIfPresent(Int.self, forKey: .gelCount) ?? 0
        gelNames = try values.decodeIfPresent([String].self, forKey: .gelNames)
        memo = try values.decodeIfPresent(String.self, forKey: .memo) ?? ""
        checklistItems = try values.decodeIfPresent([LegacyChecklistItem].self, forKey: .checklistItems) ?? []
    }

    var racePlan: RacePlan {
        RacePlan(
            id: id, name: name, raceDate: raceDate, startTime: startTime,
            distanceKm: distanceKm, targetHours: targetHours, targetMinutes: targetMinutes,
            gelCount: gelCount, gelNames: gelNames ?? [], memo: memo,
            checklistItems: checklistItems.enumerated().map { index, item in
                ChecklistItem(id: item.id, title: item.title, isChecked: item.isChecked, order: index)
            }
        )
    }
}

private struct LegacyChecklistItem: Decodable {
    let id: UUID
    let title: String
    let isChecked: Bool

    enum CodingKeys: String, CodingKey { case id, title, isChecked }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        isChecked = try values.decodeIfPresent(Bool.self, forKey: .isChecked) ?? false
    }
}
