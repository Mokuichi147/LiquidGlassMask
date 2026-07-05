import CoreGraphics
import Foundation

/// デモ用のマスク画像をランタイムで生成する
/// (黒背景に白い形状 = 任意の PNG マスク画像と同じ形式)
enum SampleMask: String, CaseIterable, Identifiable, Codable {
    case star = "スター"
    case heart = "ハート"
    case lightning = "稲妻"
    case blob = "ブロブ"

    var id: String { rawValue }

    func render(size: Int = 512) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        let bounds = CGRect(x: 0, y: 0, width: size, height: size)
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(bounds)

        // パス座標を上原点(UIKit と同じ向き)で書けるように Y 軸を反転する
        context.translateBy(x: 0, y: CGFloat(size))
        context.scaleBy(x: 1, y: -1)

        context.setFillColor(gray: 1, alpha: 1)
        context.addPath(path(in: bounds.insetBy(dx: 40, dy: 40)))
        context.fillPath()
        return context.makeImage()!
    }

    private func path(in rect: CGRect) -> CGPath {
        switch self {
        case .star:
            return Self.starPath(in: rect, points: 5)
        case .heart:
            return Self.heartPath(in: rect)
        case .lightning:
            return Self.lightningPath(in: rect)
        case .blob:
            return Self.blobPath(in: rect)
        }
    }

    private static func starPath(in rect: CGRect, points: Int) -> CGPath {
        let path = CGMutablePath()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.45
        for i in 0..<(points * 2) {
            let radius = i.isMultiple(of: 2) ? outer : inner
            let angle = CGFloat(i) * .pi / CGFloat(points) - .pi / 2
            let point = CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private static func heartPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let w = rect.width, h = rect.height
        let ox = rect.minX, oy = rect.minY
        path.move(to: CGPoint(x: ox + w * 0.5, y: oy + h * 0.95))
        path.addCurve(
            to: CGPoint(x: ox, y: oy + h * 0.3),
            control1: CGPoint(x: ox + w * 0.1, y: oy + h * 0.7),
            control2: CGPoint(x: ox, y: oy + h * 0.5)
        )
        path.addCurve(
            to: CGPoint(x: ox + w * 0.5, y: oy + h * 0.2),
            control1: CGPoint(x: ox, y: oy),
            control2: CGPoint(x: ox + w * 0.4, y: oy)
        )
        path.addCurve(
            to: CGPoint(x: ox + w, y: oy + h * 0.3),
            control1: CGPoint(x: ox + w * 0.6, y: oy),
            control2: CGPoint(x: ox + w, y: oy)
        )
        path.addCurve(
            to: CGPoint(x: ox + w * 0.5, y: oy + h * 0.95),
            control1: CGPoint(x: ox + w, y: oy + h * 0.5),
            control2: CGPoint(x: ox + w * 0.9, y: oy + h * 0.7)
        )
        path.closeSubpath()
        return path
    }

    private static func lightningPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let points: [(CGFloat, CGFloat)] = [
            (0.6, 0.0), (0.2, 0.55), (0.45, 0.55),
            (0.35, 1.0), (0.8, 0.4), (0.55, 0.4),
        ]
        for (i, p) in points.enumerated() {
            let point = CGPoint(
                x: rect.minX + rect.width * p.0,
                y: rect.minY + rect.height * p.1
            )
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private static func blobPath(in rect: CGRect) -> CGPath {
        // 中心からの半径を波打たせた有機的な形状
        let path = CGMutablePath()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let base = min(rect.width, rect.height) / 2
        let steps = 120
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
            let wobble = 0.75 + 0.15 * sin(t * 3) + 0.1 * cos(t * 5 + 1.3)
            let radius = base * wobble
            let point = CGPoint(
                x: center.x + radius * cos(t),
                y: center.y + radius * sin(t)
            )
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}
