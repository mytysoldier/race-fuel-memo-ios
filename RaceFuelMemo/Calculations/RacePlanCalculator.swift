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
            return stride(from: 5.0, through: distanceKm, by: 5.0)
                .map { min($0, distanceKm) }
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

    static func formatDistance(_ distanceKm: Double) -> String {
        let rounded = distanceKm.rounded()

        if abs(distanceKm - rounded) < 0.001 {
            return "\(Int(rounded))km"
        }

        return String(format: "%.3fkm", distanceKm)
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
