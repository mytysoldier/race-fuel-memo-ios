import Foundation

enum RaceCardAudience: String, CaseIterable {
    case runner, supporter

    var title: String { self == .runner ? String(localized: "ランナー本人向け") : String(localized: "サポート向け") }
}

enum RaceCardFormat: String, CaseIterable {
    case card, paceBand

    var title: String { self == .card ? "Race Card" : String(localized: "ペースバンド") }
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
                throw RaceCardError.invalidPlan(String(localized: "出力対象のペースプランが見つかりません。"))
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
        planName = plan.selectedPacePlan?.name ?? String(localized: "基本計画")
        self.audience = audience
        let clock = DateFormatter()
        clock.locale = .current
        clock.dateStyle = .short
        clock.timeStyle = .medium
        let date = DateFormatter()
        date.locale = .current
        date.dateStyle = .long
        let duration = RacePlanCalculator.formatDuration
        let distance = RacePlanCalculator.formatDistance
        let calculation = plan.calculation
        var sections = [RaceCardSection(title: String(localized: "大会・目標"), lines: [
            plan.name,
            "\(date.string(from: plan.raceDate))・\(distance(plan.distanceKm))",
            "\(planName)・\(audience.title)",
            String(format: String(localized: "card.start"), clock.string(from: plan.startTime)),
            String(format: String(localized: "card.goal_pace"), duration(plan.activeTargetSeconds), calculation.targetPaceText),
            String(format: String(localized: "card.finish"), clock.string(from: plan.startTime.addingTimeInterval(TimeInterval(plan.activeTargetSeconds))))
        ])]

        let checkpoints = RacePlanCalculator.checkpointSchedules(for: plan)
        var checkpointLines = checkpoints.map { schedule in
            let checkpoint = schedule.checkpoint
            var line = "\(distance(checkpoint.distanceKm)) \(checkpoint.name)（\(checkpoint.kind.title)）"
            line += String(format: String(localized: "card.elapsed_passing"), duration(schedule.elapsedSeconds), clock.string(from: schedule.passingTime))
            if checkpoint.hasAidStation { line += String(localized: "card.water") }
            if let cutoff = checkpoint.cutoffTime {
                line += String(format: String(localized: "card.cutoff"), clock.string(from: cutoff))
            }
            if let margin = schedule.cutoffMarginSeconds {
                line += margin >= 0 ? String(format: String(localized: "card.margin"), duration(margin)) : String(format: String(localized: "card.over"), duration(-margin))
            }
            if !checkpoint.segmentNote.isEmpty { line += String(format: String(localized: "card.segment_note"), checkpoint.segmentNote) }
            if !checkpoint.cautionNote.isEmpty { line += String(format: String(localized: "card.caution"), checkpoint.cautionNote) }
            return line
        }
        if !checkpoints.contains(where: { $0.checkpoint.kind == .finish }) {
            checkpointLines.append(String(format: String(localized: "card.finish_line"), distance(plan.distanceKm), duration(plan.activeTargetSeconds), clock.string(from: plan.startTime.addingTimeInterval(TimeInterval(plan.activeTargetSeconds)))))
        }
        let checkpointSection = RaceCardSection(title: String(localized: "通過地点・関門"), lines: checkpointLines)

        let paceLines: [String]
        if let selected = plan.selectedPacePlan {
            paceLines = selected.segments.map { segment in
                let pace = RacePlanCalculator.targetPace(totalSeconds: segment.targetSeconds,
                    distanceKm: segment.endDistanceKm - segment.startDistanceKm)
                let elapsed = RacePlanCalculator.elapsedSeconds(at: segment.endDistanceKm, for: plan)
                return String(format: String(localized: "card.pace_line"), distance(segment.startDistanceKm), distance(segment.endDistanceKm), pace.displayText, duration(elapsed), clock.string(from: plan.startTime.addingTimeInterval(TimeInterval(elapsed))))
            }
        } else {
            var previous = 0.0
            paceLines = calculation.splitTimes.map { split in
                defer { previous = split.distanceKm }
                return String(format: String(localized: "card.pace_line"), distance(previous), split.distanceText, calculation.targetPaceText, split.elapsedTimeText, clock.string(from: plan.startTime.addingTimeInterval(TimeInterval(split.elapsedSeconds))))
            }
        }
        let paceSection = RaceCardSection(title: String(localized: "区間ペース・通過予定"), lines: paceLines)

        let fuelingLines: [String]
        if !plan.fuelingEvents.isEmpty {
            fuelingLines = RaceFuelingPlanCalculator.schedule(for: plan).map { scheduled in
                let event = scheduled.event
                var line = "\(distance(scheduled.distanceKm))"
                if let name = scheduled.checkpointName { line += " \(name)" }
                line += String(format: String(localized: "card.elapsed_time"), duration(scheduled.elapsedSeconds), clock.string(from: scheduled.passingTime))
                line += "\n\(event.kind.title)・\(event.name) ×\(event.quantity)・\(event.pickup.title)"
                if let grams = event.carbohydrateGramsPerItem { line += String(format: String(localized: "card.carbs"), grams.formatted()) }
                if event.containsCaffeine { line += String(localized: "card.caffeine") }
                if !event.note.isEmpty { line += String(format: String(localized: "card.fueling_note"), event.note) }
                return line
            }
        } else {
            fuelingLines = calculation.fuelTimings.enumerated().map { index, timing in
                let names = plan.gelNames ?? []
                let name = index < names.count && !names[index].isEmpty ? names[index] : String(localized: "補給ジェル")
                let elapsed = RacePlanCalculator.elapsedSeconds(at: timing.distanceKm, for: plan)
                return String(format: String(localized: "card.legacy_fuel"), timing.displayText, duration(elapsed), clock.string(from: plan.startTime.addingTimeInterval(TimeInterval(elapsed))), name)
            }
        }
        let fuelingSection = RaceCardSection(title: String(localized: "補給・給水"), lines: fuelingLines.isEmpty ? [String(localized: "補給予定なし")] : fuelingLines)
        let requirements = RaceFuelingPlanCalculator.requirements(for: plan.fuelingEvents)
        let requirementsSection = RaceCardSection(title: String(localized: "必要な補給品"), lines: requirements.map {
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
        if !plan.memo.isEmpty { sections.append(RaceCardSection(title: String(localized: "大会メモ"), lines: [plan.memo])) }
        self.sections = sections
    }
}

enum RaceCardError: LocalizedError {
    case invalidPlan(String)
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .invalidPlan(let message): message
        case .generationFailed: String(localized: "出力を作成できませんでした。空き容量と計画の内容を確認してください。")
        }
    }
}
