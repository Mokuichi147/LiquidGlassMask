import SwiftUI
import AppKit
import QuartzCore

/// glassEffect の内部レイヤーのうち、白味(ヴィブランシー膜)を描く
/// vibrantColorMatrix レイヤーだけを非表示にする(実験的)
///
/// glassEffect のレイヤー構造(実測):
///   CABackdropLayer filters=[glassBackground]  ← 屈折・ぼかし(残す)
///   SDFPortalLayer @1
///   CASDFLayer @2 filters=[vibrantColorMatrix] ← 白い膜(これを隠す)
/// 私有のレイヤー構造に依存するため、OS アップデートで動かなくなる可能性あり。
struct GlassFilmRemover: NSViewRepresentable {
    var removeRim: Bool
    var refractionScale: Double

    func makeNSView(context: Context) -> GlassFilmRemoverView {
        GlassFilmRemoverView()
    }

    func updateNSView(_ view: GlassFilmRemoverView, context: Context) {
        view.removeRim = removeRim
        view.refractionScale = refractionScale
    }
}

final class GlassFilmRemoverView: NSView {
    var removeRim = false {
        didSet { apply() }
    }
    var refractionScale = 1.0 {
        didSet { apply() }
    }
    private var timer: Timer?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        timer?.invalidate()
        guard window != nil else { return }
        // SwiftUI がレイヤーを作り直すたびに再適用が必要なため定期的に走らせる
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.apply()
        }
    }

    private func apply() {
        guard let root = window?.contentView?.layer else { return }
        walk(root, insideGraphicsView: false)
        Self.debugDumpIfNeeded(root: root)
    }

    // MARK: - 非アクティブ時もアクティブ時のガラス描画を維持する
    //
    // アプリが非アクティブになると macOS は glassBackground の
    // inputOuterRefractionAmount を 0、inputBlurRadius を 10 に変更して
    // 平坦な曇りガラスに落とす(実測)。アクティブ時の値を保存しておき、
    // 非アクティブ中は書き戻して Liquid Glass の見た目を維持する。

    private var savedFilterValues: [ObjectIdentifier: [String: Any]] = [:]
    private static let pinnedKeys = ["inputOuterRefractionAmount", "inputBlurRadius"]

    /// このビューが属するウィンドウが本当にキーかどうか。
    /// (アプリ非アクティブ時や、複数ウィンドウで非キーのときに false になる)
    private var isWindowTrulyActive: Bool {
        (window as? ChromelessWindow)?.isActuallyKey ?? NSApp.isActive
    }

    private func pinActiveAppearance(of layer: CALayer, filter: NSObject) {
        let id = ObjectIdentifier(layer)
        if isWindowTrulyActive {
            var values: [String: Any] = [:]
            for key in Self.pinnedKeys {
                values[key] = filter.value(forKey: key)
            }
            savedFilterValues[id] = values
        } else if let values = savedFilterValues[id] {
            for key in Self.pinnedKeys {
                if let value = values[key] {
                    layer.setValue(value, forKeyPath: "filters.glassBackground.\(key)")
                }
            }
        }
    }

    // MARK: - 屈折帯の高さの調整
    //
    // 屈折帯の高さ(inputInnerRefractionHeight)が形状の幅より大きいと、
    // 細い部分で両側の屈折帯が衝突して筋になる。倍率で縮小できるようにする。
    // SwiftUI がリサイズ等で値を再設定した場合は、それを新しい元値として追従する。

    private var refractionHeightOriginal: [ObjectIdentifier: Double] = [:]
    private var refractionHeightLastSet: [ObjectIdentifier: Double] = [:]

    private func applyRefractionScale(of layer: CALayer, filter: NSObject) {
        let key = "inputInnerRefractionHeight"
        let id = ObjectIdentifier(layer)
        guard let current = (filter.value(forKey: key) as? NSNumber)?.doubleValue else { return }

        // SwiftUI 側が値を書き換えていたら、それを新しい元値として採用する
        if current != refractionHeightLastSet[id] {
            refractionHeightOriginal[id] = current
        }
        guard let original = refractionHeightOriginal[id] else { return }

        let target = original * refractionScale
        if current != target {
            layer.setValue(target, forKeyPath: "filters.glassBackground.\(key)")
            refractionHeightLastSet[id] = target
        }
    }

    // MARK: - アクティブ/非アクティブ時のレイヤー状態を比較するための調査用ダンプ

    private static var didDumpActive = false
    private static var didDumpInactive = false

    private static func debugDumpIfNeeded(root: CALayer) {
        let active = NSApp.isActive
        if active {
            guard !didDumpActive else { return }
            didDumpActive = true
        } else {
            guard !didDumpInactive else { return }
            didDumpInactive = true
        }
        var output = "appActive=\(active)\n"
        dumpLayer(root, indent: "", into: &output)
        let path = active ? "/private/tmp/glass-active-dump.txt" : "/private/tmp/glass-inactive-dump.txt"
        try? output.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
    }

    private static func dumpLayer(_ layer: CALayer, indent: String, into output: inout String) {
        let cls = String(describing: type(of: layer))
        var filterInfo = ""
        for filter in layer.filters ?? [] {
            let name = String(describing: filter)
            filterInfo += " filter=\(name)"
            if name.contains("glassBackground"), let object = filter as? NSObject,
               let data = try? NSKeyedArchiver.archivedData(withRootObject: object, requiringSecureCoding: false) {
                filterInfo += " archiveHash=\(data.count)-\(data.hashValue)"
                // 値の比較のため代表的なパラメータを読む
                for key in ["inputFaceOpacity", "inputInnerRefractionAmount", "inputOuterRefractionAmount",
                            "inputBlurRadius", "inputRefractionOpacity", "inputBlurOpacity0"] {
                    if let value = object.value(forKey: key) {
                        filterInfo += " \(key)=\(value)"
                    }
                }
            }
        }
        output += "\(indent)\(cls) name=\(layer.name ?? "-") hidden=\(layer.isHidden) opacity=\(layer.opacity)\(filterInfo) contents=\(layer.contents != nil)\n"
        for sublayer in layer.sublayers ?? [] {
            dumpLayer(sublayer, indent: indent + "  ", into: &output)
        }
    }

    private func walk(_ layer: CALayer, insideGraphicsView: Bool) {
        // コントロールパネル側(_NSGraphicsView 配下)のガラスは対象外にする
        let inGraphics = insideGraphicsView
            || (layer.name?.contains("_NSGraphicsView") ?? false)

        // 縁のハイライトを描く vibrantColorMatrix レイヤー。
        // 非アクティブ時に opacity を 0 にされるため常に 1 へ戻す
        if !inGraphics,
           String(describing: type(of: layer)) == "CASDFLayer",
           (layer.filters ?? []).contains(where: { String(describing: $0).contains("vibrantColorMatrix") }) {
            layer.isHidden = removeRim
            if !removeRim, layer.opacity != 1 {
                layer.opacity = 1
            }
        }
        if !inGraphics,
           let glassFilter = (layer.filters ?? []).first(where: {
               String(describing: $0).contains("glassBackground")
           }) as? NSObject {
            // 全面に乗る膜(face)を常時無効化。屈折・ぼかしはそのまま残る
            layer.setValue(0, forKeyPath: "filters.glassBackground.inputFaceOpacity")
            pinActiveAppearance(of: layer, filter: glassFilter)
            applyRefractionScale(of: layer, filter: glassFilter)
        }
        for sublayer in layer.sublayers ?? [] {
            walk(sublayer, insideGraphicsView: inGraphics)
        }
    }

}
