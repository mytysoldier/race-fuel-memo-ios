import SwiftUI

struct ProPaywallView: View {
    @Environment(ProStore.self) private var proStore
    @Environment(\.dismiss) private var dismiss
    let feature: ProFeature

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Running Race Mate Pro", systemImage: "sparkles")
                            .font(.title2.bold()).accessibilityAddTraits(.isHeader)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(feature.title)はProの機能です。")
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(feature.summary).fixedSize(horizontal: false, vertical: true)
                        Text("買い切り・一度の購入でPro機能を解放。サブスクリプションではありません。")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    price
                    VStack(alignment: .leading, spacing: 12) {
                        Text("計画のイメージ（サンプル）")
                            .font(.headline).accessibilityAddTraits(.isHeader)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("10km地点・エイド\n通過 1:00 ／ 関門まで 15分\n補給ジェル・給水をこの地点で予定")
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Proなら地点・ペース・補給を結びつけて確認し、Race Cardとして持ち出せます。サンプルは補給量やペースの推奨ではありません。")
                            .font(.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Proでできること").font(.headline).accessibilityAddTraits(.isHeader)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(ProFeature.allCases) { feature in
                            VStack(alignment: .leading, spacing: 4) {
                                Label(feature.title, systemImage: "checkmark.circle")
                                    .font(.subheadline.weight(.semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(feature.summary).font(.footnote).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }.accessibilityElement(children: .combine)
                        }
                    }
                    Text(
                        "無料のままでもレースの作成・保存・履歴、基本のペース・固定区間の通過計算、標準チェックリストを利用できます。保存件数に新たな制限はなく、保存済みのレースや詳細データも閲覧できます。閉じても入力中の内容は失われません。"
                    )
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }.padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Proのご案内")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button {
                    dismiss()
                } label: {
                    Text("閉じて戻る").font(.body)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("paywall.close")
                .padding(.horizontal).padding(.vertical, 8)
                .background(.regularMaterial)
            }
            .task {
                if case .notLoaded = proStore.productState { await proStore.loadProduct() }
            }
        }
        .accessibilityIdentifier("paywall")
        #if DEBUG
            // UIKit sheet hosting starts from system traits rather than the preview
            // environment override used by our large-text UI fixture.
            .transformEnvironment(\.dynamicTypeSize) { size in
                if ProcessInfo.processInfo.arguments.contains("--large-ui-testing") {
                    size = .accessibility5
                }
            }
        #endif
    }

    @ViewBuilder
    private var price: some View {
        VStack(alignment: .leading, spacing: 8) {
            if proStore.entitlementState == .checking {
                ProgressView("購入状況を確認中")
            } else if proStore.isPro {
                Label("Proは解放済みです。閉じて機能を利用してください。", systemImage: "checkmark.seal")
                    .fixedSize(horizontal: false, vertical: true)
            }
            switch proStore.pricePresentation {
            case .loading:
                ProgressView("価格を読み込み中")
            case .available(let price):
                Text("\(price)・買い切り").font(.title3.bold())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("paywall.price")
            case .unavailable:
                Text("価格を取得できませんでした。通信環境を確認して再試行してください。")
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("paywall.priceUnavailable")
                Button("価格を再読み込み") { Task { await proStore.loadProduct() } }
                    .accessibilityIdentifier("paywall.retry")
            }
            // Purchase and restore actions are intentionally supplied by Issue #46.
            Text("このバージョンでは購入手続きをまだ利用できません。")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One entry-point control shared by every advanced action. Never runs its
/// action until a verified entitlement is present (including during checking).
struct ProFeatureButton: View {
    @Environment(ProStore.self) private var proStore
    @State private var showsPaywall = false
    let feature: ProFeature
    let title: String
    var systemImage = "sparkles"
    let action: () -> Void

    var body: some View {
        Button {
            if proStore.canUse(feature) { action() } else { showsPaywall = true }
        } label: {
            Label("\(title) · Pro", systemImage: systemImage)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("pro.\(feature.rawValue)")
        .sheet(isPresented: $showsPaywall) { ProPaywallView(feature: feature) }
    }
}

/// Also guard destinations, so direct navigation and entitlement changes while
/// an editor/output screen is open cannot leave advanced controls enabled.
private struct ProProtection: ViewModifier {
    @Environment(ProStore.self) private var proStore
    let feature: ProFeature
    func body(content: Content) -> some View {
        if proStore.canUse(feature) { content } else { ProPaywallView(feature: feature) }
    }
}

extension View {
    func proProtected(_ feature: ProFeature) -> some View {
        modifier(ProProtection(feature: feature))
    }
}

struct ProInformationButton: View {
    @Environment(ProStore.self) private var proStore
    @State private var showsPaywall = false
    var body: some View {
        Button {
            showsPaywall = true
        } label: {
            HStack {
                Image(systemName: "sparkles")
                Text(proStore.isPro ? "Pro 解放済み" : "Pro機能を見る")
            }
        }
        .accessibilityIdentifier("pro.information")
        .sheet(isPresented: $showsPaywall) { ProPaywallView(feature: .raceCard) }
    }
}
