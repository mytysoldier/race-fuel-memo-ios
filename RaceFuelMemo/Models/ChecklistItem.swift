import Foundation

struct ChecklistItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var isChecked: Bool
    var order: Int
    var category: String?
    var isRequired: Bool
    var dueDate: Date?

    init(
        id: UUID = UUID(),
        title: String,
        isChecked: Bool = false,
        order: Int = 0,
        category: String? = nil,
        isRequired: Bool = false,
        dueDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.isChecked = isChecked
        self.order = order
        self.category = category
        self.isRequired = isRequired
        self.dueDate = dueDate
    }
}
