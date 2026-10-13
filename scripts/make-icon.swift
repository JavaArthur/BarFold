import AppKit
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let set = root.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let n = CGFloat(pixels)
        let background = NSBezierPath(roundedRect: NSRect(x: n * 0.05, y: n * 0.05, width: n * 0.9, height: n * 0.9), xRadius: n * 0.2, yRadius: n * 0.2)
        NSGradient(starting: NSColor(calibratedRed: 0.05, green: 0.30, blue: 0.32, alpha: 1), ending: NSColor(calibratedRed: 0.08, green: 0.65, blue: 0.59, alpha: 1))!.draw(in: background, angle: 60)
        NSColor.white.withAlphaComponent(0.92).setFill()
        NSBezierPath(roundedRect: NSRect(x: n * 0.20, y: n * 0.62, width: n * 0.60, height: n * 0.105), xRadius: n * 0.04, yRadius: n * 0.04).fill()
        NSColor.white.withAlphaComponent(0.62).setFill()
        for i in 0..<3 { NSBezierPath(ovalIn: NSRect(x: n * (0.24 + CGFloat(i) * 0.16), y: n * 0.43, width: n * 0.08, height: n * 0.08)).fill() }
        let arrow = NSBezierPath(); arrow.lineWidth = n * 0.045; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
        arrow.move(to: NSPoint(x: n * 0.40, y: n * 0.32)); arrow.line(to: NSPoint(x: n * 0.50, y: n * 0.24)); arrow.line(to: NSPoint(x: n * 0.60, y: n * 0.32)); NSColor.white.setStroke(); arrow.stroke()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: set.appendingPathComponent(name))
    }
}
let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", set.path, "-o", root.appendingPathComponent("AppIcon.icns").path]
try task.run(); task.waitUntilExit(); guard task.terminationStatus == 0 else { exit(1) }
try FileManager.default.removeItem(at: set)
