# 動作確認

## 環境

- Xcode 26.6（`.mise.toml` の `[env]` で `DEVELOPER_DIR` を Xcode.app に固定）
- bundle id: `com.d0ne1s.mobileide`
- ターゲット: iPhone（iOS 17.0+）
- 実機署名: Team `VYDUR99LAM` の自動署名（Vid と同じ）

## セットアップ

`project.yml` を編集したら必ず再生成する。

```sh
mise run gen    # = xcodegen generate
```

アイコンを変えたら `scripts/generate-app-icon.swift` を編集して再生成する（light / dark の 1024px を asset catalog に書き出す）。

```sh
mise run icon
```

## シミュレータ

```sh
mise run boot   # iPhone 17 シミュレータ起動
mise run run    # build → install → launch
mise run shot   # スクリーンショットを /tmp/mobile-ide.png に保存
```

確認項目:

- 起動して「接続先が未設定です」のプレースホルダが表示されること
- ホーム画面に金の C 型の耳（青地）のアイコンが出ていること。ダークモードにすると地が濃紺になること

## 実機（iPhone）

iPhone を Mac とペアリング済み（一度 USB で接続して「このコンピュータを信頼」）で、**ロックを解除した状態**で行う。ペアリング後は同一 Wi-Fi 上なら USB 無しでも devicectl の tunnel が張られ、転送できる（2026-09-04 に実証）。ロック中は developer disk image のマウントが `kAMDMobileImageMounterDeviceLocked` で失敗する。

```sh
bash scripts/device-id.sh   # ペアリング済み iPhone の識別子が 1 行出ればよい
mise run device-run         # build → devicectl install → launch
```

- 初回は iPhone 側で「設定 → 一般 → VPN とデバイス管理」から開発者 App を信頼する必要がある場合がある
- 別の iPhone を使うときは `MOBILE_IDE_DEVICE=<識別子> mise run device-run`
- 署名に失敗するときは Xcode で `MobileIDE.xcodeproj` を開き、Signing & Capabilities で Team を選び直す（`project.yml` の `DEVELOPMENT_TEAM` を書き換えて `mise run gen`）

確認項目:

- ホーム画面に「Mobile IDE」の名前でアイコンが並ぶこと
- 起動してプレースホルダ画面が表示されること
