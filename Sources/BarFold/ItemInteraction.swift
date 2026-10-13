import AppKit
import ApplicationServices
import BarFoldCore

enum InteractionFailure: LocalizedError {
    case permission, stale, offscreen, creation, position
    var errorDescription: String? {
        switch self {
        case .permission: return "请先在系统设置中授予 BarFold 辅助功能权限。"
        case .stale: return "图标已变化，请刷新后再试。"
        case .offscreen: return "这个图标仍在屏幕外。请先展开全部图标，或按住 Command 手动调整位置。"
        case .creation: return "无法创建鼠标事件，请稍后再试。"
        case .position: return "系统没有移动这个图标。它可能是固定系统项目；可按住 Command 手动尝试。"
        }
    }
}
@MainActor final class ItemInteraction {
    private(set) var busy = false
    func click(_ item: MenuItem) async throws {
        guard !busy else { return }; busy = true; defer { busy = false }
        let rect = try target(item)
        if let element = item.axElement, let axRect = ItemCatalog.rect(of: element),
           abs(axRect.midX - rect.midX) < 3, abs(axRect.midY - rect.midY) < 3,
           AXUIElementPerformAction(element, kAXPressAction as CFString) == .success { return }
        try await gesture(from: CGPoint(x: rect.midX, y: rect.midY), to: nil)
    }
    func move(_ item: MenuItem, to destination: CGPoint) async throws {
        guard !busy else { return }; busy = true; defer { busy = false }
        let rect = try target(item)
        guard screens.contains(where: { $0.contains(destination) }) else { throw InteractionFailure.offscreen }
        let start = CGPoint(x: rect.midX, y: rect.midY)
        try await gesture(from: start, to: destination)
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard let result = ItemCatalog.currentRect(id: item.id, pid: item.pid), abs(result.midX - start.x) > 2 else {
            throw InteractionFailure.position
        }
    }
    private var screens: [CGRect] { NSScreen.screens.map { StatusLayout.quartzRect($0.frame) } }
    private func target(_ item: MenuItem) throws -> CGRect {
        guard ItemCatalog.accessibilityPermission else { throw InteractionFailure.permission }
        guard let rect = ItemCatalog.currentRect(id: item.id, pid: item.pid) else { throw InteractionFailure.stale }
        guard MenuGeometry.validTarget(rect, on: screens) else { throw InteractionFailure.offscreen }
        return rect
    }
    private func gesture(from start: CGPoint, to destination: CGPoint?) async throws {
        let original = CGEvent(source: nil)?.location
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left),
              let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: destination ?? start, mouseButton: .left) else {
            throw InteractionFailure.creation
        }
        let flags: CGEventFlags = destination == nil ? [] : .maskCommand
        down.flags = flags; up.flags = flags
        // Always release the mouse button, including cancellation during the drag.
        down.post(tap: .cghidEventTap)
        defer {
            up.post(tap: .cghidEventTap)
            if let original { CGWarpMouseCursorPosition(original) }
        }
        try await Task.sleep(nanoseconds: 70_000_000)
        if let destination {
            for step in 1...8 {
                let t = Double(step) / 8
                let point = CGPoint(x: start.x + (destination.x - start.x) * t, y: start.y + (destination.y - start.y) * t)
                guard let drag = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: point, mouseButton: .left) else { throw InteractionFailure.creation }
                drag.flags = .maskCommand; drag.post(tap: .cghidEventTap)
                try await Task.sleep(nanoseconds: 20_000_000)
            }
        }
    }
}
