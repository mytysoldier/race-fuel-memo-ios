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
                            ZStack(alignment: .topTrailing) {
                                NavigationLink {
                                    RaceDetailView(racePlan: racePlan)
                                } label: {
                                    RacePlanRow(racePlan: racePlan)
                                }
                                .buttonStyle(.plain)

                                Button(role: .destructive) {
                                    racePlanStore.deleteRacePlan(id: racePlan.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(width: 36, height: 36)
                                        .background(.ultraThinMaterial, in: Circle())
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.red)
                                .padding(12)
                                .accessibilityLabel("\(racePlan.name)を削除")
                            }
                            .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    racePlanStore.deleteRacePlan(id: racePlan.id)
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                            }
                        }
                        .onDelete(perform: racePlanStore.deleteRacePlans)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color(.systemGroupedBackground))
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                dateBadge

                VStack(alignment: .leading, spacing: 5) {
                    Text(racePlan.name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(racePlan.startTime.formatted(date: .omitted, time: .shortened) + " スタート")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 54)
            }

            HStack(spacing: 8) {
                metric(title: "距離", value: formattedDistance, systemImage: "figure.run")
                metric(title: "目標", value: formattedTargetTime, systemImage: "timer")
                metric(title: "ペース", value: racePlan.calculation.targetPaceText, systemImage: "speedometer")
            }

            HStack(spacing: 6) {
                Image(systemName: "arrow.right.circle.fill")
                Text("レースプランを見る")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tint)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.primary.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var dateBadge: some View {
        VStack(spacing: 1) {
            Text(racePlan.raceDate.formatted(.dateTime.month(.abbreviated)))
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
            Text(racePlan.raceDate.formatted(.dateTime.day()))
                .font(.title2.weight(.heavy))
        }
        .foregroundStyle(.tint)
        .frame(width: 58, height: 58)
        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func metric(title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var formattedDistance: String {
        if let distanceOption = DistanceOption.allCases.first(where: { $0.distanceKm == racePlan.distanceKm }) {
            return distanceOption.label
        }

        return racePlan.distanceKm.formatted(.number.precision(.fractionLength(0...2))) + "km"
    }

    private var formattedTargetTime: String {
        RacePlanCalculator.formatDuration(
            RacePlanCalculator.targetDurationSeconds(
                hours: racePlan.targetHours,
                minutes: racePlan.targetMinutes
            )
        )
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
