import SwiftUI

@main
struct LiquidGlassMaskApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @ObservedObject private var state = AppState.shared

    var body: some Scene {
        #if os(macOS)
        // ウィンドウは AppDelegate が自前で作るため、ここではウィンドウを作らない
        Settings {
            EmptyView()
        }
        .commands {
            CommandMenu("マスク") {
                Picker("形状", selection: $state.selection) {
                    ForEach(SampleMask.allCases) { mask in
                        Text(mask.rawValue).tag(MaskSelection.sample(mask))
                    }
                    if !state.customMasks.isEmpty {
                        Divider()
                        ForEach(state.customMasks) { mask in
                            Text(mask.name).tag(MaskSelection.custom(mask.id))
                        }
                    }
                }
                Divider()
                Button("マスク画像を追加…") {
                    state.showFileImporter = true
                }
                .keyboardShortcut("o")
            }
            CommandMenu("ガラス") {
                Toggle("クリアガラス(高透明)", isOn: $state.useClearGlass)
                Toggle("縁のハイライトを除去", isOn: $state.removeRim)
                Picker("屈折の高さ", selection: $state.refractionScale) {
                    Text("100%").tag(1.0)
                    Text("70%").tag(0.7)
                    Text("50%").tag(0.5)
                    Text("35%").tag(0.35)
                    Text("20%").tag(0.2)
                }
                Picker("ガラスの濃さ", selection: $state.glassOpacity) {
                    Text("100%").tag(1.0)
                    Text("80%").tag(0.8)
                    Text("60%").tag(0.6)
                    Text("40%").tag(0.4)
                    Text("20%").tag(0.2)
                }
                Divider()
                Toggle("ウィンドウ枠を表示", isOn: $state.showWindowFrame)
                Toggle("最前面に固定", isOn: $state.alwaysOnTop)
            }
        }
        #else
        WindowGroup {
            ContentView()
        }
        #endif
    }
}

#if os(macOS)
import AppKit
import Combine

/// ボーダーレスでもキーウィンドウになれるウィンドウ。
/// isKeyWindow/isMainWindow を常に true にして、非アクティブ時でも
/// ガラスがアクティブ外観のまま描画されるようにする
final class ChromelessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}

/// タイトルバーも枠も一切ない完全透過ウィンドウを自前で生成する。
/// SwiftUI 管理のウィンドウは後から styleMask を borderless に変更できない
/// (例外でクラッシュする)ため、最初からボーダーレスで作る。
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: ChromelessWindow?
    private var cancellables = Set<AnyCancellable>()
    private var clickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = ChromelessWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        // UI はメニューバーに移したため、ウィンドウ内のドラッグは
        // すべてウィンドウ移動として扱ってよい
        window.isMovableByWindowBackground = true
        // 非アクティブ時もガラスがアクティブ外観(Liquid Glass)を維持するようにする
        let hostingView = NSHostingView(
            rootView: ContentView().environment(\.controlActiveState, .key)
        )
        // SwiftUI の固有サイズでウィンドウが縮まないようにする
        hostingView.sizingOptions = []
        window.contentView = hostingView
        window.setContentSize(NSSize(width: 900, height: 700))
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)

        AppState.shared.$showWindowFrame
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] show in
                self?.applyWindowFrame(show)
            }
            .store(in: &cancellables)

        AppState.shared.$alwaysOnTop
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] onTop in
                self?.window?.level = onTop ? .floating : .normal
            }
            .store(in: &cancellables)

        // ダブルクリックの検知はイベント配送を妨げないローカルモニタで行う。
        // (sendEvent 内でウィンドウを再構成するとイベント処理が壊れるため)
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            if event.clickCount == 2, event.window === self?.window {
                DispatchQueue.main.async {
                    AppState.shared.showWindowFrame.toggle()
                }
            }
            return event
        }
    }

    /// ウィンドウ枠(タイトルバー)の表示/非表示を切り替える。
    /// 自前生成のウィンドウなので styleMask を動的に変更できる
    private func applyWindowFrame(_ show: Bool) {
        guard let window else { return }
        if show {
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            // 透明タイトルバーだと枠が見えないため、通常の不透明なタイトルバーを出す
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = false
            window.title = "Liquid Glass Mask"
            window.hasShadow = true
        } else {
            window.styleMask = [.borderless, .resizable]
            window.hasShadow = false
        }
        window.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
#endif
