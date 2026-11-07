import Foundation

/// Only advanced operations are gated. Reading saved races, basic editing,
/// legacy calculations and checking existing checklist items remain free.
enum ProFeature: String, CaseIterable, Identifiable, Codable {
    case checkpoints, paceStrategies, fuelingPlan, customChecklist
    case planReuse, raceCard, preparationDashboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .checkpoints: String(localized: "通過地点・関門")
        case .paceStrategies: String(localized: "詳細ペース・A／B／C比較")
        case .fuelingPlan: String(localized: "補給・給水プラン")
        case .customChecklist: String(localized: "チェックリスト拡張")
        case .planReuse: String(localized: "計画の複製・再利用")
        case .raceCard: String(localized: "Race Card出力")
        case .preparationDashboard: String(localized: "準備状況ダッシュボード")
        }
    }

    var summary: String {
        switch self {
        case .checkpoints: String(localized: "任意の地点・エイド・給水所と、通過時刻・関門の余裕を計画。")
        case .paceStrategies: String(localized: "区間ごとのペース戦略を設定し、A・B・Cプランを比較。")
        case .fuelingPlan: String(localized: "補給・給水のタイミングと量を設定し、プリセットを再利用。")
        case .customChecklist: String(localized: "項目・カテゴリ・必須設定・期限を編集し、テンプレートと期限通知を利用。")
        case .planReuse: String(localized: "保存済みの計画を複製し、テンプレートや別レースから設定を適用。")
        case .raceCard: String(localized: "画像・PDF・印刷・ペースバンドで、計画を持ち出し・共有。")
        case .preparationDashboard: String(localized: "関門超過・補給不足・未完了の必須項目をまとめて確認。")
        }
    }
}

enum ProPricePresentation: Equatable {
    case loading
    case available(String)
    case unavailable
}

extension ProStore {
    func canUse(_ feature: ProFeature) -> Bool { isPro }

    var pricePresentation: ProPricePresentation {
        switch productState {
        case .notLoaded, .loading: .loading
        case .loaded(let product): .available(product.displayPrice)
        case .failed: .unavailable
        }
    }
}
