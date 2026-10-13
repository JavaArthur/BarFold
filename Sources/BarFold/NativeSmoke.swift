import AppKit
import BarFoldCore

@MainActor final class NativeSmoke {
    let model: AppModel
    let reportURL: URL
    var fixtures: [NSStatusItem] = []
    var checks: [[String: Any]] = []
    init(model: AppModel, reportURL: URL) { self.model = model; self.reportURL = reportURL }
    func run() {
        Task { @MainActor in
            UserDefaults.standard.set(2, forKey: "NSStatusItem Preferred Position BarFold.Smoke.Fixture")
            let item = NSStatusBar.system.statusItem(withLength: 60)
            item.autosaveName = "BarFold.Smoke.Fixture"
            item.button?.title = "BF.TEST"
            fixtures.append(item)
            model.setMode(.allVisible)
            await settle()
            record("control has native window", model.layout.control.button?.window != nil)
            record("control stays on screen while expanded", controlVisible)
            let expanded = item.button?.window?.frame ?? .zero
            let dividerExpanded = model.layout.divider.button?.window?.frame ?? .zero
            record("expanded fixture is actually on screen", NSScreen.screens.contains { $0.frame.contains(CGPoint(x: expanded.midX, y: expanded.midY)) })
            model.setMode(.collapsed)
            await settle()
            record("control stays on screen while collapsed", controlVisible)
            let collapsed = item.button?.window?.frame ?? .zero
            let dividerCollapsed = model.layout.divider.button?.window?.frame ?? .zero
            record("native divider window expands", dividerCollapsed.width > dividerExpanded.width + 1000)
            record("native fixture moves left or becomes invisible", collapsed.minX < expanded.minX - 1000 || item.button?.window?.isVisible == false)
            model.setMode(.expanded)
            await settle()
            let restored = item.button?.window?.frame ?? .zero
            record("native fixture returns after expansion", abs(restored.minX - expanded.minX) < 3)
            model.layout.enablePermanent(true)
            model.setMode(.expanded); await settle()
            record("always-hidden blocker active", (model.layout.permanent?.length ?? 0) >= 5000)
            model.setMode(.allVisible); await settle()
            record("arrange reveals both sections", model.layout.divider.length == 22 && model.layout.permanent?.length == 22)
            model.layout.enablePermanent(false)
            record("disabled permanent divider removed", model.layout.permanent == nil)
            model.showSettings(); await settle()
            record("settings window opens", NSApp.windows.contains { $0.title == "BarFold · 设置" && $0.isVisible })
            let permissionBefore = ItemCatalog.accessibilityPermission
            model.showPalette(arrange: true); await settle()
            record("palette opens", NSApp.windows.contains { $0.title == "BarFold · 图标面板" && $0.isVisible })
            record("discovery does not request accessibility", permissionBefore == ItemCatalog.accessibilityPermission)
            let payload: [String: Any] = ["checks": checks, "failed": checks.filter { !($0["passed"] as? Bool ?? false) }.count,
                "dividerExpanded": NSStringFromRect(dividerExpanded), "controlFrame": NSStringFromRect(model.layout.control.button?.window?.frame ?? .zero), "fixtureExpanded": NSStringFromRect(expanded), "fixtureCollapsed": NSStringFromRect(collapsed),
                "fixtureRestored": NSStringFromRect(restored), "screenRecordingGranted": ItemCatalog.screenPermission,
                "accessibilityGranted": ItemCatalog.accessibilityPermission, "macOS": ProcessInfo.processInfo.operatingSystemVersionString]
            do {
                let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: reportURL, options: .atomic)
                print(String(data: data, encoding: .utf8)!)
            } catch { fputs("Smoke report failed: \(error)\n", stderr) }
            NSApp.terminate(nil)
        }
    }
    private var controlVisible: Bool {
        guard let window = model.layout.control.button?.window else { return false }
        return NSScreen.screens.contains { $0.frame.contains(CGPoint(x: window.frame.midX, y: window.frame.midY)) }
    }
    private func settle() async { try? await Task.sleep(nanoseconds: 500_000_000) }
    private func record(_ name: String, _ result: Bool) { checks.append(["name": name, "passed": result]) }
    func cleanup() { for item in fixtures { NSStatusBar.system.removeStatusItem(item) }; fixtures.removeAll() }
}
