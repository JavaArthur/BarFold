import AppKit
import BarFoldCore

final class StatusLayout {
    let bar = NSStatusBar.system
    let control: NSStatusItem
    let divider: NSStatusItem
    private(set) var permanent: NSStatusItem?
    private var mode: FoldMode = .expanded
    var onToggle: (() -> Void)?
    var onMenu: (() -> Void)?
    var onHover: (() -> Void)?
    private let actions = StatusActions()
    private var hoverView: HoverView?
    private let prefix: String
    private let defaults: UserDefaults

    init(prefix: String = "BarFold", defaults: UserDefaults = .standard) {
        self.prefix = prefix; self.defaults = defaults
        for (name, position) in [("Control", 0), ("Divider", 1), ("Always", 2)] {
            let key = "NSStatusItem Preferred Position \(prefix).\(name)"
            if defaults.object(forKey: key) == nil { defaults.set(position, forKey: key) }
        }
        divider = bar.statusItem(withLength: 22)
        divider.autosaveName = "\(prefix).Divider"
        control = bar.statusItem(withLength: 30)
        control.autosaveName = "\(prefix).Control"
        control.button?.target = actions
        control.button?.action = #selector(StatusActions.clicked(_:))
        control.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        actions.action = { [weak self] in
            guard let self else { return }
            if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
                self.onMenu?()
            } else { self.onToggle?() }
        }
        configureDivider(divider, title: "│", label: "左侧图标折叠；按住 Command 拖动图标到此线左侧")
        if let button = control.button {
            let view = HoverView(frame: button.bounds)
            view.autoresizingMask = [.width, .height]
            view.onHover = { [weak self] in self?.onHover?() }
            button.addSubview(view); hoverView = view
        }
        apply(.expanded)
    }

    private func configureDivider(_ item: NSStatusItem, title: String, label: String) {
        item.button?.title = title
        item.button?.alignment = .right
        item.button?.font = NSFont.systemFont(ofSize: 16, weight: .light)
        item.button?.toolTip = label
        item.button?.setAccessibilityLabel(label)
    }
    func enablePermanent(_ enabled: Bool) {
        if enabled && permanent == nil {
            let item = bar.statusItem(withLength: 22)
            item.autosaveName = "\(prefix).Always"
            configureDivider(item, title: "┊", label: "始终隐藏分界线；左侧图标仅在整理时显示")
            permanent = item
        } else if !enabled, let item = permanent {
            bar.removeStatusItem(item); permanent = nil
        }
        apply(mode)
    }
    func apply(_ mode: FoldMode) {
        self.mode = mode
        let width = MenuGeometry.blockerLength(screenWidths: NSScreen.screens.map { $0.frame.width })
        divider.length = mode == .collapsed ? width : 22
        permanent?.length = mode == .allVisible ? 22 : width
        control.button?.image = NSImage(systemSymbolName: mode == .collapsed ? "chevron.left" : "chevron.right", accessibilityDescription: "BarFold")
        control.button?.toolTip = mode == .collapsed ? "BarFold · 点击展开，右键打开菜单" : "BarFold · 点击折叠，右键打开菜单"
        control.button?.setAccessibilityLabel(mode == .collapsed ? "BarFold，展开图标" : "BarFold，折叠图标")
    }
    func popUp(_ menu: NSMenu) {
        control.menu = menu
        control.button?.performClick(nil)
        control.menu = nil
    }
    func cleanup() {
        if let permanent { bar.removeStatusItem(permanent) }
        permanent = nil
        bar.removeStatusItem(divider); bar.removeStatusItem(control)
    }
    var dividerRect: CGRect? { divider.button?.window.map { Self.quartzRect($0.frame) } }
    var permanentRect: CGRect? { permanent?.button?.window.map { Self.quartzRect($0.frame) } }
    static func quartzRect(_ rect: CGRect) -> CGRect {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
    }
}
private final class StatusActions: NSObject {
    var action: (() -> Void)?
    @objc func clicked(_ sender: Any?) { action?() }
}
private final class HoverView: NSView {
    var onHover: (() -> Void)?
    private var area: NSTrackingArea?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func updateTrackingAreas() {
        if let area { removeTrackingArea(area) }
        let next = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(next); area = next
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { onHover?() }
}
