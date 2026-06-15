import Foundation
import Combine

final class RacePlanStore: ObservableObject {
    @Published private(set) var racePlans: [RacePlan]

    private let storage: RacePlanStorage

    init(storage: RacePlanStorage = UserDefaultsRacePlanStorage()) {
        self.storage = storage
        racePlans = storage.loadRacePlans()
    }

    func addRacePlan(
        name: String,
        raceDate: Date,
        startTime: Date,
        distance: DistanceOption,
        targetHours: Int,
        targetMinutes: Int,
        gelCount: Int,
        memo: String = ""
    ) {
        let racePlan = RacePlan(
            name: name,
            raceDate: raceDate,
            startTime: startTime,
            distanceKm: distance.distanceKm,
            targetHours: targetHours,
            targetMinutes: targetMinutes,
            gelCount: gelCount,
            memo: memo
        )
        racePlans.append(racePlan)
        persist()
    }

    func addRacePlan(_ racePlan: RacePlan) {
        racePlans.append(racePlan)
        persist()
    }

    func updateRacePlan(_ racePlan: RacePlan) {
        guard let index = racePlans.firstIndex(where: { $0.id == racePlan.id }) else {
            return
        }

        racePlans[index] = racePlan
        persist()
    }

    func deleteRacePlan(id: RacePlan.ID) {
        racePlans.removeAll { $0.id == id }
        persist()
    }

    func deleteRacePlans(at offsets: IndexSet) {
        for offset in offsets.sorted(by: >) {
            racePlans.remove(at: offset)
        }
        persist()
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

        racePlans[racePlanIndex].checklistItems[checklistItemIndex].isChecked = isChecked
        persist()
    }

    private func persist() {
        storage.saveRacePlans(racePlans)
    }
}
