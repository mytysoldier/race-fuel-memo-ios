# 開発手順

## Xcodeで実行

`RaceFuelMemo.xcodeproj` を開き、`RaceFuelMemo` スキームを実行します。

## コマンドラインでビルド確認

```sh
xcodebuild -project RaceFuelMemo.xcodeproj -scheme RaceFuelMemo -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```
