import Foundation

struct ChecklistItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var isChecked: Bool

    init(
        id: UUID = UUID(),
        title: String,
        isChecked: Bool = false
    ) {
        self.id = id
        self.title = title
        self.isChecked = isChecked
    }
}
