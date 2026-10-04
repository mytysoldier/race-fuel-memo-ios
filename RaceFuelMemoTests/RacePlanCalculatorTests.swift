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
    #expect(RacePlanCalculator.roundedElapsedSecondsToWholeMinute(3_413) == 3_420)
    #expect(RacePlanCalculator.suggestedManualCheckpointElapsedSeconds(
        totalSeconds: 14_400, checkpointDistanceKm: 42.15, raceDistanceKm: 42.195, isFinish: false
    ) == 14_340)
    #expect(RacePlanCalculator.suggestedManualCheckpointElapsedSeconds(
        totalSeconds: 14_400, checkpointDistanceKm: 42.195, raceDistanceKm: 42.195, isFinish: true
    ) == 14_400)
    #expect(RacePlanCalculator.suggestedManualCheckpointElapsedSeconds(
        totalSeconds: 1_200, checkpointDistanceKm: 0.1, raceDistanceKm: 5, isFinish: false
    ) == 60)
    #expect(RacePlanCalculator.boundedManualCheckpointElapsedSeconds(
        60, after: 60, before: 1_200
    ) == 120)
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

@Test func selectingFinishNormalizesManualElapsedTime() {
    let racePlan = makeRacePlan()
    var checkpoint = RaceCheckpoint(
        order: 0,
        name: "ゴール",
        distanceKm: 20,
        plannedElapsedSeconds: 7_200
    )
    checkpoint.kind = .finish

    let normalizedCheckpoint = racePlan.normalizedFinishCheckpoint(checkpoint)

    #expect(normalizedCheckpoint.distanceKm == racePlan.distanceKm)
    #expect(normalizedCheckpoint.plannedElapsedSeconds == 14_400)
}

@Test func cutoffTimesMoveWithRaceStartChanges() {
    let originalStart = Date(timeIntervalSinceReferenceDate: 86_400)
    let updatedStart = originalStart.addingTimeInterval(7 * 86_400 + 30 * 60)
    var racePlan = RacePlan(
        name: "日程変更レース",
        raceDate: originalStart,
        startTime: originalStart,
        distanceKm: 20,
        targetHours: 4,
        targetMinutes: 0,
        gelCount: 0,
        checkpoints: [RaceCheckpoint(
            order: 0,
            name: "関門",
            distanceKm: 10,
            cutoffTime: originalStart.addingTimeInterval(3 * 3_600),
            kind: .cutoff
        )]
    )

    racePlan.raceDate = updatedStart
    racePlan.startTime = updatedStart
    racePlan.moveCutoffTimes(from: originalStart, to: updatedStart)

    #expect(racePlan.checkpoints[0].cutoffTime == updatedStart.addingTimeInterval(3 * 3_600))
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

@Test func paceStrategiesKeepGoalAndMoveHalfwayPassingTime() {
    let distance = 20.0
    let target = 7_200
    let strategies: [RacePaceStrategy] = [.even, .negative, .positive, .custom]
    let plans = strategies.map { strategy in
        RacePacePlanCalculator.normalized(
            RacePacePlan(order: 0, name: strategy.title, targetSeconds: target,
                         strategy: strategy, halfDifferenceSeconds: 600),
            raceDistanceKm: distance, checkpoints: []
        )
    }

    for plan in plans {
        #expect(plan.segments.first?.startDistanceKm == 0)
        #expect(plan.segments.last?.endDistanceKm == distance)
        #expect(plan.segments.reduce(0) { $0 + $1.targetSeconds } == target)
        #expect(RacePacePlanCalculator.elapsedSeconds(at: distance, in: plan,
                                                       raceDistanceKm: distance) == target)
    }
    #expect(RacePacePlanCalculator.elapsedSeconds(at: 10, in: plans[0], raceDistanceKm: distance) == 3_600)
    #expect(RacePacePlanCalculator.elapsedSeconds(at: 10, in: plans[1], raceDistanceKm: distance) == 3_900)
    #expect(RacePacePlanCalculator.elapsedSeconds(at: 10, in: plans[2], raceDistanceKm: distance) == 3_300)
}

@Test func customSegmentEditsAndTargetChangesPreserveTotal() {
    var plan = RacePacePlanCalculator.normalized(
        RacePacePlan(order: 0, name: "A", targetSeconds: 3_600),
        raceDistanceKm: 10, checkpoints: []
    )
    plan = RacePacePlanCalculator.changingSegment(plan, at: 0,
                                                   to: plan.segments[0].targetSeconds + 300)
    #expect(plan.strategy == .custom)
    #expect(plan.segments.reduce(0) { $0 + $1.targetSeconds } == 3_600)
    #expect(RacePacePlanCalculator.elapsedSeconds(at: 5, in: plan, raceDistanceKm: 10) > 1_800)

    plan.targetSeconds = 4_200
    plan = RacePacePlanCalculator.normalized(plan, raceDistanceKm: 10, checkpoints: [])
    #expect(plan.segments.reduce(0) { $0 + $1.targetSeconds } == 4_200)
    #expect(RacePacePlanCalculator.elapsedSeconds(at: 10, in: plan, raceDistanceKm: 10) == 4_200)
}

@Test func selectedPacePlanChangesCheckpointsAndCutoffWarnings() throws {
    var race = makeRacePlan()
    race.distanceKm = 20
    race.checkpoints = [RaceCheckpoint(
        order: 0, name: "関門", distanceKm: 10,
        cutoffTime: race.startTime.addingTimeInterval(3_800), kind: .cutoff
    )]
    let quick = RacePacePlan(order: 0, name: "A", targetSeconds: 7_200)
    let cautious = RacePacePlan(order: 1, name: "B", targetSeconds: 9_000)
    race.pacePlans = [quick, cautious]
    race.selectedPacePlanID = quick.id
    race.normalizePacePlans()
    #expect(RaceCheckpointValidator.error(for: race) == nil)
    #expect(RacePlanCalculator.checkpointSchedules(for: race)[0].cutoffMarginSeconds == 200)

    race.selectedPacePlanID = cautious.id
    #expect(RacePlanCalculator.calculate(for: race).splitTimes.last?.elapsedSeconds == 9_000)
    #expect(RacePlanCalculator.checkpointSchedules(for: race)[0].cutoffMarginSeconds == -700)
}

@Test func pacePlanValidationRejectsMoreThanThreeAndBadSelection() {
    var race = makeRacePlan()
    race.pacePlans = (0..<4).map { index in
        RacePacePlanCalculator.normalized(
            RacePacePlan(order: index, name: "\(index)", targetSeconds: 14_400),
            raceDistanceKm: race.distanceKm, checkpoints: []
        )
    }
    #expect(RacePacePlanCalculator.validationError(for: race) != nil)
    race.pacePlans.removeLast()
    race.selectedPacePlanID = UUID()
    #expect(RacePacePlanCalculator.validationError(for: race) != nil)
}

@Test func firstPacePlanRetainsExistingManualCheckpointTime() {
    var race = makeRacePlan()
    race.distanceKm = 20
    race.checkpoints = [RaceCheckpoint(order: 0, name: "中間", distanceKm: 10,
                                       plannedElapsedSeconds: 8_000)]

    let first = RacePacePlanCalculator.initialPlan(for: race)
    #expect(first.strategy == .custom)
    #expect(RacePacePlanCalculator.elapsedSeconds(at: 10, in: first,
                                                   raceDistanceKm: 20) == 8_000)
    #expect(first.segments.reduce(0) { $0 + $1.targetSeconds } == 14_400)
}

@Test func finalKickMakesLastSectionFasterWithoutMovingGoal() {
    let plan = RacePacePlanCalculator.normalized(
        RacePacePlan(order: 0, name: "A", targetSeconds: 7_200,
                     kickDistanceKm: 5, kickGainSecondsPerKm: 30),
        raceDistanceKm: 20, checkpoints: []
    )
    let beforeKick = RacePacePlanCalculator.elapsedSeconds(at: 15, in: plan, raceDistanceKm: 20)
    #expect(beforeKick > 5_400)
    #expect(RacePacePlanCalculator.elapsedSeconds(at: 20, in: plan, raceDistanceKm: 20) == 7_200)
}

@Test func distanceChangeRebuildsCustomSegmentsWithoutLosingGoal() {
    var race = makeRacePlan()
    race.distanceKm = 10
    var custom = RacePacePlanCalculator.normalized(
        RacePacePlan(order: 0, name: "A", targetSeconds: 3_600),
        raceDistanceKm: 10, checkpoints: []
    )
    custom = RacePacePlanCalculator.changingSegment(custom, at: 0, to: 2_000)
    race.pacePlans = [custom]
    race.selectedPacePlanID = custom.id
    race.distanceKm = 20
    race.normalizePacePlans()

    #expect(RacePacePlanCalculator.validationError(for: race) == nil)
    #expect(race.pacePlans[0].segments.last?.endDistanceKm == 20)
    #expect(race.pacePlans[0].segments.reduce(0) { $0 + $1.targetSeconds } == 3_600)
    #expect(RacePacePlanCalculator.elapsedSeconds(at: 10, in: race.pacePlans[0],
                                                   raceDistanceKm: 20) == 2_000)
}
