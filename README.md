# LiquidGlassMask

Apple の Liquid Glass(macOS/iOS 26 の `glassEffect`)を、任意の形状のマスク画像でデスクトップに表示する macOS アプリ。

黒背景に白い形状のマスク画像を読み込むと、その形どおりの本物の Liquid Glass(屈折・ぼかし・縁のハイライト)が、完全透過のボーダーレスウィンドウとしてデスクトップに浮かびます。

## 仕組み

### マスク画像 → Shape 変換

`glassEffect(_:in:)` は `Shape` しか受け取れないため、以下のパイプラインで画像を Shape に変換している:

1. **Vision の `VNDetectContoursRequest`** で輪郭を抽出([MaskShape.swift](Sources/MaskShape.swift))
2. `polygonApproximation`(ε=0.0015)でピクセルの階段状ノイズを除去
3. 折れ角 45°未満の頂点は **2次ベジェで曲線化**(鋭い角は保持)し、ガラスの縁がファセット状に見えるのを防止
4. バウンディングボックスで**余白を自動トリミング**し、形状のアスペクト比を維持して表示

### 透過ウィンドウ

- SwiftUI 管理のウィンドウは使わず、`AppDelegate` がボーダーレス・完全透過の自前ウィンドウを生成([LiquidGlassMaskApp.swift](Sources/LiquidGlassMaskApp.swift))
- マスク形状の内側だけがクリック・ドラッグ可能(透明部分へのクリックは背後のアプリに透過)
- ダブルクリックでタイトルバー付きの枠表示に切り替え(位置・サイズ調整用)
- ウィンドウサイズに合わせてガラスの表示サイズも変わる

### 内部レイヤーの調整(実験的)

glassEffect が生成する私有レイヤー構造(`CABackdropLayer` + `glassBackground` フィルター)を実測で解析し、公開 API にないパラメータを直接操作している([GlassLayerInspector.swift](Sources/GlassLayerInspector.swift)):

| 操作 | パラメータ | 目的 |
|---|---|---|
| 白い膜の除去(常時) | `inputFaceOpacity` = 0 | 全面に乗る膜を消し、屈折だけ残す |
| 縁のハイライト除去 | `vibrantColorMatrix` レイヤー非表示 | 縁の白い輪郭を消す |
| 屈折の高さ調整 | `inputInnerRefractionHeight` × 倍率 | 細い形状での屈折帯の継ぎ目を軽減 |
| 非アクティブ時の維持 | `inputOuterRefractionAmount` 等を書き戻し | 他アプリにフォーカスが移ってもガラスを維持 |

**注意:** 私有のレイヤー構造・パラメータに依存するため、将来の macOS アップデートで動かなくなる可能性がある。App Store 配布向けではない。

## 使い方

- **マスクメニュー**: 形状の選択(サンプル4種 + 追加した画像)、マスク画像の追加(⌘O)
- **ガラスメニュー**: クリアガラス、縁のハイライト除去、屈折の高さ、ガラスの濃さ、ウィンドウ枠、最前面固定
- **ドラッグ**: ウィンドウごと移動 / **ダブルクリック**: 枠の表示切り替え / **枠表示中の端ドラッグ**: リサイズ
- 追加したマスク画像と設定はすべて保存され、次回起動時に復元される

### マスク画像の形式

- 黒背景に白い形状(グレースケール可)
- 輪郭がはっきりしていること
- 形状の外側の余白は自動でトリミングされる

## 必要環境 / ビルド

- Xcode 26 以降(macOS 26 SDK)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

```sh
xcodegen generate
xcodebuild -project LiquidGlassMask.xcodeproj -scheme LiquidGlassMaskMac \
  -destination 'platform=macOS,arch=arm64' build
```

iOS 用ターゲット `LiquidGlassMask` も同じソースからビルド可能(実行には iOS 26 以降が必要)。

## ライセンス

[MIT License](LICENSE)
