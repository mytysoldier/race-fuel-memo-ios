import Foundation

struct ChecklistItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var isChecked: Bool
    var order: Int
    var category: String?
    var isRequired: Bool
    var dueDate: Date?
    var dueTiming: ChecklistDueTiming?

    init(
        id: UUID = UUID(),
        title: String,
        isChecked: Bool = false,
        order: Int = 0,
        category: String? = nil,
        isRequired: Bool = false,
        dueDate: Date? = nil,
        dueTiming: ChecklistDueTiming? = nil
    ) {
        self.id = id
        self.title = title
        self.isChecked = isChecked
        self.order = order
        self.category = category
        self.isRequired = isRequired
        self.dueDate = dueDate
        self.dueTiming = dueTiming
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, isChecked, order, category, isRequired, dueDate, dueTiming
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        isChecked = try values.decodeIfPresent(Bool.self, forKey: .isChecked) ?? false
        order = try values.decodeIfPresent(Int.self, forKey: .order) ?? 0
        category = try values.decodeIfPresent(String.self, forKey: .category)
        isRequired = try values.decodeIfPresent(Bool.self, forKey: .isRequired) ?? false
        dueDate = try values.decodeIfPresent(Date.self, forKey: .dueDate)
        dueTiming = try values.decodeIfPresent(ChecklistDueTiming.self, forKey: .dueTiming)
    }

    func resolvedDueDate(for plan: RacePlan, calendar: Calendar = .current) -> Date? {
        switch dueTiming {
        case .dayBefore:
            guard let priorDay = calendar.date(byAdding: .day, value: -1, to: plan.startTime) else { return nil }
            return calendar.date(bySettingHour: 20, minute: 0, second: 0, of: priorDay)
        case .raceMorning:
            return calendar.date(byAdding: .hour, value: -2, to: plan.startTime)
        case nil:
            return dueDate
        }
    }
}

enum ChecklistCategory: String, CaseIterable, Codable {
    case gear, registration, travel, fueling, raceMorning, afterFinish, other

    var title: String {
        switch self {
        case .gear: "持ち物"
        case .registration: "手続き"
        case .travel: "移動"
        case .fueling: "補給"
        case .raceMorning: "当日朝"
        case .afterFinish: "ゴール後"
        case .other: "その他"
        }
    }
}

enum ChecklistDueTiming: String, CaseIterable, Codable {
    case dayBefore, raceMorning

    var title: String {
        switch self {
        case .dayBefore: "前日20:00まで"
        case .raceMorning: "スタート2時間前まで"
        }
    }
}
