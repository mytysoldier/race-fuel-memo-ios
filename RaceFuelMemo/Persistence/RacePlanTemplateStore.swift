import Foundation
import Observation

@Observable final class RacePlanTemplateStore {
    private(set) var templates: [RacePlanTemplate] = []
    private(set) var error: String?
    private let defaults: UserDefaults
    static let storageKey = "racePlanTemplatesV1"

    // Built-in templates can be added here without mixing them with user-owned storage.
    static var standardTemplates: [RacePlanTemplate] { [] }
    var availableTemplates: [RacePlanTemplate] { Self.standardTemplates + templates }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: Self.storageKey) else { return }
        do {
            templates = try JSONDecoder().decode([RacePlanTemplate].self, from: data)
        } catch {
            self.error = "保存済みの計画テンプレートを読み込めません。データ保護のため変更を停止しました。"
        }
    }

    func save(name: String, source: RacePlan) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard RaceCheckpointValidator.error(for: source) == nil else { return false }
        return persist(templates + [RacePlanTemplate(name: trimmed, source: source)])
    }

    func rename(id: UUID, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = templates.firstIndex(where: { $0.id == id }) else { return false }
        var updated = templates
        updated[index].name = trimmed
        return persist(updated)
    }

    func delete(id: UUID) -> Bool {
        guard templates.contains(where: { $0.id == id }) else { return false }
        return persist(templates.filter { $0.id != id })
    }

    private func persist(_ updated: [RacePlanTemplate]) -> Bool {
        guard error == nil else { return false }
        do {
            defaults.set(try JSONEncoder().encode(updated), forKey: Self.storageKey)
            templates = updated
            return true
        } catch {
            self.error = "計画テンプレートを保存できませんでした。"
            return false
        }
    }
}
