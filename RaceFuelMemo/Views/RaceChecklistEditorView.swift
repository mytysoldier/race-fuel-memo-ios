import SwiftUI

struct RaceChecklistEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RacePlanStore.self) private var racePlanStore
    @Environment(ChecklistTemplateStore.self) private var templateStore
    @Environment(ProStore.self) private var proStore

    let racePlan: RacePlan
    let onSave: ([ChecklistItem], Bool) -> Bool

    @State private var items: [ChecklistItem]
    @State private var notificationsEnabled: Bool
    @State private var templateName = ""
    @State private var renameTemplateID: UUID?
    @State private var renameName = ""
    @State private var deleteTemplateID: UUID?
    @State private var isRenaming = false
    @State private var isDeleting = false
    @State private var isSaving = false
    @State private var isShowingError = false
    @State private var didSaveWithoutNotifications = false
    @State private var errorText = ""

    init(racePlan: RacePlan, onSave: @escaping ([ChecklistItem], Bool) -> Bool) {
        self.racePlan = racePlan
        self.onSave = onSave
        _items = State(initialValue: racePlan.checklistItems.sorted { $0.order < $1.order })
        _notificationsEnabled = State(initialValue: racePlan.checklistNotificationsEnabled)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("項目ごとにカテゴリ・必須設定・期限を指定できます。並び替えは「編集」から行えます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("準備項目") {
                    ForEach($items) { $item in
                        itemEditor($item)
                    }
                    .onDelete { items.remove(atOffsets: $0) }
                    .onMove { items.move(fromOffsets: $0, toOffset: $1) }

                    Button {
                        items.append(ChecklistItem(title: "", order: items.count,
                                                   category: ChecklistCategory.gear.rawValue))
                    } label: {
                        Label("項目を追加", systemImage: "plus.circle.fill")
                    }
                }

                Section("期限通知") {
                    Toggle("未完了の必須項目を通知", isOn: $notificationsEnabled)
                    Text("期限がある未完了の必須項目を、近い順に最大50件通知します。通知を拒否してもチェックリストは保存できます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("テンプレートとして保存") {
                    TextField("テンプレート名", text: $templateName)
                    Button("現在の項目を保存") {
                        guard proStore.canUse(.customChecklist) else { return }
                        if templateStore.save(name: templateName, items: normalizedItems) {
                            templateName = ""
                        }
                    }
                    .disabled(templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || normalizedItems.isEmpty || hasInvalidTitle)
                    Text("チェック状態とレース固有の固定日時はテンプレートに含めません。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("テンプレートを適用") {
                    ForEach(templateStore.templates) { template in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(template.name)
                                Text("\(template.items.count)項目")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("適用") {
                                guard proStore.canUse(.customChecklist) else { return }
                                items = template.checklistItems()
                            }
                            .buttonStyle(.borderless)
                            if !template.isStandard {
                                Menu {
                                    Button("名前を変更") {
                                        renameTemplateID = template.id
                                        renameName = template.name
                                        isRenaming = true
                                    }
                                    Button("削除", role: .destructive) {
                                        deleteTemplateID = template.id
                                        isDeleting = true
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                                .accessibilityLabel("\(template.name)の操作")
                            }
                        }
                    }
                    Text("適用すると編集中の項目を置き換えます。保存前ならキャンセルで元に戻せます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let error = templateStore.error {
                    Section {
                        Label(error, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("レースのチェックリスト")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .accessibilityIdentifier("checklist.save")
                        .disabled(hasInvalidTitle || isSaving)
                }
            }
            .alert("テンプレート名を変更", isPresented: $isRenaming) {
                TextField("名前", text: $renameName)
                Button("保存") {
                    guard proStore.canUse(.customChecklist) else { return }
                    if let id = renameTemplateID { _ = templateStore.rename(id: id, to: renameName) }
                }
                Button("キャンセル", role: .cancel) {}
            }
            .confirmationDialog("テンプレートを削除しますか？", isPresented: $isDeleting) {
                Button("削除", role: .destructive) {
                    if let id = deleteTemplateID { _ = templateStore.delete(id: id) }
                }
            }
            .alert(didSaveWithoutNotifications ? "チェックリストを保存しました" : "保存できません", isPresented: $isShowingError) {
                Button("OK", role: .cancel) {
                    if didSaveWithoutNotifications { dismiss() }
                }
            } message: {
                Text(errorText)
            }
        }
        .proProtected(.customChecklist)
    }

    private func itemEditor(_ item: Binding<ChecklistItem>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("項目名", text: item.title)
                .font(.headline)
            // Form pickers inside this row can capture taps on adjacent switches.
            // Explicit borderless menus keep each control's hit area independent.
            Menu {
                ForEach(ChecklistCategory.allCases, id: \.self) { category in
                    Button(category.title) { categoryBinding(for: item).wrappedValue = category }
                }
            } label: {
                LabeledContent("カテゴリ", value: categoryBinding(for: item).wrappedValue.title)
            }
            .buttonStyle(.borderless)
            Toggle("必須", isOn: item.isRequired)
            HStack {
                Text("準備完了").accessibilityHidden(true)
                Spacer()
                Toggle("準備完了", isOn: item.isChecked)
                    .labelsHidden()
                    .accessibilityLabel("準備完了")
            }
            Menu {
                Button("なし") { dueTimingBinding(for: item).wrappedValue = nil }
                ForEach(ChecklistDueTiming.allCases, id: \.self) { timing in
                    Button(timing.title) { dueTimingBinding(for: item).wrappedValue = timing }
                }
            } label: {
                LabeledContent("期限", value: dueTimingBinding(for: item).wrappedValue?.title ?? "なし")
            }
            .buttonStyle(.borderless)
            if item.wrappedValue.dueTiming == nil, let dueDate = item.wrappedValue.dueDate {
                Text("従来の期限: \(dueDate.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("従来の期限を解除") { item.wrappedValue.dueDate = nil }
                    .font(.footnote)
            }
        }
        .padding(.vertical, 6)
    }

    private func categoryBinding(for item: Binding<ChecklistItem>) -> Binding<ChecklistCategory> {
        Binding {
            ChecklistCategory(rawValue: item.wrappedValue.category ?? "") ?? .other
        } set: { item.wrappedValue.category = $0.rawValue }
    }

    private func dueTimingBinding(for item: Binding<ChecklistItem>) -> Binding<ChecklistDueTiming?> {
        Binding {
            item.wrappedValue.dueTiming
        } set: { timing in
            item.wrappedValue.dueTiming = timing
            item.wrappedValue.dueDate = nil
        }
    }

    private var hasInvalidTitle: Bool {
        items.contains { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var normalizedItems: [ChecklistItem] {
        items.enumerated().map { index, item in
            var copy = item
            copy.order = index
            copy.title = copy.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return copy
        }
    }

    private func save() {
        isSaving = true
        Task { @MainActor in
            var enable = notificationsEnabled
            var denied = false
            if enable {
                do {
                    try await ChecklistReminderScheduler.requestAuthorization()
                } catch {
                    enable = false
                    denied = true
                }
            }
            guard proStore.canUse(.customChecklist) else { isSaving = false; return }
            let saved = onSave(normalizedItems, enable)
            isSaving = false
            if saved && !denied {
                dismiss()
            } else {
                didSaveWithoutNotifications = saved && denied
                errorText = saved
                    ? "通知は許可されなかったためオフにしました。チェックリストは保存済みです。"
                    : (racePlanStore.storageError ?? racePlanStore.validationError ?? "保存処理に失敗しました。")
                isShowingError = true
            }
        }
    }
}

/// Saved data remains manageable without Pro. Applying/editing templates still
/// belongs to the protected race checklist editor.
struct ChecklistTemplatesView: View {
    @Environment(ChecklistTemplateStore.self) private var templateStore
    @Environment(ProStore.self) private var proStore
    @State private var deletion: ChecklistTemplate?
    @State private var rename: ChecklistTemplate?
    @State private var name = ""
    @State private var showsDelete = false
    @State private var showsRename = false
    @State private var showsPaywall = false
    @State private var operationError: String?

    var body: some View {
        List {
            ForEach(templateStore.templates) { template in
                Section(template.name) {
                    DisclosureGroup("\(template.items.count)項目を確認") {
                        ForEach(Array(template.items.enumerated()), id: \.offset) { _, item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                if let category = item.category, !category.isEmpty { Text(category) }
                                if item.isRequired { Label("必須", systemImage: "exclamationmark.circle") }
                                if let timing = item.dueTiming { Text(timing.title) }
                            }.accessibilityElement(children: .combine)
                        }
                    }
                    if !template.isStandard {
                        ProFeatureButton(feature: .customChecklist, title: "名前を変更") {
                            rename = template
                            name = template.name
                            showsRename = true
                        }
                        Button("削除", role: .destructive) {
                            deletion = template
                            showsDelete = true
                        }
                    }
                }
            }
            if let error = templateStore.error ?? operationError {
                Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red)
            }
        }
        .navigationTitle("チェックリストテンプレート")
        .navigationBarTitleDisplayMode(.inline)
        .alert("テンプレートの名前を変更", isPresented: $showsRename) {
            TextField("名前", text: $name)
            Button("保存") {
                guard proStore.canUse(.customChecklist) else { showsPaywall = true; return }
                if let template = rename, !templateStore.rename(id: template.id, to: name) {
                    operationError = "名前を変更できませんでした。"
                }
            }
            Button("キャンセル", role: .cancel) {}
        }
        .alert("テンプレートを削除しますか？", isPresented: $showsDelete) {
            Button("削除", role: .destructive) {
                if let template = deletion, !templateStore.delete(id: template.id) {
                    operationError = "テンプレートを削除できませんでした。"
                }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("保存済みレースのチェックリストには影響しません。")
        }
        .sheet(isPresented: $showsPaywall) { ProPaywallView(feature: .customChecklist) }
    }
}
