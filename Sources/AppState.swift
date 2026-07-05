import SwiftUI
import ImageIO

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

/// メニューバーとビューの間で共有する設定(UserDefaults に永続化される)
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var selection: MaskSelection {
        didSet { Self.saveCodable(selection, key: "selection") }
    }
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
    @Published var showFileImporter = false
    @Published var showWindowFrame = false

    private init() {
        let defaults = UserDefaults.standard
        let masks = Self.loadCodable([CustomMask].self, key: "customMasks") ?? []
        customMasks = masks
        let saved = Self.loadCodable(MaskSelection.self, key: "selection") ?? .sample(.star)
        // 保存されていたカスタム画像が消えていたらデフォルトに戻す
        if case .custom(let id) = saved, !masks.contains(where: { $0.id == id }) {
            selection = .sample(.star)
        } else {
            selection = saved
        }
        useClearGlass = defaults.object(forKey: "useClearGlass") as? Bool ?? true
        removeRim = defaults.object(forKey: "removeRim") as? Bool ?? true
        alwaysOnTop = defaults.object(forKey: "alwaysOnTop") as? Bool ?? false
        refractionScale = defaults.object(forKey: "refractionScale") as? Double ?? 0.35
        glassOpacity = defaults.object(forKey: "glassOpacity") as? Double ?? 1.0
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

    /// 選択された画像ファイルをコピーして形状リストに追加し、選択状態にする
    func addCustomMask(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
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
        selection = .custom(id)
    }

    /// 保存済みのカスタムマスク画像を読み込む
    func loadCustomImage(id: UUID) -> CGImage? {
        guard let mask = customMasks.first(where: { $0.id == id }) else { return nil }
        let url = Self.masksDirectory.appendingPathComponent(mask.fileName)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
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
