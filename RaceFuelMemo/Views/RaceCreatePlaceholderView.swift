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
            Section("基本情報") {
                TextField("レース名", text: $raceName)
                    .textInputAutocapitalization(.never)

                DatePicker("レース日", selection: $raceDate, displayedComponents: .date)

                DatePicker("スタート時刻", selection: $startTime, displayedComponents: .hourAndMinute)

                Picker("距離", selection: $distance) {
                    ForEach(DistanceOption.allCases) { distanceOption in
                        Text(distanceOption.label)
                            .tag(distanceOption)
                    }
                }
            }

            Section("目標タイム") {
                Stepper(value: $targetHours, in: 0...24) {
                    LabeledContent("時間", value: "\(targetHours)時間")
                }

                Stepper(value: $targetMinutes, in: 0...59) {
                    LabeledContent("分", value: "\(targetMinutes)分")
                }

                if !hasValidTargetTime {
                    Text("目標タイムは1分以上にしてください。")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("補給") {
                Stepper(value: $gelCount, in: 0...20) {
                    LabeledContent("補給ジェル", value: "\(gelCount)個")
                }
            }

            Section("メモ") {
                TextEditor(text: $memo)
                    .frame(minHeight: 120)
            }
        }
        .navigationTitle("レース作成")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: saveRacePlan)
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

    private func saveRacePlan() {
        guard canSave else {
            return
        }

        racePlanStore.addRacePlan(
            name: trimmedRaceName,
            raceDate: raceDate,
            startTime: startTime,
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
