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
    @State private var racePlanStore = RacePlanStore()

    var body: some Scene {
        WindowGroup {
            RaceListView()
                .environment(racePlanStore)
        }
    }
}
