import AppKit
import SwiftUI
import ServiceManagement
import BarFoldCore

@MainActor final class AppModel: NSObject, ObservableObject, NSMenuDelegate, NSWindowDelegate {
    @Published var preferences = Preferences()
    @Published var mode: FoldMode = .expanded
    @Published var items: [MenuItem] = []
    @Published var message = ""
    @Published var refreshInProgress = false
    @Published var accessibilityGranted = ItemCatalog.accessibilityPermission
    @Published var screenGranted = ItemCatalog.screenPermission
    @Published var loginEnabled = false
    @Published var operationInProgress = false
    @Published var configurationLocked = false
    let layout: StatusLayout
    let store: PreferencesStore
    private var fold = FoldState()
    private let hotKey = HotKey()
    private let catalog = ItemCatalog()
    private let interaction = ItemInteraction()
    private var timer: Timer?
    private var captureTask: Task<Void, Never>?
    private var refreshVersion = 0
    private var heldWindows = Set<ObjectIdentifier>()
    private var settingsWindow: NSWindow?
    private var paletteWindow: NSWindow?
    private var menu: NSMenu?
    private var menuHeld = false
    private var hoverWork: DispatchWorkItem?
    private let testMode: Bool

    init(configURL: URL, testMode: Bool = false) {
        self.testMode = testMode
        self.store = PreferencesStore(url: configURL)
        self.layout = StatusLayout(prefix: testMode ? "BarFold.Smoke" : "BarFold")
        super.init()
        do { preferences = try store.load() }
        catch { configurationLocked = true; message = "配置文件无法读取，已保留原文件。当前以默认设置运行且不写入：\(error.localizedDescription)" }
        layout.enablePermanent(preferences.alwaysHiddenEnabled)
        layout.onToggle = { [weak self] in self?.toggle() }
        layout.onMenu = { [weak self] in self?.showMenu() }
        layout.onHover = { [weak self] in self?.hover() }
        hotKey.action = { [weak self] in self?.toggle() }
        if !testMode { applyShortcut() }
        loginEnabled = SMAppService.mainApp.status == .enabled
        setMode(preferences.setupCompleted && preferences.launchCollapsed ? .collapsed : .expanded)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(activated), name: NSApplication.didBecomeActiveNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(screenChanged), name: NSWorkspace.didWakeNotification, object: nil)
    }
    func start() { if !preferences.setupCompleted && !testMode { showSettings() } }
    func setMode(_ next: FoldMode) {
        fold.set(next); mode = next; layout.apply(next); scheduleCollapse()
        let ticket = fold.generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.fold.generation == ticket, self.mode != .allVisible,
                  let control = self.layout.control.button?.window else { return }
            if !NSScreen.screens.contains(where: { $0.frame.contains(CGPoint(x: control.frame.midX, y: control.frame.midY)) }) {
                self.fold.set(.allVisible); self.mode = .allVisible; self.layout.apply(.allVisible)
                self.timer?.invalidate()
                self.message = "箭头位置不可见，已展开全部。请将箭头拖到两个分界线右侧，并检查其他菜单栏管理器。"
            }
        }
    }
    func toggle() { setMode(mode == .collapsed ? .expanded : .collapsed) }
    func updatePreferences(_ mutate: (inout Preferences) -> Void) {
        guard !configurationLocked else { return }
        var next = preferences; mutate(&next)
        do { try store.save(next); preferences = next; layout.enablePermanent(next.alwaysHiddenEnabled); applyShortcut(); scheduleCollapse() }
        catch { message = "设置未保存：\(error.localizedDescription)" }
    }
    private func applyShortcut() {
        if !hotKey.register(key: preferences.shortcutKeyCode, modifiers: preferences.shortcutModifiers, enabled: preferences.shortcutEnabled) {
            message = "快捷键已被其他应用占用，请在设置中更换。"
        }
    }
    private func scheduleCollapse() {
        timer?.invalidate(); timer = nil
        guard !testMode, preferences.autoCollapseSeconds > 0, mode != .collapsed, fold.holdCount == 0 else { return }
        let ticket = fold.generation
        timer = Timer.scheduledTimer(withTimeInterval: preferences.autoCollapseSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.fold.mayAutoCollapse(ticket: ticket) else { return }
                if self.pointerInMenuBar || NSEvent.pressedMouseButtons != 0 || self.hasOpenSystemMenu {
                    self.scheduleCollapse(); return
                }
                self.setMode(.collapsed)
            }
        }
    }
    private var pointerInMenuBar: Bool {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.contains { $0.frame.contains(point) && point.y > $0.frame.maxY - 44 }
    }
    private var hasOpenSystemMenu: Bool {
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { window in
            guard let layer = window[kCGWindowLayer as String] as? Int else { return false }
            return layer == 101 || layer == 102
        }
    }
    private func hover() {
        guard preferences.hoverToExpand, mode == .collapsed else { return }
        hoverWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let button = self.layout.control.button, let window = button.window,
                  window.frame.contains(NSEvent.mouseLocation) else { return }
            self.setMode(.expanded)
        }
        hoverWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
    @objc private func screenChanged() { layout.apply(mode); scheduleCollapse() }
    @objc private func activated() {
        accessibilityGranted = ItemCatalog.accessibilityPermission; screenGranted = ItemCatalog.screenPermission
        loginEnabled = SMAppService.mainApp.status == .enabled
    }
    func requestAccessibility() { ItemCatalog.requestAccessibility(); activated() }
    func requestScreenshots() {
        ItemCatalog.requestScreenRecording(); activated()
        if screenGranted { updatePreferences { $0.thumbnailsEnabled = true }; refresh() }
        else { message = "在系统设置中允许屏幕录制后，可能需要退出并重新打开 BarFold。" }
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval { message = "请在系统设置 → 通用 → 登录项中批准 BarFold。"; SMAppService.openSystemSettingsLoginItems() }
        } catch { message = "开机启动设置失败：\(error.localizedDescription)" }
    }
    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 650), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "BarFold · 设置"; window.isReleasedWhenClosed = false; window.delegate = self
            window.contentView = NSHostingView(rootView: SettingsView(model: self)); window.center(); settingsWindow = window
        }
        if let window = settingsWindow { hold(window); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    }
    func showPalette(arrange: Bool = false) {
        setMode(arrange ? .allVisible : .expanded)
        if paletteWindow == nil {
            let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 470), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.hidesOnDeactivate = false
            window.title = "BarFold · 图标面板"; window.isReleasedWhenClosed = false; window.delegate = self
            window.minSize = NSSize(width: 540, height: 330)
            window.contentView = NSHostingView(rootView: PaletteView(model: self)); paletteWindow = window
        }
        if let window = paletteWindow {
            hold(window)
            let screen = layout.control.button?.window?.screen ?? NSScreen.main
            if let frame = screen?.visibleFrame { window.setFrameTopLeftPoint(NSPoint(x: max(frame.minX, frame.maxX - window.frame.width - 16), y: frame.maxY - 14)) }
            window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.refresh() }
    }
    func beginArrangement() { setMode(.allVisible); DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.refresh() } }
    func refresh() {
        guard !operationInProgress, let divider = layout.dividerRect else { return }
        captureTask?.cancel(); refreshVersion += 1
        let version = refreshVersion
        accessibilityGranted = ItemCatalog.accessibilityPermission; screenGranted = ItemCatalog.screenPermission
        items = catalog.discover(divider: divider, always: layout.permanentRect)
        refreshInProgress = false
        guard preferences.thumbnailsEnabled, screenGranted else { return }
        refreshInProgress = true; let current = items
        captureTask = Task { [weak self] in
            guard let self else { return }
            let images = await self.catalog.thumbnails(for: current)
            guard !Task.isCancelled, version == self.refreshVersion else { return }
            for index in self.items.indices {
                if let image = images[self.items[index].id] { self.items[index].image = image; self.items[index].isScreenshot = true }
            }
            self.refreshInProgress = false
        }
    }
    func activateItem(_ item: MenuItem) {
        guard !operationInProgress else { return }
        if !accessibilityGranted { requestAccessibility(); message = "授权后，刷新面板再点击图标。"; return }
        operationInProgress = true
        paletteWindow?.orderOut(nil)
        Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            do {
                try await interaction.click(item)
                if let window = paletteWindow { release(window) }
                scheduleCollapse()
            } catch { message = error.localizedDescription; paletteWindow?.makeKeyAndOrderFront(nil) }
            operationInProgress = false
        }
    }
    func moveItem(_ item: MenuItem, section: ItemSection) {
        guard mode == .allVisible else { message = "请先点击“整理全部”，再移动图标。"; return }
        guard !operationInProgress, let divider = layout.dividerRect else { return }
        if !accessibilityGranted { requestAccessibility(); message = "授权后，刷新面板再移动图标。"; return }
        let x: Double
        switch section {
        case .visible: x = divider.maxX + item.rect.width / 2 + 3
        case .hidden: x = divider.minX - item.rect.width / 2 - 3
        case .alwaysHidden:
            guard let permanent = layout.permanentRect else { message = "请先在设置中启用始终隐藏分区。"; return }
            x = permanent.minX - item.rect.width / 2 - 3
        }
        operationInProgress = true
        Task {
            do { try await interaction.move(item, to: CGPoint(x: x, y: divider.midY)); message = "已移动图标，位置由系统记住。" }
            catch { message = error.localizedDescription }
            operationInProgress = false; refresh()
        }
    }
    private func hold(_ window: NSWindow) { if heldWindows.insert(ObjectIdentifier(window)).inserted { fold.beginHold(); timer?.invalidate() } }
    private func release(_ window: NSWindow) { if heldWindows.remove(ObjectIdentifier(window)) != nil { fold.endHold(); scheduleCollapse() } }
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            release(window)
            if window === paletteWindow { captureTask?.cancel(); refreshInProgress = false; if mode == .allVisible { setMode(.expanded) } }
        }
    }
    func showMenu() {
        let menu = NSMenu(); menu.delegate = self
        func add(_ title: String, _ selector: Selector, key: String = "") {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: key); item.target = self; menu.addItem(item)
        }
        add(mode == .collapsed ? "展开图标" : "折叠图标", #selector(menuToggle))
        add("图标面板…", #selector(menuPalette))
        add("整理全部图标…", #selector(menuArrange))
        menu.addItem(.separator()); add("设置…", #selector(menuSettings), key: ",")
        add("退出 BarFold", #selector(menuQuit), key: "q")
        self.menu = menu; layout.popUp(menu)
    }
    func menuWillOpen(_ menu: NSMenu) { if !menuHeld { menuHeld = true; fold.beginHold(); timer?.invalidate() } }
    func menuDidClose(_ menu: NSMenu) { if menuHeld { menuHeld = false; fold.endHold(); scheduleCollapse() } }
    @objc private func menuToggle() { toggle() }
    @objc private func menuPalette() { showPalette() }
    @objc private func menuArrange() { showPalette(arrange: true) }
    @objc private func menuSettings() { showSettings() }
    @objc private func menuQuit() { NSApp.terminate(nil) }
    func cleanup() { timer?.invalidate(); hoverWork?.cancel(); captureTask?.cancel(); layout.cleanup() }
}
