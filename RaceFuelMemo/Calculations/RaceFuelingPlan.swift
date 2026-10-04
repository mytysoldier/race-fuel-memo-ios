import Foundation
import Observation

struct ScheduledFuelingEvent: Identifiable {
    let event: RaceFuelingEvent
    let distanceKm: Double
    let elapsedSeconds: Int
    let passingTime: Date
    let checkpointName: String?

    var id: UUID { event.id }
}

struct FuelingRequirement: Identifiable {
    let name: String
    let kind: RaceFuelingKind
    let quantity: Int

    var id: String { "\(kind.rawValue):\(name)" }
}

enum RaceFuelingPlanCalculator {
    static func initialEvents(for plan: RacePlan) -> [RaceFuelingEvent] {
        guard plan.fuelingEvents.isEmpty else { return plan.fuelingEvents.sorted { $0.order < $1.order } }
        let names = plan.gelNames ?? []
        return RacePlanCalculator.fuelTimings(gelCount: max(plan.gelCount, names.count),
                                               distanceKm: plan.distanceKm)
            .enumerated().map { index, timing in
                RaceFuelingEvent(
                    order: index,
                    name: index < names.count && !names[index].isEmpty ? names[index] : "補給ジェル \(index + 1)",
                    quantity: 1, distanceKm: timing.distanceKm
                )
            }
    }

    static func validationError(for plan: RacePlan) -> String? {
        let events = plan.fuelingEvents
        guard Set(events.map(\.id)).count == events.count,
              Set(events.map(\.order)).count == events.count else {
            return "補給イベントの並び順に重複があります。"
        }
        for event in events {
            guard !event.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return "補給品名を入力してください。"
            }
            guard (1...999).contains(event.quantity) else {
                return "補給品の個数は1〜999個で入力してください。"
            }
            if let grams = event.carbohydrateGramsPerItem,
               !grams.isFinite || !(0...1_000).contains(grams) {
                return "炭水化物量は1個あたり0〜1000gで入力してください。"
            }
            if let checkpointID = event.checkpointID,
               plan.checkpoints.contains(where: { $0.id == checkpointID }) {
                continue
            }
            if let seconds = event.elapsedSeconds {
                guard (0...plan.activeTargetSeconds).contains(seconds) else {
                    return "補給の経過時間は目標タイム以内にしてください。"
                }
            } else if let distance = event.distanceKm {
                guard distance.isFinite, (0...plan.distanceKm).contains(distance) else {
                    return "補給地点の距離はコース内にしてください。"
                }
            } else {
                return "補給の距離・経過時間・地点のいずれかを指定してください。"
            }
        }
        return nil
    }

    static func schedule(for plan: RacePlan) -> [ScheduledFuelingEvent] {
        guard validationError(for: plan) == nil,
              RaceCheckpointValidator.error(for: plan) == nil else { return [] }
        let checkpoints = RacePlanCalculator.checkpointSchedules(for: plan)
        let anchors = [(0.0, 0)]
            + checkpoints.map { ($0.checkpoint.distanceKm, $0.elapsedSeconds) }
            + [(plan.distanceKm, plan.activeTargetSeconds)]
        let elapsedAt: (Double) -> Int = { distance in
            if plan.selectedPacePlan != nil {
                return RacePlanCalculator.elapsedSeconds(at: distance, for: plan)
            }
            return elapsedTime(at: distance, anchors: anchors)
        }

        return plan.fuelingEvents.map { event in
            let checkpoint = checkpoints.first { $0.id == event.checkpointID }
            let distance: Double
            let seconds: Int
            if let checkpoint {
                distance = checkpoint.checkpoint.distanceKm
                seconds = checkpoint.elapsedSeconds
            } else if let elapsed = event.elapsedSeconds {
                seconds = elapsed
                if plan.selectedPacePlan == nil,
                   let upperIndex = anchors.firstIndex(where: { $0.1 >= elapsed }),
                   upperIndex > 0 {
                    let lower = anchors[upperIndex - 1]
                    let upper = anchors[upperIndex]
                    distance = lower.0 + (upper.0 - lower.0)
                        * Double(elapsed - lower.1) / Double(upper.1 - lower.1)
                } else {
                    var low = 0.0
                    var high = plan.distanceKm
                    for _ in 0..<35 {
                        let midpoint = (low + high) / 2
                        if elapsedAt(midpoint) < elapsed {
                            low = midpoint
                        } else {
                            high = midpoint
                        }
                    }
                    distance = (low + high) / 2
                }
            } else {
                distance = event.distanceKm ?? 0
                seconds = elapsedAt(distance)
            }
            return ScheduledFuelingEvent(
                event: event, distanceKm: distance, elapsedSeconds: seconds,
                passingTime: plan.startTime.addingTimeInterval(TimeInterval(seconds)),
                checkpointName: checkpoint?.checkpoint.name
            )
        }.sorted {
            $0.elapsedSeconds == $1.elapsedSeconds
                ? $0.event.order < $1.event.order
                : $0.elapsedSeconds < $1.elapsedSeconds
        }
    }

    static func requirements(for events: [RaceFuelingEvent]) -> [FuelingRequirement] {
        var totals: [String: Int] = [:]
        var names: [String: String] = [:]
        for event in events {
            let name = event.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, event.quantity > 0 else { continue }
            let key = "\(event.kind.rawValue):\(name.folding(options: [.caseInsensitive, .widthInsensitive], locale: .current))"
            totals[key, default: 0] += event.quantity
            names[key] = names[key] ?? name
        }
        return totals.keys.sorted().compactMap { key in
            guard let name = names[key], let quantity = totals[key],
                  let kind = RaceFuelingKind(rawValue: String(key.prefix(while: { $0 != ":" }))) else {
                return nil
            }
            return FuelingRequirement(name: name, kind: kind, quantity: quantity)
        }
    }

    private static func elapsedTime(at distance: Double, anchors: [(Double, Int)]) -> Int {
        guard let upperIndex = anchors.firstIndex(where: { $0.0 >= distance }) else {
            return anchors.last?.1 ?? 0
        }
        guard upperIndex > 0 else { return 0 }
        let lower = anchors[upperIndex - 1]
        let upper = anchors[upperIndex]
        guard upper.0 > lower.0 else { return upper.1 }
        return lower.1 + Int((Double(upper.1 - lower.1) * (distance - lower.0) / (upper.0 - lower.0)).rounded())
    }
}

struct RaceFuelingPreset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    let sourceDistanceKm: Double
    let sourceTargetSeconds: Int
    let events: [RaceFuelingEvent]

    init(id: UUID = UUID(), name: String, plan: RacePlan) {
        self.id = id
        self.name = name
        sourceDistanceKm = plan.distanceKm
        sourceTargetSeconds = plan.activeTargetSeconds
        events = plan.fuelingEvents.map { event in
            var copy = event
            if let checkpoint = plan.checkpoints.first(where: { $0.id == event.checkpointID }) {
                copy.distanceKm = checkpoint.distanceKm
                copy.elapsedSeconds = nil
            }
            copy.checkpointID = nil
            return copy
        }
    }

    func events(for plan: RacePlan) -> [RaceFuelingEvent] {
        guard sourceDistanceKm.isFinite, sourceDistanceKm > 0,
              sourceTargetSeconds > 0 else { return [] }
        return events.enumerated().map { index, original in
            RaceFuelingEvent(
                order: index, name: original.name, quantity: original.quantity,
                distanceKm: original.distanceKm.map {
                    min(plan.distanceKm, max(0, $0 / sourceDistanceKm * plan.distanceKm))
                },
                elapsedSeconds: original.elapsedSeconds.map {
                    Int((Double($0) / Double(sourceTargetSeconds) * Double(plan.activeTargetSeconds)).rounded())
                },
                kind: original.kind,
                carbohydrateGramsPerItem: original.carbohydrateGramsPerItem,
                containsCaffeine: original.containsCaffeine,
                note: original.note, pickup: original.pickup
            )
        }
    }
}

@Observable final class RaceFuelingPresetStore {
    private(set) var presets: [RaceFuelingPreset] = []
    private(set) var error: String?
    private let defaults: UserDefaults
    private let key = "raceFuelingPresetsV1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: key) else { return }
        do {
            presets = try JSONDecoder().decode([RaceFuelingPreset].self, from: data)
        } catch {
            self.error = "保存済み補給プリセットを読み込めません。データ保護のため変更を停止しました。"
        }
    }

    func save(_ preset: RaceFuelingPreset) -> Bool {
        persist(presets + [preset])
    }

    func delete(id: UUID) -> Bool {
        persist(presets.filter { $0.id != id })
    }

    private func persist(_ updated: [RaceFuelingPreset]) -> Bool {
        guard error == nil else { return false }
        do {
            defaults.set(try JSONEncoder().encode(updated), forKey: key)
            presets = updated
            return true
        } catch {
            self.error = "補給プリセットを保存できませんでした。"
            return false
        }
    }
}
