import SwiftUI

struct RaceFuelingPlanEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RaceFuelingPresetStore.self) private var presetStore
    @State private var events: [RaceFuelingEvent]
    @State private var presetName = ""

    let racePlan: RacePlan
    let onSave: ([RaceFuelingEvent]) -> Void

    init(racePlan: RacePlan, onSave: @escaping ([RaceFuelingEvent]) -> Void) {
        self.racePlan = racePlan
        self.onSave = onSave
        _events = State(initialValue: RaceFuelingPlanCalculator.initialEvents(for: racePlan))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("補給品の量やタイミングはご自身の計画として入力してください。栄養情報は商品表示をご確認ください。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("補給・給水イベント") {
                    ForEach($events) { $event in
                        eventRow($event)
                    }
                    .onMove(perform: move)

                    Button {
                        events.append(RaceFuelingEvent(
                            order: events.count, name: "", quantity: 1,
                            distanceKm: racePlan.distanceKm / 2
                        ))
                    } label: {
                        Label("補給イベントを追加", systemImage: "plus.circle.fill")
                    }
                }

                if !events.isEmpty {
                    Section("必要な補給品") {
                        ForEach(RaceFuelingPlanCalculator.requirements(for: events)) { item in
                            LabeledContent("\(item.kind.title)・\(item.name)", value: "\(item.quantity)個")
                        }
                    }

                    Section("この計画をプリセットに保存") {
                        TextField("プリセット名", text: $presetName)
                        Button("保存") {
                            let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !name.isEmpty else { return }
                            var plan = candidate
                            plan.fuelingEvents = events
                            if presetStore.save(RaceFuelingPreset(name: name, plan: plan)) {
                                presetName = ""
                            }
                        }
                        .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || validationError != nil)
                    }
                }

                if !presetStore.presets.isEmpty {
                    Section("保存済みプリセット") {
                        ForEach(presetStore.presets) { preset in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(preset.name)
                                    Text("\(preset.events.count)イベント")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("適用") {
                                    events = preset.events(for: racePlan)
                                }
                                .buttonStyle(.borderless)
                                Button(role: .destructive) {
                                    _ = presetStore.delete(id: preset.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("\(preset.name)を削除")
                            }
                        }
                    }
                }

                if let error = validationError ?? presetStore.error {
                    Section {
                        Label(error, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("補給・給水プラン")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(events)
                        dismiss()
                    }
                    .disabled(validationError != nil)
                }
            }
        }
    }

    private func eventRow(_ binding: Binding<RaceFuelingEvent>) -> some View {
        let event = binding.wrappedValue
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("商品名", text: binding.name)
                    .font(.headline)
                Button(role: .destructive) {
                    events.removeAll { $0.id == event.id }
                    normalizeOrders()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(event.name)を削除")
            }

            Picker("種別", selection: binding.kind) {
                ForEach(RaceFuelingKind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            TextField("個数", value: binding.quantity, format: .number)
                .keyboardType(.numberPad)

            Picker("タイミング", selection: trigger(for: binding)) {
                Text("距離").tag(FuelingTrigger.distance)
                Text("経過時間").tag(FuelingTrigger.elapsed)
                if !racePlan.checkpoints.isEmpty {
                    Text("地点・給水所").tag(FuelingTrigger.checkpoint)
                }
            }

            switch trigger(for: binding).wrappedValue {
            case .distance:
                TextField("距離 (km)", value: distance(for: binding),
                          format: .number.precision(.fractionLength(0...4)))
                    .keyboardType(.decimalPad)
            case .elapsed:
                TextField("経過分", value: elapsedMinutes(for: binding), format: .number)
                    .keyboardType(.numberPad)
            case .checkpoint:
                Picker("地点", selection: checkpoint(for: binding)) {
                    ForEach(racePlan.checkpoints.sorted(by: { $0.order < $1.order })) { checkpoint in
                        Text("\(checkpoint.name)・\(RacePlanCalculator.formatDistance(checkpoint.distanceKm))")
                            .tag(Optional(checkpoint.id))
                    }
                }
            }

            Picker("受け取り方法", selection: binding.pickup) {
                ForEach(RaceFuelingPickup.allCases, id: \.self) { pickup in
                    Text(pickup.title).tag(pickup)
                }
            }
            Toggle("炭水化物量を記録", isOn: carbohydrateEnabled(for: binding))
            if event.carbohydrateGramsPerItem != nil {
                TextField("1個あたりの炭水化物 (g)", value: carbohydrate(for: binding),
                          format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
            }
            Toggle("カフェイン入り", isOn: binding.containsCaffeine)
            TextField("メモ（任意）", text: binding.note, axis: .vertical)
                .lineLimit(2...4)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }

    private var candidate: RacePlan {
        var plan = racePlan
        plan.fuelingEvents = events
        return plan
    }

    private var validationError: String? {
        RaceFuelingPlanCalculator.validationError(for: candidate)
    }

    private func move(from source: IndexSet, to destination: Int) {
        events.move(fromOffsets: source, toOffset: destination)
        normalizeOrders()
    }

    private func normalizeOrders() {
        for index in events.indices { events[index].order = index }
    }

    private func trigger(for event: Binding<RaceFuelingEvent>) -> Binding<FuelingTrigger> {
        Binding {
            if let id = event.wrappedValue.checkpointID,
               racePlan.checkpoints.contains(where: { $0.id == id }) { return .checkpoint }
            return event.wrappedValue.elapsedSeconds != nil ? .elapsed : .distance
        } set: { trigger in
            event.wrappedValue.checkpointID = nil
            event.wrappedValue.elapsedSeconds = nil
            switch trigger {
            case .distance:
                event.wrappedValue.distanceKm = min(racePlan.distanceKm,
                                                     event.wrappedValue.distanceKm ?? racePlan.distanceKm / 2)
            case .elapsed:
                event.wrappedValue.distanceKm = nil
                event.wrappedValue.elapsedSeconds = racePlan.activeTargetSeconds / 2
            case .checkpoint:
                event.wrappedValue.checkpointID = racePlan.checkpoints.first?.id
                event.wrappedValue.distanceKm = racePlan.checkpoints.first?.distanceKm
            }
        }
    }

    private func distance(for event: Binding<RaceFuelingEvent>) -> Binding<Double> {
        Binding { event.wrappedValue.distanceKm ?? 0 }
        set: { event.wrappedValue.distanceKm = $0 }
    }

    private func elapsedMinutes(for event: Binding<RaceFuelingEvent>) -> Binding<Int> {
        Binding { (event.wrappedValue.elapsedSeconds ?? 0) / 60 }
        set: { event.wrappedValue.elapsedSeconds = max(0, min($0, racePlan.activeTargetSeconds / 60)) * 60 }
    }

    private func checkpoint(for event: Binding<RaceFuelingEvent>) -> Binding<UUID?> {
        Binding { event.wrappedValue.checkpointID }
        set: { id in
            event.wrappedValue.checkpointID = id
            event.wrappedValue.distanceKm = racePlan.checkpoints.first(where: { $0.id == id })?.distanceKm
        }
    }

    private func carbohydrateEnabled(for event: Binding<RaceFuelingEvent>) -> Binding<Bool> {
        Binding { event.wrappedValue.carbohydrateGramsPerItem != nil }
        set: { event.wrappedValue.carbohydrateGramsPerItem = $0 ? 0 : nil }
    }

    private func carbohydrate(for event: Binding<RaceFuelingEvent>) -> Binding<Double> {
        Binding { event.wrappedValue.carbohydrateGramsPerItem ?? 0 }
        set: { event.wrappedValue.carbohydrateGramsPerItem = $0 }
    }

    private enum FuelingTrigger: Hashable {
        case distance, elapsed, checkpoint
    }
}
