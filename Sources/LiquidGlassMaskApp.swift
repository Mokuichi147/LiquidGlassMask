import SwiftUI
import AppKit
import Combine

@main
struct LiquidGlassMaskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var state = AppState.shared
    @State private var selectedSelection: MaskSelection

    init() {
        _selectedSelection = State(initialValue: AppState.shared.lastSelection)
    }

    /// 現在アクティブなウィンドウの選択状態を取得
    private var activeSelection: MaskSelection {
        state.activeWindowState?.selection ?? selectedSelection
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandMenu("マスク") {
                // サンプル形状
                ForEach(SampleMask.allCases) { mask in
                    Button(
                        action: {
                            let sel = MaskSelection.sample(mask)
                            selectedSelection = sel
                            state.activeWindowState?.selection = sel
                            state.noteSelectionChanged(sel)
                        },
                        label: {
                            Label(
                                mask.rawValue,
                                systemImage: activeSelection == .sample(mask) ? "checkmark" : "circle"
                            )
                        }
                    )
                }

                if !state.customMasks.isEmpty {
                    Divider()
                    ForEach(state.customMasks) { mask in
                        Button(
                            action: {
                                let sel = MaskSelection.custom(mask.id)
                                selectedSelection = sel
                                state.activeWindowState?.selection = sel
                                state.noteSelectionChanged(sel)
                            },
                            label: {
                                Label(
                                    mask.name,
                                    systemImage: activeSelection == .custom(mask.id) ? "checkmark" : "circle"
                                )
                            }
                        )
                    }
                }

                Divider()
                Button("マスク画像を追加…") {
                    state.pickAndAddCustomMask()
                }
                .keyboardShortcut("o")

                // 選択中のカスタム画像がある場合に削除ボタンを表示
                if case .custom(let id) = activeSelection,
                   state.customMasks.contains(where: { $0.id == id }) {
                    Divider()
                    Button("この画像を削除") {
                        state.removeCustomMask(id: id)
                        selectedSelection = .sample(.star)
                        state.activeWindowState?.selection = .sample(.star)
                        state.noteSelectionChanged(.sample(.star))
                    }
                    .foregroundStyle(.red)
                }
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
            }
            CommandMenu("ウィンドウ操作") {
                Button("新規ウィンドウ") {
                    AppDelegate.shared?.newWindow()
                }
                .keyboardShortcut("n")
                Button("ウィンドウを閉じる") {
                    AppDelegate.shared?.closeActiveWindow()
                }
                .keyboardShortcut("w")
                Divider()
                Toggle("ウィンドウ枠を表示", isOn: frameBinding)
                Toggle("最前面に固定", isOn: $state.alwaysOnTop)
            }
        }
    }

    /// ウィンドウ枠のトグルも、最後にアクティブだったウィンドウに向ける
    private var frameBinding: Binding<Bool> {
        Binding(
            get: { state.activeWindowState?.showFrame ?? false },
            set: { newValue in
                state.activeWindowState?.showFrame = newValue
                state.objectWillChange.send()
            }
        )
    }
}

/// ボーダーレスでもキーウィンドウになれるウィンドウ。
/// isKeyWindow/isMainWindow を常に true にして、非アクティブ時でも
/// ガラスがアクティブ外観のまま描画されるようにする
final class ChromelessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }

    /// isKeyWindow を偽装しているため、本当のキー状態はここで追跡する
    /// (ガラスのアクティブ外観維持の判定に使う)
    private(set) var isActuallyKey = false

    override func becomeKey() {
        isActuallyKey = true
        super.becomeKey()
        // macOS が isKeyWindow 偽装のためウィンドウ順序を正しく管理しないため、
        // キーウィンドウになった時点で明示的に手前に出す
        orderFront(nil)
    }

    override func resignKey() {
        isActuallyKey = false
        super.resignKey()
    }
}

/// 1つのガラスウィンドウ(ウィンドウ本体 + 状態 + 枠切り替え)を管理する
@MainActor
final class GlassWindowController: NSObject, NSWindowDelegate {
    let window: ChromelessWindow
    let state: WindowGlassState
    var onClose: ((GlassWindowController) -> Void)?
    private var cancellables = Set<AnyCancellable>()

    init(selection: MaskSelection, cascadeIndex: Int) {
        state = WindowGlassState(selection: selection)
        window = ChromelessWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = AppState.shared.alwaysOnTop ? .floating : .normal
        window.delegate = self

        let hostingView = NSHostingView(
            rootView: ContentView(windowState: state).environment(\.controlActiveState, .key)
        )
        hostingView.sizingOptions = []
        window.contentView = hostingView
        window.setContentSize(NSSize(width: 900, height: 700))
        window.center()
        if cascadeIndex > 0 {
            let offset = CGFloat(cascadeIndex % 8) * 40
            window.setFrameOrigin(NSPoint(
                x: window.frame.origin.x + offset,
                y: window.frame.origin.y - offset
            ))
        }

        state.$showFrame
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] show in
                self?.applyWindowFrame(show)
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKeyNotification),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )

        window.makeKeyAndOrderFront(nil)
        AppState.shared.setActive(state)
    }

    @objc private func windowDidBecomeKeyNotification() {
        AppState.shared.setActive(state)
    }

    private func applyWindowFrame(_ show: Bool) {
        if show {
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
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

    func windowWillClose(_ notification: Notification) {
        onClose?(self)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate?

    private var controllers: [GlassWindowController] = []
    private var cancellables = Set<AnyCancellable>()
    private var clickMonitor: Any?

    override init() {
        super.init()
        Self.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        newWindow()
        NSApp.activate(ignoringOtherApps: true)

        AppState.shared.$alwaysOnTop
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] onTop in
                for controller in self?.controllers ?? [] {
                    controller.window.level = onTop ? .floating : .normal
                }
            }
            .store(in: &cancellables)

        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            if event.clickCount == 2,
               let controller = self?.controllers.first(where: { $0.window === event.window }) {
                DispatchQueue.main.async {
                    controller.state.showFrame.toggle()
                }
            }
            return event
        }
    }

    func newWindow() {
        let controller = GlassWindowController(
            selection: AppState.shared.lastSelection,
            cascadeIndex: controllers.count
        )
        controller.onClose = { [weak self] closed in
            self?.controllers.removeAll { $0 === closed }
        }
        controllers.append(controller)
    }

    func closeActiveWindow() {
        guard let active = AppState.shared.activeWindowState,
              let controller = controllers.first(where: { $0.state === active }) else { return }
        controller.window.close()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
