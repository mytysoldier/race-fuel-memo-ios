import SwiftUI
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
    @UIApplicationDelegateAdaptor(RaceFuelMemoAppDelegate.self) private var appDelegate
    @State private var racePlanStore: RacePlanStore
    @State private var fuelingPresetStore: RaceFuelingPresetStore
    @State private var checklistTemplateStore: ChecklistTemplateStore
    @State private var racePlanTemplateStore: RacePlanTemplateStore
    @State private var creationDraftStore: RaceCreationDraftStore

    init() {
        #if DEBUG
        let defaults: UserDefaults
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
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
                #if DEBUG
                .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--dark-ui-testing") ? .dark : nil)
                .transformEnvironment(\.dynamicTypeSize) { size in
                    if ProcessInfo.processInfo.arguments.contains("--large-ui-testing") { size = .accessibility5 }
                }
                #endif
        }
    }
}
