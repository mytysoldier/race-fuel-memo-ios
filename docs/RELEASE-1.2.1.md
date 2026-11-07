# 1.2.1 release preparation

Related: #47 and #87. Prepared 2026-11-07 (Japan time) from main commit 3ee0bbba4c3abf8fc5d106e9724bbe97d882b98f.

The Japanese App Store lookup reported 1.2.0 as the public version. App Store Connect now has 1.2.1 in Prepare for Submission. The project proposes build 1; build availability and upload remain to be confirmed.

## Verification performed

- Release configuration build for generic iOS Simulator succeeded with code signing disabled. This is not a signed archive or an App Store upload.

- iOS 17.4 simulator: English race creation, Race Card preview, save and relaunch in Japanese retained the sample race; Japanese guided creation and Race Card flow passed separately. An English UI test verifies the Minutes label stays on one line at the default text size.
- Japanese unit tests: 82 tests excluding ProStoreTests and StoreKit integration passed together; 37 ProStoreTests passed in separate runs. The combined suite hung and was interrupted, so it has not passed as a single run.
- Local StoreKit on iOS 26.2 simulator: Ask to Buy approval and purchase/restart/refund integration tests passed separately.
- Local StoreKit on iOS 17.4: Ask to Buy approval did not satisfy the expected Pro entitlement and feedback condition within 15 seconds on two simulators. The purchase/restart/refund test did not complete and was interrupted. The cause is unconfirmed; these results do not establish real-device behavior.
- English screenshots: iPhone 15 Pro simulator 1179 × 2556 and iPhone 15 Pro Max simulator 1290 × 2796 JPEG without alpha. They use sample data and simulated Pro entitlement. See docs/app-store/en-US.
- App Store Connect: the Pro non-consumable product is approved; Japanese release notes and English (US) description, subtitle, release notes, keywords and App Review notes were saved. English screenshots are not yet uploaded.

## Outstanding before release

- Investigate the iOS 17 local StoreKit discrepancy and verify purchase, restore, pending approval and failure handling on real devices/Sandbox. Do not treat simulated tests as Sandbox evidence.
- Confirm upgrade from the released app retains races, templates, checklist state and Pro entitlement; check accessibility and Japanese/English layouts on intended devices.
- In App Store Connect, verify build number 1 availability and upload the signed build and English screenshots. Confirm metadata and screenshot slots before submission.
- The paired iPhone was unreachable on 2026-11-07; its last reported OS was iOS 27.0.1. No iOS 17 physical device was verified.
