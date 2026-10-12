import SwiftUI
import StoreKit
import UserNotifications

final class RaceFuelMemoAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}

@main
struct RaceFuelMemoApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(RaceFuelMemoAppDelegate.self) private var appDelegate
    @State private var racePlanStore: RacePlanStore
    @State private var fuelingPresetStore: RaceFuelingPresetStore
    @State private var checklistTemplateStore: ChecklistTemplateStore
    @State private var racePlanTemplateStore: RacePlanTemplateStore
    @State private var creationDraftStore: RaceCreationDraftStore
    @State private var proStore = ProStore()

    init() {
        #if DEBUG
        let defaults: UserDefaults
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            _proStore = State(initialValue: ProStore(client: ProUITestClient(
                purchased: ProcessInfo.processInfo.arguments.contains("--pro-ui-testing"))))
            let suite = "com.mytysoldier.RaceFuelMemo.UITests"
            defaults = UserDefaults(suiteName: suite)!
            if ProcessInfo.processInfo.arguments.contains("--reset-ui-testing") {
                defaults.removePersistentDomain(forName: suite)
            }
            if ProcessInfo.processInfo.arguments.contains("--preparation-fixture") {
                let start = Date().addingTimeInterval(86400)
                let fixture = RacePlan(name: "Warning race", raceDate: start, startTime: start,
                    distanceKm: 20, targetHours: 2, targetMinutes: 0, gelCount: 0,
                    checklistItems: [ChecklistItem(title: "Required gear", isRequired: true)],
                    checkpoints: [RaceCheckpoint(order: 0, name: "Late cutoff", distanceKm: 10,
                        cutoffTime: start.addingTimeInterval(1800), kind: .cutoff)])
                try? UserDefaultsRacePlanStorage(userDefaults: defaults).saveRacePlans([fixture])
            }
            if ProcessInfo.processInfo.arguments.contains("--checkpoint-cleanup-fixture") {
                let start = Date().addingTimeInterval(86_400)
                let distant = RaceCheckpoint(order: 1, name: "Remove at 8km", distanceKm: 8)
                let fixture = RacePlan(name: "Shorten race", raceDate: start, startTime: start,
                    distanceKm: 10, targetHours: 1, targetMinutes: 0, gelCount: 0,
                    checkpoints: [RaceCheckpoint(order: 0, name: "Keep at 4km", distanceKm: 4), distant],
                    fuelingEvents: [RaceFuelingEvent(order: 0, name: "Linked fuel", quantity: 1,
                                                     checkpointID: distant.id)])
                try? UserDefaultsRacePlanStorage(userDefaults: defaults).saveRacePlans([fixture])
            }
            if ProcessInfo.processInfo.arguments.contains("--checklist-template-fixture") {
                let store = ChecklistTemplateStore(defaults: defaults)
                if !store.templates.contains(where: { $0.name == "Saved checklist" }) {
                    _ = store.save(name: "Saved checklist", items: [
                        ChecklistItem(title: "Saved gear"),
                        ChecklistItem(title: "Saved deadline", isRequired: true, dueTiming: .dayBefore)
                    ])
                }
            }
        } else {
            defaults = .standard
        }
        #else
        let defaults = UserDefaults.standard
        #endif
        _racePlanStore = State(initialValue: RacePlanStore(storage: UserDefaultsRacePlanStorage(userDefaults: defaults)))
        _fuelingPresetStore = State(initialValue: RaceFuelingPresetStore(defaults: defaults))
        _checklistTemplateStore = State(initialValue: ChecklistTemplateStore(defaults: defaults))
        _racePlanTemplateStore = State(initialValue: RacePlanTemplateStore(defaults: defaults))
        _creationDraftStore = State(initialValue: RaceCreationDraftStore(defaults: defaults))
    }

    var body: some Scene {
        WindowGroup {
            RaceListView()
                .environment(racePlanStore)
                .environment(fuelingPresetStore)
                .environment(checklistTemplateStore)
                .environment(racePlanTemplateStore)
                .environment(creationDraftStore)
                .environment(proStore)
                .task {
                    if shouldStartStoreKit { await proStore.start() }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active && shouldStartStoreKit {
                        Task { await proStore.refreshEntitlements() }
                    }
                }
                #if DEBUG
                .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--dark-ui-testing") ? .dark : nil)
                .transformEnvironment(\.dynamicTypeSize) { size in
                    if ProcessInfo.processInfo.arguments.contains("--large-ui-testing") { size = .accessibility5 }
                }
                #endif
        }
    }

    private var shouldStartStoreKit: Bool {
        #if DEBUG
        // Unit tests configure their own SKTestSession before starting their Store.
        // Avoid a second listener and requests against the pre-test StoreKit environment.
        return ProcessInfo.processInfo.arguments.contains("--ui-testing")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        #else
        return true
        #endif
    }
}

#if DEBUG
/// Deterministic UI fixtures, never compiled into the distributed app. Production
/// always uses StoreKit verification, not launch arguments or stored flags.
@MainActor
private struct ProUITestClient: ProStoreKitClient {
    let purchased: Bool
    func fetchProduct() async throws -> Product? { nil }
    func currentEntitlements() async -> [ProVerificationResult] {
        purchased ? [.verified(ProEntitlement(productID: ProProductID.lifetime,
            isNonConsumable: true, revocationDate: nil, expirationDate: nil, isUpgraded: false))] : []
    }
    func updates() -> AsyncStream<ProTransactionUpdate> { AsyncStream { $0.finish() } }
}
#endif
