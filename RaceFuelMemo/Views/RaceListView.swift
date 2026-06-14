import SwiftUI

struct RaceListView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ContentUnavailableView(
                        "レースプランがありません",
                        systemImage: "flag.checkered",
                        description: Text("右上の追加ボタンからレースプランを作成できます。")
                    )
                }
            }
            .navigationTitle("レース一覧")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("設定")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        RaceCreatePlaceholderView()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("レースを追加")
                }
            }
        }
    }
}

#Preview {
    RaceListView()
}
