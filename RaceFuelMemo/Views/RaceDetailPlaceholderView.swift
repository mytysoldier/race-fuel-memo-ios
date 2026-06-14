import SwiftUI

struct RaceDetailPlaceholderView: View {
    var body: some View {
        List {
            Section("レース詳細") {
                Text("レース詳細画面は後続Issueで実装します。")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("レース詳細")
    }
}

#Preview {
    NavigationStack {
        RaceDetailPlaceholderView()
    }
}
