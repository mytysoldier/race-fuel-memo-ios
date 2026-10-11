import Foundation
import Observation

@Observable
final class RaceCreationDraftStore {
    private(set) var draft: RaceCreationDraft?
    private(set) var error: String?
    private let defaults: UserDefaults
    private let key = "raceCreationDraftV1"
    private var isReadable = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: key) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.nonConformingFloatDecodingStrategy = .convertFromString(
                positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
            draft = try decoder.decode(RaceCreationDraft.self, from: data)
        } catch {
            isReadable = false
            self.error = "作成途中のデータを読み込めません。既存の下書きを保護するため上書きしません。"
        }
    }

    func save(_ draft: RaceCreationDraft) {
        guard isReadable else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            encoder.nonConformingFloatEncodingStrategy = .convertToString(
                positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
            let data = try encoder.encode(draft)
            guard defaults.data(forKey: key) != data else { return }
            defaults.set(data, forKey: key)
            self.draft = draft
            error = nil
        } catch {
            self.error = "下書きを保存できませんでした。入力値を確認してください。"
        }
    }

    func clear(savedID: UUID) {
        guard isReadable, draft?.id == savedID else { return }
        defaults.removeObject(forKey: key)
        draft = nil
    }
}
