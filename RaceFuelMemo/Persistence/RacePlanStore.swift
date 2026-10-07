import Foundation
import Observation

@Observable
final class RacePlanStore {
    private(set) var racePlans: [RacePlan]
    private(set) var storageError: String?
    private(set) var validationError: String?

    private let storage: RacePlanStorage

    init(storage: RacePlanStorage = UserDefaultsRacePlanStorage()) {
        self.storage = storage
        do {
            racePlans = try storage.loadRacePlans()
            let loadedPlans = racePlans
            Task { @MainActor in
                ChecklistReminderScheduler.enqueueReconciliation(for: loadedPlans)
            }
        } catch {
            racePlans = []
            storageError = error.localizedDescription
        }
    }

    func addRacePlan(
        name: String,
        raceDate: Date,
        startTime: Date,
        distance: DistanceOption,
        targetHours: Int,
        targetMinutes: Int,
        gelCount: Int,
        gelNames: [String] = [],
        memo: String = ""
    ) -> Bool {
        let racePlan = RacePlan(
            name: name,
            raceDate: raceDate,
            startTime: startTime,
            distanceKm: distance.distanceKm,
            targetHours: targetHours,
            targetMinutes: targetMinutes,
            gelCount: gelCount,
            gelNames: gelNames,
            memo: memo
        )
        return addRacePlan(racePlan)
    }

    func addRacePlan(_ racePlan: RacePlan) -> Bool {
        var normalizedRacePlan = racePlan
        normalizedRacePlan.normalizeFinishCheckpoints()
        normalizedRacePlan.normalizePacePlans()
        normalizedRacePlan.normalizeFuelingEvents()
        if let error = RaceCheckpointValidator.error(for: normalizedRacePlan) {
            validationError = error
            return false
        }
        validationError = nil
        return commit(racePlans + [normalizedRacePlan])
    }

    func updateRacePlan(_ racePlan: RacePlan) -> Bool {
        var normalizedRacePlan = racePlan
        normalizedRacePlan.normalizeFinishCheckpoints()
        normalizedRacePlan.normalizePacePlans()
        normalizedRacePlan.normalizeFuelingEvents()
        if let error = RaceCheckpointValidator.error(for: normalizedRacePlan) {
            validationError = error
            return false
        }
        validationError = nil
        guard let index = racePlans.firstIndex(where: { $0.id == normalizedRacePlan.id }) else {
            return false
        }

        var updated = racePlans
        updated[index] = normalizedRacePlan
        return commit(updated)
    }

    func deleteRacePlan(id: RacePlan.ID) {
        let updated = racePlans.filter { $0.id != id }
        if updated.count != racePlans.count && commit(updated) {
            RaceReminderScheduler.cancelReminders(for: id)
        }
    }

    func deleteRacePlans(at offsets: IndexSet) {
        let racePlanIDs = offsets.map { racePlans[$0].id }
        let updated = racePlans.enumerated().compactMap { index, plan in
            offsets.contains(index) ? nil : plan
        }
        if commit(updated) {
            for racePlanID in racePlanIDs {
                RaceReminderScheduler.cancelReminders(for: racePlanID)
            }
        }
    }

    func setChecklistItemChecked(
        racePlanID: RacePlan.ID,
        checklistItemID: ChecklistItem.ID,
        isChecked: Bool
    ) {
        guard
            let racePlanIndex = racePlans.firstIndex(where: { $0.id == racePlanID }),
            let checklistItemIndex = racePlans[racePlanIndex].checklistItems.firstIndex(where: { $0.id == checklistItemID })
        else {
            return
        }

        var updated = racePlans
        updated[racePlanIndex].checklistItems[checklistItemIndex].isChecked = isChecked
        _ = commit(updated)
    }

    @discardableResult
    private func commit(_ updated: [RacePlan]) -> Bool {
        guard storageError == nil else { return false }
        do {
            try storage.saveRacePlans(updated)
            racePlans = updated
            Task { @MainActor in
                ChecklistReminderScheduler.enqueueReconciliation(for: updated)
            }
            return true
        } catch {
            storageError = error.localizedDescription
            return false
        }
    }

}
