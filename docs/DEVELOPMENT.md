# 開発手順

## Xcodeで実行

`RaceFuelMemo.xcodeproj` を開き、`RaceFuelMemo` スキームを実行します。

## コマンドラインでビルド確認

```sh
xcodebuild -project RaceFuelMemo.xcodeproj -scheme RaceFuelMemo -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## Pro権利判定とStoreKitローカルテスト

非消耗型商品のIDは `ProProductID.lifetime`（`com.mytysoldier.RaceFuelMemo.pro`）で管理します。
App Store Connectでの商品作成時にも同じIDを使用します。
`ProStore` をSwiftUIのEnvironmentから参照でき、商品取得状態 (`productState`) と
購入権利 (`entitlementState` / `isPro`) は独立しています。起動時・フォアグラウンド復帰時・
`Transaction.updates` 受信時に権利を再評価します。

権利はStoreKitの `Transaction.currentEntitlements` に含まれる検証済みの非消耗型Pro商品だけで
判断します。未検証、別商品、別商品種別、失効・返金済みの結果では有効になりません。
オフラインでもStoreKitが端末に保持している検証済み権利を使います。商品情報の取得失敗は
購入権利を変更しません。独自のUserDefaultsフラグによる権利キャッシュは作りません。
起動直後の未確認状態は `.checking` で、確認完了までは `isPro == false` です。

`RaceFuelMemo` スキームのRunには `StoreKit/RunningRaceMate.storekit` を設定済みです。
ローカル価格600円はテスト用で、アプリが表示する価格には取得した `Product.displayPrice` を使います。
Xcodeの **Debug > StoreKit > Manage Transactions** からローカル購入・返金を操作できます。
Sandboxを確認する場合はスキームの **Run > Options > StoreKit Configuration** を **None** にします。
このファイルは単体テストのバンドルにだけコピーされ、配布アプリには含めません。

`ProStoreTests` は商品取得失敗、未検証結果、購入・返金更新、競合する権利照会、監視の終了を検証します。
`ProStoreKitIntegrationTests` は `SKTestSession` を使い、実際の商品取得、ローカル購入、
Store再生成による権利再取得、返金通知をまとめて確認します。
Debug単体テストのホストアプリではStoreKitの自動起動を抑え、`SKTestSession` 初期化後に
テスト用のStoreを起動します。

StoreKit実購入テストはXcode 26.2 / iOS 26.2で確認しています。この開発環境のiOS 18.3.1では
ローカルStoreKitの権利照会が停止したため、実購入テストにはiOS 26.2を使用します。

```sh
xcodebuild -project RaceFuelMemo.xcodeproj -scheme RaceFuelMemo -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -parallel-testing-enabled NO -only-testing:RaceFuelMemoTests CODE_SIGN_IDENTITY=- test
```

Paywall・購入・復元のユーザー導線は後続Issueで追加します。端末内の購入成功結果は
`Transaction.updates` だけで受け取れるとは限らないため、購入処理の実装時には
`Product.PurchaseResult.success` の検証・権利再評価・完了処理も行います。
