import Foundation

struct RacePlan: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var raceDate: Date
    var startTime: Date
    var distanceKm: Double
    var targetHours: Int
    var targetMinutes: Int
    var gelCount: Int
    var gelNames: [String]?
    var memo: String
    var checklistItems: [ChecklistItem]
    var checkpoints: [RaceCheckpoint]
    var pacePlans: [RacePacePlan]
    var selectedPacePlanID: UUID?
    var fuelingEvents: [RaceFuelingEvent]

    init(
        id: UUID = UUID(),
        name: String,
        raceDate: Date,
        startTime: Date,
        distanceKm: Double,
        targetHours: Int,
        targetMinutes: Int,
        gelCount: Int,
        gelNames: [String] = [],
        memo: String = "",
        checklistItems: [ChecklistItem] = RacePlan.defaultChecklistItems,
        checkpoints: [RaceCheckpoint] = [],
        pacePlans: [RacePacePlan] = [],
        selectedPacePlanID: UUID? = nil,
        fuelingEvents: [RaceFuelingEvent] = []
    ) {
        self.id = id
        self.name = name
        self.raceDate = raceDate
        self.startTime = startTime
        self.distanceKm = distanceKm
        self.targetHours = targetHours
        self.targetMinutes = targetMinutes
        self.gelCount = gelCount
        self.gelNames = gelNames
        self.memo = memo
        self.checklistItems = checklistItems
        self.checkpoints = checkpoints
        self.pacePlans = pacePlans
        self.selectedPacePlanID = selectedPacePlanID
        self.fuelingEvents = fuelingEvents
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, raceDate, startTime, distanceKm, targetHours, targetMinutes
        case gelCount, gelNames, memo, checklistItems, checkpoints, pacePlans
        case selectedPacePlanID, fuelingEvents
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
        checklistItems = try values.decodeIfPresent([ChecklistItem].self, forKey: .checklistItems) ?? []
        pacePlans = try values.decodeIfPresent([RacePacePlan].self, forKey: .pacePlans) ?? []
        selectedPacePlanID = try values.decodeIfPresent(UUID.self, forKey: .selectedPacePlanID)
        fuelingEvents = try values.decodeIfPresent([RaceFuelingEvent].self, forKey: .fuelingEvents) ?? []

        checkpoints = try values.decodeIfPresent([RaceCheckpoint].self, forKey: .checkpoints) ?? []
        // Checkpoint kind was introduced after v2 storage. A legacy checkpoint at
        // the race distance represented the finish, so normalize it on load.
        for index in checkpoints.indices where !checkpoints[index].wasKindExplicitlyStored
            && abs(checkpoints[index].distanceKm - distanceKm) < 0.000_001 {
            checkpoints[index].kind = .finish
            checkpoints[index] = normalizedFinishCheckpoint(checkpoints[index])
        }
        normalizePacePlans()
    }
}

enum RaceCheckpointKind: String, CaseIterable, Codable {
    case regular
    case aidStation
    case cutoff
    case turnaround
    case finish

    var title: String {
        switch self {
        case .regular: "通常地点"
        case .aidStation: "給水所"
        case .cutoff: "関門"
        case .turnaround: "折り返し"
        case .finish: "ゴール"
        }
    }
}

/// A point on the course. The legacy aid-station flag is retained for existing v2 documents.
struct RaceCheckpoint: Identifiable, Codable, Equatable {
    let id: UUID
    var order: Int
    var name: String
    var distanceKm: Double
    var plannedElapsedSeconds: Int?
    var cutoffTime: Date?
    var hasAidStation: Bool
    var kind: RaceCheckpointKind
    var segmentNote: String
    var cautionNote: String
    fileprivate var wasKindExplicitlyStored: Bool

    init(id: UUID = UUID(), order: Int, name: String, distanceKm: Double,
         plannedElapsedSeconds: Int? = nil, cutoffTime: Date? = nil, hasAidStation: Bool = false,
         kind: RaceCheckpointKind = .regular, segmentNote: String = "", cautionNote: String = "") {
        self.id = id
        self.order = order
        self.name = name
        self.distanceKm = distanceKm
        self.plannedElapsedSeconds = plannedElapsedSeconds
        self.cutoffTime = cutoffTime
        self.hasAidStation = hasAidStation || kind == .aidStation
        self.kind = kind
        self.segmentNote = segmentNote
        self.cautionNote = cautionNote
        self.wasKindExplicitlyStored = true
    }

    private enum CodingKeys: String, CodingKey {
        case id, order, name, distanceKm, plannedElapsedSeconds, cutoffTime
        case hasAidStation, kind, segmentNote, cautionNote
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        order = try values.decode(Int.self, forKey: .order)
        name = try values.decode(String.self, forKey: .name)
        distanceKm = try values.decode(Double.self, forKey: .distanceKm)
        plannedElapsedSeconds = try values.decodeIfPresent(Int.self, forKey: .plannedElapsedSeconds)
        cutoffTime = try values.decodeIfPresent(Date.self, forKey: .cutoffTime)
        hasAidStation = try values.decodeIfPresent(Bool.self, forKey: .hasAidStation) ?? false
        wasKindExplicitlyStored = values.contains(.kind)
        kind = try values.decodeIfPresent(RaceCheckpointKind.self, forKey: .kind)
            ?? (cutoffTime != nil ? .cutoff : hasAidStation ? .aidStation : .regular)
        if kind == .aidStation { hasAidStation = true }
        segmentNote = try values.decodeIfPresent(String.self, forKey: .segmentNote) ?? ""
        cautionNote = try values.decodeIfPresent(String.self, forKey: .cautionNote) ?? ""
    }
}

struct RacePacePlan: Identifiable, Codable, Equatable {
    let id: UUID
    var order: Int
    var name: String
    var targetSeconds: Int
    var segments: [RacePaceSegment]
    var strategy: RacePaceStrategy
    var halfDifferenceSeconds: Int
    var kickDistanceKm: Double
    var kickGainSecondsPerKm: Int

    init(id: UUID = UUID(), order: Int, name: String, targetSeconds: Int,
         segments: [RacePaceSegment] = [], strategy: RacePaceStrategy = .even,
         halfDifferenceSeconds: Int = 0, kickDistanceKm: Double = 0,
         kickGainSecondsPerKm: Int = 0) {
        self.id = id
        self.order = order
        self.name = name
        self.targetSeconds = targetSeconds
        self.segments = segments
        self.strategy = strategy
        self.halfDifferenceSeconds = halfDifferenceSeconds
        self.kickDistanceKm = kickDistanceKm
        self.kickGainSecondsPerKm = kickGainSecondsPerKm
    }

    private enum CodingKeys: String, CodingKey {
        case id, order, name, targetSeconds, segments, strategy
        case halfDifferenceSeconds, kickDistanceKm, kickGainSecondsPerKm
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        order = try values.decode(Int.self, forKey: .order)
        name = try values.decode(String.self, forKey: .name)
        targetSeconds = try values.decode(Int.self, forKey: .targetSeconds)
        segments = try values.decodeIfPresent([RacePaceSegment].self, forKey: .segments) ?? []
        strategy = try values.decodeIfPresent(RacePaceStrategy.self, forKey: .strategy) ?? .even
        halfDifferenceSeconds = try values.decodeIfPresent(Int.self, forKey: .halfDifferenceSeconds) ?? 0
        kickDistanceKm = try values.decodeIfPresent(Double.self, forKey: .kickDistanceKm) ?? 0
        kickGainSecondsPerKm = try values.decodeIfPresent(Int.self, forKey: .kickGainSecondsPerKm) ?? 0
    }
}

enum RacePaceStrategy: String, CaseIterable, Codable {
    case even, negative, positive, custom

    var title: String {
        switch self {
        case .even: "イーブン"
        case .negative: "ネガティブ"
        case .positive: "ポジティブ"
        case .custom: "区間別カスタム"
        }
    }
}

struct RacePaceSegment: Identifiable, Codable, Equatable {
    let id: UUID
    var order: Int
    var startDistanceKm: Double
    var endDistanceKm: Double
    var targetSeconds: Int

    init(id: UUID = UUID(), order: Int, startDistanceKm: Double,
         endDistanceKm: Double, targetSeconds: Int) {
        self.id = id
        self.order = order
        self.startDistanceKm = startDistanceKm
        self.endDistanceKm = endDistanceKm
        self.targetSeconds = targetSeconds
    }
}

struct RaceFuelingEvent: Identifiable, Codable, Equatable {
    let id: UUID
    var order: Int
    var name: String
    var quantity: Int
    var distanceKm: Double?
    var elapsedSeconds: Int?
    var checkpointID: UUID?

    init(id: UUID = UUID(), order: Int, name: String, quantity: Int,
         distanceKm: Double? = nil, elapsedSeconds: Int? = nil, checkpointID: UUID? = nil) {
        self.id = id
        self.order = order
        self.name = name
        self.quantity = quantity
        self.distanceKm = distanceKm
        self.elapsedSeconds = elapsedSeconds
        self.checkpointID = checkpointID
    }
}

extension RacePlan {
    var selectedPacePlan: RacePacePlan? {
        pacePlans.first { $0.id == selectedPacePlanID }
    }

    var activeTargetSeconds: Int {
        selectedPacePlan?.targetSeconds
            ?? RacePlanCalculator.targetDurationSeconds(hours: targetHours, minutes: targetMinutes)
    }

    func normalizedFinishCheckpoint(_ checkpoint: RaceCheckpoint) -> RaceCheckpoint {
        guard checkpoint.kind == .finish else { return checkpoint }

        var normalizedCheckpoint = checkpoint
        normalizedCheckpoint.distanceKm = distanceKm
        if normalizedCheckpoint.plannedElapsedSeconds != nil {
            normalizedCheckpoint.plannedElapsedSeconds = targetHours * 3_600 + targetMinutes * 60
        }
        return normalizedCheckpoint
    }

    mutating func normalizeFinishCheckpoints() {
        for index in checkpoints.indices where checkpoints[index].kind == .finish {
            checkpoints[index] = normalizedFinishCheckpoint(checkpoints[index])
        }
    }

    mutating func moveCutoffTimes(from previousStartTime: Date, to newStartTime: Date) {
        checkpoints.moveCutoffTimes(from: previousStartTime, to: newStartTime)
    }
}

extension Array where Element == RaceCheckpoint {
    mutating func moveCutoffTimes(from previousStartTime: Date, to newStartTime: Date) {
        let offset = newStartTime.timeIntervalSince(previousStartTime)
        guard offset != 0 else { return }

        for index in indices where self[index].cutoffTime != nil {
            self[index].cutoffTime = self[index].cutoffTime?.addingTimeInterval(offset)
        }
    }
}

extension RacePlan {
    static var defaultChecklistItems: [ChecklistItem] {
        let items = [
            ChecklistItem(title: "ランニングシューズ"),
            ChecklistItem(title: "ウェア"),
            ChecklistItem(title: "ゼッケン"),
            ChecklistItem(title: "計測チップ"),
            ChecklistItem(title: "ランニングウォッチ"),
            ChecklistItem(title: "補給ジェル"),
            ChecklistItem(title: "塩タブレット"),
            ChecklistItem(title: "着替え"),
            ChecklistItem(title: "タオル"),
            ChecklistItem(title: "モバイルバッテリー")
        ]
        return items.enumerated().map { index, item in
            var orderedItem = item
            orderedItem.order = index
            return orderedItem
        }
    }
}
