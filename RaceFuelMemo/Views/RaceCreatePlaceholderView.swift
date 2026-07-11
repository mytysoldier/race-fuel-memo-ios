import SwiftUI

struct RaceCreatePlaceholderView: View {
    @Environment(RacePlanStore.self) private var racePlanStore
    @Environment(\.dismiss) private var dismiss

    @State private var raceName = ""
    @State private var raceDate = Date()
    @State private var startTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
    @State private var distance = DistanceOption.halfMarathon
    @State private var targetHours = 2
    @State private var targetMinutes = 0
    @State private var gels = [GelDraft(name: "補給ジェル 1")]
    @State private var memo = ""

    var body: some View {
        Form {
            Section(String(localized: "race_create.section.basic_info")) {
                TextField(String(localized: "race_create.field.name"), text: $raceName)
                    .textInputAutocapitalization(.never)

                if trimmedRaceName.isEmpty {
                    validationMessage(String(localized: "race_create.validation.name_required"))
                }

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

                HStack(spacing: 16) {
                    Text(String(localized: "race_create.field.target_minutes"))
                        .frame(width: 52, alignment: .leading)

                    Picker("", selection: $targetMinutes) {
                        ForEach(0..<60) { minute in
                            Text(String(format: String(localized: "race_create.value.minutes"), minute))
                                .tag(minute)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .clipped()
                }

                if !hasValidTargetTime {
                    validationMessage(String(localized: "race_create.validation.target_time_required"))
                }
            }

            Section(String(localized: "race_create.section.fueling")) {
                ForEach($gels) { $gel in
                    HStack {
                        TextField("補給ジェル名", text: $gel.name)
                        Button(role: .destructive) {
                            gels.removeAll { $0.id == gel.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    gels.append(GelDraft(name: "補給ジェル \(gels.count + 1)"))
                } label: {
                    Label("補給ジェルを追加", systemImage: "plus.circle.fill")
                }
            }

            Section(String(localized: "race_create.section.memo")) {
                TextField(
                    String(localized: "race_create.section.memo"),
                    text: $memo,
                    prompt: Text(String(localized: "race_create.field.memo_placeholder")),
                    axis: .vertical
                )
                .lineLimit(4...8)
            }

            Section {
                HStack {
                    Spacer()
                    Button(action: saveRacePlan) {
                        Text("レースプランを作成")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 24)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(!canSave)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(String(localized: "race_create.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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

    private func validationMessage(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.footnote)
            .foregroundStyle(.red)
            .accessibilityLabel(
                String(
                    format: String(localized: "race_create.validation.accessibility_format"),
                    message
                )
            )
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
            gelCount: gels.count,
            gelNames: gels.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) },
            memo: trimmedMemo
        )
        dismiss()
    }
}

private struct GelDraft: Identifiable {
    let id = UUID()
    var name: String
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
