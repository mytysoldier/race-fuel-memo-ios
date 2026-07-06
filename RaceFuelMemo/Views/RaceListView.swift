import SwiftUI

struct RaceListView: View {
    @Environment(RacePlanStore.self) private var racePlanStore
    @State private var isShowingSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if racePlanStore.racePlans.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(racePlanStore.racePlans) { racePlan in
                            NavigationLink {
                                RaceDetailPlaceholderView(racePlan: racePlan)
                            } label: {
                                RacePlanRow(racePlan: racePlan)
                            }
                        }
                        .onDelete(perform: racePlanStore.deleteRacePlans)
                    }
                }
            }
            .navigationTitle("レース一覧")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("設定")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        RaceCreatePlaceholderView()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("レースを追加")
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                NavigationStack {
                    SettingsView()
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("レースプランがありません", systemImage: "flag.checkered")
        } description: {
            Text("右上の追加ボタンからレースプランを作成できます。")
        }
    }
}

#Preview {
    RaceListView()
        .environment(RacePlanStore.preview)
}

private struct RacePlanRow: View {
    let racePlan: RacePlan

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(racePlan.name)
                .font(.headline)

            HStack(spacing: 12) {
                Label(racePlan.raceDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                Label(formattedDistance, systemImage: "figure.run")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var formattedDistance: String {
        if let distanceOption = DistanceOption.allCases.first(where: { $0.distanceKm == racePlan.distanceKm }) {
            return distanceOption.label
        }

        return racePlan.distanceKm.formatted(.number.precision(.fractionLength(0...2))) + "km"
    }
}

private extension RacePlanStore {
    static var preview: RacePlanStore {
        RacePlanStore(
            storage: PreviewRacePlanStorage(
                racePlans: [
                    RacePlan(
                        name: "東京マラソン",
                        raceDate: Date(),
                        startTime: Date(),
                        distanceKm: DistanceOption.fullMarathon.distanceKm,
                        targetHours: 4,
                        targetMinutes: 0,
                        gelCount: 4
                    )
                ]
            )
        )
    }
}

private struct PreviewRacePlanStorage: RacePlanStorage {
    let racePlans: [RacePlan]

    func loadRacePlans() -> [RacePlan] {
        racePlans
    }

    func saveRacePlans(_ racePlans: [RacePlan]) {}
}
