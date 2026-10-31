import SwiftUI

struct RaceCreatePlaceholderView: View {
    @Environment(RacePlanStore.self) private var racePlanStore
    @Environment(RaceCreationDraftStore.self) private var draftStore
    @Environment(ProStore.self) private var proStore
    @Environment(\.dismiss) private var dismiss

    @State private var raceName = ""
    @State private var raceDate = Date()
    @State private var startTime =
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
    @State private var distance = DistanceOption.halfMarathon
    @State private var usesCustomDistance = false
    @State private var customDistanceKm = 21.0975
    @State private var targetHours = 2
    @State private var targetMinutes = 0
    @State private var gels = [GelDraft(name: "補給ジェル 1")]
    @State private var memo = ""
    @State private var checkpoints: [RaceCheckpoint] = []
    @State private var pacePlans: [RacePacePlan] = []
    @State private var courseElevation: CourseElevationProfile?
    @State private var courseAdjustments: [CourseAdjustmentRecord] = []
    @State private var selectedPacePlanID: UUID?
    @State private var fuelingEvents: [RaceFuelingEvent] = []
    @State private var checklistItems = RacePlan.defaultChecklistItems
    @State private var checklistNotificationsEnabled = false
    @State private var draftRacePlanID = UUID()
    @State private var isShowingCheckpointEditor = false
    @State private var isShowingPacePlanEditor = false
    @State private var isShowingFuelingEditor = false
    @State private var isShowingChecklistEditor = false
    @State private var isShowingReuse = false
    @State private var isShowingPreview = false
    @State private var editedProFeature: ProFeature?
    @State private var paywallFeature: ProFeature?
    @State private var step = RacePreparationStep.basic
    @State private var isGuided = true
    @State private var savedPlan: RacePlan?
    @State private var didSave = false
    private let isDuplicate: Bool

    init(initialPlan: RacePlan? = nil, savedDraft: RaceCreationDraft? = nil) {
        isDuplicate = initialPlan != nil
        if initialPlan == nil, let draft = savedDraft {
            _raceName = State(initialValue: draft.name)
            _raceDate = State(initialValue: draft.raceDate)
            _startTime = State(initialValue: draft.startTime)
            let option = DistanceOption.allCases.first { $0.distanceKm == draft.distanceKm }
            _distance = State(initialValue: option ?? .halfMarathon)
            _usesCustomDistance = State(initialValue: draft.usesCustomDistance)
            _customDistanceKm = State(initialValue: draft.customDistanceKm)
            _targetHours = State(initialValue: draft.targetHours)
            _targetMinutes = State(initialValue: draft.targetMinutes)
            _gels = State(initialValue: draft.gelNames.map { GelDraft(name: $0) })
            _memo = State(initialValue: draft.memo)
            _checkpoints = State(initialValue: draft.checkpoints)
            _pacePlans = State(initialValue: draft.pacePlans)
            _selectedPacePlanID = State(initialValue: draft.selectedPacePlanID)
            _fuelingEvents = State(initialValue: draft.fuelingEvents)
            _checklistItems = State(initialValue: draft.checklistItems)
            _checklistNotificationsEnabled = State(
                initialValue: draft.checklistNotificationsEnabled)
            _draftRacePlanID = State(initialValue: draft.id)
            _step = State(initialValue: draft.step)
            _isGuided = State(initialValue: draft.isGuided)
            _editedProFeature = State(initialValue: draft.editedProFeature)
        }
        guard let plan = initialPlan else { return }
        _raceName = State(initialValue: plan.name)
        _raceDate = State(initialValue: plan.raceDate)
        _startTime = State(initialValue: plan.startTime)
        let option = DistanceOption.allCases.first { $0.distanceKm == plan.distanceKm }
        _distance = State(initialValue: option ?? .halfMarathon)
        _usesCustomDistance = State(initialValue: option == nil)
        _customDistanceKm = State(initialValue: plan.distanceKm)
        _targetHours = State(initialValue: plan.targetHours)
        _targetMinutes = State(initialValue: plan.targetMinutes)
        _gels = State(
            initialValue: (0..<max(0, max(plan.gelCount, plan.gelNames?.count ?? 0))).map {
                GelDraft(
                    name: $0 < (plan.gelNames?.count ?? 0) ? plan.gelNames![$0] : "補給ジェル \($0 + 1)")
            })
        _memo = State(initialValue: plan.memo)
        _checkpoints = State(initialValue: plan.checkpoints)
        _pacePlans = State(initialValue: plan.pacePlans)
        _courseElevation = State(initialValue: plan.courseElevation)
        _courseAdjustments = State(initialValue: plan.courseAdjustments)
        _selectedPacePlanID = State(initialValue: plan.selectedPacePlanID)
        _fuelingEvents = State(initialValue: plan.fuelingEvents)
        _checklistItems = State(initialValue: plan.checklistItems)
        _checklistNotificationsEnabled = State(initialValue: plan.checklistNotificationsEnabled)
        _draftRacePlanID = State(initialValue: plan.id)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("順番に作成（オフで従来の一括入力）", isOn: $isGuided)
                            .accessibilityIdentifier("creation.guided")
                        if isGuided {
                            Text(
                                "\(RacePreparationStep.allCases.firstIndex(of: step)! + 1)/6・\(step.title)"
                            )
                            .font(.title3.weight(.semibold))
                            .accessibilityIdentifier("creation.step")
                            Text(step.guidance).foregroundStyle(.secondary)
                        }
                        Text(
                            isDuplicate
                                ? "複製の入力はこの画面内で保持します。" : "入力は下書きとして自動保存します。編集画面の変更は「保存」で反映してください。"
                        )
                        .font(.footnote).foregroundStyle(.secondary)
                        if let error = draftStore.error, !isDuplicate {
                            validationMessage(error)
                        }
                    }
                    .padding(.horizontal)
                    .id("creation.top")
                    if shows(.basic) {
                        reuseSection
                        basicSection
                    }

                    if shows(.pace) {
                        targetSection
                        paceSection
                    }

                    if shows(.fueling) {
                        fuelingSection
                    }

                    if shows(.checkpoints) {
                        checkpointSection
                    }

                    if shows(.checklist) {
                        checklistSection
                    }

                    if shows(.output) {
                        memoSection
                        outputSection

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
                            .accessibilityIdentifier("creation.save")
                            Spacer()
                        }
                    }
                    if isGuided {
                        HStack {
                            if step != .basic {
                                Button("前へ") { moveStep(-1) }
                                    .accessibilityIdentifier("creation.previous")
                            }
                            Spacer()
                            if step != .output {
                                Button("次へ") { moveStep(1) }
                                    .buttonStyle(.borderedProminent)
                                    .accessibilityIdentifier("creation.next")
                            }
                        }.padding(.horizontal)
                    }
                    if isGuided && step != .output {
                        formSection("全体を確認") {
                            RacePreparationView(plan: draftRacePlan) { select($0) }
                        }
                    }
                    if let saveError = racePlanStore.storageError ?? racePlanStore.validationError {
                        validationMessage(saveError)
                            .padding(.horizontal)
                    }
                }
            }
            .onChange(of: step) { _, _ in proxy.scrollTo("creation.top", anchor: .top) }
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: creationDraft) { _, draft in
            if !isDuplicate && !didSave { draftStore.save(draft) }
        }
        .onDisappear {
            if !isDuplicate && !didSave { draftStore.save(creationDraft) }
        }
        .onChange(of: raceStartDateTime) { previousStartTime, newStartTime in
            checkpoints.moveCutoffTimes(from: previousStartTime, to: newStartTime)
            let offset = newStartTime.timeIntervalSince(previousStartTime)
            for index in checklistItems.indices where checklistItems[index].dueDate != nil {
                checklistItems[index].dueDate = checklistItems[index].dueDate?.addingTimeInterval(
                    offset)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(String(localized: "race_create.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("入力完了") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .accessibilityIdentifier("creation.keyboardDone")
            }
        }
        .sheet(isPresented: $isShowingCheckpointEditor) {
            RaceCheckpointEditorView(racePlan: draftRacePlan) {
                guard proStore.canUse(.checkpoints) else { return }
                editedProFeature = .checkpoints
                checkpoints = $0
                normalizeDraftPacePlans()
            }
        }
        .sheet(isPresented: $isShowingPacePlanEditor) {
            NavigationStack {
                RacePacePlansEditorView(racePlan: draftRacePlan) { plans, selected in
                    guard proStore.canUse(.paceStrategies) else { return }
                    editedProFeature = .paceStrategies
                    pacePlans = plans
                    selectedPacePlanID = selected
                }
            }
        }
        .sheet(isPresented: $isShowingFuelingEditor) {
            RaceFuelingPlanEditorView(racePlan: draftRacePlan) {
                guard proStore.canUse(.fuelingPlan) else { return }
                editedProFeature = .fuelingPlan
                fuelingEvents = $0
                gels = []
            }
        }
        .sheet(isPresented: $isShowingChecklistEditor) {
            RaceChecklistEditorView(racePlan: draftRacePlan) { items, notificationsEnabled in
                guard proStore.canUse(.customChecklist) else { return false }
                editedProFeature = .customChecklist
                checklistItems = items
                checklistNotificationsEnabled = notificationsEnabled
                return true
            }
        }
        .sheet(isPresented: $isShowingReuse) {
            RacePlanReuseView(destination: draftRacePlan) { updated in
                guard proStore.canUse(.planReuse) else { return false }
                editedProFeature = .planReuse
                applyReusableSettings(updated)
                return true
            }
        }
        .sheet(isPresented: $isShowingPreview) {
            NavigationStack {
                RaceCardView(racePlan: draftRacePlan)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("閉じる") { isShowingPreview = false }
                        }
                    }
            }
        }
        .sheet(item: $paywallFeature) { ProPaywallView(feature: $0) }
        .sheet(item: $savedPlan, onDismiss: { dismiss() }) { plan in
            NavigationStack {
                RaceCardView(racePlan: plan)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完了") { savedPlan = nil }
                                .accessibilityIdentifier("creation.done")
                        }
                    }
            }
        }
    }

    private func shows(_ step: RacePreparationStep) -> Bool { !isGuided || self.step == step }
    private func select(_ step: RacePreparationStep) {
        isGuided = true
        self.step = step
    }
    private func moveStep(_ offset: Int) {
        let steps = RacePreparationStep.allCases
        guard let index = steps.firstIndex(of: step), steps.indices.contains(index + offset) else {
            return
        }
        step = steps[index + offset]
    }
    private var creationDraft: RaceCreationDraft {
        RaceCreationDraft(
            id: draftRacePlanID, name: raceName, raceDate: raceDate, startTime: startTime,
            distanceKm: distance.distanceKm, usesCustomDistance: usesCustomDistance,
            customDistanceKm: customDistanceKm, targetHours: targetHours,
            targetMinutes: targetMinutes,
            gelNames: gels.map(\.name), memo: memo, checkpoints: checkpoints, pacePlans: pacePlans,
            selectedPacePlanID: selectedPacePlanID, fuelingEvents: fuelingEvents,
            checklistItems: checklistItems,
            checklistNotificationsEnabled: checklistNotificationsEnabled,
            step: step, isGuided: isGuided, editedProFeature: editedProFeature)
    }

    private var reuseSection: some View {
        formSection("計画を再利用") {
            if isDuplicate {
                Text("元の計画を複製しています。大会名・開催日・スタート時刻を確認してから作成してください。チェック済み状態と通知オン状態はリセットされています。")
                    .foregroundStyle(.secondary)
            }
            ProFeatureButton(feature: .planReuse, title: "テンプレート・保存済みレースから設定を再利用") {
                isShowingReuse = true
            }
        }
    }

    private var basicSection: some View {
        formSection(String(localized: "race_create.section.basic_info")) {
            TextField(String(localized: "race_create.field.name"), text: $raceName)
                .accessibilityIdentifier("creation.name")
                .textInputAutocapitalization(.never)
                .textFieldStyle(.roundedBorder)

            if trimmedRaceName.isEmpty {
                validationMessage(String(localized: "race_create.validation.name_required"))
            }

            DatePicker(
                String(localized: "race_create.field.race_date"), selection: $raceDate,
                displayedComponents: .date)

            DatePicker(
                String(localized: "race_create.field.start_time"), selection: $startTime,
                displayedComponents: .hourAndMinute)

            Picker(String(localized: "race_create.field.distance"), selection: $distance) {
                ForEach(DistanceOption.allCases) { distanceOption in
                    Text(distanceOption.label)
                        .tag(distanceOption)
                }
            }
            Toggle("任意の距離を指定", isOn: $usesCustomDistance)
            if usesCustomDistance {
                TextField(
                    "距離 (1〜200km)", value: $customDistanceKm,
                    format: .number.precision(.fractionLength(0...4))
                )
                .keyboardType(.decimalPad)
            }
        }
    }

    private var targetSection: some View {
        formSection("基本目標タイム") {
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
    }

    private var paceSection: some View {
        formSection("ペース戦略・Pro対象") {
            Text(pacePlans.isEmpty ? "基本の均等ペースを使用" : "\(pacePlans.count)プランを設定済み")
                .foregroundStyle(.secondary)
            ProFeatureButton(feature: .paceStrategies, title: "A・B・Cプランを設定") {
                isShowingPacePlanEditor = true
            }
            if let error = RacePacePlanCalculator.validationError(for: draftRacePlan) {
                validationMessage(error)
            }
        }
    }

    private var fuelingSection: some View {
        formSection(String(localized: "race_create.section.fueling")) {
            if fuelingEvents.isEmpty {
                Text("従来の補給ジェル")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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

            Divider()
            Text(fuelingEvents.isEmpty ? "詳細な補給イベントは未設定" : "\(fuelingEvents.count)件の補給イベントを設定済み")
                .foregroundStyle(.secondary)
            ProFeatureButton(feature: .fuelingPlan, title: "補給・給水プランを設定", systemImage: "drop.fill") {
                isShowingFuelingEditor = true
            }
            if let error = RaceFuelingPlanCalculator.validationError(for: draftRacePlan) {
                validationMessage(error)
            }
        }
    }

    private var checkpointSection: some View {
        formSection("チェックポイント") {
            Text(checkpoints.isEmpty ? "地点未設定（従来の5kmごとの表示を使用）" : "\(checkpoints.count)地点を設定済み")
                .foregroundStyle(.secondary)
            ProFeatureButton(feature: .checkpoints, title: "地点を編集", systemImage: "mappin.and.ellipse") {
                isShowingCheckpointEditor = true
            }
            if let validationError = RaceCheckpointValidator.error(for: draftRacePlan) {
                validationMessage(validationError)
            }
        }
    }

    private var checklistSection: some View {
        formSection("チェックリスト") {
            Text("\(checklistItems.count)項目を設定済み")
                .foregroundStyle(.secondary)
            ProFeatureButton(feature: .customChecklist, title: "項目・期限・テンプレートを編集", systemImage: "checklist") {
                isShowingChecklistEditor = true
            }
            ForEach($checklistItems) { $item in
                Toggle(item.title, isOn: $item.isChecked)
            }
        }
    }

    private var memoSection: some View {
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
    }

    private var outputSection: some View {
        formSection("確認・出力") {
            RacePreparationView(plan: draftRacePlan) { select($0) }
            ProFeatureButton(feature: .raceCard, title: "保存前にRace Cardを確認") {
                isShowingPreview = true
            }
            .disabled(!canSave)
            .accessibilityIdentifier("creation.preview")
        }
    }

    private func formSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content)
        -> some View
    {
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
            id: draftRacePlanID, name: trimmedRaceName, raceDate: raceDate,
            startTime: raceStartDateTime,
            distanceKm: selectedDistanceKm, targetHours: targetHours, targetMinutes: targetMinutes,
            gelCount: gels.count, gelNames: gels.map(\.name), memo: trimmedMemo,
            checklistItems: checklistItems,
            checklistNotificationsEnabled: checklistNotificationsEnabled,
            checkpoints: checkpoints, pacePlans: pacePlans,
            selectedPacePlanID: selectedPacePlanID, fuelingEvents: fuelingEvents
        )
        racePlan.courseElevation = courseElevation
        racePlan.courseAdjustments = courseAdjustments
        racePlan.normalizeFinishCheckpoints()
        racePlan.normalizePacePlans()
        return racePlan
    }

    private func normalizeDraftPacePlans() {
        var plan = draftRacePlan
        plan.normalizePacePlans()
        pacePlans = plan.pacePlans
    }

    private func applyReusableSettings(_ plan: RacePlan) {
        let option = DistanceOption.allCases.first { $0.distanceKm == plan.distanceKm }
        distance = option ?? .halfMarathon
        usesCustomDistance = option == nil
        customDistanceKm = plan.distanceKm
        targetHours = plan.targetHours
        targetMinutes = plan.targetMinutes
        pacePlans = plan.pacePlans
        courseElevation = plan.courseElevation
        courseAdjustments = plan.courseAdjustments
        selectedPacePlanID = plan.selectedPacePlanID
        fuelingEvents = plan.fuelingEvents
        let names = plan.gelNames ?? []
        gels = (0..<max(0, max(plan.gelCount, names.count))).map {
            GelDraft(name: $0 < names.count ? names[$0] : "補給ジェル \($0 + 1)")
        }
        checkpoints = plan.checkpoints
        checklistItems = plan.checklistItems
        checklistNotificationsEnabled = plan.checklistNotificationsEnabled
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
        if let feature = editedProFeature, !proStore.canUse(feature) {
            paywallFeature = feature
            return
        }
        guard canSave else {
            return
        }

        var racePlan = draftRacePlan
        racePlan.gelNames = gels.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
        let saved = racePlanStore.addRacePlan(racePlan)
        if saved {
            didSave = true
            if !isDuplicate { draftStore.clear(savedID: racePlan.id) }
            if proStore.canUse(.raceCard) {
                savedPlan = racePlan
            } else {
                dismiss()
            }
        }
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
    .environment(RaceFuelingPresetStore())
    .environment(ChecklistTemplateStore())
    .environment(ProStore())
    .environment(RacePlanTemplateStore())
    .environment(RaceCreationDraftStore())
}

private struct EmptyRacePlanStorage: RacePlanStorage {
    func loadRacePlans() -> [RacePlan] {
        []
    }

    func saveRacePlans(_ racePlans: [RacePlan]) {}
}
