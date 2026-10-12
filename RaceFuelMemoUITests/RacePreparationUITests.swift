import XCTest

final class RacePreparationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing", "--reset-ui-testing", "-AppleLanguages", "(ja)", "-AppleLocale",
            "ja_JP", "--pro-ui-testing",
        ]
    }

    private func tap(_ element: XCUIElement) {
        _ = element.waitForExistence(timeout: 3)
        if element.exists && (element.label == "キャンセル" || element.label == "保存") {
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "hittable == true"), object: element)], timeout: 10), .completed)
        }
        for attempt in 0..<40 {
            if element.exists && element.isHittable { break }
            // Exclude the keyboard's short horizontal candidate scroll view.
            // Only use a visible content surface (not the screen behind a sheet).
            let scroll = app.scrollViews.allElementsBoundByIndex
                .filter { $0.frame.height > 150 && $0.isHittable }
                .max { $0.frame.height < $1.frame.height }
                ?? app.collectionViews.allElementsBoundByIndex
                    .filter { $0.frame.height > 150 && $0.isHittable }
                    .max { $0.frame.height < $1.frame.height }
                ?? app.collectionViews.firstMatch
            let above = element.exists && !element.frame.isEmpty
                ? element.frame.midY < scroll.frame.midY : attempt >= 20
            let keyboard = app.keyboards.firstMatch
            let visibleBottom = keyboard.exists && !keyboard.frame.isEmpty
                ? min(scroll.frame.maxY, keyboard.frame.minY) : scroll.frame.maxY
            let visibleHeight = max(50, visibleBottom - scroll.frame.minY)
            let origin = scroll.coordinate(withNormalizedOffset: .zero)
            // The scroll view's accessibility frame can extend behind the
            // keyboard. Keep both ends of the gesture in visible app content.
            origin.withOffset(CGVector(dx: scroll.frame.width * 0.97,
                                       dy: visibleHeight * (above ? 0.2 : 0.8)))
                .press(
                    forDuration: 0.05,
                    thenDragTo: origin.withOffset(CGVector(dx: scroll.frame.width * 0.97,
                                                          dy: visibleHeight * (above ? 0.8 : 0.2)))
                )
        }
        XCTAssertTrue(element.exists)
        XCTAssertTrue(element.isHittable)
        XCTAssertTrue(
            NSPredicate(format: "enabled == true").evaluate(with: element)
                || XCTWaiter.wait(
                    for: [
                        XCTNSPredicateExpectation(
                            predicate: NSPredicate(format: "enabled == true"), object: element)
                    ], timeout: 10) == .completed
        )
        if element.elementType == .switch {
            // A SwiftUI Toggle's accessibility frame can include its entire
            // label row. Hit the native switch at the trailing edge, not the label.
            element.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
                .withOffset(CGVector(dx: -20, dy: 0)).tap()
        } else {
            element.tap()
        }
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

    private func assertPaywallAndClose() {
        XCTAssertTrue(app.navigationBars["Proのご案内"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["paywall.priceUnavailable"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["paywall.price"].exists)
        tap(app.buttons["paywall.retry"])
        XCTAssertTrue(app.staticTexts["paywall.priceUnavailable"].waitForExistence(timeout: 10))
        tap(app.buttons["paywall.close"])
    }

    func testFreeCreationGatesEveryAdvancedFeatureAndKeepsDraftOnDismiss() {
        app.launchArguments.removeAll { $0 == "--pro-ui-testing" }
        app.launchArguments += ["--large-ui-testing", "--dark-ui-testing"]
        app.launch()
        tap(app.buttons["races.add"])
        tap(app.textFields["creation.name"])
        app.textFields["creation.name"].typeText("Free race")
        tap(app.buttons["creation.keyboardDone"])
        tap(app.buttons["pro.planReuse"])
        screenshot("paywall-large-dark")
        assertPaywallAndClose()
        tap(app.buttons["pro.preparationDashboard"])
        assertPaywallAndClose()
        for feature in ["paceStrategies", "checkpoints", "fuelingPlan", "customChecklist"] {
            tap(app.buttons["creation.next"])
            tap(app.buttons["pro.\(feature)"])
            assertPaywallAndClose()
        }
        tap(app.buttons["creation.next"])
        tap(app.buttons["creation.preview"])
        assertPaywallAndClose()
        app.terminate()
        app.launchArguments.removeAll { $0 == "--reset-ui-testing" }
        app.launch()
        tap(app.buttons["races.add"])
        XCTAssertTrue(app.staticTexts["creation.step"].label.contains("確認・出力"))
        // Saving this restored draft and finding its original name below proves
        // that the input survived all paywall dismissals and the app restart.
        tap(app.buttons["creation.save"])
        XCTAssertTrue(app.staticTexts["Free race"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["Race Card出力"].exists)
        tap(app.staticTexts["Free race"])
        XCTAssertTrue(app.buttons["編集"].waitForExistence(timeout: 10))
        screenshot("free-saved-detail-large-dark")
    }

    func testFreeSavedAdvancedRaceRemainsReadableAndBasicEditingAndChecksWork() {
        app.launchArguments.removeAll { $0 == "--pro-ui-testing" }
        app.launchArguments.append("--preparation-fixture")
        app.launch()
        tap(app.staticTexts["Warning race"])
        tap(app.staticTexts["Late cutoff"])
        tap(app.switches["Required gear"])
        XCTAssertEqual(app.switches["Required gear"].value as? String, "1")
        tap(app.buttons["pro.customChecklist"])
        assertPaywallAndClose()
        tap(app.buttons["編集"])
        let nameField = app.textFields["planEditor.name"]
        tap(nameField)
        if !app.keyboards.firstMatch.waitForExistence(timeout: 3) {
            // Tap the text itself if the sheet transition consumed the first tap.
            nameField.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
        }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        nameField.typeText(" updated")
        tap(app.buttons["pro.checkpoints"])
        assertPaywallAndClose()
        tap(app.buttons["planEditor.save"])
        tap(app.staticTexts["Late cutoff"])
        tap(app.switches["Required gear"])
        // Basic editing has not reset the saved checked state.
        XCTAssertEqual(app.switches["Required gear"].value as? String, "0")
        app.terminate()
        app.launchArguments.removeAll { $0 == "--reset-ui-testing" || $0 == "--preparation-fixture" }
        app.launch()
        tap(app.staticTexts["Warning race updated"])
        tap(app.staticTexts["Late cutoff"])
        screenshot("free-existing-advanced-race")
    }

    func testFreeShorterDistanceOffersConfirmedCheckpointCleanup() {
        app.launchArguments.removeAll { $0 == "--pro-ui-testing" }
        app.launchArguments.append("--checkpoint-cleanup-fixture")
        app.launch()
        tap(app.staticTexts["Shorten race"])
        tap(app.buttons["編集"])
        let distancePicker = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "10km")
        ).firstMatch
        tap(distancePicker)
        tap(app.buttons["5km"])
        XCTAssertFalse(app.buttons["planEditor.save"].isEnabled)
        tap(app.buttons["planEditor.cleanupInvalidAdvancedData"])
        XCTAssertTrue(app.alerts["保存済みデータを整理しますか？"].waitForExistence(timeout: 5))
        tap(app.alerts.buttons["キャンセル"])
        XCTAssertFalse(app.buttons["planEditor.save"].isEnabled)
        tap(app.buttons["planEditor.cleanupInvalidAdvancedData"])
        tap(app.alerts.buttons["整理する"])
        XCTAssertTrue(app.buttons["planEditor.save"].isEnabled)
        tap(app.buttons["planEditor.save"])
        XCTAssertTrue(app.navigationBars["Shorten race"].waitForExistence(timeout: 10))
        app.terminate()
        app.launchArguments.removeAll {
            $0 == "--reset-ui-testing" || $0 == "--checkpoint-cleanup-fixture"
        }
        app.launch()
        tap(app.staticTexts["Shorten race"])
        tap(app.buttons["編集"])
        XCTAssertTrue(app.staticTexts["1地点を設定済み"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["planEditor.cleanupInvalidAdvancedData"].exists)
        XCTAssertTrue(app.buttons["planEditor.save"].isEnabled)
    }

    func testFreeShorterTargetCanKeepCheckpointAndClearInvalidTimes() {
        app.launchArguments.removeAll { $0 == "--pro-ui-testing" }
        app.launchArguments.append("--target-cleanup-fixture")
        app.launch()
        tap(app.staticTexts["Shorten target"])
        tap(app.buttons["編集"])
        let minutes = app.pickerWheels.firstMatch
        XCTAssertTrue(minutes.waitForExistence(timeout: 10))
        minutes.adjust(toPickerWheelValue: "20分")
        XCTAssertFalse(app.buttons["planEditor.save"].isEnabled)
        tap(app.buttons["planEditor.cleanupInvalidAdvancedData"])
        XCTAssertTrue(app.alerts["保存済みデータを整理しますか？"].waitForExistence(timeout: 5))
        tap(app.alerts.buttons["整理する"])
        XCTAssertTrue(app.buttons["planEditor.save"].isEnabled)
        tap(app.buttons["planEditor.save"])
        XCTAssertTrue(app.navigationBars["Shorten target"].waitForExistence(timeout: 10))
        app.terminate()
        app.launchArguments.removeAll {
            $0 == "--reset-ui-testing" || $0 == "--target-cleanup-fixture"
        }
        app.launch()
        tap(app.staticTexts["Shorten target"])
        tap(app.buttons["編集"])
        XCTAssertTrue(app.staticTexts["1地点を設定済み"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.pickerWheels.firstMatch.value as? String, "20分")
        XCTAssertFalse(app.buttons["planEditor.cleanupInvalidAdvancedData"].exists)
    }

    func testPaywallInformationAccessibilityAndDismissal() throws {
        app.launchArguments.removeAll { $0 == "--pro-ui-testing" }
        app.launch()
        tap(app.buttons["pro.information"])
        XCTAssertTrue(app.navigationBars["Proのご案内"].waitForExistence(timeout: 10))
        try app.performAccessibilityAudit(for: [.dynamicType, .textClipped, .sufficientElementDescription]) { issue in
            if let element = issue.element { print("Paywall audit issue: \(element.debugDescription)") }
            return false // Report every issue; never suppress a failed audit.
        }
        screenshot("paywall-information-accessibility")
        assertPaywallAndClose()
        XCTAssertTrue(app.buttons["races.add"].waitForExistence(timeout: 10))
    }

    func testPaywallMaximumTextDarkModeDismissal() {
        app.launchArguments.removeAll { $0 == "--pro-ui-testing" }
        app.launchArguments += ["--large-ui-testing", "--dark-ui-testing"]
        app.launch()
        tap(app.buttons["pro.information"])
        XCTAssertTrue(app.navigationBars["Proのご案内"].waitForExistence(timeout: 10))
        screenshot("paywall-maximum-text-dark")
        tap(app.buttons["paywall.close"])
        XCTAssertTrue(app.buttons["races.add"].waitForExistence(timeout: 10))
    }

    func testFreeChecklistTemplatesCanBeReadAndDeletedButRenameRequiresPro() {
        app.launchArguments.removeAll { $0 == "--pro-ui-testing" }
        app.launchArguments.append("--checklist-template-fixture")
        app.launch()
        tap(app.buttons["races.settings"])
        tap(app.buttons["settings.checklistTemplates"])
        XCTAssertTrue(app.staticTexts["Saved checklist"].waitForExistence(timeout: 10))
        tap(app.buttons["2項目を確認"])
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Saved gear")).firstMatch.exists)
        tap(app.buttons["pro.customChecklist"])
        assertPaywallAndClose()
        tap(app.buttons["削除"])
        tap(app.alerts.buttons["削除"])
        XCTAssertFalse(app.staticTexts["Saved checklist"].exists)
        XCTAssertTrue(app.staticTexts["標準の持ち物10項目"].exists)
    }

    func testProCreationCanOpenAdvancedEditorsWithoutPaywall() {
        app.launch()
        tap(app.buttons["races.add"])
        tap(app.buttons["pro.planReuse"])
        XCTAssertTrue(app.navigationBars["計画の設定を再利用"].waitForExistence(timeout: 10))
        tap(app.buttons["キャンセル"])
        for (feature, title) in [
            ("paceStrategies", "ペース戦略"), ("checkpoints", "チェックポイント"),
            ("fuelingPlan", "補給・給水プラン"), ("customChecklist", "レースのチェックリスト")
        ] {
            tap(app.buttons["creation.next"])
            tap(app.buttons["pro.\(feature)"])
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10))
            XCTAssertFalse(app.navigationBars["Proのご案内"].exists)
            tap(app.buttons["キャンセル"])
        }
    }

    func testPaywallRestoresWithoutProductPriceAndUnlocksProEntry() {
        app.launchArguments.removeAll { $0 == "--pro-ui-testing" }
        app.launchArguments.append("--restore-pro-ui-testing")
        app.launch()
        tap(app.buttons["pro.information"])
        XCTAssertTrue(app.staticTexts["paywall.priceUnavailable"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["paywall.purchase"].isEnabled)
        tap(app.buttons["pro.restore"])
        XCTAssertTrue(app.staticTexts["pro.purchaseFeedback"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["pro.purchaseFeedback"].label, "購入を復元しました。Proを利用できます。")
        XCTAssertFalse(app.buttons["paywall.purchase"].exists)
        tap(app.buttons["paywall.close"])
        XCTAssertTrue(app.buttons["pro.information"].label.contains("Pro 解放済み"))
        tap(app.buttons["races.add"])
        tap(app.buttons["pro.planReuse"])
        XCTAssertTrue(app.navigationBars["計画の設定を再利用"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["Proのご案内"].exists)
    }

    func testSettingsRestoreReportsNoPurchaseAndKeepsFreeCreationAvailable() {
        app.launchArguments.removeAll { $0 == "--pro-ui-testing" }
        app.launch()
        tap(app.buttons["races.settings"])
        tap(app.buttons["pro.restore"])
        XCTAssertTrue(app.staticTexts["pro.purchaseFeedback"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["pro.purchaseFeedback"].label.contains("購入が見つかりませんでした"))
        XCTAssertTrue(app.buttons["pro.restore"].isEnabled)
        tap(app.buttons["完了"])
        tap(app.buttons["races.add"])
        XCTAssertTrue(app.textFields["creation.name"].waitForExistence(timeout: 10))
    }
}
