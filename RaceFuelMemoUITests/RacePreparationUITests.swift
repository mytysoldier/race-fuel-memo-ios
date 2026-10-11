import XCTest

final class RacePreparationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing", "--reset-ui-testing", "-AppleLanguages", "(ja)", "-AppleLocale",
            "ja_JP",
        ]
    }

    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        if element.label == "キャンセル" || element.label == "保存" {
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "hittable == true"), object: element)], timeout: 10), .completed)
        }
        for _ in 0..<40 where !element.isHittable {
            let scroll = app.scrollViews.firstMatch.exists ? app.scrollViews.firstMatch : app.collectionViews.firstMatch
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.8))
                .press(
                    forDuration: 0.05,
                    thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.2))
                )
        }
        XCTAssertTrue(element.isHittable)
        XCTAssertTrue(
            NSPredicate(format: "enabled == true").evaluate(with: element)
                || XCTWaiter.wait(
                    for: [
                        XCTNSPredicateExpectation(
                            predicate: NSPredicate(format: "enabled == true"), object: element)
                    ], timeout: 10) == .completed
        )
        element.tap()
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testGuidedCreationPersistsAndLeadsToRaceCard() {
        app.launch()
        tap(app.buttons["races.add"])
        tap(app.textFields["creation.name"])
        app.textFields["creation.name"].typeText("UI race")
        tap(app.buttons["creation.keyboardDone"])
        tap(app.buttons["creation.next"])
        XCTAssertTrue(app.staticTexts["creation.step"].label.contains("ペース"))
        // Kill/relaunch, rather than only navigating back, to verify durable input.
        app.terminate()
        app.launchArguments.removeAll { $0 == "--reset-ui-testing" }
        app.launch()
        tap(app.buttons["races.add"])
        XCTAssertTrue(app.staticTexts["creation.step"].label.contains("ペース"))
        tap(app.buttons["creation.previous"])
        XCTAssertEqual(app.textFields["creation.name"].value as? String, "UI race")
        for title in ["ペース", "通過地点", "補給", "持ち物・準備", "確認・出力"] {
            tap(app.buttons["creation.next"])
            XCTAssertTrue(app.staticTexts["creation.step"].label.contains(title))
        }
        screenshot("guided-output")
        tap(app.buttons["creation.save"])
        XCTAssertTrue(app.navigationBars["Race Card出力"].waitForExistence(timeout: 10))
        tap(app.buttons["creation.done"])
        XCTAssertTrue(app.staticTexts["UI race"].waitForExistence(timeout: 10))
        tap(app.buttons["races.add"])
        XCTAssertNotEqual(app.textFields["creation.name"].value as? String, "UI race")
    }

    func testWarningDashboardLinksToCourseFuelingAndChecklist() {
        app.launchArguments.append("--preparation-fixture")
        app.launch()
        tap(app.staticTexts["Warning race"])
        XCTAssertTrue(app.buttons["preparation.checkpoints"].label.contains("関門超過"))
        XCTAssertTrue(app.buttons["preparation.fueling"].label.contains("補給未設定"))
        XCTAssertTrue(app.buttons["preparation.checklist"].label.contains("必須項目"))
        screenshot("preparation-warnings")
        tap(app.buttons["preparation.checkpoints"])
        XCTAssertTrue(app.navigationBars["チェックポイント"].waitForExistence(timeout: 10))
        tap(app.buttons["checkpoints.cancel"])
        tap(app.buttons["planEditor.cancel"])
        tap(app.buttons["preparation.fueling"])
        XCTAssertTrue(app.navigationBars["補給・給水プラン"].waitForExistence(timeout: 10))
        tap(app.buttons["fueling.cancel"])
        tap(app.buttons["planEditor.cancel"])
        tap(app.buttons["preparation.checklist"])
        XCTAssertTrue(app.navigationBars["レースのチェックリスト"].waitForExistence(timeout: 10))
        tap(app.switches["準備完了"])
        XCTAssertEqual(app.switches["準備完了"].value as? String, "1")
        tap(app.buttons["checklist.save"])
        XCTAssertTrue(app.buttons["preparation.checklist"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["preparation.checklist"].label.contains("入力済み"))
    }

    func testLegacyInputAvailableWithLargeTextAndDarkMode() {
        app.launchArguments += ["--large-ui-testing", "--dark-ui-testing"]
        app.launch()
        tap(app.buttons["races.add"])
        tap(app.switches["creation.guided"])
        tap(app.textFields["creation.name"])
        app.textFields["creation.name"].typeText("Legacy race")
        tap(app.buttons["creation.keyboardDone"])
        tap(app.buttons["creation.save"])
        XCTAssertTrue(app.navigationBars["Race Card出力"].waitForExistence(timeout: 10))
        screenshot("large-dark-race-card")
        tap(app.buttons["creation.done"])
        XCTAssertTrue(app.staticTexts["Legacy race"].waitForExistence(timeout: 10))
    }
}
