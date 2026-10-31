import SwiftUI

struct RaceDetailView: View {
    @Environment(RacePlanStore.self) private var racePlanStore
    @Environment(RacePlanTemplateStore.self) private var templateStore
    @Environment(ProStore.self) private var proStore
    @State private var paywallFeature: ProFeature?
    @Environment(\.openURL) private var openURL
    @State private var isShowingReminderSettings = false
    @State private var isShowingChecklistEditor = false
    @State private var isShowingActivitiesEditor = false
    @State private var duplicateDraft: RacePlan?
    @State private var isShowingReuse = false
    @State private var isShowingSaveTemplate = false
    @State private var templateName = ""
    @State private var templateMessage = ""
    @State private var isShowingTemplateMessage = false
    @State private var preparationEditorStep: RacePreparationStep?
    @State private var isShowingPreparationOutput = false
    @State private var isShowingPaceComparison = false
    @State private var isShowingCourseElevation = false
    @State private var isShowingPacePlanSelectionError = false
    @State private var pacePlanSelectionError = ""
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
            Section {
                RacePreparationView(plan: currentRacePlan) { step in
                    switch step {
                    case .checklist: isShowingChecklistEditor = true
                    case .output: isShowingPreparationOutput = true
                    default:
                        preparationEditorStep = step
                    }
                }
                .disabled(isLoadingReminderState)
            }
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

            Section("レース前の行動予定") {
                if currentRacePlan.preRaceActivities.isEmpty {
                    Text("予定はまだありません。受付や移動などを記録できます。")
                        .foregroundStyle(.secondary)
                }
                ForEach(currentRacePlan.preRaceActivities.chronologicallySorted) { activity in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(activity.name).font(.headline)
                        Text(activity.date.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                        if !activity.location.isEmpty {
                            Label(activity.location, systemImage: "mappin")
                        }
                        if !activity.note.isEmpty { Text(activity.note) }
                    }
                }
                Button("行動予定を編集", systemImage: "calendar") { isShowingActivitiesEditor = true }
                    .accessibilityIdentifier("activities.edit")
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
                    Picker("使用するプラン · Pro", selection: Binding(
                        get: { currentRacePlan.selectedPacePlanID },
                        set: { selectPacePlan($0) }
                    )) {
                        ForEach(currentRacePlan.pacePlans.sorted(by: { $0.order < $1.order })) { plan in
                            Text(plan.name).tag(Optional(plan.id))
                        }
                    }
                    LabeledContent("選択中の目標", value:
                        RacePlanCalculator.formatDuration(currentRacePlan.activeTargetSeconds))
                    ProFeatureButton(feature: .paceStrategies, title: "A・B・Cプランを比較") {
                        isShowingPaceComparison = true
                    }
                }
            }

            Section("コースの標高") {
                if let profile = currentRacePlan.courseElevation {
                    LabeledContent("GPXの距離", value: RacePlanCalculator.formatDistance(profile.distanceKm))
                }
                ProFeatureButton(feature: .courseElevation, title: "GPX・標高とペース補正", systemImage: "mountain.2") {
                    isShowingCourseElevation = true
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
                ForEach(currentRacePlan.checklistItems.sorted(by: { $0.order < $1.order })) { checklistItem in
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(checklistItem.title, isOn: checklistItemBinding(for: checklistItem))
                        HStack(spacing: 8) {
                            let category = ChecklistCategory(rawValue: checklistItem.category ?? "")
                            Text(category?.title ?? "その他")
                            if checklistItem.isRequired {
                                Label("必須", systemImage: "exclamationmark.circle.fill")
                            }
                            if let dueDate = checklistItem.resolvedDueDate(for: currentRacePlan) {
                                Text("期限 \(dueDate.formatted(date: .abbreviated, time: .shortened))")
                            }
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
                ProFeatureButton(feature: .customChecklist, title: "チェックリストを編集", systemImage: "checklist") {
                    isShowingChecklistEditor = true
                }
                if currentRacePlan.checklistNotificationsEnabled {
                    Label("必須項目の期限通知はオン", systemImage: "bell.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section(String(localized: "race_detail.section.memo")) {
                Text(displayedMemo)
                    .foregroundStyle(.secondary)
            }

            Section("Race Card") {
                ProFeatureButton(feature: .raceCard, title: "画像・PDF・ペースバンド出力", systemImage: "square.and.arrow.up") {
                    isShowingPreparationOutput = true
                }
            }

            Section("計画を再利用") {
                ProFeatureButton(feature: .planReuse, title: "この計画を複製", systemImage: "doc.on.doc") {
                    duplicateDraft = currentRacePlan.duplicated()
                }
                Text("この計画のペース・補給・持ち物を保存し、次のレースに使えます。")
                    .font(.footnote).foregroundStyle(.secondary)
                ProFeatureButton(feature: .planReuse, title: "テンプレートとして保存") {
                    templateName = "\(currentRacePlan.name)の設定"
                    isShowingSaveTemplate = true
                }
                ProFeatureButton(feature: .planReuse, title: "テンプレート・別のレースから設定を適用") {
                    isShowingReuse = true
                }
                NavigationLink("保存したテンプレートを管理") {
                    RacePlanTemplatesView()
                }
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
                    preparationEditorStep = .basic
                }
                .disabled(isLoadingReminderState)
            }
        }
        .sheet(item: $preparationEditorStep) { step in
            NavigationStack {
                RacePlanEditView(racePlan: currentRacePlan, initialStep: step) { updatedRacePlan in
                    rescheduleRemindersIfNeeded(for: updatedRacePlan)
                }
            }
        }
        .sheet(isPresented: $isShowingPreparationOutput) {
            NavigationStack {
                RaceCardView(racePlan: currentRacePlan)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("閉じる") { isShowingPreparationOutput = false }
                        }
                    }
            }
        }
        .sheet(item: $duplicateDraft) { draft in
            NavigationStack {
                RaceCreatePlaceholderView(initialPlan: draft)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("キャンセル") { duplicateDraft = nil }
                        }
                    }
            }
            .proProtected(.planReuse)
        }
        .sheet(isPresented: $isShowingReuse) {
            RacePlanReuseView(destination: currentRacePlan) { updated in
                guard proStore.canUse(.planReuse), racePlanStore.updateRacePlan(updated) else { return false }
                rescheduleRemindersIfNeeded(for: updated)
                return true
            }
        }
        .alert("計画テンプレートを保存", isPresented: $isShowingSaveTemplate) {
            TextField("テンプレート名", text: $templateName)
            Button("保存") {
                guard proStore.canUse(.planReuse) else { paywallFeature = .planReuse; return }
                let saved = templateStore.save(name: templateName, source: currentRacePlan)
                templateMessage = saved ? "テンプレートを保存しました。" :
                    (templateStore.error ?? "保存できませんでした。名前と計画の設定を確認してください。")
                isShowingTemplateMessage = true
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("大会名・日時・メモ・コース地点・固定期限を除いて、設定を保存します。")
        }
        .alert("計画テンプレート", isPresented: $isShowingTemplateMessage) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(templateMessage)
        }
        .sheet(isPresented: $isShowingActivitiesEditor) {
            PreRaceActivitiesEditor(activities: currentRacePlan.preRaceActivities,
                                    defaultDate: currentRacePlan.startTime) { activities in
                guard var updated = racePlanStore.racePlans.first(where: { $0.id == currentRacePlan.id }) else { return false }
                updated.preRaceActivities = activities
                return racePlanStore.updateRacePlan(updated)
            }
        }
        .sheet(isPresented: $isShowingChecklistEditor) {
            RaceChecklistEditorView(racePlan: currentRacePlan) { items, notificationsEnabled in
                guard proStore.canUse(.customChecklist) else { return false }
                var updated = currentRacePlan
                updated.checklistItems = items
                updated.checklistNotificationsEnabled = notificationsEnabled
                return racePlanStore.updateRacePlan(updated)
            }
        }
        .sheet(isPresented: $isShowingCourseElevation) {
            RaceCourseElevationView(racePlan: currentRacePlan) { updated in
                guard proStore.canUse(.courseElevation) else { return false }
                return racePlanStore.updateRacePlan(updated)
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
        .sheet(item: $paywallFeature) { ProPaywallView(feature: $0) }
        .alert("ペースプランを変更できません", isPresented: $isShowingPacePlanSelectionError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(pacePlanSelectionError)
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
        guard proStore.canUse(.paceStrategies) else { paywallFeature = .paceStrategies; return }
        guard let id, currentRacePlan.pacePlans.contains(where: { $0.id == id }) else { return }
        var updated = currentRacePlan
        updated.selectedPacePlanID = id
        if racePlanStore.updateRacePlan(updated) {
            rescheduleRemindersIfNeeded(for: updated)
        } else {
            pacePlanSelectionError = racePlanStore.validationError ?? "ペースプランを変更できませんでした。"
            isShowingPacePlanSelectionError = true
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
                let reservationToken = await racePlanStore.reserveChecklistReminderCapacity(
                    for: reminderTimings.count
                )
                defer {
                    racePlanStore.releaseChecklistReminderCapacity(reservationToken)
                }
                guard !Task.isCancelled else {
                    return
                }
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
                let reservationToken = await racePlanStore.reserveChecklistReminderCapacity(
                    for: reminderTimings.count
                )
                defer {
                    racePlanStore.releaseChecklistReminderCapacity(reservationToken)
                }
                guard generation == reminderSchedulingGeneration, isDetailVisible else {
                    return
                }
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
        ChecklistReminderScheduler.enqueueReconciliation(for: racePlanStore.racePlans)
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
    @Environment(ProStore.self) private var proStore
    @State private var editedProFeature: ProFeature?
    @State private var paywallFeature: ProFeature?
    @Environment(\.dismiss) private var dismiss

    let racePlan: RacePlan
    let onSaved: (RacePlan) -> Void
    let initialStep: RacePreparationStep

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
    @State private var isShowingBasicEditCleanupConfirmation = false
    @State private var didOpenInitialStep = false

    init(racePlan: RacePlan, initialStep: RacePreparationStep = .basic, onSaved: @escaping (RacePlan) -> Void) {
        self.racePlan = racePlan
        self.onSaved = onSaved
        self.initialStep = initialStep
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
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 20) {
                formSection("基本情報") {
                    TextField("レース名", text: $raceName)
                        .accessibilityIdentifier("planEditor.name")
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
            .id("edit.pace")

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
                ProFeatureButton(feature: .fuelingPlan, title: "補給・給水プランを設定", systemImage: "drop.fill") {
                    isShowingFuelingEditor = true
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
                ProFeatureButton(feature: .checkpoints, title: "地点を編集", systemImage: "mappin.and.ellipse") {
                    isShowingCheckpointEditor = true
                }
                if let error = RaceCheckpointValidator.error(for: workingRacePlan) {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if !proStore.canUse(.checkpoints), !basicEditCleanup.isEmpty {
                formSection("基本情報の変更に伴う整理") {
                    Text("新しい距離・目標タイムに合わない保存済みデータがあります。対象を確認して整理できます。")
                        .foregroundStyle(.secondary)
                    if !basicEditCleanup.removedCheckpoints.isEmpty {
                        Text("削除する地点: \(basicEditCleanup.removedCheckpoints.map(\.name).joined(separator: "、"))")
                    }
                    if !basicEditCleanup.clearedCheckpointTimes.isEmpty {
                        Text("手動通過時刻を解除する地点: \(basicEditCleanup.clearedCheckpointTimes.map(\.name).joined(separator: "、"))")
                    }
                    if !basicEditCleanup.removedFuelingEvents.isEmpty {
                        Text("削除する補給予定: \(basicEditCleanup.removedFuelingEvents.map(\.name).joined(separator: "、"))")
                    }
                    Button("合わないデータを整理", role: .destructive) {
                        isShowingBasicEditCleanupConfirmation = true
                    }
                    .accessibilityIdentifier("planEditor.cleanupInvalidAdvancedData")
                }
            }

            formSection("ペース戦略") {
                Text(pacePlans.isEmpty ? "基本の均等ペースを使用" : "\(pacePlans.count)プランを設定済み")
                    .foregroundStyle(.secondary)
                ProFeatureButton(feature: .paceStrategies, title: "A・B・Cプランを設定", systemImage: "figure.run") {
                    isShowingPacePlanEditor = true
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
        .onAppear {
            if initialStep == .pace { proxy.scrollTo("edit.pace", anchor: .top) }
        }
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            guard !didOpenInitialStep else { return }
            didOpenInitialStep = true
            switch initialStep {
            case .pace: break
            case .checkpoints: isShowingCheckpointEditor = true
            case .fueling: isShowingFuelingEditor = true
            default: break
            }
        }
        .onChange(of: raceStartDateTime) { previousStartTime, newStartTime in
            checkpoints.moveCutoffTimes(from: previousStartTime, to: newStartTime)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("レースプランを編集")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingCheckpointEditor) {
            RaceCheckpointEditorView(racePlan: workingRacePlan) {
                guard proStore.canUse(.checkpoints) else { return }
                editedProFeature = .checkpoints
                checkpoints = $0
                var normalized = workingRacePlan
                normalized.normalizePacePlans()
                pacePlans = normalized.pacePlans
            }
        }
        .sheet(isPresented: $isShowingPacePlanEditor) {
            NavigationStack {
                RacePacePlansEditorView(racePlan: workingRacePlan) { plans, selected in
                    guard proStore.canUse(.paceStrategies) else { return }
                    editedProFeature = .paceStrategies
                    pacePlans = plans
                    selectedPacePlanID = selected
                }
            }
        }
        .sheet(isPresented: $isShowingFuelingEditor) {
            RaceFuelingPlanEditorView(racePlan: workingRacePlan) {
                guard proStore.canUse(.fuelingPlan) else { return }
                editedProFeature = .fuelingPlan
                fuelingEvents = $0
                gels = []
            }
        }
        .alert("保存できません", isPresented: $isShowingSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(racePlanStore.storageError ?? racePlanStore.validationError ?? "保存処理に失敗しました。")
        }
        .alert("保存済みデータを整理しますか？", isPresented: $isShowingBasicEditCleanupConfirmation) {
            Button("整理する", role: .destructive) {
                let cleanup = basicEditCleanup
                guard !cleanup.isEmpty else { return }
                let cleaned = cleanup.applying(to: workingRacePlan)
                checkpoints = cleaned.checkpoints
                fuelingEvents = cleaned.fuelingEvents
                pacePlans = cleaned.pacePlans
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("表示された地点・補給予定の削除と手動通過時刻の解除を行います。保存するまではレースに反映されません。")
        }
        .sheet(item: $paywallFeature) { ProPaywallView(feature: $0) }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル", action: dismiss.callAsFunction)
                    .accessibilityIdentifier("planEditor.cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
                    .accessibilityIdentifier("planEditor.save")
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

    private var basicEditCleanup: RacePlanBasicEditCleanup {
        RacePlanBasicEditCleanup(original: racePlan, candidate: workingRacePlan)
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
        if let feature = editedProFeature, !proStore.canUse(feature) {
            paywallFeature = feature
            return
        }
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
    .environment(ChecklistTemplateStore())
    .environment(ProStore())
    .environment(RacePlanTemplateStore())
}

private struct RaceDetailPreviewRacePlanStorage: RacePlanStorage {
    let racePlans: [RacePlan]

    func loadRacePlans() -> [RacePlan] {
        racePlans
    }

    func saveRacePlans(_ racePlans: [RacePlan]) {}
}

private struct PreRaceActivitiesEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var activities: [PreRaceActivity]
    @State private var saveError = false
    let defaultDate: Date
    let onSave: ([PreRaceActivity]) -> Bool

    init(activities: [PreRaceActivity], defaultDate: Date, onSave: @escaping ([PreRaceActivity]) -> Bool) {
        _activities = State(initialValue: activities.chronologicallySorted)
        self.defaultDate = defaultDate
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                if activities.isEmpty {
                    Section { Text("受付・移動・荷物預けなどの予定を追加できます。")
                        .foregroundStyle(.secondary) }
                }
                ForEach($activities) { $activity in
                    Section {
                        TextField("予定名", text: $activity.name)
                        DatePicker("日時", selection: $activity.date, displayedComponents: [.date, .hourAndMinute])
                        TextField("場所（任意）", text: $activity.location)
                        TextField("メモ（任意）", text: $activity.note, axis: .vertical)
                        Button("この予定を削除", role: .destructive) {
                            let id = activity.id
                            activities.removeAll { $0.id == id }
                        }
                    } header: {
                        Text(activity.name.isEmpty ? "新しい予定" : activity.name)
                    }
                }
                Section {
                    Button("予定を追加", systemImage: "plus") {
                        activities.append(PreRaceActivity(date: defaultDate))
                    }
                    .accessibilityIdentifier("activities.add")
                } footer: {
                    Text("予定は日時順に表示します。レース日時を変更しても予定の日時は自動変更されず、通知も設定されません。")
                }
                if saveError { Section { Text("予定を保存できませんでした。")
                    .foregroundStyle(.red) } }
            }
            .navigationTitle("行動予定を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let cleaned = activities.map { activity in
                            var value = activity
                            value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
                            value.location = value.location.trimmingCharacters(in: .whitespacesAndNewlines)
                            value.note = value.note.trimmingCharacters(in: .whitespacesAndNewlines)
                            return value
                        }.chronologicallySorted
                        if onSave(cleaned) { dismiss() } else { saveError = true }
                    }
                    .disabled(activities.contains { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                    .accessibilityIdentifier("activities.save")
                }
            }
        }
    }
}
