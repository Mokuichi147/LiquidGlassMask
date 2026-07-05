import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// 現在選択中のマスク(サンプル形状 or ユーザーが追加した画像)
enum MaskSelection: Codable, Hashable {
    case sample(SampleMask)
    case custom(UUID)
}

/// ユーザーが追加したマスク画像のメタデータ
struct CustomMask: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var fileName: String
}

/// 1ウィンドウ分の状態(形状選択・枠表示)
@MainActor
final class WindowGlassState: ObservableObject, Identifiable {
    nonisolated let id = UUID()

    @Published var selection: MaskSelection {
        didSet { AppState.shared.noteSelectionChanged(selection) }
    }
    @Published var showFrame = false

    init(selection: MaskSelection) {
        self.selection = selection
    }
}

/// 全ウィンドウ共通の設定(UserDefaults に永続化される)
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var customMasks: [CustomMask] {
        didSet { Self.saveCodable(customMasks, key: "customMasks") }
    }
    @Published var useClearGlass: Bool {
        didSet { UserDefaults.standard.set(useClearGlass, forKey: "useClearGlass") }
    }
    @Published var removeRim: Bool {
        didSet { UserDefaults.standard.set(removeRim, forKey: "removeRim") }
    }
    @Published var alwaysOnTop: Bool {
        didSet { UserDefaults.standard.set(alwaysOnTop, forKey: "alwaysOnTop") }
    }
    /// 屈折帯の高さの倍率(1.0 = 標準)。小さくすると細い部分の継ぎ目が減る
    @Published var refractionScale: Double {
        didSet { UserDefaults.standard.set(refractionScale, forKey: "refractionScale") }
    }
    @Published var glassOpacity: Double {
        didSet { UserDefaults.standard.set(glassOpacity, forKey: "glassOpacity") }
    }

    /// メニュー操作の対象になる、最後にアクティブだったウィンドウの状態
    @Published private(set) var activeWindowState: WindowGlassState?
    /// 最後に選択された形状(新規ウィンドウの初期値・次回起動時の復元に使う)
    private(set) var lastSelection: MaskSelection

    private init() {
        let defaults = UserDefaults.standard
        let masks = Self.loadCodable([CustomMask].self, key: "customMasks") ?? []
        customMasks = masks
        let saved = Self.loadCodable(MaskSelection.self, key: "selection") ?? .sample(.star)
        // 保存されていたカスタム画像が消えていたらデフォルトに戻す
        if case .custom(let id) = saved, !masks.contains(where: { $0.id == id }) {
            lastSelection = .sample(.star)
        } else {
            lastSelection = saved
        }
        useClearGlass = defaults.object(forKey: "useClearGlass") as? Bool ?? true
        removeRim = defaults.object(forKey: "removeRim") as? Bool ?? true
        alwaysOnTop = defaults.object(forKey: "alwaysOnTop") as? Bool ?? false
        refractionScale = defaults.object(forKey: "refractionScale") as? Double ?? 0.35
        glassOpacity = defaults.object(forKey: "glassOpacity") as? Double ?? 1.0
    }

    // MARK: - ウィンドウ状態の管理

    func setActive(_ windowState: WindowGlassState) {
        activeWindowState = windowState
    }

    func noteSelectionChanged(_ selection: MaskSelection) {
        lastSelection = selection
        Self.saveCodable(selection, key: "selection")
        // メニューのチェックマークを更新させる
        objectWillChange.send()
    }

    // MARK: - カスタムマスク画像の管理

    /// 追加された画像の保存先(Application Support 配下)
    private static var masksDirectory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LiquidGlassMask/masks", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// ファイル選択ダイアログを開いてマスク画像を追加する
    func pickAndAddCustomMask() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addCustomMask(from: url)
    }

    /// 画像ファイルをコピーして形状リストに追加し、アクティブなウィンドウで選択する
    func addCustomMask(from url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }

        let id = UUID()
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
        let fileName = "\(id.uuidString).\(ext)"
        let destination = Self.masksDirectory.appendingPathComponent(fileName)
        guard (try? data.write(to: destination)) != nil else { return }

        let mask = CustomMask(
            id: id,
            name: url.deletingPathExtension().lastPathComponent,
            fileName: fileName
        )
        customMasks.append(mask)
        activeWindowState?.selection = .custom(id)
    }

    /// 保存済みのカスタムマスク画像を読み込む
    func loadCustomImage(id: UUID) -> CGImage? {
        guard let mask = customMasks.first(where: { $0.id == id }) else { return nil }
        let url = Self.masksDirectory.appendingPathComponent(mask.fileName)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// カスタムマスク画像を削除する
    func removeCustomMask(id: UUID) {
        guard let index = customMasks.firstIndex(where: { $0.id == id }) else { return }
        let mask = customMasks[index]
        let url = Self.masksDirectory.appendingPathComponent(mask.fileName)
        try? FileManager.default.removeItem(at: url)
        customMasks.remove(at: index)
        // アクティブなウィンドウが削除中の画像を選択中ならデフォルトに戻す
        if activeWindowState?.selection == .custom(id) {
            activeWindowState?.selection = .sample(.star)
        }
    }

    // MARK: - 永続化ヘルパー

    private static func saveCodable<T: Codable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func loadCodable<T: Codable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
