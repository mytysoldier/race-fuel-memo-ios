import SwiftUI

struct RacePacePlansEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: RacePlan
    @State private var editingID: UUID
    let onSave: ([RacePacePlan], UUID?) -> Void

    init(racePlan: RacePlan, onSave: @escaping ([RacePacePlan], UUID?) -> Void) {
        var initial = racePlan
        if initial.pacePlans.isEmpty {
            let first = RacePacePlanCalculator.initialPlan(for: initial)
            initial.pacePlans = [first]
            initial.selectedPacePlanID = first.id
        }
        initial.normalizePacePlans()
        _draft = State(initialValue: initial)
        _editingID = State(initialValue: initial.selectedPacePlanID ?? initial.pacePlans[0].id)
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("プラン") {
                Picker("使用するプラン", selection: $draft.selectedPacePlanID) {
                    ForEach(draft.pacePlans.sorted(by: { $0.order < $1.order })) { plan in
                        Text(plan.name).tag(Optional(plan.id))
                    }
                }
                Picker("編集中", selection: $editingID) {
                    ForEach(draft.pacePlans.sorted(by: { $0.order < $1.order })) { plan in
                        Text(plan.name).tag(plan.id)
                    }
                }
                HStack {
                    Button("プランを複製") { duplicatePlan() }
                        .disabled(draft.pacePlans.count >= 3)
                    Spacer()
                    if draft.pacePlans.count > 1 {
                        Button("削除", role: .destructive) { deleteEditingPlan() }
                    }
                }
            }

            if let index = editingIndex {
                planFields(at: index)
            }

            if let error = RacePacePlanCalculator.validationError(for: draft) {
                Section { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red) }
            }
        }
        .navigationTitle("ペース戦略")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    draft.normalizePacePlans()
                    onSave(draft.pacePlans, draft.selectedPacePlanID)
                    dismiss()
                }
                .disabled(RacePacePlanCalculator.validationError(for: draft) != nil)
            }
        }
    }

    @ViewBuilder
    private func planFields(at index: Int) -> some View {
        Section("\(letter(for: index))プラン") {
            TextField("プラン名", text: $draft.pacePlans[index].name)
            Stepper("目標 \(RacePlanCalculator.formatDuration(draft.pacePlans[index].targetSeconds))",
                    value: targetMinutesBinding(at: index), in: 1...14_459)
            Picker("方式", selection: strategyBinding(at: index)) {
                ForEach(RacePaceStrategy.allCases, id: \.self) { strategy in
                    Text(strategy.title).tag(strategy)
                }
            }
            if draft.pacePlans[index].strategy == .negative || draft.pacePlans[index].strategy == .positive {
                Stepper("前後半の差 \(draft.pacePlans[index].halfDifferenceSeconds / 60)分",
                        value: halfDifferenceBinding(at: index), in: 0...120)
            }
            if draft.pacePlans[index].strategy != .custom {
                Stepper("ラストスパート \(draft.pacePlans[index].kickDistanceKm.formatted(.number.precision(.fractionLength(1))))km",
                        value: kickDistanceBinding(at: index), in: 0...max(0, draft.distanceKm - 0.5), step: 0.5)
                if draft.pacePlans[index].kickDistanceKm > 0 {
                    Stepper("短縮 \(draft.pacePlans[index].kickGainSecondsPerKm)秒/km",
                            value: kickGainBinding(at: index), in: 0...120, step: 5)
                }
            }
        }

        Section("区間配分") {
            Text("合計時間は目標に固定。区間を調整すると他の区間へ配分します。")
                .font(.footnote).foregroundStyle(.secondary)
            ForEach(draft.pacePlans[index].segments.indices, id: \.self) { segmentIndex in
                let segment = draft.pacePlans[index].segments[segmentIndex]
                VStack(alignment: .leading) {
                    Text("\(RacePlanCalculator.formatDistance(segment.startDistanceKm)) → \(RacePlanCalculator.formatDistance(segment.endDistanceKm))")
                        .font(.subheadline)
                    HStack {
                        Text(RacePlanCalculator.formatDuration(segment.targetSeconds))
                        Spacer()
                        Text(RacePlanCalculator.targetPace(
                            totalSeconds: segment.targetSeconds,
                            distanceKm: segment.endDistanceKm - segment.startDistanceKm
                        ).displayText)
                            .foregroundStyle(.secondary)
                    }
                    if draft.pacePlans[index].segments.count > 1 {
                        Stepper("区間ペースを調整", onIncrement: {
                            adjustSegment(planIndex: index, segmentIndex: segmentIndex,
                                          paceChangeSecondsPerKm: 5)
                        }, onDecrement: {
                            adjustSegment(planIndex: index, segmentIndex: segmentIndex,
                                          paceChangeSecondsPerKm: -5)
                        })
                        .labelsHidden()
                        .accessibilityLabel("\(RacePlanCalculator.formatDistance(segment.endDistanceKm))までの区間ペース")
                    }
                }
            }
        }
    }

    private var editingIndex: Int? { draft.pacePlans.firstIndex { $0.id == editingID } }

    private func letter(for index: Int) -> String { ["A", "B", "C"][min(index, 2)] }

    private func targetMinutesBinding(at index: Int) -> Binding<Int> {
        Binding {
            max(1, draft.pacePlans[index].targetSeconds / 60)
        } set: { minutes in
            draft.pacePlans[index].targetSeconds = minutes * 60
            rebuild(at: index)
        }
    }

    private func strategyBinding(at index: Int) -> Binding<RacePaceStrategy> {
        Binding { draft.pacePlans[index].strategy } set: { value in
            draft.pacePlans[index].strategy = value
            rebuild(at: index)
        }
    }

    private func halfDifferenceBinding(at index: Int) -> Binding<Int> {
        Binding { draft.pacePlans[index].halfDifferenceSeconds / 60 } set: { value in
            draft.pacePlans[index].halfDifferenceSeconds = value * 60
            rebuild(at: index)
        }
    }

    private func kickDistanceBinding(at index: Int) -> Binding<Double> {
        Binding { draft.pacePlans[index].kickDistanceKm } set: { value in
            draft.pacePlans[index].kickDistanceKm = value
            rebuild(at: index)
        }
    }

    private func kickGainBinding(at index: Int) -> Binding<Int> {
        Binding { draft.pacePlans[index].kickGainSecondsPerKm } set: { value in
            draft.pacePlans[index].kickGainSecondsPerKm = value
            rebuild(at: index)
        }
    }

    private func rebuild(at index: Int) {
        draft.pacePlans[index] = RacePacePlanCalculator.normalized(
            draft.pacePlans[index], raceDistanceKm: draft.distanceKm,
            checkpoints: draft.checkpoints
        )
    }

    private func adjustSegment(planIndex: Int, segmentIndex: Int,
                               paceChangeSecondsPerKm: Int) {
        let plan = draft.pacePlans[planIndex]
        let segment = plan.segments[segmentIndex]
        let change = max(1, Int(((segment.endDistanceKm - segment.startDistanceKm)
                                 * Double(abs(paceChangeSecondsPerKm))).rounded()))
        draft.pacePlans[planIndex] = RacePacePlanCalculator.changingSegment(
            plan, at: segmentIndex,
            to: segment.targetSeconds + (paceChangeSecondsPerKm > 0 ? change : -change)
        )
    }

    private func duplicatePlan() {
        guard draft.pacePlans.count < 3, let index = editingIndex else { return }
        let newOrder = draft.pacePlans.count
        let original = draft.pacePlans[index]
        let copy = RacePacePlan(order: newOrder, name: "\(letter(for: newOrder))・\(original.name)",
                                targetSeconds: original.targetSeconds,
                                segments: original.segments.enumerated().map { offset, segment in
                                    RacePaceSegment(order: offset, startDistanceKm: segment.startDistanceKm,
                                                    endDistanceKm: segment.endDistanceKm,
                                                    targetSeconds: segment.targetSeconds)
                                }, strategy: original.strategy,
                                halfDifferenceSeconds: original.halfDifferenceSeconds,
                                kickDistanceKm: original.kickDistanceKm,
                                kickGainSecondsPerKm: original.kickGainSecondsPerKm)
        draft.pacePlans.append(copy)
        editingID = copy.id
    }

    private func deleteEditingPlan() {
        guard draft.pacePlans.count > 1 else { return }
        draft.pacePlans.removeAll { $0.id == editingID }
        for index in draft.pacePlans.indices { draft.pacePlans[index].order = index }
        editingID = draft.pacePlans[0].id
        if !draft.pacePlans.contains(where: { $0.id == draft.selectedPacePlanID }) {
            draft.selectedPacePlanID = editingID
        }
    }
}

struct RacePaceComparisonView: View {
    let racePlan: RacePlan

    var body: some View {
        List {
            ForEach(racePlan.pacePlans.sorted(by: { $0.order < $1.order })) { plan in
                Section("\(plan.name) · \(plan.strategy.title)") {
                    LabeledContent("ゴール", value: RacePlanCalculator.formatDuration(plan.targetSeconds))
                    ForEach(RacePlanCalculator.splitDistances(for: racePlan.distanceKm), id: \.self) { distance in
                        LabeledContent(RacePlanCalculator.formatDistance(distance), value:
                            RacePlanCalculator.formatDuration(RacePacePlanCalculator.elapsedSeconds(
                                at: distance, in: plan, raceDistanceKm: racePlan.distanceKm
                            )))
                    }
                    ForEach(plan.segments) { segment in
                        LabeledContent(
                            "\(RacePlanCalculator.formatDistance(segment.startDistanceKm)) → \(RacePlanCalculator.formatDistance(segment.endDistanceKm))",
                            value: RacePlanCalculator.targetPace(
                                totalSeconds: segment.targetSeconds,
                                distanceKm: segment.endDistanceKm - segment.startDistanceKm
                            ).displayText
                        )
                    }
                    ForEach(racePlan.checkpoints.sorted(by: { $0.order < $1.order })) { checkpoint in
                        let elapsed = RacePacePlanCalculator.elapsedSeconds(
                            at: checkpoint.distanceKm, in: plan, raceDistanceKm: racePlan.distanceKm
                        )
                        VStack(alignment: .leading) {
                            LabeledContent(checkpoint.name, value: racePlan.startTime
                                .addingTimeInterval(TimeInterval(elapsed))
                                .formatted(date: .abbreviated, time: .shortened))
                            if let cutoff = checkpoint.cutoffTime {
                                let margin = Int(cutoff.timeIntervalSince(
                                    racePlan.startTime.addingTimeInterval(TimeInterval(elapsed))
                                ).rounded())
                                Label(margin >= 0
                                      ? "関門余裕 \(RacePlanCalculator.formatDuration(margin))"
                                      : "関門超過 \(RacePlanCalculator.formatDuration(-margin))",
                                      systemImage: margin >= 0 ? "checkmark.circle" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(margin >= 0 ? Color.secondary : Color.red)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("プラン比較")
    }
}
