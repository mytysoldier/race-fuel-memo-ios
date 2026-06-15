import SwiftUI

@main
struct RaceFuelMemoApp: App {
    @State private var racePlanStore = RacePlanStore()

    var body: some Scene {
        WindowGroup {
            RaceListView()
                .environment(racePlanStore)
        }
    }
}
