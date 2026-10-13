import AppKit
import ScreenCaptureKit
import ApplicationServices
import BarFoldCore

struct MenuItem: Identifiable {
    var id: CGWindowID
    var pid: pid_t
    var title: String
    var appName: String
    var rect: CGRect
    var section: ItemSection
    var image: NSImage?
    var isScreenshot = false
    var axElement: AXUIElement?
}

final class ItemCatalog {
    static var screenPermission: Bool { CGPreflightScreenCaptureAccess() }
    static var accessibilityPermission: Bool { AXIsProcessTrusted() }
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    static func requestScreenRecording() { _ = CGRequestScreenCaptureAccess() }

    func discover(divider: CGRect, always: CGRect?) -> [MenuItem] {
        let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let own = ProcessInfo.processInfo.processIdentifier
        var results: [MenuItem] = []
        for value in list {
            guard let layer = value[kCGWindowLayer as String] as? Int, layer == 25,
                  let id = value[kCGWindowNumber as String] as? UInt32,
                  let pid = value[kCGWindowOwnerPID as String] as? Int32, pid != own,
                  let dictionary = value[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dictionary),
                  rect.width >= 4, rect.width <= 200, rect.height >= 8, rect.height <= 80,
                  abs(rect.midY - divider.midY) < 12 else { continue }
            let app = NSRunningApplication(processIdentifier: pid)
            let name = app?.localizedName ?? value[kCGWindowOwnerName as String] as? String ?? "未知应用"
            let title = value[kCGWindowName as String] as? String ?? ""
            if title.contains("StatusItemClone") || title.contains("Status Item Clone") { continue }
            results.append(MenuItem(id: id, pid: pid, title: title.isEmpty ? name : title, appName: name, rect: rect,
                                    section: MenuGeometry.section(item: rect, divider: divider, alwaysDivider: always), image: app?.icon))
        }
        if Self.accessibilityPermission { enrichWithAccessibility(&results) }
        results.sort { $0.rect.minX < $1.rect.minX }
        var unknown = 0
        for index in results.indices where results[index].axElement == nil {
            if NSRunningApplication(processIdentifier: results[index].pid)?.bundleIdentifier == "com.apple.controlcenter" &&
                (results[index].title == results[index].appName || results[index].title.isEmpty) {
                unknown += 1; results[index].title = "待识别图标 \(unknown)"
            }
        }
        return results
    }

    private func enrichWithAccessibility(_ items: inout [MenuItem]) {
        for app in NSWorkspace.shared.runningApplications where app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            let process = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(process, 0.08)
            var menu: CFTypeRef?
            guard AXUIElementCopyAttributeValue(process, kAXExtrasMenuBarAttribute as CFString, &menu) == .success,
                  let menu, CFGetTypeID(menu) == AXUIElementGetTypeID() else { continue }
            let menuElement = unsafeBitCast(menu, to: AXUIElement.self)
            var children: CFTypeRef?
            guard AXUIElementCopyAttributeValue(menuElement, kAXChildrenAttribute as CFString, &children) == .success,
                  let elements = children as? [AXUIElement] else { continue }
            for element in elements {
                AXUIElementSetMessagingTimeout(element, 0.08)
                guard let rect = Self.rect(of: element) else { continue }
                guard let index = items.indices.first(where: {
                    abs(items[$0].rect.midX - rect.midX) < 3 && abs(items[$0].rect.midY - rect.midY) < 3
                }) else { continue }
                items[index].axElement = element
                items[index].appName = app.localizedName ?? items[index].appName
                var text: CFTypeRef?
                for attribute in [kAXTitleAttribute, kAXDescriptionAttribute] {
                    if AXUIElementCopyAttributeValue(element, attribute as CFString, &text) == .success,
                       let name = text as? String, !name.isEmpty { items[index].title = name; break }
                }
            }
        }
    }
    static func rect(of element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero; var dimensions = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
    static func currentRect(id: CGWindowID, pid: pid_t) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]],
              let window = list.first(where: { ($0[kCGWindowNumber as String] as? UInt32) == id && ($0[kCGWindowOwnerPID as String] as? Int32) == pid }),
              let value = window[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: value)
    }
    func thumbnails(for items: [MenuItem]) async -> [CGWindowID: NSImage] {
        guard Self.screenPermission else { return [:] }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            let requested = Set(items.map(\.id)); var images: [CGWindowID: NSImage] = [:]
            for window in content.windows where requested.contains(window.windowID) {
                let filter = SCContentFilter(desktopIndependentWindow: window)
                let config = SCStreamConfiguration()
                config.width = max(1, min(400, Int(window.frame.width * 2)))
                config.height = max(1, min(160, Int(window.frame.height * 2)))
                config.showsCursor = false
                config.ignoreShadowsSingleWindow = true
                if let cgImage = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                    images[window.windowID] = NSImage(cgImage: cgImage, size: window.frame.size)
                }
                if Task.isCancelled { break }
            }
            return images
        } catch { return [:] }
    }
}
