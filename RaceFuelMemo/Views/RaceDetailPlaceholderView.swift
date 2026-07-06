import SwiftUI

struct RaceDetailView: View {
    @Environment(RacePlanStore.self) private var racePlanStore

    let racePlan: RacePlan

    var body: some View {
        List {
            Section(String(localized: "race_detail.section.basic_info")) {
                LabeledContent(
                    String(localized: "race_detail.field.name"),
                    value: currentRacePlan.name
                )
                LabeledContent(
                    String(localized: "race_detail.field.race_date"),
                    value: formattedRaceDate
                )
                LabeledContent(
                    String(localized: "race_detail.field.start_time"),
                    value: formattedStartTime
                )
                LabeledContent(
                    String(localized: "race_detail.field.distance"),
                    value: formattedDistance
                )
                LabeledContent(
                    String(localized: "race_detail.field.target_time"),
                    value: formattedTargetTime
                )
            }

            Section(String(localized: "race_detail.section.target_pace")) {
                LabeledContent(
                    String(localized: "race_detail.field.pace_per_kilometer"),
                    value: calculation.targetPaceText
                )
            }

            Section(String(localized: "race_detail.section.split_times")) {
                ForEach(calculation.splitTimes) { splitTime in
                    LabeledContent(splitTime.distanceText, value: splitTime.elapsedTimeText)
                }
            }

            Section(String(localized: "race_detail.section.fueling")) {
                if calculation.fuelTimings.isEmpty {
                    Text(String(localized: "race_detail.empty.fuel_timings"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(calculation.fuelTimings) { fuelTiming in
                        Label(fuelTiming.displayText, systemImage: "drop.fill")
                    }
                }
            }

            Section(String(localized: "race_detail.section.checklist")) {
                ForEach(currentRacePlan.checklistItems) { checklistItem in
                    Toggle(
                        checklistItem.title,
                        isOn: checklistItemBinding(for: checklistItem)
                    )
                }
            }

            Section(String(localized: "race_detail.section.memo")) {
                Text(displayedMemo)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                } label: {
                    Label(String(localized: "race_detail.action.notification_settings"), systemImage: "bell.badge")
                }
            }
        }
        .navigationTitle(currentRacePlan.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var currentRacePlan: RacePlan {
        racePlanStore.racePlans.first(where: { $0.id == racePlan.id }) ?? racePlan
    }

    private var calculation: RacePlanCalculation {
        currentRacePlan.calculation
    }

    private var formattedRaceDate: String {
        currentRacePlan.raceDate.formatted(date: .long, time: .omitted)
    }

    private var formattedStartTime: String {
        currentRacePlan.startTime.formatted(date: .omitted, time: .shortened)
    }

    private var formattedDistance: String {
        if let distanceOption = DistanceOption.allCases.first(where: { $0.distanceKm == currentRacePlan.distanceKm }) {
            return distanceOption.label
        }

        return RacePlanCalculator.formatDistance(currentRacePlan.distanceKm)
    }

    private var formattedTargetTime: String {
        RacePlanCalculator.formatDuration(
            RacePlanCalculator.targetDurationSeconds(
                hours: currentRacePlan.targetHours,
                minutes: currentRacePlan.targetMinutes
            )
        )
    }

    private var displayedMemo: String {
        guard !currentRacePlan.memo.isEmpty else {
            return String(localized: "race_detail.empty.memo")
        }

        return currentRacePlan.memo
    }

    private func checklistItemBinding(for checklistItem: ChecklistItem) -> Binding<Bool> {
        Binding {
            currentRacePlan.checklistItems
                .first(where: { $0.id == checklistItem.id })?
                .isChecked ?? checklistItem.isChecked
        } set: { isChecked in
            racePlanStore.setChecklistItemChecked(
                racePlanID: currentRacePlan.id,
                checklistItemID: checklistItem.id,
                isChecked: isChecked
            )
        }
    }
}

#Preview {
    let racePlan = RacePlan(
        name: "東京マラソン",
        raceDate: Date(),
        startTime: Date(),
        distanceKm: DistanceOption.fullMarathon.distanceKm,
        targetHours: 4,
        targetMinutes: 0,
        gelCount: 4,
        memo: "朝食はスタート3時間前までに済ませる。"
    )

    NavigationStack {
        RaceDetailView(racePlan: racePlan)
    }
    .environment(RacePlanStore(storage: RaceDetailPreviewRacePlanStorage(racePlans: [racePlan])))
}

private struct RaceDetailPreviewRacePlanStorage: RacePlanStorage {
    let racePlans: [RacePlan]

    func loadRacePlans() -> [RacePlan] {
        racePlans
    }

    func saveRacePlans(_ racePlans: [RacePlan]) {}
}
