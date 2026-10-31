import SwiftUI

struct RacePacePlansEditorView: View {
    @Environment(ProStore.self) private var proStore
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
                    guard proStore.canUse(.paceStrategies) else { return }
                    draft.normalizePacePlans()
                    onSave(draft.pacePlans, draft.selectedPacePlanID)
                    dismiss()
                }
                .disabled(RacePacePlanCalculator.validationError(for: draft) != nil)
            }
        }
        .proProtected(.paceStrategies)
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
        .proProtected(.paceStrategies)
    }
}

import UniformTypeIdentifiers

struct RaceCourseElevationView: View {
    @Environment(ProStore.self) private var proStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: RacePlan
    @State private var isImporting = false
    @State private var message: String?
    @State private var terrain: [CourseTerrain] = []
    @State private var maintainTarget = true
    let onSave: (RacePlan) -> Bool

    init(racePlan: RacePlan, onSave: @escaping (RacePlan) -> Bool) {
        _draft = State(initialValue: racePlan)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("コース") {
                    Button("GPXを選択") { isImporting = true }
                    Text("標高付きの単一コースを選択してください。位置情報は保存せず、距離と標高のみを保存します。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let profile = draft.courseElevation {
                        LabeledContent("GPXの距離", value: RacePlanCalculator.formatDistance(profile.distanceKm))
                        LabeledContent("累積上昇", value: "\(Int(profile.ascentMeters.rounded())) m")
                        LabeledContent("累積下降", value: "\(Int(profile.descentMeters.rounded())) m")
                        CourseElevationGraph(profile: profile)
                        .frame(height: 180)
                        .accessibilityLabel("標高グラフ")
                        if abs(profile.distanceKm - draft.distanceKm) / draft.distanceKm > 0.05 {
                            Text("レース距離との差が5%を超えるため補正できません。コースまたはレース距離を確認してください。")
                                .foregroundStyle(.red)
                        } else {
                            Text("距離の差は比率で調整して地点に割り当てます。標高の値はGPSの誤差を含む場合があります。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Button("GPXを削除", role: .destructive) { draft.courseElevation = nil }
                    }
                }
                if let profile = draft.courseElevation, let index = selectedIndex,
                   abs(profile.distanceKm - draft.distanceKm) / draft.distanceKm <= 0.05 {
                    Section("ペース補正 · \(draft.pacePlans[index].name)") {
                        LabeledContent("現在の目標", value: RacePlanCalculator.formatDuration(draft.pacePlans[index].targetSeconds))
                        Picker("補正方法", selection: $maintainTarget) {
                            Text("目標タイムを維持").tag(true)
                            Text("単純補正").tag(false)
                        }
                        Text("標高による簡易的な目安です。実際のペースを保証するものではありません。")
                            .font(.footnote).foregroundStyle(.secondary)
                        ForEach(draft.pacePlans[index].segments.indices, id: \.self) { segmentIndex in
                            let segment = draft.pacePlans[index].segments[segmentIndex]
                            if terrain.indices.contains(segmentIndex) {
                                let changes = CoursePaceAdjustment.gainLoss(start: segment.startDistanceKm, end: segment.endDistanceKm, raceDistance: draft.distanceKm, profile: profile)
                                Text("区間の上昇 \(Int(changes.0.rounded())) m・下降 \(Int(changes.1.rounded())) m · \(RacePlanCalculator.formatDuration(segment.targetSeconds))")
                                    .font(.footnote).foregroundStyle(.secondary)
                                Picker("\(RacePlanCalculator.formatDistance(segment.startDistanceKm)) → \(RacePlanCalculator.formatDistance(segment.endDistanceKm))", selection: $terrain[segmentIndex]) {
                                    ForEach(CourseTerrain.allCases, id: \.self) { value in
                                        Text(value.title).tag(value)
                                    }
                                }
                            }
                        }
                        Button("補正を適用") { applyAdjustment() }
                        Text("適用後はペース戦略画面で各区間を手動調整できます。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else if draft.pacePlans.isEmpty, draft.courseElevation != nil {
                    Section { Text("補正するには、先にペース戦略でプランを作成してください。") }
                }
                if canRestoreSaved {
                    Section { Button("補正を元に戻す") { restoreOriginal() } }
                }
            }
            .navigationTitle("GPX・標高")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard proStore.canUse(.courseElevation) else { return }
                        if onSave(draft) { dismiss() } else { message = "保存できませんでした。" }
                    }
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.data]) { result in
                do {
                    let url = try result.get()
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 10_000_000 else { throw GPXImportError.tooLarge }
                    draft.courseElevation = try GPXCourseParser.parse(Data(contentsOf: url))
                    message = nil
                } catch { message = error.localizedDescription }
            }
            .alert("処理できません", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("OK", role: .cancel) { message = nil }
            } message: {
                Text(message ?? "")
            }
            .onAppear {
                if let index = selectedIndex {
                    terrain = Array(repeating: .automatic, count: draft.pacePlans[index].segments.count)
                }
            }
            .proProtected(.courseElevation)
        }
    }

    private var selectedIndex: Int? { draft.pacePlans.firstIndex { $0.id == draft.selectedPacePlanID } }

    private func applyAdjustment() {
        guard let index = selectedIndex, let profile = draft.courseElevation else { return }
        let baseline = draft.adjustmentBaseline(for: draft.pacePlans[index]) ?? draft.pacePlans[index]
        guard let adjusted = CoursePaceAdjustment.apply(to: baseline, profile: profile,
                                                        terrain: terrain, maintainTarget: maintainTarget) else {
            message = "このプランには補正を適用できません。距離と目標タイムを確認してください。"
            return
        }
        draft.setCourseAdjustment(original: baseline, adjusted: adjusted)
        draft.pacePlans[index] = adjusted
        message = nil
    }

    private func restoreOriginal() {
        guard let index = selectedIndex,
              let baseline = draft.adjustmentBaseline(for: draft.pacePlans[index]) else { return }
        draft.pacePlans[index] = baseline
        draft.removeCourseAdjustment(for: baseline.id)
    }

    private var canRestoreSaved: Bool {
        guard let index = selectedIndex else { return false }
        return draft.adjustmentBaseline(for: draft.pacePlans[index]) != nil
    }
}

private struct CourseElevationGraph: View {
    let profile: CourseElevationProfile
    var body: some View {
        GeometryReader { geometry in
            let minElevation = profile.samples.map(\.elevationMeters).min() ?? 0
            let maxElevation = profile.samples.map(\.elevationMeters).max() ?? 0
            let range = max(1, maxElevation - minElevation)
            Path { path in
                for (index, sample) in profile.samples.enumerated() {
                    let point = CGPoint(x: geometry.size.width * sample.distanceKm / max(0.001, profile.distanceKm),
                                        y: geometry.size.height * (1 - (sample.elevationMeters - minElevation) / range))
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }.stroke(Color.accentColor, lineWidth: 2)
        }
    }
}
