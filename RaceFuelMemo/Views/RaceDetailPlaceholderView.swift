import SwiftUI

struct RaceDetailView: View {
    @Environment(RacePlanStore.self) private var racePlanStore
    @Environment(\.openURL) private var openURL
    @State private var isShowingReminderSettings = false
    @State private var isShowingRacePlanEditor = false
    @State private var isShowingPaceComparison = false
    @State private var showsClockTimes = false
    @State private var notificationMessage = ""
    @State private var isShowingNotificationAlert = false
    @State private var notificationRegistrationTask: Task<Void, Never>?
    @State private var testNotificationTask: Task<Void, Never>?
    @State private var reminderReschedulingTask: Task<Void, Never>?
    @State private var selectedReminderTimings: Set<RaceReminderTiming> = []
    @State private var registeredReminderTimings: Set<RaceReminderTiming> = []
    @State private var registeredReminderDates: [Date] = []
    @State private var shouldOfferSettings = false
    @State private var reminderStateRevision = 0
    @State private var reminderSchedulingGeneration = 0
    @State private var isLoadingReminderState = true
    @State private var isDetailVisible = false

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
                    "基本目標タイム",
                    value: formattedTargetTime
                )
            }

            Section(String(localized: "race_detail.section.target_pace")) {
                LabeledContent(
                    String(localized: "race_detail.field.pace_per_kilometer"),
                    value: calculation.targetPaceText
                )
            }

            Section("ペース戦略") {
                if currentRacePlan.pacePlans.isEmpty {
                    Text("基本の均等ペース")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("使用するプラン", selection: Binding(
                        get: { currentRacePlan.selectedPacePlanID },
                        set: { selectPacePlan($0) }
                    )) {
                        ForEach(currentRacePlan.pacePlans.sorted(by: { $0.order < $1.order })) { plan in
                            Text(plan.name).tag(Optional(plan.id))
                        }
                    }
                    LabeledContent("選択中の目標", value:
                        RacePlanCalculator.formatDuration(currentRacePlan.activeTargetSeconds))
                    Button("A・B・Cプランを比較") {
                        isShowingPaceComparison = true
                    }
                }
            }

            if currentRacePlan.checkpoints.isEmpty {
                Section(String(localized: "race_detail.section.split_times")) {
                    ForEach(calculation.splitTimes) { splitTime in
                        LabeledContent(splitTime.distanceText, value: splitTime.elapsedTimeText)
                    }
                }
            } else {
                Section("チェックポイント") {
                    Picker("表示時刻", selection: $showsClockTimes) {
                        Text("経過時間").tag(false)
                        Text("時計時刻").tag(true)
                    }
                    .pickerStyle(.segmented)

                    ForEach(RacePlanCalculator.checkpointSchedules(for: currentRacePlan)) { schedule in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Label(schedule.checkpoint.name,
                                      systemImage: checkpointSymbol(schedule.checkpoint.kind))
                                Spacer()
                                Text(RacePlanCalculator.formatDistance(schedule.checkpoint.distanceKm))
                                    .foregroundStyle(.secondary)
                            }
                            Text(showsClockTimes
                                 ? schedule.passingTime.formatted(date: .abbreviated, time: .shortened)
                                 : RacePlanCalculator.formatDuration(schedule.elapsedSeconds))
                                .font(.headline)
                            if schedule.checkpoint.hasAidStation && schedule.checkpoint.kind != .aidStation {
                                Label("給水あり", systemImage: "drop.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            if let cutoff = schedule.checkpoint.cutoffTime {
                                Text("関門 \(cutoff.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.subheadline)
                            }
                            if let margin = schedule.cutoffMarginSeconds {
                                Text(margin >= 0
                                     ? "関門余裕 \(RacePlanCalculator.formatDuration(margin))"
                                     : "関門超過 \(RacePlanCalculator.formatDuration(-margin))")
                                    .foregroundStyle(margin >= 0 ? Color.secondary : Color.red)
                            }
                            if !schedule.checkpoint.segmentNote.isEmpty {
                                Text(schedule.checkpoint.segmentNote)
                                    .font(.subheadline)
                            }
                            if !schedule.checkpoint.cautionNote.isEmpty {
                                Label(schedule.checkpoint.cautionNote, systemImage: "exclamationmark.triangle")
                                    .font(.subheadline)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                    }
                    if !currentRacePlan.checkpoints.contains(where: { $0.kind == .finish }) {
                        LabeledContent("ゴール \(formattedDistance)", value: showsClockTimes
                            ? currentRacePlan.startTime.addingTimeInterval(
                                TimeInterval(currentRacePlan.activeTargetSeconds)
                            ).formatted(date: .abbreviated, time: .shortened)
                            : RacePlanCalculator.formatDuration(currentRacePlan.activeTargetSeconds))
                    }
                    if let error = RaceCheckpointValidator.error(for: currentRacePlan) {
                        Label(error, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                }
            }

            Section(String(localized: "race_detail.section.fueling")) {
                if let error = RaceFuelingPlanCalculator.validationError(for: currentRacePlan) {
                    Label(error, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                }
                if !currentRacePlan.fuelingEvents.isEmpty {
                    ForEach(RaceFuelingPlanCalculator.schedule(for: currentRacePlan)) { scheduled in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(scheduled.event.kind.title)・\(scheduled.event.name) ×\(scheduled.event.quantity)")
                                .font(.headline)
                            Text("\(scheduled.checkpointName ?? RacePlanCalculator.formatDistance(scheduled.distanceKm))・\(RacePlanCalculator.formatDuration(scheduled.elapsedSeconds))・\(scheduled.passingTime.formatted(date: .omitted, time: .shortened))")
                                .font(.subheadline)
                            Text(scheduled.event.pickup.title)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let grams = scheduled.event.carbohydrateGramsPerItem {
                                Text("炭水化物 \(grams.formatted())g/個")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            if scheduled.event.containsCaffeine {
                                Text("カフェイン入り")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            if !scheduled.event.note.isEmpty {
                                Text(scheduled.event.note)
                                    .font(.subheadline)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    DisclosureGroup("必要な補給品") {
                        ForEach(RaceFuelingPlanCalculator.requirements(for: currentRacePlan.fuelingEvents)) { item in
                            LabeledContent("\(item.kind.title)・\(item.name)", value: "\(item.quantity)個")
                        }
                    }
                } else if calculation.fuelTimings.isEmpty {
                    Text(String(localized: "race_detail.empty.fuel_timings"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(calculation.fuelTimings.enumerated()), id: \.offset) { _, fuelTiming in
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
                    selectedReminderTimings = registeredReminderTimings
                    isShowingReminderSettings = true
                } label: {
                    Label(String(localized: "race_detail.action.notification_settings"), systemImage: "bell.badge")
                }
                .disabled(isLoadingReminderState)
            }

            Section("通知設定") {
                if isLoadingReminderState {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("通知設定を確認中")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ReminderStatusCards(selectedTimings: registeredReminderTimings)

                    if !registeredReminderDates.isEmpty {
                        ForEach(registeredReminderDates, id: \.self) { date in
                            Label(date.formatted(date: .abbreviated, time: .shortened), systemImage: "bell.fill")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(currentRacePlan.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("編集") {
                    isShowingRacePlanEditor = true
                }
                .disabled(isLoadingReminderState)
            }
        }
        .sheet(isPresented: $isShowingRacePlanEditor) {
            NavigationStack {
                RacePlanEditView(racePlan: currentRacePlan) { updatedRacePlan in
                    rescheduleRemindersIfNeeded(for: updatedRacePlan)
                }
            }
        }
        .sheet(isPresented: $isShowingPaceComparison) {
            NavigationStack {
                RacePaceComparisonView(racePlan: currentRacePlan)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("閉じる") { isShowingPaceComparison = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $isShowingReminderSettings) {
            ReminderSettingsSheet(
                selectedTimings: $selectedReminderTimings,
                hasRegisteredReminders: !registeredReminderTimings.isEmpty,
                onSave: {
                    isShowingReminderSettings = false
                    registerNotifications()
                },
                onCancelReminders: {
                    isShowingReminderSettings = false
                    cancelNotificationRegistration()
                    shouldOfferSettings = false
                    notificationMessage = String(localized: "notification.message.cancelled")
                    isShowingNotificationAlert = true
                },
                onSendTestNotification: {
                    isShowingReminderSettings = false
                    sendTestNotification()
                }
            )
            .presentationDetents([.large])
        }
        .alert(String(localized: "notification.alert.title"), isPresented: $isShowingNotificationAlert) {
            if shouldOfferSettings {
                Button("設定を開く") {
                    openURL(URL(string: UIApplication.openSettingsURLString)!)
                }
            }
            Button(String(localized: "notification.action.ok"), role: .cancel) {}
        } message: {
            Text(notificationMessage)
        }
        .onDisappear {
            isDetailVisible = false
            notificationRegistrationTask?.cancel()
            testNotificationTask?.cancel()
        }
        .onAppear {
            isDetailVisible = true
        }
        .task(id: currentRacePlan.id) {
            await refreshRegisteredReminderDates()
        }
    }

    private var currentRacePlan: RacePlan {
        racePlanStore.racePlans.first(where: { $0.id == racePlan.id }) ?? racePlan
    }

    private var calculation: RacePlanCalculation {
        currentRacePlan.calculation
    }

    private func checkpointSymbol(_ kind: RaceCheckpointKind) -> String {
        switch kind {
        case .regular: "mappin"
        case .aidStation: "drop.fill"
        case .cutoff: "clock.badge.exclamationmark"
        case .turnaround: "arrow.uturn.backward"
        case .finish: "flag.checkered"
        }
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

    private func selectPacePlan(_ id: UUID?) {
        guard let id, currentRacePlan.pacePlans.contains(where: { $0.id == id }) else { return }
        var updated = currentRacePlan
        updated.selectedPacePlanID = id
        if racePlanStore.updateRacePlan(updated) {
            rescheduleRemindersIfNeeded(for: updated)
        }
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

    private func registerNotifications() {
        notificationRegistrationTask?.cancel()
        reminderReschedulingTask?.cancel()
        reminderReschedulingTask = nil
        reminderSchedulingGeneration += 1
        shouldOfferSettings = false
        let racePlan = currentRacePlan
        let reminderTimings = selectedReminderTimings

        guard !reminderTimings.isEmpty else {
            guard !registeredReminderTimings.isEmpty else {
                return
            }

            cancelNotificationRegistration()
            notificationMessage = String(localized: "notification.message.cancelled")
            isShowingNotificationAlert = true
            return
        }

        notificationRegistrationTask = Task { @MainActor in
            do {
                let count = try await RaceReminderScheduler.requestAuthorizationAndSchedule(
                    for: racePlan,
                    timings: reminderTimings
                )
                guard !Task.isCancelled else {
                    return
                }

                notificationMessage = count == 0
                    ? String(localized: "notification.message.no_future_reminders")
                    : String(format: String(localized: "notification.message.registered"), count)
                isShowingNotificationAlert = true
                shouldOfferSettings = false
                await refreshRegisteredReminderDates()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                notificationMessage = error.localizedDescription
                shouldOfferSettings = error is RaceReminderSchedulerError
                isShowingNotificationAlert = true
            }
        }
    }

    private func rescheduleRemindersIfNeeded(for racePlan: RacePlan) {
        guard !registeredReminderTimings.isEmpty else {
            return
        }

        notificationRegistrationTask?.cancel()
        notificationRegistrationTask = nil
        reminderReschedulingTask?.cancel()
        reminderSchedulingGeneration += 1
        let generation = reminderSchedulingGeneration
        let reminderTimings = registeredReminderTimings
        reminderReschedulingTask = Task { @MainActor in
            guard generation == reminderSchedulingGeneration else {
                return
            }

            do {
                _ = try await RaceReminderScheduler.requestAuthorizationAndSchedule(
                    for: racePlan,
                    timings: reminderTimings
                )
                guard generation == reminderSchedulingGeneration, isDetailVisible else {
                    return
                }

                await refreshRegisteredReminderDates()
            } catch is CancellationError {
                return
            } catch {
                guard generation == reminderSchedulingGeneration, isDetailVisible else {
                    return
                }

                notificationMessage = error.localizedDescription
                shouldOfferSettings = error is RaceReminderSchedulerError
                isShowingNotificationAlert = true
            }
        }
    }

    private func cancelNotificationRegistration() {
        notificationRegistrationTask?.cancel()
        notificationRegistrationTask = nil
        reminderReschedulingTask?.cancel()
        reminderReschedulingTask = nil
        reminderStateRevision += 1
        reminderSchedulingGeneration += 1
        isLoadingReminderState = false
        RaceReminderScheduler.cancelReminders(for: currentRacePlan.id)
        registeredReminderDates = []
        registeredReminderTimings = []
        selectedReminderTimings = []
    }

    private func sendTestNotification() {
        #if DEBUG
        testNotificationTask?.cancel()
        shouldOfferSettings = false

        testNotificationTask = Task { @MainActor in
            do {
                try await RaceReminderScheduler.requestAuthorizationAndScheduleTestNotifications()
                guard !Task.isCancelled else {
                    return
                }

                notificationMessage = String(localized: "notification.message.test_scheduled")
                isShowingNotificationAlert = true
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                notificationMessage = error.localizedDescription
                shouldOfferSettings = error is RaceReminderSchedulerError
                isShowingNotificationAlert = true
            }
        }
        #endif
    }

    @MainActor
    private func refreshRegisteredReminderDates() async {
        reminderStateRevision += 1
        let revision = reminderStateRevision
        isLoadingReminderState = true
        defer {
            if revision == reminderStateRevision {
                isLoadingReminderState = false
            }
        }
        let dates = await RaceReminderScheduler.pendingReminderDates(for: currentRacePlan.id)
        let pendingTimings = await RaceReminderScheduler.pendingReminderTimings(for: currentRacePlan.id)

        guard revision == reminderStateRevision, !Task.isCancelled else {
            return
        }

        registeredReminderDates = dates
        registeredReminderTimings = pendingTimings
        selectedReminderTimings = pendingTimings
    }
}

private struct RacePlanEditView: View {
    @Environment(RacePlanStore.self) private var racePlanStore
    @Environment(\.dismiss) private var dismiss

    let racePlan: RacePlan
    let onSaved: (RacePlan) -> Void

    @State private var raceName: String
    @State private var raceDate: Date
    @State private var startTime: Date
    @State private var distance: DistanceOption
    @State private var usesCustomDistance: Bool
    @State private var customDistanceKm: Double
    @State private var targetHours: Int
    @State private var targetMinutes: Int
    @State private var gels: [EditableGelDraft]
    @State private var memo: String
    @State private var checkpoints: [RaceCheckpoint]
    @State private var pacePlans: [RacePacePlan]
    @State private var selectedPacePlanID: UUID?
    @State private var fuelingEvents: [RaceFuelingEvent]
    @State private var isShowingCheckpointEditor = false
    @State private var isShowingPacePlanEditor = false
    @State private var isShowingFuelingEditor = false
    @State private var isShowingSaveError = false

    init(racePlan: RacePlan, onSaved: @escaping (RacePlan) -> Void) {
        self.racePlan = racePlan
        self.onSaved = onSaved
        _raceName = State(initialValue: racePlan.name)
        _raceDate = State(initialValue: racePlan.raceDate)
        _startTime = State(initialValue: racePlan.startTime)
        _distance = State(initialValue: DistanceOption.allCases.first(where: { $0.distanceKm == racePlan.distanceKm }) ?? .halfMarathon)
        _usesCustomDistance = State(initialValue: !DistanceOption.allCases.contains { $0.distanceKm == racePlan.distanceKm })
        _customDistanceKm = State(initialValue: racePlan.distanceKm)
        _targetHours = State(initialValue: racePlan.targetHours)
        _targetMinutes = State(initialValue: racePlan.targetMinutes)
        _gels = State(initialValue: Self.gelDrafts(for: racePlan))
        _memo = State(initialValue: racePlan.memo)
        _checkpoints = State(initialValue: racePlan.checkpoints)
        _pacePlans = State(initialValue: racePlan.pacePlans)
        _selectedPacePlanID = State(initialValue: racePlan.selectedPacePlanID)
        _fuelingEvents = State(initialValue: racePlan.fuelingEvents)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                formSection("基本情報") {
                    TextField("レース名", text: $raceName)
                        .textFieldStyle(.roundedBorder)
                    DatePicker("開催日", selection: $raceDate, displayedComponents: .date)
                    DatePicker("スタート時刻", selection: $startTime, displayedComponents: .hourAndMinute)
                    Picker("距離", selection: $distance) {
                        ForEach(DistanceOption.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    Toggle("任意の距離を指定", isOn: $usesCustomDistance)
                    if usesCustomDistance {
                        TextField("距離 (1〜200km)", value: $customDistanceKm,
                                  format: .number.precision(.fractionLength(0...4)))
                            .keyboardType(.decimalPad)
                    }
                }

            formSection("基本目標タイム") {
                Stepper(value: $targetHours, in: 0...240) {
                    LabeledContent("時間", value: "\(targetHours)時間")
                }

                HStack(spacing: 16) {
                    Text("分")
                        .frame(width: 52, alignment: .leading)
                    Picker("", selection: $targetMinutes) {
                        ForEach(0..<60) { minute in
                            Text("\(minute)分").tag(minute)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .clipped()
                }
            }

            formSection("補給") {
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
                        gels.append(EditableGelDraft(name: "補給ジェル \(gels.count + 1)"))
                    } label: {
                        Label("補給ジェルを追加", systemImage: "plus.circle.fill")
                    }
                }
                Divider()
                Text(fuelingEvents.isEmpty ? "詳細な補給イベントは未設定" : "\(fuelingEvents.count)件の補給イベントを設定済み")
                    .foregroundStyle(.secondary)
                Button {
                    isShowingFuelingEditor = true
                } label: {
                    Label("補給・給水プランを設定", systemImage: "drop.fill")
                }
                if let error = RaceFuelingPlanCalculator.validationError(for: workingRacePlan) {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.red)
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
                if let error = RaceCheckpointValidator.error(for: workingRacePlan) {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            formSection("ペース戦略") {
                Text(pacePlans.isEmpty ? "基本の均等ペースを使用" : "\(pacePlans.count)プランを設定済み")
                    .foregroundStyle(.secondary)
                Button {
                    isShowingPacePlanEditor = true
                } label: {
                    Label("A・B・Cプランを設定", systemImage: "figure.run")
                }
                if let error = RacePacePlanCalculator.validationError(for: workingRacePlan) {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.footnote).foregroundStyle(.red)
                }
            }

            formSection("メモ") {
                TextField("当日の持ち物や注意点などを入力（任意）", text: $memo, axis: .vertical)
                    .lineLimit(4...8)
                    .textFieldStyle(.roundedBorder)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: raceStartDateTime) { previousStartTime, newStartTime in
            checkpoints.moveCutoffTimes(from: previousStartTime, to: newStartTime)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("レースプランを編集")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingCheckpointEditor) {
            RaceCheckpointEditorView(racePlan: workingRacePlan) {
                checkpoints = $0
                var normalized = workingRacePlan
                normalized.normalizePacePlans()
                pacePlans = normalized.pacePlans
            }
        }
        .sheet(isPresented: $isShowingPacePlanEditor) {
            NavigationStack {
                RacePacePlansEditorView(racePlan: workingRacePlan) { plans, selected in
                    pacePlans = plans
                    selectedPacePlanID = selected
                }
            }
        }
        .sheet(isPresented: $isShowingFuelingEditor) {
            RaceFuelingPlanEditorView(racePlan: workingRacePlan) {
                fuelingEvents = $0
                gels = []
            }
        }
        .alert("保存できません", isPresented: $isShowingSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(racePlanStore.storageError ?? racePlanStore.validationError ?? "保存処理に失敗しました。")
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル", action: dismiss.callAsFunction)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
                    .disabled(trimmedRaceName.isEmpty || !hasValidTargetTime
                              || RaceCheckpointValidator.error(for: workingRacePlan) != nil)
            }
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

    private var hasValidTargetTime: Bool {
        targetHours > 0 || targetMinutes > 0
    }

    private var workingRacePlan: RacePlan {
        var updated = racePlan
        updated.name = trimmedRaceName
        updated.raceDate = raceDate
        updated.startTime = raceStartDateTime
        updated.distanceKm = usesCustomDistance ? customDistanceKm : distance.distanceKm
        updated.targetHours = targetHours
        updated.targetMinutes = targetMinutes
        updated.gelCount = gels.count
        updated.gelNames = gels.map(\.name)
        updated.checkpoints = checkpoints
        updated.pacePlans = pacePlans
        updated.selectedPacePlanID = selectedPacePlanID
        updated.fuelingEvents = fuelingEvents
        updated.normalizeFinishCheckpoints()
        updated.normalizePacePlans()
        return updated
    }

    private var raceStartDateTime: Date {
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: raceDate)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: startTime)
        return calendar.date(from: DateComponents(
            year: dateComponents.year,
            month: dateComponents.month,
            day: dateComponents.day,
            hour: timeComponents.hour,
            minute: timeComponents.minute
        )) ?? startTime
    }

    private func save() {
        guard !trimmedRaceName.isEmpty, hasValidTargetTime else {
            return
        }

        guard var updatedRacePlan = racePlanStore.racePlans.first(where: { $0.id == racePlan.id }) else {
            return
        }
        updatedRacePlan.name = trimmedRaceName
        updatedRacePlan.raceDate = raceDate
        updatedRacePlan.startTime = raceStartDateTime
        updatedRacePlan.distanceKm = usesCustomDistance ? customDistanceKm : distance.distanceKm
        updatedRacePlan.targetHours = targetHours
        updatedRacePlan.targetMinutes = targetMinutes
        updatedRacePlan.gelCount = gels.count
        updatedRacePlan.gelNames = gels.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
        updatedRacePlan.memo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedRacePlan.checkpoints = checkpoints
        updatedRacePlan.pacePlans = pacePlans
        updatedRacePlan.selectedPacePlanID = selectedPacePlanID
        updatedRacePlan.fuelingEvents = fuelingEvents
        updatedRacePlan.normalizeFinishCheckpoints()
        updatedRacePlan.normalizePacePlans()
        if racePlanStore.updateRacePlan(updatedRacePlan) {
            onSaved(updatedRacePlan)
            dismiss()
        } else {
            isShowingSaveError = true
        }
    }

    private static func gelDrafts(for racePlan: RacePlan) -> [EditableGelDraft] {
        let names = racePlan.gelNames ?? []
        if !names.isEmpty {
            return names.map(EditableGelDraft.init)
        }

        return (0..<racePlan.gelCount).map { EditableGelDraft(name: "補給ジェル \($0 + 1)") }
    }
}

private struct EditableGelDraft: Identifiable {
    let id = UUID()
    var name: String
}

private struct ReminderStatusCards: View {
    let selectedTimings: Set<RaceReminderTiming>

    var body: some View {
        HStack(spacing: 8) {
            ReminderStatusCard(
                title: "通知なし",
                systemImage: "bell.slash.fill",
                isEnabled: selectedTimings.isEmpty
            )

            ForEach(RaceReminderTiming.allCases) { timing in
                ReminderStatusCard(
                    title: timing.shortLabel,
                    systemImage: "bell.fill",
                    isEnabled: selectedTimings.contains(timing)
                )
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ReminderStatusCard: View {
    let title: String
    let systemImage: String
    let isEnabled: Bool

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.bold))
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary)
        .background(
            isEnabled ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }
}

private struct ReminderSettingsSheet: View {
    @Binding var selectedTimings: Set<RaceReminderTiming>
    let hasRegisteredReminders: Bool
    let onSave: () -> Void
    let onCancelReminders: () -> Void
    let onSendTestNotification: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    reminderOption(
                        title: "通知なし",
                        subtitle: "通知を登録しない",
                        systemImage: "bell.slash.fill",
                        isSelected: selectedTimings.isEmpty
                    ) {
                        selectedTimings = []
                    }

                    ForEach(RaceReminderTiming.allCases) { timing in
                        reminderOption(
                            title: timing.label,
                            subtitle: timing.detailLabel,
                            systemImage: "bell.fill",
                            isSelected: selectedTimings.contains(timing)
                        ) {
                            if selectedTimings.contains(timing) {
                                selectedTimings.remove(timing)
                            } else {
                                selectedTimings.insert(timing)
                            }
                        }
                    }
                }

                Spacer()

                Button("保存", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)

                Button("登録済み通知を取り消す", role: .destructive, action: onCancelReminders)
                    .disabled(!hasRegisteredReminders)
                    .frame(maxWidth: .infinity)

                #if DEBUG
                Button("実際の通知をテスト送信", action: onSendTestNotification)
                    .frame(maxWidth: .infinity)
                #endif
            }
            .padding()
            .navigationTitle("通知設定")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func reminderOption(
        title: String,
        subtitle: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: systemImage)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                }
                Text(title)
                    .font(.subheadline.weight(.bold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 94, alignment: .leading)
            .padding(12)
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .background(
                isSelected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
        .buttonStyle(.plain)
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
