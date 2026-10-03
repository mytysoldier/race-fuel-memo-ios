import Foundation

struct RacePlanCalculation: Equatable {
    let targetPace: RacePace
    let splitTimes: [RaceSplitTime]
    let fuelTimings: [FuelTiming]

    var targetPaceText: String {
        targetPace.displayText
    }

    var fuelTimingText: String {
        guard !fuelTimings.isEmpty else {
            return "補給予定なし"
        }

        return fuelTimings
            .map(\.displayText)
            .joined(separator: "、")
    }
}

struct RacePace: Equatable {
    let secondsPerKilometer: Int

    var displayText: String {
        let minutes = secondsPerKilometer / 60
        let seconds = secondsPerKilometer % 60

        return "\(minutes)分\(seconds)秒/km"
    }
}

struct RaceSplitTime: Identifiable, Equatable {
    var id: Double {
        distanceKm
    }

    let distanceKm: Double
    let elapsedSeconds: Int

    var distanceText: String {
        RacePlanCalculator.formatDistance(distanceKm)
    }

    var elapsedTimeText: String {
        RacePlanCalculator.formatDuration(elapsedSeconds)
    }
}

struct FuelTiming: Identifiable, Equatable {
    var id: Double {
        distanceKm
    }

    let distanceKm: Double

    var displayText: String {
        "\(RacePlanCalculator.formatDistance(distanceKm))地点"
    }
}

struct RaceCheckpointSchedule: Identifiable, Equatable {
    let checkpoint: RaceCheckpoint
    let elapsedSeconds: Int
    let passingTime: Date
    let cutoffMarginSeconds: Int?

    var id: UUID { checkpoint.id }
}

enum RaceCheckpointValidator {
    static func error(for racePlan: RacePlan) -> String? {
        guard racePlan.distanceKm.isFinite, (1...200).contains(racePlan.distanceKm) else {
            return "レース距離は1〜200kmで入力してください。"
        }
        let targetSeconds = RacePlanCalculator.targetDurationSeconds(
            hours: racePlan.targetHours, minutes: racePlan.targetMinutes
        )
        guard targetSeconds > 0 else { return "目標タイムを入力してください。" }

        let checkpoints = racePlan.checkpoints.sorted { $0.order < $1.order }
        guard Set(checkpoints.map(\.id)).count == checkpoints.count,
              Set(checkpoints.map(\.order)).count == checkpoints.count else {
            return "地点の並び順に重複があります。"
        }
        var previousDistance = 0.0
        var previousElapsed = 0
        var finishCount = 0
        for checkpoint in checkpoints {
            guard !checkpoint.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return "地点名を入力してください。"
            }
            guard checkpoint.distanceKm.isFinite,
                  checkpoint.distanceKm > previousDistance + 0.000_001,
                  checkpoint.distanceKm <= racePlan.distanceKm + 0.000_001 else {
                return "地点の距離は重複せず、ゴールまで昇順に入力してください。"
            }
            if checkpoint.kind == .finish {
                finishCount += 1
                guard abs(checkpoint.distanceKm - racePlan.distanceKm) < 0.000_001 else {
                    return "ゴール地点の距離をレース距離と一致させてください。"
                }
            } else if abs(checkpoint.distanceKm - racePlan.distanceKm) < 0.000_001 {
                return "レース距離の地点はゴールに設定してください。"
            }
            if let elapsed = checkpoint.plannedElapsedSeconds {
                guard elapsed > previousElapsed,
                      elapsed <= targetSeconds,
                      (checkpoint.kind == .finish) == (elapsed == targetSeconds) else {
                    return "地点の予定経過時間は距離順に増え、ゴール時に目標タイムと一致させてください。"
                }
                previousElapsed = elapsed
            }
            if let cutoffTime = checkpoint.cutoffTime,
               cutoffTime <= racePlan.startTime {
                return "関門時刻はスタートより後に設定してください。"
            }
            if checkpoint.kind == .cutoff && checkpoint.cutoffTime == nil {
                return "関門地点には関門時刻を設定してください。"
            }
            previousDistance = checkpoint.distanceKm
        }
        guard finishCount <= 1 else { return "ゴール地点は1つだけ設定してください。" }

        // Explicit times are anchors. Every intervening point must fit between them.
        let anchors = checkpoints.compactMap { checkpoint -> (Double, Int)? in
            checkpoint.plannedElapsedSeconds.map { (checkpoint.distanceKm, $0) }
        }
        var previousAnchor = (distance: 0.0, elapsed: 0)
        for anchor in anchors + [(racePlan.distanceKm, targetSeconds)] {
            if anchor.0 > previousAnchor.distance + 0.000_001 && anchor.1 <= previousAnchor.elapsed {
                return "距離が進む地点の予定経過時間は前の地点より後にしてください。"
            }
            previousAnchor = (anchor.0, anchor.1)
        }
        return nil
    }
}

enum RacePlanCalculator {
    static func calculate(for racePlan: RacePlan) -> RacePlanCalculation {
        let targetSeconds = targetDurationSeconds(
            hours: racePlan.targetHours,
            minutes: racePlan.targetMinutes
        )
        let pace = targetPace(
            totalSeconds: targetSeconds,
            distanceKm: racePlan.distanceKm
        )

        return RacePlanCalculation(
            targetPace: pace,
            splitTimes: splitTimes(
                totalSeconds: targetSeconds,
                distanceKm: racePlan.distanceKm
            ),
            fuelTimings: fuelTimings(
                gelCount: racePlan.gelCount,
                distanceKm: racePlan.distanceKm
            )
        )
    }

    static func targetDurationSeconds(hours: Int, minutes: Int) -> Int {
        max(0, hours) * 3_600 + max(0, minutes) * 60
    }

    static func targetPace(totalSeconds: Int, distanceKm: Double) -> RacePace {
        guard totalSeconds > 0, distanceKm > 0 else {
            return RacePace(secondsPerKilometer: 0)
        }

        let secondsPerKilometer = Int((Double(totalSeconds) / distanceKm).rounded())
        return RacePace(secondsPerKilometer: secondsPerKilometer)
    }

    static func estimatedCheckpointElapsedSeconds(
        totalSeconds: Int,
        checkpointDistanceKm: Double,
        raceDistanceKm: Double
    ) -> Int? {
        guard totalSeconds > 0,
              checkpointDistanceKm.isFinite,
              raceDistanceKm.isFinite,
              checkpointDistanceKm >= 0,
              raceDistanceKm > 0 else {
            return nil
        }

        let estimated = (Double(totalSeconds) * checkpointDistanceKm / raceDistanceKm).rounded()
        guard estimated.isFinite, estimated >= 0, estimated <= Double(Int.max) else {
            return nil
        }
        return Int(estimated)
    }

    static func splitDistances(for distanceKm: Double) -> [Double] {
        switch distanceKm {
        case DistanceOption.fullMarathon.distanceKm:
            return [5, 10, 15, 20, 25, 30, 35, 40, DistanceOption.fullMarathon.distanceKm]
        case DistanceOption.halfMarathon.distanceKm:
            return [5, 10, 15, 20, DistanceOption.halfMarathon.distanceKm]
        case DistanceOption.tenKilometers.distanceKm:
            return [5, DistanceOption.tenKilometers.distanceKm]
        case DistanceOption.fiveKilometers.distanceKm:
            return [DistanceOption.fiveKilometers.distanceKm]
        default:
            let splits = stride(from: 5.0, through: distanceKm, by: 5.0).map { $0 }
            return splits.last == distanceKm ? splits : splits + [distanceKm]
        }
    }

    static func splitTimes(totalSeconds: Int, distanceKm: Double) -> [RaceSplitTime] {
        guard totalSeconds > 0, distanceKm > 0 else {
            return []
        }

        return splitDistances(for: distanceKm).map { splitDistanceKm in
            RaceSplitTime(
                distanceKm: splitDistanceKm,
                elapsedSeconds: Int((Double(totalSeconds) * splitDistanceKm / distanceKm).rounded())
            )
        }
    }

    static func fuelTimings(gelCount: Int, distanceKm: Double) -> [FuelTiming] {
        guard gelCount > 0, distanceKm > 0 else {
            return []
        }

        let distances: [Double]

        switch distanceKm {
        case DistanceOption.fullMarathon.distanceKm:
            distances = evenlySpacedDistances(count: gelCount, startKm: 10, endKm: 35)
        case DistanceOption.halfMarathon.distanceKm:
            distances = centeredDistances(
                count: gelCount,
                centerKm: distanceKm / 2,
                spacingKm: 5,
                minimumKm: 5,
                maximumKm: 16
            )
        case ...DistanceOption.tenKilometers.distanceKm:
            distances = centeredDistances(
                count: gelCount,
                centerKm: distanceKm / 2,
                spacingKm: 2,
                minimumKm: max(1, distanceKm * 0.25),
                maximumKm: distanceKm * 0.75
            )
        default:
            distances = evenlySpacedDistances(
                count: gelCount,
                startKm: max(5, distanceKm * 0.25),
                endKm: min(distanceKm - 2, distanceKm * 0.8)
            )
        }

        return distances.map { FuelTiming(distanceKm: $0) }
    }

    static func checkpointSchedules(for racePlan: RacePlan) -> [RaceCheckpointSchedule] {
        guard RaceCheckpointValidator.error(for: racePlan) == nil else { return [] }
        let checkpoints = racePlan.checkpoints.sorted { $0.order < $1.order }
        let targetSeconds = targetDurationSeconds(hours: racePlan.targetHours, minutes: racePlan.targetMinutes)
        let anchors = [(0.0, 0)]
            + checkpoints.compactMap { checkpoint -> (Double, Int)? in
                checkpoint.plannedElapsedSeconds.map { (checkpoint.distanceKm, $0) }
            }
            + [(racePlan.distanceKm, targetSeconds)]

        return checkpoints.map { checkpoint in
            let elapsed: Int
            if let explicit = checkpoint.plannedElapsedSeconds {
                elapsed = explicit
            } else if let upperIndex = anchors.firstIndex(where: { $0.0 >= checkpoint.distanceKm }) {
                let lower = anchors[max(0, upperIndex - 1)]
                let upper = anchors[upperIndex]
                let fraction = (checkpoint.distanceKm - lower.0) / (upper.0 - lower.0)
                elapsed = lower.1 + Int((Double(upper.1 - lower.1) * fraction).rounded())
            } else {
                elapsed = targetSeconds
            }
            let passingTime = racePlan.startTime.addingTimeInterval(TimeInterval(elapsed))
            return RaceCheckpointSchedule(
                checkpoint: checkpoint,
                elapsedSeconds: elapsed,
                passingTime: passingTime,
                cutoffMarginSeconds: checkpoint.cutoffTime.map {
                    Int($0.timeIntervalSince(passingTime).rounded())
                }
            )
        }
    }

    static func formatDistance(_ distanceKm: Double) -> String {
        let rounded = distanceKm.rounded()

        if abs(distanceKm - rounded) < 0.001 {
            return "\(Int(rounded))km"
        }

        var text = String(format: "%.4f", distanceKm)
        while text.last == "0" { text.removeLast() }
        if text.last == "." { text.removeLast() }
        return "\(text)km"
    }

    static func formatDuration(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours)時間\(minutes)分\(seconds)秒"
        }

        return "\(minutes)分\(seconds)秒"
    }

    private static func evenlySpacedDistances(count: Int, startKm: Double, endKm: Double) -> [Double] {
        guard count > 1 else {
            return [startKm]
        }

        let interval = (endKm - startKm) / Double(count)
        return (0..<count).map { index in
            startKm + interval * Double(index)
        }
    }

    private static func centeredDistances(
        count: Int,
        centerKm: Double,
        spacingKm: Double,
        minimumKm: Double,
        maximumKm: Double
    ) -> [Double] {
        let startKm = centerKm - spacingKm * Double(count - 1) / 2

        return (0..<count).map { index in
            min(
                max(startKm + spacingKm * Double(index), minimumKm),
                maximumKm
            )
        }
    }
}

extension RacePlan {
    var calculation: RacePlanCalculation {
        RacePlanCalculator.calculate(for: self)
    }
}
