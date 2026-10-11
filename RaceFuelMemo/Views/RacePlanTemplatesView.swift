import SwiftUI

struct RacePlanReuseView: View {
    @Environment(RacePlanStore.self) private var racePlanStore
    @Environment(RacePlanTemplateStore.self) private var templateStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTemplate: RacePlanTemplate?
    @State private var components = Set(RacePlanReuseComponent.allCases)
    @State private var error: String?

    let destination: RacePlan
    let onApply: (RacePlan) -> Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("保存済みテンプレート") {
                    if templateStore.availableTemplates.isEmpty {
                        Text("レース詳細から計画をテンプレートとして保存できます。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(templateStore.availableTemplates) { template in
                        sourceButton(template)
                    }
                    if let storageError = templateStore.error {
                        Text(storageError).foregroundStyle(.red)
                    }
                    NavigationLink("テンプレートを管理") {
                        RacePlanTemplatesView()
                    }
                }
                Section("保存済みレースから再利用") {
                    ForEach(racePlanStore.racePlans.filter { $0.id != destination.id }) { plan in
                        sourceButton(RacePlanTemplate(id: plan.id, name: plan.name, source: plan))
                    }
                }
                if let selectedTemplate {
                    Section {
                        Text("選択中：\(selectedTemplate.name)")
                        Text("\(RacePlanCalculator.formatDistance(selectedTemplate.distanceKm))・基本目標 \(RacePlanCalculator.formatDuration(selectedTemplate.targetHours * 3_600 + selectedTemplate.targetMinutes * 60))")
                            .foregroundStyle(.secondary)
                        ForEach(RacePlanReuseComponent.allCases) { component in
                            Toggle(component.title, isOn: Binding(
                                get: { components.contains(component) },
                                set: { enabled in
                                    if enabled { components.insert(component) }
                                    else { components.remove(component) }
                                    error = nil
                                }
                            ))
                        }
                    } header: {
                        Text("適用する要素")
                    } footer: {
                        Text("選択した要素を置き換えます。大会名・日時・メモ・チェックポイントは引き継ぎません。チェック済み状態、固定日時の期限、通知オン状態も引き継ぎません。")
                    }
                }
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red) }
                }
            }
            .navigationTitle("計画の設定を再利用")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("適用", action: apply)
                        .disabled(selectedTemplate == nil || components.isEmpty)
                }
            }
        }
    }

    private func sourceButton(_ template: RacePlanTemplate) -> some View {
        Button {
            selectedTemplate = template
            error = nil
        } label: {
            HStack {
                Text(template.name).foregroundStyle(.primary)
                Spacer()
                if selectedTemplate?.id == template.id {
                    Image(systemName: "checkmark").accessibilityLabel("選択中")
                }
            }
        }
        .accessibilityAddTraits(selectedTemplate?.id == template.id ? .isSelected : [])
    }

    private func apply() {
        guard let selectedTemplate else { return }
        do {
            let updated = try selectedTemplate.applying(to: destination, components: components)
            if onApply(updated) { dismiss() }
            else { error = racePlanStore.storageError ?? racePlanStore.validationError ?? "計画を更新できませんでした。" }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct RacePlanTemplatesView: View {
    @Environment(RacePlanTemplateStore.self) private var templateStore
    @State private var templateToRename: RacePlanTemplate?
    @State private var templateToDelete: RacePlanTemplate?
    @State private var name = ""
    @State private var showsRename = false
    @State private var showsDelete = false
    @State private var operationError: String?

    var body: some View {
        List {
            Section {
                Text("大会名・日時・コース地点を含まない、ペース・補給・持ち物の設定です。新規作成画面やレース詳細から適用できます。")
                    .foregroundStyle(.secondary)
            }
            ForEach(templateStore.templates) { template in
                Section {
                    Text(template.name).font(.headline)
                    Text("\(RacePlanCalculator.formatDistance(template.distanceKm))・ペース \(template.pacePlans.count)件・補給 \(template.fuelingEvents.count)件・持ち物 \(template.checklistItems.count)件")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("名称変更") {
                        templateToRename = template
                        name = template.name
                        showsRename = true
                    }
                    Button("削除", role: .destructive) {
                        templateToDelete = template
                        showsDelete = true
                    }
                }
            }
            if templateStore.templates.isEmpty {
                Text("保存済みテンプレートはありません。レース詳細の「テンプレートとして保存」から追加できます。")
                    .foregroundStyle(.secondary)
            }
            if let error = templateStore.error ?? operationError {
                Text(error).foregroundStyle(.red)
            }
        }
        .navigationTitle("計画テンプレート")
        .navigationBarTitleDisplayMode(.inline)
        .alert("テンプレートの名称変更", isPresented: $showsRename) {
            TextField("名前", text: $name)
            Button("保存") {
                operationError = nil
                if let template = templateToRename, !templateStore.rename(id: template.id, to: name) {
                    operationError = "名称を変更できません。空でない名前を入力してください。"
                }
            }
            Button("キャンセル", role: .cancel) {}
        }
        .alert("テンプレートを削除しますか？", isPresented: $showsDelete) {
            Button("削除", role: .destructive) {
                operationError = nil
                if let template = templateToDelete, !templateStore.delete(id: template.id) {
                    operationError = "テンプレートを削除できませんでした。"
                }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("保存済みレースには影響しません。")
        }
    }
}
