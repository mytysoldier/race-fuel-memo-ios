import SwiftUI

struct RacePreparationView: View {
    let plan: RacePlan
    let onSelect: (RacePreparationStep) -> Void
    var body: some View {
        let preparation = RacePreparation(plan: plan)
        VStack(alignment: .leading, spacing: 12) {
            Text("準備状況・Pro対象").font(.headline).accessibilityAddTraits(.isHeader)
            ForEach(preparation.statuses) { status in
                Button {
                    onSelect(status.step)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(
                            "\(status.step.title)・\(status.label)",
                            systemImage: symbol(status.state)
                        )
                        .font(.subheadline.weight(.semibold))
                        Text(status.detail).font(.footnote).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("preparation.\(status.id)")
                .accessibilityElement(children: .combine)
                .accessibilityHint("タップして設定を確認・修正")
            }
            Button("次に設定: \(preparation.nextStep.title)") {
                onSelect(preparation.nextStep)
            }
            .accessibilityIdentifier("preparation.next")
            Text("Pro対象: 詳細ペース・通過地点・補給プラン・チェックリスト拡張・計画の再利用・Race Card出力。現在は購入なしで利用できます。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func symbol(_ state: RacePreparationStatus.State) -> String {
        switch state {
        case .ready: "checkmark.circle"
        case .unset: "circle.dashed"
        case .attention: "exclamationmark.triangle"
        }
    }
}

/// Only the primary new-plan entry restores the persistent draft. Duplication
/// keeps its existing isolated state and cannot overwrite an unrelated draft.
struct RaceCreationEntryView: View {
    @Environment(RaceCreationDraftStore.self) private var draftStore
    @Environment(RacePlanStore.self) private var planStore
    var body: some View {
        let alreadySaved =
            draftStore.draft.map { draft in planStore.racePlans.contains { $0.id == draft.id } }
            ?? false
        RaceCreatePlaceholderView(savedDraft: alreadySaved ? nil : draftStore.draft)
            .onAppear {
                if alreadySaved, let id = draftStore.draft?.id { draftStore.clear(savedID: id) }
            }
    }
}
