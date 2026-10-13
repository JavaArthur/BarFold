import AppKit
import BarFoldCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    var smoke: NativeSmoke?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        let isSmoke = arguments.contains("--native-smoke")
        if !isSmoke, let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil); return
        }
        let config: URL
        if let index = arguments.firstIndex(of: "--config"), arguments.indices.contains(index + 1) {
            config = URL(fileURLWithPath: arguments[index + 1])
        } else {
            config = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("BarFold/config.json")
        }
        let appMenu = NSMenu()
        let rootItem = NSMenuItem(); appMenu.addItem(rootItem)
        let actions = NSMenu(); rootItem.submenu = actions
        let quit = NSMenuItem(title: "退出 BarFold", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp; actions.addItem(quit); NSApp.mainMenu = appMenu
        let model = AppModel(configURL: config, testMode: isSmoke); self.model = model
        if isSmoke {
            let report: String
            if let i = arguments.firstIndex(of: "--report"), arguments.indices.contains(i + 1) { report = arguments[i + 1] }
            else { report = "/tmp/BarFold-smoke.json" }
            let smoke = NativeSmoke(model: model, reportURL: URL(fileURLWithPath: report)); self.smoke = smoke
            smoke.run()
        } else { model.start(); if arguments.contains("--settings") { model.showSettings() } }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model?.showSettings(); return true
    }
    func applicationWillTerminate(_ notification: Notification) { smoke?.cleanup(); model?.cleanup() }
}
MainActor.assumeIsolated {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    application.delegate = delegate
    withExtendedLifetime(delegate) { application.run() }
}
