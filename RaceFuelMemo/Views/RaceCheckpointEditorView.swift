import SwiftUI

struct RaceCheckpointEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var checkpoints: [RaceCheckpoint]

    let racePlan: RacePlan
    let onSave: ([RaceCheckpoint]) -> Void

    init(racePlan: RacePlan, onSave: @escaping ([RaceCheckpoint]) -> Void) {
        self.racePlan = racePlan
        self.onSave = onSave
        var normalizedRacePlan = racePlan
        normalizedRacePlan.normalizeFinishCheckpoints()
        _checkpoints = State(initialValue: normalizedRacePlan.checkpoints.sorted { $0.order < $1.order })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(racePlan.pacePlans.isEmpty
                         ? "地点ごとの通過時間は、目標タイムから自動計算されます。必要な地点だけ手動指定できます。"
                         : "手動通過時間は基本目標の記録です。ペースプラン選択中の表示には、そのプランの区間配分を使用します。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("コース上の地点") {
                    ForEach($checkpoints) { $checkpoint in
                        checkpointRow($checkpoint)
                    }
                    .onMove(perform: move)

                    Button {
                        let insertionIndex = checkpoints.firstIndex { $0.kind == .finish } ?? checkpoints.count
                        checkpoints.insert(RaceCheckpoint(
                            order: insertionIndex,
                            name: "新しい地点",
                            distanceKm: suggestedDistance(before: insertionIndex)
                        ), at: insertionIndex)
                        normalizeOrders()
                    } label: {
                        Label("地点を追加", systemImage: "plus.circle.fill")
                    }
                    .disabled(!hasValidRaceDistance)
                }

                if let validationError {
                    Section {
                        Label(validationError, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("チェックポイント")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(checkpoints)
                        dismiss()
                    }
                    .disabled(validationError != nil)
                }
            }
        }
    }

    private func checkpointRow(_ binding: Binding<RaceCheckpoint>) -> some View {
        let checkpoint = binding.wrappedValue
        return VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                TextField("地点名", text: binding.name)
                                    .font(.headline)
                                Button(role: .destructive) {
                                    checkpoints.removeAll { $0.id == checkpoint.id }
                                    normalizeOrders()
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("\(checkpoint.name)を削除")
                            }

                            Picker("種別", selection: binding.kind) {
                                ForEach(RaceCheckpointKind.allCases, id: \.self) { kind in
                                    Text(kind.title).tag(kind)
                                }
                            }
                            .onChange(of: checkpoint.kind) { _, newKind in
                                if newKind == .aidStation { binding.hasAidStation.wrappedValue = true }
                                if newKind == .finish {
                                    binding.wrappedValue = racePlan.normalizedFinishCheckpoint(binding.wrappedValue)
                                }
                                if newKind == .cutoff && checkpoint.cutoffTime == nil {
                                    binding.cutoffTime.wrappedValue = racePlan.startTime.addingTimeInterval(3_600)
                                }
                            }

                            if checkpoint.kind != .aidStation {
                                Toggle("給水あり", isOn: binding.hasAidStation)
                            }

                            TextField("距離 (km)", value: binding.distanceKm,
                                      format: .number.precision(.fractionLength(0...4)))
                                .keyboardType(.decimalPad)
                                .disabled(checkpoint.kind == .finish)

                            Toggle("通過時間を手動指定", isOn: elapsedEnabled(for: binding))
                                .disabled(
                                    checkpoint.plannedElapsedSeconds == nil && !canEstimateElapsedTime
                                )
                            if checkpoint.plannedElapsedSeconds != nil {
                                TextField("スタートからの経過分", value: elapsedMinutes(for: binding), format: .number)
                                    .keyboardType(.numberPad)
                            }

                            Toggle("関門時刻を設定", isOn: cutoffEnabled(for: binding))
                            if checkpoint.cutoffTime != nil {
                                DatePicker("関門時刻", selection: cutoffDate(for: binding),
                                           displayedComponents: [.date, .hourAndMinute])
                            }

                            TextField("この区間のメモ（任意）", text: binding.segmentNote, axis: .vertical)
                                .lineLimit(2...4)
                            TextField("注意点（任意）", text: binding.cautionNote, axis: .vertical)
                                .lineLimit(2...4)
                        }
                        .padding(.vertical, 8)
                        .accessibilityElement(children: .contain)
    }

    private var validationError: String? {
        var candidate = racePlan
        candidate.checkpoints = checkpoints
        return RaceCheckpointValidator.error(for: candidate)
    }

    private var hasValidRaceDistance: Bool {
        racePlan.distanceKm.isFinite && (1...200).contains(racePlan.distanceKm)
    }

    private var canEstimateElapsedTime: Bool {
        RacePlanCalculator.estimatedCheckpointElapsedSeconds(
            totalSeconds: RacePlanCalculator.targetDurationSeconds(
                hours: racePlan.targetHours,
                minutes: racePlan.targetMinutes
            ),
            checkpointDistanceKm: 0,
            raceDistanceKm: racePlan.distanceKm
        ) != nil
    }

    private func suggestedDistance(before insertionIndex: Int) -> Double {
        guard hasValidRaceDistance else { return 0 }
        let previous = insertionIndex > 0 ? checkpoints[insertionIndex - 1].distanceKm : 0
        let next = insertionIndex < checkpoints.count
            ? checkpoints[insertionIndex].distanceKm : racePlan.distanceKm
        let distance = min(racePlan.distanceKm, max(1, (previous + next) / 2))
        return (distance * 10_000).rounded() / 10_000
    }

    private func move(from source: IndexSet, to destination: Int) {
        checkpoints.move(fromOffsets: source, toOffset: destination)
        normalizeOrders()
    }

    private func normalizeOrders() {
        for index in checkpoints.indices { checkpoints[index].order = index }
    }

    private func elapsedEnabled(for checkpoint: Binding<RaceCheckpoint>) -> Binding<Bool> {
        Binding {
            checkpoint.wrappedValue.plannedElapsedSeconds != nil
        } set: { enabled in
            guard enabled else {
                checkpoint.wrappedValue.plannedElapsedSeconds = nil
                return
            }
            checkpoint.wrappedValue.plannedElapsedSeconds = suggestedManualElapsedSeconds(
                for: checkpoint.wrappedValue
            )
        }
    }

    private func suggestedManualElapsedSeconds(for checkpoint: RaceCheckpoint) -> Int? {
        let targetSeconds = RacePlanCalculator.targetDurationSeconds(
            hours: racePlan.targetHours,
            minutes: racePlan.targetMinutes
        )
        guard let suggestedSeconds = RacePlanCalculator.suggestedManualCheckpointElapsedSeconds(
            totalSeconds: targetSeconds,
            checkpointDistanceKm: checkpoint.distanceKm,
            raceDistanceKm: racePlan.distanceKm,
            isFinish: checkpoint.kind == .finish
        ) else {
            return nil
        }

        guard checkpoint.kind != .finish,
              let index = checkpoints.firstIndex(where: { $0.id == checkpoint.id }) else {
            return suggestedSeconds
        }

        let previousElapsedSeconds = checkpoints[..<index]
            .reversed()
            .compactMap(\.plannedElapsedSeconds)
            .first ?? 0
        let nextElapsedSeconds = checkpoints[(index + 1)...]
            .compactMap(\.plannedElapsedSeconds)
            .first ?? targetSeconds
        return RacePlanCalculator.boundedManualCheckpointElapsedSeconds(
            suggestedSeconds,
            after: previousElapsedSeconds,
            before: nextElapsedSeconds
        )
    }

    private func elapsedMinutes(for checkpoint: Binding<RaceCheckpoint>) -> Binding<Int> {
        Binding {
            (checkpoint.wrappedValue.plannedElapsedSeconds ?? 0) / 60
        } set: { minutes in
            checkpoint.wrappedValue.plannedElapsedSeconds = minutes * 60
        }
    }

    private func cutoffEnabled(for checkpoint: Binding<RaceCheckpoint>) -> Binding<Bool> {
        Binding {
            checkpoint.wrappedValue.cutoffTime != nil
        } set: { enabled in
            checkpoint.wrappedValue.cutoffTime = enabled
                ? racePlan.startTime.addingTimeInterval(3_600)
                : nil
        }
    }

    private func cutoffDate(for checkpoint: Binding<RaceCheckpoint>) -> Binding<Date> {
        Binding {
            checkpoint.wrappedValue.cutoffTime ?? racePlan.startTime
        } set: { date in
            checkpoint.wrappedValue.cutoffTime = date
        }
    }
}
