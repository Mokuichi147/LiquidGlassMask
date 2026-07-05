import SwiftUI
import ImageIO
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject private var state = AppState.shared
    @State private var maskPath: Path?
    @State private var maskAspect: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            content(in: geometry.size)
        }
    }

    private func content(in windowSize: CGSize) -> some View {
        ZStack {
            // 背景は置かない(ウィンドウごと透過させる)
            // ドラッグ移動・ダブルクリック検知はウィンドウ側(AppKit)で行う
            Color.clear

            // 枠表示中はウィンドウ全体の範囲がわかるように薄い背景と境界線を出す
            if state.showWindowFrame {
                Rectangle()
                    .fill(Color.black.opacity(0.15))
                    .overlay(
                        Rectangle()
                            .strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1)
                    )
                    .ignoresSafeArea()
            }

            if let maskPath {
                let glassSize = glassSize(in: windowSize)
                glassView(maskPath: maskPath, size: glassSize)
            }

            GlassFilmRemover(removeRim: state.removeRim, refractionScale: state.refractionScale)
                .frame(width: 1, height: 1)
        }
        .task {
            // ビューが作り直されたときも現在の選択マスクを復元する
            applyCurrentMask()
        }
        .onChange(of: state.selection) {
            applyCurrentMask()
        }
        .fileImporter(isPresented: $state.showFileImporter, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            // 形状リストへの追加・永続化・選択は AppState 側で行う
            state.addCustomMask(from: url)
        }
    }

    private func glassView(maskPath: Path, size: CGSize) -> some View {
        Color.clear
            .frame(width: size.width, height: size.height)
            .glassEffect(
                (state.useClearGlass ? Glass.clear : .regular).interactive(),
                in: MaskImageShape(normalizedPath: maskPath)
            )
            .opacity(state.glassOpacity)
            // 透過ウィンドウはピクセル単位でクリック透過されるため、
            // マスク形状の内側にだけ極薄の塗りを敷いてクリックを受けられるようにする。
            // 形状の外(完全透明)はクリックが下のウィンドウへ抜ける
            .overlay(
                MaskImageShape(normalizedPath: maskPath)
                    .fill(Color.white.opacity(0.02))
            )
    }

    /// 現在選択中のマスク(サンプル形状 or 追加した画像)を適用する
    private func applyCurrentMask() {
        switch state.selection {
        case .sample(let sample):
            applyMask(sample.render())
        case .custom(let id):
            if let image = state.loadCustomImage(id: id) {
                applyMask(image)
            } else {
                applyMask(SampleMask.star.render())
            }
        }
    }

    /// マスク画像から輪郭を抽出して glassEffect 用の形状を更新する。
    /// 形状の外側の余白はトリミングして、形状がぴったり収まるようにする
    private func applyMask(_ image: CGImage) {
        guard var path = MaskContourExtractor.normalizedPath(from: image) else {
            maskPath = nil
            return
        }
        let bounds = path.boundingRect
        if bounds.width > 0, bounds.height > 0 {
            // バウンディングボックスが 0〜1 いっぱいになるようパスを拡大する
            let transform = CGAffineTransform(scaleX: 1 / bounds.width, y: 1 / bounds.height)
                .translatedBy(x: -bounds.minX, y: -bounds.minY)
            path = path.applying(transform)
            maskAspect = (CGFloat(image.width) * bounds.width)
                / (CGFloat(image.height) * bounds.height)
        } else {
            maskAspect = CGFloat(image.width) / CGFloat(image.height)
        }
        maskPath = path
    }

    /// マスク画像のアスペクト比を保ったままウィンドウいっぱいに収めたサイズ
    /// (ウィンドウをリサイズすると表示サイズが変わる)
    private func glassSize(in windowSize: CGSize) -> CGSize {
        let margin: CGFloat = 24
        let available = CGSize(
            width: max(windowSize.width - margin * 2, 50),
            height: max(windowSize.height - margin * 2, 50)
        )
        let scale = min(available.width / maskAspect, available.height)
        return CGSize(width: scale * maskAspect, height: scale)
    }
}
