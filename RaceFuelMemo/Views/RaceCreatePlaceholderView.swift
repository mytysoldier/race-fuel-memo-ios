import SwiftUI

struct RaceCreatePlaceholderView: View {
    @Environment(RacePlanStore.self) private var racePlanStore
    @Environment(\.dismiss) private var dismiss

    @State private var raceName = ""
    @State private var raceDate = Date()
    @State private var startTime = Date()
    @State private var distance = DistanceOption.fullMarathon
    @State private var targetHours = 4
    @State private var targetMinutes = 0
    @State private var gelCount = 4
    @State private var memo = ""

    var body: some View {
        Form {
            Section(String(localized: "race_create.section.basic_info")) {
                TextField(String(localized: "race_create.field.name"), text: $raceName)
                    .textInputAutocapitalization(.never)

                DatePicker(String(localized: "race_create.field.race_date"), selection: $raceDate, displayedComponents: .date)

                DatePicker(String(localized: "race_create.field.start_time"), selection: $startTime, displayedComponents: .hourAndMinute)

                Picker(String(localized: "race_create.field.distance"), selection: $distance) {
                    ForEach(DistanceOption.allCases) { distanceOption in
                        Text(distanceOption.label)
                            .tag(distanceOption)
                    }
                }
            }

            Section(String(localized: "race_create.section.target_time")) {
                Stepper(value: $targetHours, in: 0...24) {
                    LabeledContent(
                        String(localized: "race_create.field.target_hours"),
                        value: String(format: String(localized: "race_create.value.hours"), targetHours)
                    )
                }

                Stepper(value: $targetMinutes, in: 0...59) {
                    LabeledContent(
                        String(localized: "race_create.field.target_minutes"),
                        value: String(format: String(localized: "race_create.value.minutes"), targetMinutes)
                    )
                }

                if !hasValidTargetTime {
                    Text(String(localized: "race_create.validation.target_time_required"))
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section(String(localized: "race_create.section.fueling")) {
                Stepper(value: $gelCount, in: 0...20) {
                    LabeledContent(
                        String(localized: "race_create.field.gel_count"),
                        value: String(format: String(localized: "race_create.value.items"), gelCount)
                    )
                }
            }

            Section(String(localized: "race_create.section.memo")) {
                TextEditor(text: $memo)
                    .frame(minHeight: 120)
            }
        }
        .navigationTitle(String(localized: "race_create.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "race_create.action.save"), action: saveRacePlan)
                    .disabled(!canSave)
            }
        }
    }

    private var trimmedRaceName: String {
        raceName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedMemo: String {
        memo.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasValidTargetTime: Bool {
        targetHours > 0 || targetMinutes > 0
    }

    private var canSave: Bool {
        !trimmedRaceName.isEmpty && hasValidTargetTime
    }

    private var raceStartDateTime: Date {
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: raceDate)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: startTime)
        var combinedComponents = DateComponents()
        combinedComponents.year = dateComponents.year
        combinedComponents.month = dateComponents.month
        combinedComponents.day = dateComponents.day
        combinedComponents.hour = timeComponents.hour
        combinedComponents.minute = timeComponents.minute

        return calendar.date(from: combinedComponents) ?? startTime
    }

    private func saveRacePlan() {
        guard canSave else {
            return
        }

        racePlanStore.addRacePlan(
            name: trimmedRaceName,
            raceDate: raceDate,
            startTime: raceStartDateTime,
            distance: distance,
            targetHours: targetHours,
            targetMinutes: targetMinutes,
            gelCount: gelCount,
            memo: trimmedMemo
        )
        dismiss()
    }
}

#Preview {
    NavigationStack {
        RaceCreatePlaceholderView()
    }
    .environment(RacePlanStore(storage: EmptyRacePlanStorage()))
}

private struct EmptyRacePlanStorage: RacePlanStorage {
    func loadRacePlans() -> [RacePlan] {
        []
    }

    func saveRacePlans(_ racePlans: [RacePlan]) {}
}
