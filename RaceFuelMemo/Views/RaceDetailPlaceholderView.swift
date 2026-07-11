import SwiftUI

struct RaceDetailView: View {
    @Environment(RacePlanStore.self) private var racePlanStore
    @Environment(\.openURL) private var openURL
    @State private var isShowingReminderSettings = false
    @State private var notificationMessage = ""
    @State private var isShowingNotificationAlert = false
    @State private var notificationRegistrationTask: Task<Void, Never>?
    @State private var selectedReminderTimings: Set<RaceReminderTiming> = []
    @State private var registeredReminderTimings: Set<RaceReminderTiming> = []
    @State private var registeredReminderDates: [Date] = []
    @State private var shouldOfferSettings = false
    @State private var reminderStateRevision = 0
    @State private var isLoadingReminderState = true

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
                    String(localized: "race_detail.field.target_time"),
                    value: formattedTargetTime
                )
            }

            Section(String(localized: "race_detail.section.target_pace")) {
                LabeledContent(
                    String(localized: "race_detail.field.pace_per_kilometer"),
                    value: calculation.targetPaceText
                )
            }

            Section(String(localized: "race_detail.section.split_times")) {
                ForEach(calculation.splitTimes) { splitTime in
                    LabeledContent(splitTime.distanceText, value: splitTime.elapsedTimeText)
                }
            }

            Section(String(localized: "race_detail.section.fueling")) {
                if calculation.fuelTimings.isEmpty {
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
        .navigationTitle(currentRacePlan.name)
        .navigationBarTitleDisplayMode(.inline)
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
                }
            )
            .presentationDetents([.medium])
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
            notificationRegistrationTask?.cancel()
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
        shouldOfferSettings = false
        let racePlan = currentRacePlan
        let reminderTimings = selectedReminderTimings

        guard !reminderTimings.isEmpty else {
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

    private func cancelNotificationRegistration() {
        notificationRegistrationTask?.cancel()
        notificationRegistrationTask = nil
        reminderStateRevision += 1
        isLoadingReminderState = false
        RaceReminderScheduler.cancelReminders(for: currentRacePlan.id)
        registeredReminderDates = []
        registeredReminderTimings = []
        selectedReminderTimings = []
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

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("通知するタイミングを選択")
                    .font(.headline)

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
