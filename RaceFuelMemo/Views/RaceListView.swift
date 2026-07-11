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
                                RaceDetailView(racePlan: racePlan)
                            } label: {
                                RacePlanRow(racePlan: racePlan)
                            }
                        }
                        .onDelete(perform: racePlanStore.deleteRacePlans)
                    }
                }
            }
            .navigationTitle(String(localized: "race_list.title"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(String(localized: "race_list.action.settings"))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        RaceCreatePlaceholderView()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(String(localized: "race_list.action.add"))
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
            Label(String(localized: "race_list.empty.title"), systemImage: "flag.checkered")
        } description: {
            Text(String(localized: "race_list.empty.description"))
        } actions: {
            NavigationLink(String(localized: "race_list.empty.action")) {
                RaceCreatePlaceholderView()
            }
            .buttonStyle(.borderedProminent)
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

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    raceDateLabel
                    distanceLabel
                }
                .fixedSize(horizontal: true, vertical: false)

                VStack(alignment: .leading, spacing: 4) {
                    raceDateLabel
                    distanceLabel
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var raceDateLabel: some View {
        Label(racePlan.raceDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
    }

    private var distanceLabel: some View {
        Label(formattedDistance, systemImage: "figure.run")
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
