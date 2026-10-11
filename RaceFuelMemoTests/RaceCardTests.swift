import Foundation
import Testing
import XCTest
import PDFKit
@testable import RaceFuelMemo

private func cardRace() -> RacePlan {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let checkpoint = RaceCheckpoint(order: 0, name: "給水所・家族との合流", distanceKm: 10,
        cutoffTime: start.addingTimeInterval(4_500), kind: .cutoff,
        segmentNote: "橋を渡って右折", cautionNote: "坂道に注意")
    var race = RacePlan(name: "秋の日本語マラソン", raceDate: start, startTime: start,
        distanceKm: 20, targetHours: 2, targetMinutes: 0,
        gelCount: 0, memo: "ゴール後は東口で待ち合わせ。", checkpoints: [checkpoint])
    race.pacePlans = [
        RacePacePlan(order: 0, name: "A・目標", targetSeconds: 7_200,
                     strategy: .negative, halfDifferenceSeconds: 600),
        RacePacePlan(order: 1, name: "B・余裕", targetSeconds: 9_000),
        RacePacePlan(order: 2, name: "C・完走", targetSeconds: 10_800)
    ]
    race.selectedPacePlanID = race.pacePlans[0].id
    race.normalizePacePlans()
    race.fuelingEvents = [RaceFuelingEvent(order: 0, name: "日本語ジェル", quantity: 2,
        checkpointID: checkpoint.id, carbohydrateGramsPerItem: 25,
        containsCaffeine: true, note: "水と一緒に", pickup: .support)]
    return race
}

@Test func raceCardMatchesEachPacePlanWithoutChangingSelection() throws {
    let race = cardRace()
    let original = race
    for pacePlan in race.pacePlans {
        var candidate = race
        candidate.selectedPacePlanID = pacePlan.id
        let card = try RaceCardDocument(plan: race, pacePlanID: pacePlan.id, audience: .runner)
        let text = card.sections.flatMap(\.lines).joined(separator: "\n")
        let schedule = try #require(RacePlanCalculator.checkpointSchedules(for: candidate).first)
        let fueling = try #require(RaceFuelingPlanCalculator.schedule(for: candidate).first)
        #expect(text.contains(RacePlanCalculator.formatDuration(candidate.activeTargetSeconds)))
        #expect(text.contains("経過 \(RacePlanCalculator.formatDuration(schedule.elapsedSeconds))"))
        #expect(text.contains("経過 \(RacePlanCalculator.formatDuration(fueling.elapsedSeconds))"))
        #expect(text.contains("日本語ジェル ×2・サポート受取"))
        #expect(text.contains("炭水化物 25g/個・カフェイン入り"))
        #expect(text.contains("水と一緒に"))
        #expect(text.contains("坂道に注意"))
        for segment in pacePlan.segments {
            let pace = RacePlanCalculator.targetPace(totalSeconds: segment.targetSeconds,
                distanceKm: segment.endDistanceKm - segment.startDistanceKm)
            #expect(text.contains(pace.displayText))
        }
    }
    #expect(race == original)
}

@Test func raceCardSupportsBasicLegacyFuelingAndSupporterOrder() throws {
    var race = cardRace()
    race.fuelingEvents = []
    race.gelCount = 2
    race.gelNames = ["旧ジェルA", "旧ジェルB"]
    let runner = try RaceCardDocument(plan: race, pacePlanID: nil, audience: .runner)
    let supporter = try RaceCardDocument(plan: race, pacePlanID: nil, audience: .supporter)
    #expect(runner.planName == "基本計画")
    #expect(runner.sections[1].title == "区間ペース・通過予定")
    #expect(supporter.sections[1].title == "通過地点・関門")
    #expect(supporter.sections.first(where: { $0.title == "補給・給水" })?.lines.count == 2)
    #expect(supporter.sections.flatMap(\.lines).joined().contains("旧ジェルB"))
    #expect(runner.sections.first(where: { $0.title == "大会メモ" })?.lines == [race.memo])
}

@Test func raceCardRejectsUnknownPlanAndInvalidAlternateFueling() {
    var race = cardRace()
    #expect(throws: RaceCardError.self) {
        try RaceCardDocument(plan: race, pacePlanID: UUID(), audience: .runner)
    }
    race.fuelingEvents = [RaceFuelingEvent(order: 0, name: "遅い補給", quantity: 1, elapsedSeconds: 8_000)]
    #expect(throws: RaceCardError.self) {
        try RaceCardDocument(plan: race, pacePlanID: race.pacePlans[0].id, audience: .runner)
    }
    #expect(throws: Never.self) {
        try RaceCardDocument(plan: race, pacePlanID: race.pacePlans[1].id, audience: .runner)
    }
}

@MainActor
final class RaceCardRenderingTests: XCTestCase {
    func testCancelledExportCanBeRetried() async throws {
        let race = cardRace()
        let document = try RaceCardDocument(plan: race, pacePlanID: race.selectedPacePlanID, audience: .runner)
        let renderer = try RaceCardRenderer(document: document, format: .card)
        let cancelled = Task { try await renderer.exportForSharing() }
        cancelled.cancel()
        do {
            let output = try await cancelled.value
            output.removeTemporaryFiles()
            XCTFail("Cancelled export should not publish files")
        } catch is CancellationError {
            // Expected. The next request must still produce all pages.
        }
        let output = try await renderer.exportForSharing()
        defer { output.removeTemporaryFiles() }
        XCTAssertEqual(output.imageURLs.count, renderer.pageCount)
        XCTAssertEqual(try XCTUnwrap(PDFDocument(url: output.pdfURL)).pageCount, renderer.pageCount)
    }

    func testAirPrintRepaginatesBandsWithoutDroppingLastContainer() throws {
        var race = cardRace()
        race.memo = String(repeating: "印刷でも長いメモを保持。\n", count: 80) + "印刷最終マーカー"
        let document = try RaceCardDocument(plan: race, pacePlanID: race.selectedPacePlanID, audience: .runner)
        let renderer = try RaceCardRenderer(document: document, format: .paceBand)
        let printRenderer = FixedPaperRaceCardPrintRenderer(source: renderer)
        XCTAssertEqual(RaceCardPrintRenderer.bandsPerPage(in: printRenderer.printableRect), 3)
        XCTAssertEqual(printRenderer.numberOfPages, (renderer.containers.count + 2) / 3)
        let pdfData = UIGraphicsPDFRenderer(bounds: printRenderer.paperRect).pdfData { context in
            for page in 0..<printRenderer.numberOfPages {
                context.beginPage()
                printRenderer.drawPage(at: page, in: printRenderer.printableRect)
            }
        }
        let pdf = try XCTUnwrap(PDFDocument(data: pdfData))
        XCTAssertEqual(pdf.pageCount, printRenderer.numberOfPages)
        let text = try XCTUnwrap(pdf.string)
        XCTAssertTrue(text.contains("印刷最終マーカー"))
        for index in renderer.containers.indices {
            XCTAssertTrue(text.contains("帯 \(index + 1)/\(renderer.containers.count)"))
        }
    }

    func testJapaneseCardAndBandRenderEveryCharacterAndPDFPage() throws {
        var race = cardRace()
        race.memo += String(repeating: "長いメモでも内容を欠落させません。\n", count: 160)
        race.memo += "最終行の確認マーカー"
        let document = try RaceCardDocument(plan: race, pacePlanID: race.selectedPacePlanID, audience: .supporter)
        for format in RaceCardFormat.allCases {
            let renderer = try RaceCardRenderer(document: document, format: format)
            XCTAssertGreaterThan(renderer.pageCount, 1)
            var character = 0
            for range in renderer.renderedCharacterRanges {
                XCTAssertEqual(range.location, character)
                character = NSMaxRange(range)
            }
            XCTAssertEqual(character, renderer.storage.length)
            let output = try renderer.export()
            defer { output.removeTemporaryFiles() }
            let pdf = try XCTUnwrap(PDFDocument(url: output.pdfURL))
            XCTAssertEqual(pdf.pageCount, renderer.pageCount)
            XCTAssertEqual(output.imageURLs.count, pdf.pageCount)
            let normalize: (String) -> String = { text in
                // PDFKit folds Japanese punctuation (and can omit full-width parentheses).
                // Verify every letter and number; glyph ranges cover punctuation and symbols too.
                String(String.UnicodeScalarView(text.folding(options: .widthInsensitive,
                    locale: Locale(identifier: "ja_JP")).unicodeScalars.filter {
                        CharacterSet.alphanumerics.contains($0)
                    }))
            }
            let pdfText = normalize(try XCTUnwrap(pdf.string))
            let extraction = XCTAttachment(string: pdf.string ?? "")
            extraction.name = "\(format.rawValue)-PDF-text"
            extraction.lifetime = .keepAlways
            add(extraction)
            let source = XCTAttachment(string: renderer.storage.string)
            source.name = "\(format.rawValue)-source-text"
            source.lifetime = .keepAlways
            add(source)
            for range in renderer.renderedCharacterRanges {
                // Each physical text container is complete, even across page and band boundaries.
                let text = normalize(renderer.storage.attributedSubstring(from: range).string)
                XCTAssertTrue(pdfText.contains(text), "Missing PDF content: \(text.prefix(50))")
            }
            for page in 0..<pdf.pageCount {
                let bounds = try XCTUnwrap(pdf.page(at: page)).bounds(for: .mediaBox)
                XCTAssertEqual(bounds.width, RaceCardRenderer.pageSize.width, accuracy: 0.1)
                let png = try XCTUnwrap(UIImage(contentsOfFile: output.imageURLs[page].path))
                XCTAssertEqual(png.size.width, floor(RaceCardRenderer.pageSize.width * 2), accuracy: 1)
                XCTAssertEqual(png.size.height, floor(RaceCardRenderer.pageSize.height * 2), accuracy: 1)
            }
            let first = XCTAttachment(image: renderer.image(page: 0))
            first.name = "\(format.rawValue)-Japanese-first-page"
            first.lifetime = .keepAlways
            add(first)
            let last = XCTAttachment(image: renderer.image(page: renderer.pageCount - 1))
            last.name = "\(format.rawValue)-Japanese-last-page"
            last.lifetime = .keepAlways
            add(last)
        }
    }

    func testCompactRaceFitsOnePageAndTemporaryFilesHaveScopedLifetime() throws {
        let race = RacePlan(name: "近所の5km大会", raceDate: .now, startTime: .now,
            distanceKm: 5, targetHours: 0, targetMinutes: 30, gelCount: 0)
        let document = try RaceCardDocument(plan: race, pacePlanID: nil, audience: .runner)
        let renderer = try RaceCardRenderer(document: document, format: .card)
        XCTAssertEqual(renderer.pageCount, 1)
        var output: RaceCardExport? = try renderer.export()
        let directory = try XCTUnwrap(output).directory
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
        output = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertEqual(RaceCardRenderer.bandSize.width * 25.4 / 72, 180, accuracy: 0.01)
        XCTAssertEqual(RaceCardRenderer.bandSize.height * 25.4 / 72, 55, accuracy: 0.01)
    }
}

@MainActor
private final class FixedPaperRaceCardPrintRenderer: RaceCardPrintRenderer {
    override var paperRect: CGRect { CGRect(origin: .zero, size: RaceCardRenderer.pageSize) }
    override var printableRect: CGRect { CGRect(x: 40, y: 60, width: 515, height: 600) }
}
