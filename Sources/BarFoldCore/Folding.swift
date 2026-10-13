import Foundation
import CoreGraphics

public enum FoldMode: String, Codable { case collapsed, expanded, allVisible }
public enum ItemSection: String, Codable, CaseIterable { case visible, hidden, alwaysHidden }

public struct FoldState: Equatable {
    public private(set) var mode: FoldMode = .expanded
    public private(set) var generation: UInt = 0
    public private(set) var holdCount = 0
    public init() {}
    public mutating func set(_ mode: FoldMode) { self.mode = mode; generation &+= 1 }
    public mutating func toggle() { set(mode == .collapsed ? .expanded : .collapsed) }
    public mutating func beginHold() { holdCount += 1; generation &+= 1 }
    public mutating func endHold() { holdCount = max(0, holdCount - 1); generation &+= 1 }
    public func mayAutoCollapse(ticket: UInt) -> Bool {
        ticket == generation && mode != .collapsed && holdCount == 0
    }
}

public enum MenuGeometry {
    public static func blockerLength(screenWidths: [Double]) -> Double {
        max(5000, screenWidths.filter { $0.isFinite && $0 > 0 }.reduce(0, +) + 1000)
    }
    public static func section(item: CGRect, divider: CGRect, alwaysDivider: CGRect?) -> ItemSection {
        if let alwaysDivider, item.midX < alwaysDivider.maxX { return .alwaysHidden }
        return item.midX < divider.maxX ? .hidden : .visible
    }
    public static func validTarget(_ rect: CGRect, on screens: [CGRect]) -> Bool {
        guard rect.width >= 4, rect.width <= 200, rect.height >= 8, rect.height <= 80,
              [rect.minX, rect.minY, rect.width, rect.height].allSatisfy({ $0.isFinite }) else { return false }
        return screens.contains { $0.contains(CGPoint(x: rect.midX, y: rect.midY)) }
    }
}

public struct Preferences: Codable, Equatable {
    public var version = 1
    public var autoCollapseSeconds: Double = 8
    public var launchCollapsed = false
    public var alwaysHiddenEnabled = false
    public var hoverToExpand = false
    public var thumbnailsEnabled = false
    public var shortcutEnabled = true
    public var shortcutKeyCode: UInt32 = 11 // B
    public var shortcutModifiers: UInt32 = 0x900 // option + command (Carbon)
    public var setupCompleted = false
    public init() {}
    public func validated() throws -> Preferences {
        guard version == 1 else { throw ConfigurationError.unsupportedVersion }
        guard autoCollapseSeconds.isFinite, (0...300).contains(autoCollapseSeconds),
              shortcutKeyCode <= 127,
              shortcutModifiers & ~UInt32(0x1f00) == 0,
              !shortcutEnabled || shortcutModifiers & UInt32(0x1900) != 0 else {
            throw ConfigurationError.invalidValues
        }
        return self
    }
}
public enum ConfigurationError: Error { case unsupportedVersion, invalidValues }

public final class PreferencesStore {
    public let url: URL
    public private(set) var isWritable = true
    public init(url: URL) { self.url = url }
    public func load() throws -> Preferences {
        guard FileManager.default.fileExists(atPath: url.path) else { return Preferences() }
        do { return try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url)).validated() }
        catch { isWritable = false; throw error }
    }
    public func save(_ preferences: Preferences) throws {
        guard isWritable else { throw ConfigurationError.invalidValues }
        _ = try preferences.validated()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(preferences).write(to: url, options: .atomic)
    }
}
