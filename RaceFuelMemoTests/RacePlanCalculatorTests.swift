import Foundation
import Testing
@testable import RaceFuelMemo

@Test func fullMarathonFourHoursCalculatesExpectedPaceAndSplits() {
    let calculation = RacePlanCalculator.calculate(for: makeRacePlan())

    #expect(calculation.targetPace.secondsPerKilometer == 341)
    #expect(calculation.splitTimes.map(\.distanceKm) == [5, 10, 15, 20, 25, 30, 35, 40, 42.195])
    #expect(calculation.splitTimes.last?.elapsedSeconds == 14_400)
}

@Test func fuelTimingsAreEvenlySpacedForFullMarathon() {
    let timings = RacePlanCalculator.fuelTimings(gelCount: 4, distanceKm: DistanceOption.fullMarathon.distanceKm)

    #expect(timings.map(\.distanceKm) == [10, 16.25, 22.5, 28.75])
}

@Test func invalidInputsProduceSafeEmptyCalculation() {
    #expect(RacePlanCalculator.targetPace(totalSeconds: 0, distanceKm: 10).secondsPerKilometer == 0)
    #expect(RacePlanCalculator.splitTimes(totalSeconds: 3_600, distanceKm: 0).isEmpty)
    #expect(RacePlanCalculator.fuelTimings(gelCount: 0, distanceKm: 10).isEmpty)
    #expect(RacePlanCalculator.estimatedCheckpointElapsedSeconds(
        totalSeconds: 14_400, checkpointDistanceKm: 10, raceDistanceKm: 0
    ) == nil)
    #expect(RacePlanCalculator.estimatedCheckpointElapsedSeconds(
        totalSeconds: 14_400, checkpointDistanceKm: 10, raceDistanceKm: 20
    ) == 7_200)
}

@Test func finishCheckpointFollowsUpdatedRaceDetails() {
    var racePlan = makeRacePlan()
    racePlan.checkpoints = [RaceCheckpoint(
        order: 0,
        name: "ゴール",
        distanceKm: 42.195,
        plannedElapsedSeconds: 14_400,
        kind: .finish
    )]
    racePlan.distanceKm = 50
    racePlan.targetHours = 5

    racePlan.normalizeFinishCheckpoints()

    #expect(racePlan.checkpoints[0].distanceKm == 50)
    #expect(racePlan.checkpoints[0].plannedElapsedSeconds == 18_000)
    #expect(RaceCheckpointValidator.error(for: racePlan) == nil)
}

@Test func formatsDistanceAndDuration() {
    #expect(RacePlanCalculator.formatDistance(42) == "42km")
    #expect(RacePlanCalculator.formatDistance(42.195) == "42.195km")
    #expect(RacePlanCalculator.formatDistance(21.0975) == "21.0975km")
    #expect(RacePlanCalculator.formatDuration(14_400) == "4時間0分0秒")
    #expect(RacePlanCalculator.formatDuration(341) == "5分41秒")
}

@Test func arbitraryDistanceIncludesFinishSplit() {
    #expect(RacePlanCalculator.splitDistances(for: 12.5) == [5, 10, 12.5])
    #expect(RacePlanCalculator.splitDistances(for: 1) == [1])
}

@Test func checkpointsInterpolateBetweenExplicitTimesAndCalculateOvernightCutoff() throws {
    let start = Date(timeIntervalSinceReferenceDate: 86_400 + 23 * 3_600)
    var racePlan = RacePlan(name: "夜間レース", raceDate: start, startTime: start,
                            distanceKm: 20, targetHours: 4, targetMinutes: 0, gelCount: 0)
    racePlan.checkpoints = [
        RaceCheckpoint(order: 0, name: "給水", distanceKm: 5, kind: .aidStation),
        RaceCheckpoint(order: 1, name: "関門", distanceKm: 10,
                       plannedElapsedSeconds: 6_000,
                       cutoffTime: start.addingTimeInterval(6_900), kind: .cutoff),
        RaceCheckpoint(order: 2, name: "折り返し", distanceKm: 15, kind: .turnaround),
        RaceCheckpoint(order: 3, name: "ゴール", distanceKm: 20, kind: .finish)
    ]

    #expect(RaceCheckpointValidator.error(for: racePlan) == nil)
    let schedules = RacePlanCalculator.checkpointSchedules(for: racePlan)
    #expect(schedules.map(\.elapsedSeconds) == [3_000, 6_000, 10_200, 14_400])
    #expect(schedules[1].passingTime == start.addingTimeInterval(6_000))
    #expect(schedules[1].cutoffMarginSeconds == 900)
}

@Test func reorderedCheckpointsFollowSavedOrderAndShowCutoffOverrun() {
    var racePlan = makeRacePlan()
    racePlan.distanceKm = 20
    racePlan.checkpoints = [
        RaceCheckpoint(order: 1, name: "後半", distanceKm: 15,
                       cutoffTime: racePlan.startTime.addingTimeInterval(5_000)),
        RaceCheckpoint(order: 0, name: "前半", distanceKm: 5)
    ]

    #expect(RaceCheckpointValidator.error(for: racePlan) == nil)
    let schedules = RacePlanCalculator.checkpointSchedules(for: racePlan)
    #expect(schedules.map(\.checkpoint.name) == ["前半", "後半"])
    #expect(schedules[1].cutoffMarginSeconds == -5_800)
}

@Test func checkpointValidationRejectsInvalidDistancesAndTimes() {
    var racePlan = makeRacePlan()
    racePlan.distanceKm = 201
    #expect(RaceCheckpointValidator.error(for: racePlan) != nil)
    racePlan.distanceKm = 20
    racePlan.checkpoints = [
        RaceCheckpoint(order: 0, name: "A", distanceKm: 10),
        RaceCheckpoint(order: 1, name: "B", distanceKm: 10)
    ]
    #expect(RaceCheckpointValidator.error(for: racePlan) != nil)
    racePlan.checkpoints[1].distanceKm = 21
    #expect(RaceCheckpointValidator.error(for: racePlan) != nil)
    racePlan.checkpoints[1].distanceKm = 15
    racePlan.checkpoints[0].plannedElapsedSeconds = 8_000
    racePlan.checkpoints[1].plannedElapsedSeconds = 7_000
    #expect(RaceCheckpointValidator.error(for: racePlan) != nil)
    racePlan.checkpoints[1].plannedElapsedSeconds = 9_000
    racePlan.checkpoints[1].kind = .cutoff
    #expect(RaceCheckpointValidator.error(for: racePlan) != nil)
    racePlan.checkpoints[1].cutoffTime = racePlan.startTime.addingTimeInterval(-60)
    #expect(RaceCheckpointValidator.error(for: racePlan) != nil)
}

private func makeRacePlan() -> RacePlan {
    RacePlan(
        name: "東京マラソン",
        raceDate: .distantFuture,
        startTime: .distantFuture,
        distanceKm: DistanceOption.fullMarathon.distanceKm,
        targetHours: 4,
        targetMinutes: 0,
        gelCount: 4
    )
}
