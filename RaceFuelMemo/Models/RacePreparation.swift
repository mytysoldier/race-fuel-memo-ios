import Foundation

enum RacePreparationStep: String, CaseIterable, Codable, Identifiable {
    case basic, pace, checkpoints, fueling, checklist, output
    var id: String { rawValue }
    var title: String {
        switch self {
        case .basic: "大会情報"
        case .pace: "ペース"
        case .checkpoints: "通過地点"
        case .fueling: "補給"
        case .checklist: "持ち物・準備"
        case .output: "確認・出力"
        }
    }
    var guidance: String {
        switch self {
        case .basic: "大会名・開催日・スタート・距離を入力しましょう。"
        case .pace: "目標タイムを決めましょう。基本の均等ペースだけでも作成できます。"
        case .checkpoints: "Proでは関門・給水所を追加できます。未設定でも5kmごとの通過時間を無料で表示します。"
        case .fueling: "携行するジェル、または詳細な補給・給水を設定しましょう。"
        case .checklist: "必須の持ち物を確認しましょう。チェックは保存後も変更できます。"
        case .output: "計画を保存しましょう。Proでは準備状況の確認とRace Card出力も利用できます。注意が残っていても保存できます。"
        }
    }
}

struct RacePreparationStatus: Identifiable {
    enum State { case ready, unset, attention }
    let step: RacePreparationStep
    let state: State
    let detail: String
    var id: String { step.rawValue }
    var label: String {
        switch state {
        case .ready: "入力済み"
        case .unset: "未設定"
        case .attention: "注意"
        }
    }
}

/// Readiness is advisory. Optional advanced features never block a basic plan.
struct RacePreparation {
    let statuses: [RacePreparationStatus]
    var nextStep: RacePreparationStep {
        statuses.first {
            $0.state == .attention
                || (($0.step == .basic || $0.step == .pace) && $0.state == .unset)
        }?.step
            ?? statuses.first {
                ($0.step == .fueling || $0.step == .checklist) && $0.state == .unset
            }?
            .step
            ?? .output
    }

    init(plan: RacePlan) {
        let hasName = !plan.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let validDistance = plan.distanceKm.isFinite && (1...200).contains(plan.distanceKm)
        let validTarget =
            (0...240).contains(plan.targetHours) && (0..<60).contains(plan.targetMinutes)
            && plan.targetHours * 3600 + plan.targetMinutes * 60 > 0
        var items: [RacePreparationStatus] = []
        items.append(
            .init(
                step: .basic, state: hasName && validDistance ? .ready : .unset,
                detail: !hasName
                    ? "大会名を入力してください。"
                    : !validDistance
                        ? "距離を1〜200kmで入力してください。" : "大会名・日時・距離を設定済み"))
        let paceError = RacePacePlanCalculator.validationError(for: plan)
        items.append(
            .init(
                step: .pace, state: !validTarget ? .unset : paceError != nil ? .attention : .ready,
                detail: !validTarget
                    ? "目標タイムを入力してください。"
                    : paceError
                        ?? (plan.pacePlans.isEmpty
                            ? "基本の均等ペースを使用" : "\(plan.pacePlans.count)プランを設定済み")))

        // Validate course and compute cutoff margins independently of fueling errors.
        var coursePlan = plan
        coursePlan.fuelingEvents = []
        let courseError =
            validDistance && validTarget && paceError == nil
            ? RaceCheckpointValidator.error(for: coursePlan) : nil
        let exceeded =
            courseError == nil && validDistance && validTarget && paceError == nil
            ? RacePlanCalculator.checkpointSchedules(for: coursePlan).filter {
                ($0.cutoffMarginSeconds ?? 0) < 0
            } : []
        let needsCourseRecalculation =
            !plan.checkpoints.isEmpty
            && (!validDistance || !validTarget || paceError != nil)
        items.append(
            .init(
                step: .checkpoints,
                state: courseError != nil || !exceeded.isEmpty || needsCourseRecalculation
                    ? .attention : plan.checkpoints.isEmpty ? .unset : .ready,
                detail: needsCourseRecalculation
                    ? "大会情報・ペースを修正すると通過時刻と関門を確認できます。"
                    : courseError
                        ?? (!exceeded.isEmpty
                            ? "関門超過: " + exceeded.map { $0.checkpoint.name }.joined(separator: "、")
                            : plan.checkpoints.isEmpty
                                ? "任意・5kmごとの通過時間を使用" : "\(plan.checkpoints.count)地点を設定済み")))
        let fuelingError = RaceFuelingPlanCalculator.validationError(for: plan)
        let hasFuel = !plan.fuelingEvents.isEmpty || plan.gelCount > 0
        items.append(
            .init(
                step: .fueling, state: fuelingError != nil ? .attention : hasFuel ? .ready : .unset,
                detail: fuelingError ?? (hasFuel ? "補給を設定済み" : "補給未設定・必要な補給と給水を確認してください。")))
        let required = plan.checklistItems.filter { $0.isRequired && !$0.isChecked }
        items.append(
            .init(
                step: .checklist,
                state: !required.isEmpty
                    ? .attention : plan.checklistItems.isEmpty ? .unset : .ready,
                detail: !required.isEmpty
                    ? "必須項目が\(required.count)件未完了: " + required.map(\.title).joined(separator: "、")
                    : plan.checklistItems.isEmpty
                        ? "持ち物・準備項目が未設定" : "\(plan.checklistItems.count)項目・必須項目は確認済み"))
        let canOutput =
            hasName && validDistance && validTarget
            && RaceCheckpointValidator.error(for: plan) == nil
        items.append(
            .init(
                step: .output, state: canOutput ? .ready : .unset,
                detail: canOutput ? "Race Cardを確認・出力できます" : "大会情報と入力エラーを修正してください。"))
        statuses = items
    }
}

/// Store raw input separately from RacePlan: decoding RacePlan normalizes advanced
/// settings, which would lose invalid or unfinished input in a creation draft.
struct RaceCreationDraft: Codable, Equatable {
    var id: UUID
    var name: String
    var raceDate: Date
    var startTime: Date
    var distanceKm: Double
    var usesCustomDistance: Bool
    var customDistanceKm: Double
    var targetHours: Int
    var targetMinutes: Int
    var gelNames: [String]
    var memo: String
    var checkpoints: [RaceCheckpoint]
    var pacePlans: [RacePacePlan]
    var selectedPacePlanID: UUID?
    var fuelingEvents: [RaceFuelingEvent]
    var checklistItems: [ChecklistItem]
    var checklistNotificationsEnabled: Bool
    var step: RacePreparationStep
    var isGuided: Bool
    /// Persist the advanced edit marker across relaunch, without altering input.
    /// Older drafts have no marker and remain readable.
    var editedProFeature: ProFeature? = nil
}
