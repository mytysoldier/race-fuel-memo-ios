import Foundation

enum RacePacePlanCalculator {
    static func initialPlan(for racePlan: RacePlan) -> RacePacePlan {
        let target = RacePlanCalculator.targetDurationSeconds(
            hours: racePlan.targetHours, minutes: racePlan.targetMinutes
        )
        var plan = normalized(RacePacePlan(order: 0, name: "A・目標達成",
                                           targetSeconds: target),
                              raceDistanceKm: racePlan.distanceKm,
                              checkpoints: racePlan.checkpoints)
        let explicit = racePlan.checkpoints.compactMap { checkpoint -> (Double, Int)? in
            checkpoint.plannedElapsedSeconds.map { (checkpoint.distanceKm, $0) }
        }.sorted { $0.0 < $1.0 }
        guard !explicit.isEmpty else { return plan }
        let anchors = [(0.0, 0)] + explicit + [(racePlan.distanceKm, target)]
        var previousElapsed = 0
        for index in plan.segments.indices {
            let distance = plan.segments[index].endDistanceKm
            guard let upperIndex = anchors.firstIndex(where: { $0.0 >= distance }) else { return plan }
            let upper = anchors[upperIndex]
            let lower = anchors[max(0, upperIndex - 1)]
            let elapsed: Int
            if abs(upper.0 - lower.0) < 0.000_001 {
                elapsed = upper.1
            } else {
                elapsed = lower.1 + Int((Double(upper.1 - lower.1)
                    * (distance - lower.0) / (upper.0 - lower.0)).rounded())
            }
            guard elapsed > previousElapsed else {
                return normalized(RacePacePlan(order: 0, name: "A・目標達成",
                                               targetSeconds: target),
                                  raceDistanceKm: racePlan.distanceKm,
                                  checkpoints: racePlan.checkpoints)
            }
            plan.segments[index].targetSeconds = elapsed - previousElapsed
            previousElapsed = elapsed
        }
        plan.strategy = .custom
        return plan
    }

    static func normalized(_ plan: RacePacePlan, raceDistanceKm: Double,
                           checkpoints: [RaceCheckpoint]) -> RacePacePlan {
        guard raceDistanceKm.isFinite, raceDistanceKm > 0, plan.targetSeconds > 0 else { return plan }
        var result = plan
        result.halfDifferenceSeconds = min(max(0, result.halfDifferenceSeconds),
                                           max(0, result.targetSeconds - 1))
        result.kickDistanceKm = min(max(0, result.kickDistanceKm),
                                    max(0, raceDistanceKm - 0.5))
        result.kickGainSecondsPerKm = min(max(0, result.kickGainSecondsPerKm), 120)
        let boundaries = segmentBoundaries(distanceKm: raceDistanceKm,
                                           checkpoints: checkpoints, plan: result)
        let oldDistance = plan.segments.last?.endDistanceKm ?? raceDistanceKm
        let oldTotal = plan.segments.reduce(0) { $0 + max(0, $1.targetSeconds) }
        let starts = [0.0] + boundaries.dropLast()
        let ranges = zip(starts, boundaries).map { start, end in (start, end) }
        let weights: [Double]
        if plan.strategy == .custom, oldTotal > 0, oldDistance > 0 {
            weights = ranges.map { start, end in
                let startElapsed = rawElapsedSeconds(at: start / raceDistanceKm * oldDistance,
                                                     segments: plan.segments)
                let endElapsed = rawElapsedSeconds(at: end / raceDistanceKm * oldDistance,
                                                   segments: plan.segments)
                return Double(max(1, endElapsed - startElapsed))
            }
        } else {
            let segments = ranges.map { start, end -> (distance: Double, density: Double, hasKick: Bool) in
                let midpoint = (start + end) / 2
                let halfFactor = Double(result.halfDifferenceSeconds) / Double(plan.targetSeconds)
                let density: Double
                switch result.strategy {
                case .negative:
                    density = midpoint < raceDistanceKm / 2 ? 1 + halfFactor : 1 - halfFactor
                case .positive:
                    density = midpoint < raceDistanceKm / 2 ? 1 - halfFactor : 1 + halfFactor
                case .even, .custom:
                    density = 1
                }
                return (end - start, density,
                        result.kickDistanceKm > 0 && midpoint >= raceDistanceKm - result.kickDistanceKm)
            }
            let densityDistance = segments.reduce(0.0) { $0 + $1.distance * $1.density }
            let kickDistance = segments.reduce(0.0) { $0 + ($1.hasKick ? $1.distance : 0) }
            let kickGain = Double(result.kickGainSecondsPerKm)
            // Raise the base pace by the total saved kick time first. The kick can
            // then be subtracted directly without a second proportional scaling.
            let baseSecondsPerKm = (Double(plan.targetSeconds) + kickGain * kickDistance) / densityDistance
            weights = segments.map { segment in
                segment.distance * (baseSecondsPerKm * segment.density
                                    - (segment.hasKick ? kickGain : 0))
            }
        }
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0, plan.targetSeconds >= boundaries.count else { return plan }
        var usedSeconds = 0
        var usedWeight = 0.0
        var start = 0.0
        result.segments = boundaries.enumerated().map { index, end in
            usedWeight += weights[index]
            let remaining = boundaries.count - index - 1
            let cumulative = index == boundaries.count - 1 ? plan.targetSeconds
                : min(plan.targetSeconds - remaining,
                      max(usedSeconds + 1, Int((Double(plan.targetSeconds) * usedWeight / totalWeight).rounded())))
            let existingID = plan.segments.first {
                abs($0.startDistanceKm - start) < 0.000_001
                    && abs($0.endDistanceKm - end) < 0.000_001
            }?.id ?? UUID()
            let segment = RacePaceSegment(id: existingID, order: index, startDistanceKm: start,
                                          endDistanceKm: end, targetSeconds: cumulative - usedSeconds)
            start = end
            usedSeconds = cumulative
            return segment
        }
        return result
    }

    static func changingSegment(_ plan: RacePacePlan, at index: Int, to seconds: Int) -> RacePacePlan {
        guard plan.segments.indices.contains(index), plan.segments.count > 1 else { return plan }
        var result = plan
        result.strategy = .custom
        let selected = min(max(1, seconds), plan.targetSeconds - plan.segments.count + 1)
        result.segments[index].targetSeconds = selected
        let otherTotal = plan.segments.enumerated().reduce(0) { partial, entry in
            partial + (entry.offset == index ? 0 : max(1, entry.element.targetSeconds))
        }
        var remainingSeconds = plan.targetSeconds - selected
        var remainingWeight = otherTotal
        for otherIndex in result.segments.indices where otherIndex != index {
            let remainingCount = result.segments.indices.filter { $0 != index && $0 > otherIndex }.count
            let weight = max(1, plan.segments[otherIndex].targetSeconds)
            let assigned = remainingCount == 0 ? remainingSeconds
                : min(remainingSeconds - remainingCount,
                      max(1, Int((Double(remainingSeconds) * Double(weight) / Double(remainingWeight)).rounded())))
            result.segments[otherIndex].targetSeconds = assigned
            remainingSeconds -= assigned
            remainingWeight -= weight
        }
        return result
    }

    static func elapsedSeconds(at distanceKm: Double, in plan: RacePacePlan,
                               raceDistanceKm: Double) -> Int {
        guard raceDistanceKm > 0, distanceKm.isFinite else { return 0 }
        let distance = min(max(0, distanceKm), raceDistanceKm)
        guard hasValidSegments(plan, distanceKm: raceDistanceKm) else {
            return Int((Double(plan.targetSeconds) * distance / raceDistanceKm).rounded())
        }
        var elapsed = 0
        for segment in plan.segments {
            if distance >= segment.endDistanceKm - 0.000_001 {
                elapsed += segment.targetSeconds
            } else {
                let fraction = (distance - segment.startDistanceKm)
                    / (segment.endDistanceKm - segment.startDistanceKm)
                return elapsed + Int((Double(segment.targetSeconds) * max(0, fraction)).rounded())
            }
        }
        return elapsed
    }

    static func validationError(for racePlan: RacePlan) -> String? {
        let plans = racePlan.pacePlans
        guard plans.count <= 3 else { return "ペースプランはA・B・Cの最大3つです。" }
        guard Set(plans.map(\.id)).count == plans.count,
              Set(plans.map(\.order)).count == plans.count else {
            return "ペースプランの識別子または順序が重複しています。"
        }
        if let selected = racePlan.selectedPacePlanID,
           !plans.contains(where: { $0.id == selected }) {
            return "選択中のペースプランが見つかりません。"
        }
        if !plans.isEmpty && racePlan.selectedPacePlanID == nil {
            return "使用するペースプランを選択してください。"
        }
        for plan in plans {
            guard !plan.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  plan.targetSeconds > 0,
                  plan.targetSeconds <= 240 * 3_600 + 59 * 60 else {
                return "ペースプラン名と目標タイムを確認してください。"
            }
            guard hasValidSegments(plan, distanceKm: racePlan.distanceKm) else {
                return "区間の距離と時間の合計を確認してください。"
            }
        }
        return nil
    }

    private static func hasValidSegments(_ plan: RacePacePlan, distanceKm: Double) -> Bool {
        guard !plan.segments.isEmpty else { return false }
        guard Set(plan.segments.map(\.id)).count == plan.segments.count else { return false }
        var previousEnd = 0.0
        var total = 0
        for (index, segment) in plan.segments.enumerated() {
            guard segment.order == index,
                  abs(segment.startDistanceKm - previousEnd) < 0.000_001,
                  segment.endDistanceKm.isFinite,
                  segment.endDistanceKm > segment.startDistanceKm + 0.000_001,
                  segment.targetSeconds > 0 else { return false }
            previousEnd = segment.endDistanceKm
            total += segment.targetSeconds
        }
        return abs(previousEnd - distanceKm) < 0.000_001 && total == plan.targetSeconds
    }

    private static func rawElapsedSeconds(at distanceKm: Double,
                                          segments: [RacePaceSegment]) -> Int {
        var elapsed = 0
        for segment in segments {
            guard segment.endDistanceKm > segment.startDistanceKm,
                  segment.targetSeconds > 0 else { return elapsed }
            if distanceKm >= segment.endDistanceKm {
                elapsed += segment.targetSeconds
            } else {
                let fraction = max(0, (distanceKm - segment.startDistanceKm)
                                   / (segment.endDistanceKm - segment.startDistanceKm))
                return elapsed + Int((Double(segment.targetSeconds) * fraction).rounded())
            }
        }
        return elapsed
    }

    private static func segmentBoundaries(distanceKm: Double, checkpoints: [RaceCheckpoint],
                                          plan: RacePacePlan) -> [Double] {
        var distances = RacePlanCalculator.splitDistances(for: distanceKm)
        distances += checkpoints.map(\.distanceKm)
        distances += [distanceKm / 2, distanceKm]
        if plan.kickDistanceKm > 0, plan.kickDistanceKm < distanceKm {
            distances.append(distanceKm - plan.kickDistanceKm)
        }
        return distances.filter { $0.isFinite && $0 > 0 && $0 <= distanceKm }
            .sorted()
            .reduce(into: [Double]()) { result, distance in
                if let last = result.last, abs(last - distance) < 0.000_001 { return }
                result.append(distance)
            }
    }
}

extension RacePlan {
    mutating func normalizePacePlans() {
        for index in pacePlans.indices {
            pacePlans[index] = RacePacePlanCalculator.normalized(
                pacePlans[index], raceDistanceKm: distanceKm, checkpoints: checkpoints
            )
        }
    }
}
