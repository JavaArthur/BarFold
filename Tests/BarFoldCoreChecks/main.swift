import Foundation
import CoreGraphics
import BarFoldCore

var total = 0
var failures = 0
func check(_ name: String, _ body: () throws -> Bool) {
    total += 1
    do {
        if try body() { print("PASS \(name)") }
        else { failures += 1; print("FAIL \(name)") }
    } catch { failures += 1; print("FAIL \(name): \(error)") }
}
check("stale timer cannot collapse a newer expansion") {
    var state = FoldState(); let old = state.generation
    state.set(.collapsed); state.set(.expanded)
    return !state.mayAutoCollapse(ticket: old) && state.mayAutoCollapse(ticket: state.generation)
}
check("multiple windows hold independently") {
    var state = FoldState(); state.beginHold(); state.beginHold(); state.endHold()
    guard !state.mayAutoCollapse(ticket: state.generation) else { return false }
    state.endHold(); return state.mayAutoCollapse(ticket: state.generation)
}
check("closing a hold invalidates previously scheduled callbacks") {
    var state = FoldState(); let old = state.generation; state.beginHold(); state.endHold()
    return !state.mayAutoCollapse(ticket: old)
}
check("toggle from arrange collapses; next toggle keeps always-hidden section closed") {
    var state = FoldState(); state.set(.allVisible); state.toggle()
    guard state.mode == .collapsed else { return false }
    state.toggle(); return state.mode == .expanded
}
check("blocker spans large multi-display desktops") { MenuGeometry.blockerLength(screenWidths: [6016, 3840]) > 9856 }
check("invalid screen dimensions do not poison layout") { MenuGeometry.blockerLength(screenWidths: [.nan, .infinity, -1, 1920]) == 5000 }
let divider = CGRect(x: 800, y: 0, width: 22, height: 24)
let permanent = CGRect(x: 500, y: 0, width: 22, height: 24)
check("three groups follow spatial boundaries") {
    MenuGeometry.section(item: CGRect(x: 900, y: 0, width: 24, height: 24), divider: divider, alwaysDivider: permanent) == .visible &&
    MenuGeometry.section(item: CGRect(x: 600, y: 0, width: 24, height: 24), divider: divider, alwaysDivider: permanent) == .hidden &&
    MenuGeometry.section(item: CGRect(x: 400, y: 0, width: 24, height: 24), divider: divider, alwaysDivider: permanent) == .alwaysHidden
}
check("collapsed separator uses its right edge, not oversized midpoint") {
    let wide = CGRect(x: -4200, y: 0, width: 5000, height: 24)
    return MenuGeometry.section(item: CGRect(x: -100, y: 0, width: 24, height: 24), divider: wide, alwaysDivider: nil) == .hidden
}
check("off-screen and oversized windows are not click targets") {
    let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    return !MenuGeometry.validTarget(CGRect(x: -5000, y: 0, width: 24, height: 24), on: [screen]) &&
    !MenuGeometry.validTarget(CGRect(x: 0, y: 0, width: 5000, height: 24), on: [screen]) &&
    MenuGeometry.validTarget(CGRect(x: 1800, y: 0, width: 24, height: 24), on: [screen])
}
let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temp) }
check("configuration round-trip preserves intended values") {
    let store = PreferencesStore(url: temp.appendingPathComponent("valid.json"))
    var preferences = Preferences(); preferences.alwaysHiddenEnabled = true; preferences.autoCollapseSeconds = 15
    try store.save(preferences); return try store.load() == preferences
}
check("damaged configuration is preserved and blocks overwrite") {
    let url = temp.appendingPathComponent("broken.json"); let bytes = Data("{broken".utf8); try bytes.write(to: url)
    let store = PreferencesStore(url: url)
    do { _ = try store.load(); return false } catch {}
    do { try store.save(Preferences()); return false } catch {}
    let preserved = try Data(contentsOf: url)
    return !store.isWritable && preserved == bytes
}
check("future configuration version is not silently downgraded") {
    let url = temp.appendingPathComponent("future.json")
    var preferences = Preferences(); preferences.version = 99
    let data = try JSONEncoder().encode(preferences); try data.write(to: url)
    let store = PreferencesStore(url: url)
    do { _ = try store.load(); return false } catch {}
    let preserved = try Data(contentsOf: url)
    return !store.isWritable && preserved == data
}
check("unsafe shortcut and invalid timeout rejected") {
    var preferences = Preferences(); preferences.shortcutModifiers = 0
    do { _ = try preferences.validated(); return false } catch {}
    preferences = Preferences(); preferences.autoCollapseSeconds = -3
    do { _ = try preferences.validated(); return false } catch { return true }
}
print("\(total - failures)/\(total) checks passed")
exit(failures == 0 ? 0 : 1)
