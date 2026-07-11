import XCTest
@testable import RaceFuelMemo

final class RacePlanCalculatorTests: XCTestCase {
    func testFullMarathonFourHoursCalculatesExpectedPaceAndSplits() {
        let calculation = RacePlanCalculator.calculate(for: makeRacePlan())

        XCTAssertEqual(calculation.targetPace.secondsPerKilometer, 341)
        XCTAssertEqual(calculation.splitTimes.map(\.distanceKm), [5, 10, 15, 20, 25, 30, 35, 40, 42.195])
        XCTAssertEqual(calculation.splitTimes.last?.elapsedSeconds, 14_400)
    }

    func testFuelTimingsAreEvenlySpacedForFullMarathon() {
        let timings = RacePlanCalculator.fuelTimings(gelCount: 4, distanceKm: DistanceOption.fullMarathon.distanceKm)

        XCTAssertEqual(timings.map(\.distanceKm), [10, 16.25, 22.5, 28.75])
    }

    func testInvalidInputsProduceSafeEmptyCalculation() {
        XCTAssertEqual(RacePlanCalculator.targetPace(totalSeconds: 0, distanceKm: 10).secondsPerKilometer, 0)
        XCTAssertTrue(RacePlanCalculator.splitTimes(totalSeconds: 3_600, distanceKm: 0).isEmpty)
        XCTAssertTrue(RacePlanCalculator.fuelTimings(gelCount: 0, distanceKm: 10).isEmpty)
    }

    func testFormatsDistanceAndDuration() {
        XCTAssertEqual(RacePlanCalculator.formatDistance(42), "42km")
        XCTAssertEqual(RacePlanCalculator.formatDistance(42.195), "42.195km")
        XCTAssertEqual(RacePlanCalculator.formatDuration(14_400), "4時間0分0秒")
        XCTAssertEqual(RacePlanCalculator.formatDuration(341), "5分41秒")
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
}
