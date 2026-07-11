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
}

@Test func formatsDistanceAndDuration() {
    #expect(RacePlanCalculator.formatDistance(42) == "42km")
    #expect(RacePlanCalculator.formatDistance(42.195) == "42.195km")
    #expect(RacePlanCalculator.formatDuration(14_400) == "4時間0分0秒")
    #expect(RacePlanCalculator.formatDuration(341) == "5分41秒")
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
