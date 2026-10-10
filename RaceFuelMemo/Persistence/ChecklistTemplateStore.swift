import Foundation
import Observation

struct ChecklistTemplate: Identifiable, Codable, Equatable {
    static let standardID = UUID(uuidString: "854B54B2-67E0-4B5B-934C-20E4985D22B6")!

    let id: UUID
    var name: String
    let items: [ChecklistTemplateItem]

    var isStandard: Bool { id == Self.standardID }

    static var standard: ChecklistTemplate {
        ChecklistTemplate(id: standardID, name: "標準の持ち物10項目", items: RacePlan.defaultChecklistItems.map(ChecklistTemplateItem.init))
    }

    init(id: UUID = UUID(), name: String, items: [ChecklistItem]) {
        self.id = id
        self.name = name
        self.items = items.sorted { $0.order < $1.order }.map(ChecklistTemplateItem.init)
    }

    private init(id: UUID, name: String, items: [ChecklistTemplateItem]) {
        self.id = id
        self.name = name
        self.items = items
    }

    func checklistItems() -> [ChecklistItem] {
        items.enumerated().map { index, item in
            ChecklistItem(
                title: item.title, order: index, category: item.category,
                isRequired: item.isRequired, dueTiming: item.dueTiming
            )
        }
    }
}

struct ChecklistTemplateItem: Codable, Equatable {
    let title: String
    let category: String?
    let isRequired: Bool
    let dueTiming: ChecklistDueTiming?

    init(_ item: ChecklistItem) {
        title = item.title
        category = item.category
        isRequired = item.isRequired
        dueTiming = item.dueTiming
    }
}

@Observable final class ChecklistTemplateStore {
    private(set) var templates: [ChecklistTemplate] = [.standard]
    private(set) var error: String?
    private let defaults: UserDefaults
    private let key = "raceChecklistTemplatesV1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: key) else { return }
        do {
            let saved = try JSONDecoder().decode([ChecklistTemplate].self, from: data)
            templates += saved.filter { !$0.isStandard }
        } catch {
            self.error = "保存済みチェックリストのテンプレートを読み込めません。データ保護のため変更を停止しました。"
        }
    }

    func save(name: String, items: [ChecklistItem]) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !items.isEmpty else { return false }
        return persist(templates + [ChecklistTemplate(name: trimmed, items: items)])
    }

    func rename(id: UUID, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id != ChecklistTemplate.standardID, !trimmed.isEmpty,
              let index = templates.firstIndex(where: { $0.id == id }) else { return false }
        var updated = templates
        updated[index].name = trimmed
        return persist(updated)
    }

    func delete(id: UUID) -> Bool {
        guard id != ChecklistTemplate.standardID, templates.contains(where: { $0.id == id }) else { return false }
        return persist(templates.filter { $0.id != id })
    }

    private func persist(_ updated: [ChecklistTemplate]) -> Bool {
        guard error == nil else { return false }
        do {
            defaults.set(try JSONEncoder().encode(updated.filter { !$0.isStandard }), forKey: key)
            templates = updated
            return true
        } catch {
            self.error = "チェックリストのテンプレートを保存できませんでした。"
            return false
        }
    }
}
