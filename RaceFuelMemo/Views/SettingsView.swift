import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("アプリ") {
                LabeledContent("名称", value: "レース補給メモ")
                LabeledContent("バージョン", value: "1.0")
            }

            Section("方針") {
                Text("外部通信、ログイン、広告、課金、解析SDKは使用しません。")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完了") {
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
