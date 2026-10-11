import Foundation

enum RaceCardAudience: String, CaseIterable {
    case runner, supporter

    var title: String { self == .runner ? "ランナー本人向け" : "サポート向け" }
}

enum RaceCardFormat: String, CaseIterable {
    case card, paceBand

    var title: String { self == .card ? "Race Card" : "ペースバンド" }
}

struct RaceCardSection: Equatable {
    let title: String
    let lines: [String]
}

/// An independent output snapshot. Calculations always use the same plan selection as the app.
struct RaceCardDocument {
    let raceName: String
    let planName: String
    let audience: RaceCardAudience
    let sections: [RaceCardSection]

    init(plan source: RacePlan, pacePlanID: UUID?, audience: RaceCardAudience) throws {
        var plan = source
        if let pacePlanID {
            guard plan.pacePlans.contains(where: { $0.id == pacePlanID }) else {
                throw RaceCardError.invalidPlan("出力対象のペースプランが見つかりません。")
            }
            plan.selectedPacePlanID = pacePlanID
        } else {
            plan.pacePlans = []
            plan.selectedPacePlanID = nil
        }
        if let error = RaceCheckpointValidator.error(for: plan) {
            throw RaceCardError.invalidPlan(error)
        }
        raceName = plan.name
        planName = plan.selectedPacePlan?.name ?? "基本計画"
        self.audience = audience
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "ja_JP")
        clock.dateFormat = "M/d HH:mm:ss"
        let date = DateFormatter()
        date.locale = Locale(identifier: "ja_JP")
        date.dateFormat = "yyyy年M月d日"
        let duration = RacePlanCalculator.formatDuration
        let distance = RacePlanCalculator.formatDistance
        let calculation = plan.calculation
        var sections = [RaceCardSection(title: "大会・目標", lines: [
            plan.name,
            "\(date.string(from: plan.raceDate))・\(distance(plan.distanceKm))",
            "\(planName)・\(audience.title)",
            "スタート \(clock.string(from: plan.startTime))",
            "目標 \(duration(plan.activeTargetSeconds))・平均 \(calculation.targetPaceText)",
            "ゴール \(clock.string(from: plan.startTime.addingTimeInterval(TimeInterval(plan.activeTargetSeconds))))"
        ])]

        let checkpoints = RacePlanCalculator.checkpointSchedules(for: plan)
        var checkpointLines = checkpoints.map { schedule in
            let checkpoint = schedule.checkpoint
            var line = "\(distance(checkpoint.distanceKm)) \(checkpoint.name)（\(checkpoint.kind.title)）"
            line += "・経過 \(duration(schedule.elapsedSeconds))・通過 \(clock.string(from: schedule.passingTime))"
            if checkpoint.hasAidStation { line += "・給水あり" }
            if let cutoff = checkpoint.cutoffTime {
                line += "\n関門 \(clock.string(from: cutoff))"
            }
            if let margin = schedule.cutoffMarginSeconds {
                line += margin >= 0 ? "・余裕 \(duration(margin))" : "・超過 \(duration(-margin))"
            }
            if !checkpoint.segmentNote.isEmpty { line += "\n区間メモ: \(checkpoint.segmentNote)" }
            if !checkpoint.cautionNote.isEmpty { line += "\n注意: \(checkpoint.cautionNote)" }
            return line
        }
        if !checkpoints.contains(where: { $0.checkpoint.kind == .finish }) {
            checkpointLines.append("\(distance(plan.distanceKm)) ゴール・経過 \(duration(plan.activeTargetSeconds))・通過 \(clock.string(from: plan.startTime.addingTimeInterval(TimeInterval(plan.activeTargetSeconds))))")
        }
        let checkpointSection = RaceCardSection(title: "通過地点・関門", lines: checkpointLines)

        let paceLines: [String]
        if let selected = plan.selectedPacePlan {
            paceLines = selected.segments.map { segment in
                let pace = RacePlanCalculator.targetPace(totalSeconds: segment.targetSeconds,
                    distanceKm: segment.endDistanceKm - segment.startDistanceKm)
                let elapsed = RacePlanCalculator.elapsedSeconds(at: segment.endDistanceKm, for: plan)
                return "\(distance(segment.startDistanceKm))〜\(distance(segment.endDistanceKm))・\(pace.displayText)・経過 \(duration(elapsed))・\(clock.string(from: plan.startTime.addingTimeInterval(TimeInterval(elapsed))))"
            }
        } else {
            var previous = 0.0
            paceLines = calculation.splitTimes.map { split in
                defer { previous = split.distanceKm }
                return "\(distance(previous))〜\(split.distanceText)・\(calculation.targetPaceText)・経過 \(split.elapsedTimeText)・\(clock.string(from: plan.startTime.addingTimeInterval(TimeInterval(split.elapsedSeconds))))"
            }
        }
        let paceSection = RaceCardSection(title: "区間ペース・通過予定", lines: paceLines)

        let fuelingLines: [String]
        if !plan.fuelingEvents.isEmpty {
            fuelingLines = RaceFuelingPlanCalculator.schedule(for: plan).map { scheduled in
                let event = scheduled.event
                var line = "\(distance(scheduled.distanceKm))"
                if let name = scheduled.checkpointName { line += " \(name)" }
                line += "・経過 \(duration(scheduled.elapsedSeconds))・\(clock.string(from: scheduled.passingTime))"
                line += "\n\(event.kind.title)・\(event.name) ×\(event.quantity)・\(event.pickup.title)"
                if let grams = event.carbohydrateGramsPerItem { line += "・炭水化物 \(grams.formatted())g/個" }
                if event.containsCaffeine { line += "・カフェイン入り" }
                if !event.note.isEmpty { line += "\n補給メモ: \(event.note)" }
                return line
            }
        } else {
            fuelingLines = calculation.fuelTimings.enumerated().map { index, timing in
                let names = plan.gelNames ?? []
                let name = index < names.count && !names[index].isEmpty ? names[index] : "補給ジェル"
                let elapsed = RacePlanCalculator.elapsedSeconds(at: timing.distanceKm, for: plan)
                return "\(timing.displayText)・経過 \(duration(elapsed))・\(clock.string(from: plan.startTime.addingTimeInterval(TimeInterval(elapsed))))・\(name) ×1"
            }
        }
        let fuelingSection = RaceCardSection(title: "補給・給水", lines: fuelingLines.isEmpty ? ["補給予定なし"] : fuelingLines)
        let requirements = RaceFuelingPlanCalculator.requirements(for: plan.fuelingEvents)
        let requirementsSection = RaceCardSection(title: "必要な補給品", lines: requirements.map {
            "\($0.kind.title)・\($0.name) ×\($0.quantity)"
        })
        if audience == .supporter {
            sections += [checkpointSection, fuelingSection]
            if !requirements.isEmpty { sections.append(requirementsSection) }
            sections.append(paceSection)
        } else {
            sections += [paceSection, checkpointSection, fuelingSection]
            if !requirements.isEmpty { sections.append(requirementsSection) }
        }
        if !plan.memo.isEmpty { sections.append(RaceCardSection(title: "大会メモ", lines: [plan.memo])) }
        self.sections = sections
    }
}

enum RaceCardError: LocalizedError {
    case invalidPlan(String)
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .invalidPlan(let message): message
        case .generationFailed: "出力を作成できませんでした。空き容量と計画の内容を確認してください。"
        }
    }
}
