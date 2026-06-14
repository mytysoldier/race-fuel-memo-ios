import SwiftUI

@main
struct RaceFuelMemoApp: App {
    @StateObject private var racePlanStore = RacePlanStore()

    var body: some Scene {
        WindowGroup {
            RaceListView()
                .environmentObject(racePlanStore)
        }
    }
}
