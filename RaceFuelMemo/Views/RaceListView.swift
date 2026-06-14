import SwiftUI

struct RaceListView: View {
    @State private var isShowingSettings = false

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
                    Button {
                        isShowingSettings = true
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
            .sheet(isPresented: $isShowingSettings) {
                NavigationStack {
                    SettingsView()
                }
            }
        }
    }
}

#Preview {
    RaceListView()
}
