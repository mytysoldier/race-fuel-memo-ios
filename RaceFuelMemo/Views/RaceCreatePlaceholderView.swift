import SwiftUI

struct RaceCreatePlaceholderView: View {
    var body: some View {
        Form {
            Section("基本情報") {
                Text("レース作成フォームは後続Issueで実装します。")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("レース作成")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        RaceCreatePlaceholderView()
    }
}
