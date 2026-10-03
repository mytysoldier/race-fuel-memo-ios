import SwiftUI

struct RaceCreatePlaceholderView: View {
    @Environment(RacePlanStore.self) private var racePlanStore
    @Environment(\.dismiss) private var dismiss

    @State private var raceName = ""
    @State private var raceDate = Date()
    @State private var startTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
    @State private var distance = DistanceOption.halfMarathon
    @State private var usesCustomDistance = false
    @State private var customDistanceKm = 21.0975
    @State private var targetHours = 2
    @State private var targetMinutes = 0
    @State private var gels = [GelDraft(name: "補給ジェル 1")]
    @State private var memo = ""
    @State private var checkpoints: [RaceCheckpoint] = []
    @State private var isShowingCheckpointEditor = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                formSection(String(localized: "race_create.section.basic_info")) {
                    TextField(String(localized: "race_create.field.name"), text: $raceName)
                        .textInputAutocapitalization(.never)
                        .textFieldStyle(.roundedBorder)

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
                Toggle("任意の距離を指定", isOn: $usesCustomDistance)
                if usesCustomDistance {
                    TextField("距離 (1〜200km)", value: $customDistanceKm,
                              format: .number.precision(.fractionLength(0...4)))
                        .keyboardType(.decimalPad)
                }
            }

                formSection(String(localized: "race_create.section.target_time")) {
                    Stepper(value: $targetHours, in: 0...240) {
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

                formSection(String(localized: "race_create.section.fueling")) {
                    ForEach($gels) { $gel in
                        HStack {
                            TextField("補給ジェル名", text: $gel.name)
                                .textFieldStyle(.roundedBorder)
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

                formSection("チェックポイント") {
                    Text(checkpoints.isEmpty ? "地点未設定（従来の5kmごとの表示を使用）" : "\(checkpoints.count)地点を設定済み")
                        .foregroundStyle(.secondary)
                    Button {
                        isShowingCheckpointEditor = true
                    } label: {
                        Label("地点を編集", systemImage: "mappin.and.ellipse")
                    }
                    if let validationError = RaceCheckpointValidator.error(for: draftRacePlan) {
                        validationMessage(validationError)
                    }
                }

                formSection(String(localized: "race_create.section.memo")) {
                    TextField(
                        String(localized: "race_create.section.memo"),
                        text: $memo,
                        prompt: Text(String(localized: "race_create.field.memo_placeholder")),
                        axis: .vertical
                    )
                    .lineLimit(4...8)
                    .textFieldStyle(.roundedBorder)
                }

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
                if let saveError = racePlanStore.storageError ?? racePlanStore.validationError {
                    validationMessage(saveError)
                        .padding(.horizontal)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: raceStartDateTime) { previousStartTime, newStartTime in
            checkpoints.moveCutoffTimes(from: previousStartTime, to: newStartTime)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(String(localized: "race_create.title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingCheckpointEditor) {
            RaceCheckpointEditorView(racePlan: draftRacePlan) { checkpoints = $0 }
        }
    }

    private func formSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12, content: content)
                .padding(16)
                .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(.horizontal)
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
            && RaceCheckpointValidator.error(for: draftRacePlan) == nil
    }

    private var selectedDistanceKm: Double {
        usesCustomDistance ? customDistanceKm : distance.distanceKm
    }

    private var draftRacePlan: RacePlan {
        var racePlan = RacePlan(
            name: trimmedRaceName, raceDate: raceDate, startTime: raceStartDateTime,
            distanceKm: selectedDistanceKm, targetHours: targetHours, targetMinutes: targetMinutes,
            gelCount: gels.count, gelNames: gels.map(\.name), memo: trimmedMemo,
            checkpoints: checkpoints
        )
        racePlan.normalizeFinishCheckpoints()
        return racePlan
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

        var racePlan = draftRacePlan
        racePlan.gelNames = gels.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
        let saved = racePlanStore.addRacePlan(racePlan)
        if saved { dismiss() }
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
