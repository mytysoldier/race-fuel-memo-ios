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
    var memo: String
    var checklistItems: [ChecklistItem]

    init(
        id: UUID = UUID(),
        name: String,
        raceDate: Date,
        startTime: Date,
        distanceKm: Double,
        targetHours: Int,
        targetMinutes: Int,
        gelCount: Int,
        memo: String = "",
        checklistItems: [ChecklistItem] = RacePlan.defaultChecklistItems
    ) {
        self.id = id
        self.name = name
        self.raceDate = raceDate
        self.startTime = startTime
        self.distanceKm = distanceKm
        self.targetHours = targetHours
        self.targetMinutes = targetMinutes
        self.gelCount = gelCount
        self.memo = memo
        self.checklistItems = checklistItems
    }
}

extension RacePlan {
    static let defaultChecklistItems: [ChecklistItem] = [
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
}
