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
}

/// A point on the course. Aid stations and cutoff times can be attached to the same point.
struct RaceCheckpoint: Identifiable, Codable, Equatable {
    let id: UUID
    var order: Int
    var name: String
    var distanceKm: Double
    var plannedElapsedSeconds: Int?
    var cutoffTime: Date?
    var hasAidStation: Bool

    init(id: UUID = UUID(), order: Int, name: String, distanceKm: Double,
         plannedElapsedSeconds: Int? = nil, cutoffTime: Date? = nil, hasAidStation: Bool = false) {
        self.id = id
        self.order = order
        self.name = name
        self.distanceKm = distanceKm
        self.plannedElapsedSeconds = plannedElapsedSeconds
        self.cutoffTime = cutoffTime
        self.hasAidStation = hasAidStation
    }
}

struct RacePacePlan: Identifiable, Codable, Equatable {
    let id: UUID
    var order: Int
    var name: String
    var targetSeconds: Int
    var segments: [RacePaceSegment]

    init(id: UUID = UUID(), order: Int, name: String, targetSeconds: Int,
         segments: [RacePaceSegment] = []) {
        self.id = id
        self.order = order
        self.name = name
        self.targetSeconds = targetSeconds
        self.segments = segments
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
