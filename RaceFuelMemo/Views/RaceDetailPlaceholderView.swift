import SwiftUI

struct RaceDetailView: View {
    @Environment(RacePlanStore.self) private var racePlanStore
    @Environment(\.openURL) private var openURL
    @State private var isShowingNotificationConfirmation = false
    @State private var notificationMessage = ""
    @State private var isShowingNotificationAlert = false
    @State private var notificationRegistrationTask: Task<Void, Never>?
    @State private var selectedReminderTimings = Set(RaceReminderTiming.allCases)
    @State private var registeredReminderDates: [Date] = []
    @State private var shouldOfferSettings = false
    @State private var reminderStateRevision = 0

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
                    isShowingNotificationConfirmation = true
                } label: {
                    Label(String(localized: "race_detail.action.notification_settings"), systemImage: "bell.badge")
                }
            }

            if !registeredReminderDates.isEmpty {
                Section("登録済みの通知") {
                    ForEach(registeredReminderDates, id: \.self) { date in
                        Label(date.formatted(date: .abbreviated, time: .shortened), systemImage: "bell.fill")
                    }
                }
            }
        }
        .navigationTitle(currentRacePlan.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            String(localized: "notification.dialog.title"),
            isPresented: $isShowingNotificationConfirmation,
            titleVisibility: .visible
        ) {
            ForEach(RaceReminderTiming.allCases) { timing in
                Button {
                    if selectedReminderTimings.contains(timing) {
                        selectedReminderTimings.remove(timing)
                    } else {
                        selectedReminderTimings.insert(timing)
                    }
                    isShowingNotificationConfirmation = true
                } label: {
                    Text("\(selectedReminderTimings.contains(timing) ? "✓ " : "")\(timing.label)")
                }
            }
            Button(String(localized: "notification.action.register")) {
                registerNotifications()
            }
            .disabled(selectedReminderTimings.isEmpty)
            Button(String(localized: "notification.action.cancel_reminders"), role: .destructive) {
                cancelNotificationRegistration()
                shouldOfferSettings = false
                notificationMessage = String(localized: "notification.message.cancelled")
                isShowingNotificationAlert = true
            }
        } message: {
            Text(String(localized: "notification.dialog.message"))
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

        notificationRegistrationTask = Task { @MainActor in
            do {
                let count = try await RaceReminderScheduler.requestAuthorizationAndSchedule(
                    for: racePlan,
                    timings: selectedReminderTimings
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
        RaceReminderScheduler.cancelReminders(for: currentRacePlan.id)
        registeredReminderDates = []
    }

    @MainActor
    private func refreshRegisteredReminderDates() async {
        let revision = reminderStateRevision
        let dates = await RaceReminderScheduler.pendingReminderDates(for: currentRacePlan.id)
        let pendingTimings = await RaceReminderScheduler.pendingReminderTimings(for: currentRacePlan.id)

        guard revision == reminderStateRevision, !Task.isCancelled else {
            return
        }

        registeredReminderDates = dates
        selectedReminderTimings = pendingTimings.isEmpty
            ? Set(RaceReminderTiming.allCases)
            : pendingTimings
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
