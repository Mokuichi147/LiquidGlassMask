import SwiftUI
import Vision

/// マスク画像(黒背景に白い形状)から輪郭を抽出するユーティリティ
enum MaskContourExtractor {
    /// 画像から正規化座標(0〜1、原点は左下)の輪郭パスを抽出する
    static func normalizedPath(from cgImage: CGImage) -> Path? {
        let request = VNDetectContoursRequest()
        request.contrastAdjustment = 2.0
        request.detectsDarkOnLight = false
        request.maximumImageDimension = 1024

        let handler = VNImageRequestHandler(cgImage: cgImage)
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observation = request.results?.first,
              observation.contourCount > 0 else { return nil }

        // そのまま使うとピクセル単位の階段状ノイズが縁に残るため、
        // 各輪郭をポリゴン近似して滑らかにする
        var path = Path()
        for contour in observation.topLevelContours {
            appendSimplified(contour, to: &path)
        }
        return path.isEmpty ? nil : path
    }

    private static func appendSimplified(_ contour: VNContour, to path: inout Path) {
        // ε はピクセルの階段状ノイズ(1024px 基準で約 0.001)を少し超える程度に留め、
        // 曲線が粗い折れ線になって尖るのを防ぐ
        let simplified = (try? contour.polygonApproximation(epsilon: 0.0015)) ?? contour
        let points = simplified.normalizedPoints.map {
            CGPoint(x: CGFloat($0.x), y: CGFloat($0.y))
        }
        appendSmoothedClosedPath(points: points, to: &path)
        // 穴などの子輪郭も同様に処理する
        for child in contour.childContours {
            appendSimplified(child, to: &path)
        }
    }

    /// 折れ線のままだとガラスの縁レンズが各辺をファセットとして強調してしまうため、
    /// 緩やかな頂点は 2 次ベジェで曲線化する。鋭く曲がる頂点(星の先端など)は
    /// 角として保持する
    private static func appendSmoothedClosedPath(points: [CGPoint], to path: inout Path) {
        let n = points.count
        guard n >= 3 else { return }

        // 各頂点の折れ角が閾値(45°)を超えるものは「角」と判定する
        let cornerThreshold = cos(45 * CGFloat.pi / 180)
        let isCorner: [Bool] = (0..<n).map { i in
            let prev = points[(i - 1 + n) % n]
            let current = points[i]
            let next = points[(i + 1) % n]
            let v1 = CGVector(dx: current.x - prev.x, dy: current.y - prev.y)
            let v2 = CGVector(dx: next.x - current.x, dy: next.y - current.y)
            let lengths = hypot(v1.dx, v1.dy) * hypot(v2.dx, v2.dy)
            guard lengths > 0 else { return true }
            let cosine = (v1.dx * v2.dx + v1.dy * v2.dy) / lengths
            return cosine < cornerThreshold
        }

        func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }

        // 辺の中点を通り、頂点を制御点とする 2 次ベジェで繋ぐ(角は直線で経由)
        path.move(to: midpoint(points[0], points[1]))
        for i in 1...n {
            let current = points[i % n]
            let mid = midpoint(current, points[(i + 1) % n])
            if isCorner[i % n] {
                path.addLine(to: current)
                path.addLine(to: mid)
            } else {
                path.addQuadCurve(to: mid, control: current)
            }
        }
        path.closeSubpath()
    }
}

/// Vision が返す正規化パスを任意の rect に描画する Shape
/// glassEffect(in:) にそのまま渡せる
struct MaskImageShape: Shape {
    let normalizedPath: Path

    func path(in rect: CGRect) -> Path {
        // Vision の座標系は原点が左下なので Y 軸を反転しつつ rect に拡大する
        let transform = CGAffineTransform(translationX: rect.minX, y: rect.maxY)
            .scaledBy(x: rect.width, y: -rect.height)
        return normalizedPath.applying(transform)
    }
}
