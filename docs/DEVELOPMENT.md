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

`ProStoreTests` は商品取得失敗、未検証結果、購入・返金更新、競合する権利照会、監視の終了に加え、
購入結果の検証と完了、キャンセル／保留／通信失敗、復元結果、多重実行と呼び出し元の中断を検証します。
`ProStoreKitIntegrationTests` は `SKTestSession` を使い、実際の商品取得、`Product.purchase()` による
ローカル購入と取引完了、Store再生成による権利再取得、`AppStore.sync()` による復元、返金通知、
Ask to Buyの保留と承認後の解放を確認します。
Debug単体テストのホストアプリではStoreKitの自動起動を抑え、`SKTestSession` 初期化後に
テスト用のStoreを起動します。

StoreKit実購入テストはXcode 26.2 / iOS 26.2で確認しています。この開発環境のiOS 18.3.1では
ローカルStoreKitの権利照会が停止したため、実購入テストにはiOS 26.2を使用します。

```sh
xcodebuild -project RaceFuelMemo.xcodeproj -scheme RaceFuelMemo -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -parallel-testing-enabled NO -only-testing:RaceFuelMemoTests CODE_SIGN_IDENTITY=- test
```

Paywallの「Proを購入する」から購入し、Paywallと設定の「購入を復元する」から復元できます。
復元はユーザーの明示操作でのみ `AppStore.sync()` を呼びます。商品価格を取得できなくても復元は可能です。
端末内の購入成功結果は `Transaction.updates` だけで受け取れるとは限らないため、
`Product.PurchaseResult.success` の検証・現在の権利再評価・`finish()` も購入処理で行います。
未検証・別商品・不正な商品種別・失効した結果は解放せず、未検証取引は完了しません。
購入／復元は全画面で共通の状態管理を使い、処理中はどちらも多重実行できません。
画面を閉じたり呼び出し元が中断してもStore側の処理は継続し、フォアグラウンド復帰とTransaction監視で
権利を再確認します。承認待ちは解放せず、承認後の更新通知で反映します。
購入・復元の完了案内には、実際に反映された権利確認結果を使用します。処理中に別の権利確認が
開始された場合は最新の結果を待ち、その確認がキャンセルされた場合は照会し直します。
最新結果の世代確認と案内の反映は、間に中断を挟まず同じ処理内で行います。取引完了を待つ間の
返金・失効は通常の権利更新に反映し、完了後に古い成功案内で上書きしません。
後から権利確認や更新通知でProが有効になったときは、それ以前の復元対象なし・失敗などの案内を
解除します。承認待ちからの解放は購入成功を表示し、既にProの利用者による復元失敗は保持します。
購入や復元のAPIが失敗しても、その処理中に検証済みPro権利を取得した場合は「Proの購入を確認しました」
と案内します。未検証の購入結果からは解放せず、独立した検証済み権利の確認結果のみを利用します。
キャンセルは通常の状態として案内し、復元対象なし・通信失敗・検証失敗は別のメッセージで表示します。
StoreKitエラーやトランザクションの個人情報・機密情報はアプリのログへ出力しません。
App Store Connectの商品設定と実機Sandboxでの最終確認は #47 の検証手順に従います。

## 無料／Pro境界とPaywall

対象操作は `ProFeature` に集約し、同じ列挙値からPaywallの機能説明も生成します。
GPX・標高はProの対象です。未実装のRace Day・振り返りは解放機能として宣伝しません。
`ProFeatureButton` が未購入／権利確認中の入口をPaywallへ誘導し、`proProtected` が編集・出力の
画面自体も保護します。権利失効時に開いたままの画面から操作できないようにし、非同期の
通知許可取得後や下書きの最終保存前にも権利を再確認します。
下書き内のPro編集済みマーカーも保存し、再起動による最終保存時の判定抜けを防ぎます。
マーカー追加前の下書きは互換性を保って読み込み・保存できます。

- 無料: 作成・保存・履歴・基本編集、均等ペース／固定区間計算、標準チェックリスト。
- Pro: GPX・標高、地点編集、詳細ペース／比較、詳細補給／プリセット、チェックリスト編集／テンプレート／
  期限通知、複製／再利用、Race Card出力、高度な準備状況確認。
- 保存済みの詳細データの閲覧とチェック済み状態の変更は無料。テンプレートの閲覧／削除も
  データ管理として無料のまま残します。課金状態で保存データを削除・移行しません。
  チェックリストテンプレートは設定の管理画面から閲覧／削除でき、名前変更のみProで保護します。
- 無料で基本のレース距離・目標タイムを短くした結果、既存の地点・手動通過時刻・補給予定が
  範囲外になる場合は、対象を表示して確認付きの整理を案内します。確認前や編集キャンセル時は
  保存済みデータを変更しません。距離外の地点と時間外の補給予定は削除し、地点の無効な手動時刻は
  解除して地点自体を保持します。地点の追加・自由編集はProのままです。
- 無料の作成完了は一覧へ戻ります。Proのみ保存後にRace Cardへ進みます。
- 価格は `Product.displayPrice` のみ。未取得中は読み込み表示、失敗は金額なしで再試行を案内します。

UIテストでは `--ui-testing` によりDebug限定の注入クライアントを使い、既定は未購入です。
`--pro-ui-testing` を併用すると検証済み権利のフィクスチャでPro導線を検証します。
`--restore-pro-ui-testing` は明示的な復元操作後に権利を返すDebug限定フィクスチャです。
これらの引数・クライアントはReleaseの権利判定に影響しません。
`RacePreparationUITests` は無料の全入口、Paywallの閉じる／再試行、下書きの再起動復元、
無料保存、既存詳細データ・チェック状態の保持、Proの編集／出力と大文字／ダークを確認します。
無料のチェックリストテンプレート閲覧／削除と、名前変更時のPaywallも検証します。
保存済み地点がある無料レースの距離短縮と目標タイム短縮、整理のキャンセル／確定、再起動後の
保存結果も検証します。
PaywallはDynamic Type・文字の切れ・読み上げ用説明のXCTest監査も行います。
購入不可時のボタン無効化、価格取得失敗中の復元と即時Pro解放、設定での復元対象なしの案内も確認します。
