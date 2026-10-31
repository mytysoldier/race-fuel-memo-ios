import Foundation

enum RacePlanReuseComponent: String, CaseIterable, Identifiable {
    case basics, pace, fueling, checklist

    var id: String { rawValue }
    var title: String {
        switch self {
        case .basics: "距離・基本目標タイム"
        case .pace: "ペース戦略・A・B・Cプラン"
        case .fueling: "補給・給水セット"
        case .checklist: "チェックリスト"
        }
    }
}

/// Only reusable settings are persisted: no race dates, course points, or completion state.
struct RacePlanTemplate: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    let distanceKm: Double
    let targetHours: Int
    let targetMinutes: Int
    let pacePlans: [RacePacePlan]
    let selectedPacePlanID: UUID?
    let gelCount: Int
    let gelNames: [String]
    let fuelingEvents: [RaceFuelingEvent]
    let checklistItems: [ChecklistTemplateItem]

    init(id: UUID = UUID(), name: String, source: RacePlan) {
        self.id = id
        self.name = name
        distanceKm = source.distanceKm
        targetHours = source.targetHours
        targetMinutes = source.targetMinutes
        pacePlans = source.pacePlans
        selectedPacePlanID = source.selectedPacePlanID
        gelCount = source.gelCount
        gelNames = source.gelNames ?? []
        fuelingEvents = source.fuelingEvents.map { event in
            var reusable = event
            if let checkpoint = source.checkpoints.first(where: { $0.id == event.checkpointID }) {
                reusable.distanceKm = checkpoint.distanceKm
                reusable.elapsedSeconds = nil
            }
            reusable.checkpointID = nil
            return reusable
        }
        checklistItems = source.checklistItems.sorted { $0.order < $1.order }
            .map(ChecklistTemplateItem.init)
    }

    func applying(to destination: RacePlan, components: Set<RacePlanReuseComponent>) throws -> RacePlan {
        var result = destination
        if components.contains(.basics) {
            result.distanceKm = distanceKm
            result.targetHours = targetHours
            result.targetMinutes = targetMinutes
        }
        if (components.contains(.pace) || components.contains(.fueling)),
           abs(result.distanceKm - distanceKm) > 0.000_001 {
            throw RacePlanReuseError.incompatibleDistance
        }
        if components.contains(.pace) {
            let copied = pacePlans.freshCopies(selectedID: selectedPacePlanID)
            result.pacePlans = copied.plans
            result.selectedPacePlanID = copied.selectedID
        }
        if components.contains(.fueling) {
            result.gelCount = gelCount
            result.gelNames = gelNames
            result.fuelingEvents = fuelingEvents.map { $0.freshCopy(checkpointID: nil) }
        }
        if components.contains(.checklist) {
            result.checklistItems = checklistItems.enumerated().map { index, item in
                ChecklistItem(title: item.title, order: index, category: item.category,
                              isRequired: item.isRequired, dueTiming: item.dueTiming)
            }
            result.checklistNotificationsEnabled = false
        }
        if components.contains(.basics) {
            result.normalizeFinishCheckpoints()
        }
        if components.contains(.basics) || components.contains(.pace) {
            result.normalizePacePlans()
        }
        if let error = RaceCheckpointValidator.error(for: result) {
            throw RacePlanReuseError.invalidSettings(error)
        }
        return result
    }
}

enum RacePlanReuseError: LocalizedError {
    case incompatibleDistance
    case invalidSettings(String)

    var errorDescription: String? {
        switch self {
        case .incompatibleDistance:
            "距離が異なるため、ペース・補給を適用できません。「距離・基本目標タイム」も選ぶか、同じ距離の設定を選んでください。"
        case .invalidSettings(let message): message
        }
    }
}

extension RacePlan {
    /// Value copies also need fresh identities and remapped references for every nested element.
    func duplicated() -> RacePlan {
        var checkpointIDs: [UUID: UUID] = [:]
        let copiedCheckpoints = checkpoints.map { checkpoint in
            let id = UUID()
            checkpointIDs[checkpoint.id] = id
            return RaceCheckpoint(id: id, order: checkpoint.order, name: checkpoint.name,
                                  distanceKm: checkpoint.distanceKm, plannedElapsedSeconds: checkpoint.plannedElapsedSeconds,
                                  cutoffTime: checkpoint.cutoffTime, hasAidStation: checkpoint.hasAidStation,
                                  kind: checkpoint.kind, segmentNote: checkpoint.segmentNote, cautionNote: checkpoint.cautionNote)
        }
        let copiedPace = pacePlans.freshCopies(selectedID: selectedPacePlanID)
        var duplicate = RacePlan(
            name: "\(name) コピー", raceDate: raceDate, startTime: startTime,
            distanceKm: distanceKm, targetHours: targetHours, targetMinutes: targetMinutes,
            gelCount: gelCount, gelNames: gelNames ?? [], memo: memo,
            checklistItems: checklistItems.map {
                ChecklistItem(title: $0.title, order: $0.order, category: $0.category,
                              isRequired: $0.isRequired, dueDate: $0.dueDate, dueTiming: $0.dueTiming)
            },
            checklistNotificationsEnabled: false,
            checkpoints: copiedCheckpoints,
            pacePlans: copiedPace.plans, selectedPacePlanID: copiedPace.selectedID,
            fuelingEvents: fuelingEvents.map {
                $0.freshCopy(checkpointID: $0.checkpointID.flatMap { checkpointIDs[$0] })
            }
        )
        duplicate.courseElevation = courseElevation
        for (source, copy) in zip(pacePlans, copiedPace.plans) {
            guard let baseline = adjustmentBaseline(for: source) else { continue }
            let ids = Dictionary(uniqueKeysWithValues: zip(source.segments, copy.segments).map { ($0.id, $1.id) })
            let copiedBaseline = RacePacePlan(
                id: copy.id, order: baseline.order, name: baseline.name,
                targetSeconds: baseline.targetSeconds,
                segments: baseline.segments.map {
                    RacePaceSegment(id: ids[$0.id] ?? UUID(), order: $0.order,
                                    startDistanceKm: $0.startDistanceKm, endDistanceKm: $0.endDistanceKm,
                                    targetSeconds: $0.targetSeconds)
                }, strategy: baseline.strategy, halfDifferenceSeconds: baseline.halfDifferenceSeconds,
                kickDistanceKm: baseline.kickDistanceKm, kickGainSecondsPerKm: baseline.kickGainSecondsPerKm)
            duplicate.setCourseAdjustment(original: copiedBaseline, adjusted: copy)
        }
        return duplicate
    }
}

private extension Array where Element == RacePacePlan {
    func freshCopies(selectedID: UUID?) -> (plans: [RacePacePlan], selectedID: UUID?) {
        var newSelectedID: UUID?
        let plans = map { plan in
            let id = UUID()
            if plan.id == selectedID { newSelectedID = id }
            return RacePacePlan(id: id, order: plan.order, name: plan.name,
                                targetSeconds: plan.targetSeconds,
                                segments: plan.segments.map {
                                    RacePaceSegment(order: $0.order, startDistanceKm: $0.startDistanceKm,
                                                    endDistanceKm: $0.endDistanceKm, targetSeconds: $0.targetSeconds)
                                }, strategy: plan.strategy, halfDifferenceSeconds: plan.halfDifferenceSeconds,
                                kickDistanceKm: plan.kickDistanceKm, kickGainSecondsPerKm: plan.kickGainSecondsPerKm)
        }
        return (plans, newSelectedID)
    }
}

private extension RaceFuelingEvent {
    func freshCopy(checkpointID: UUID?) -> RaceFuelingEvent {
        RaceFuelingEvent(order: order, name: name, quantity: quantity, distanceKm: distanceKm,
                         elapsedSeconds: elapsedSeconds, checkpointID: checkpointID, kind: kind,
                         carbohydrateGramsPerItem: carbohydrateGramsPerItem,
                         containsCaffeine: containsCaffeine, note: note, pickup: pickup)
    }
}
