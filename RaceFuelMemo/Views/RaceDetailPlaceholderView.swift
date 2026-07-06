import SwiftUI

struct RaceDetailPlaceholderView: View {
    let racePlan: RacePlan

    var body: some View {
        List {
            Section("レース詳細") {
                Text(racePlan.name)
                    .font(.headline)

                Text("レース詳細画面は後続Issueで実装します。")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(racePlan.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        RaceDetailPlaceholderView(
            racePlan: RacePlan(
                name: "東京マラソン",
                raceDate: Date(),
                startTime: Date(),
                distanceKm: DistanceOption.fullMarathon.distanceKm,
                targetHours: 4,
                targetMinutes: 0,
                gelCount: 4
            )
        )
    }
}
