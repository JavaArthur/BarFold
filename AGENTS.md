# BarFold

- Native macOS 14+ menu-bar manager, built with Swift Package Manager and AppKit/SwiftUI. No external packages.
- Sources/BarFoldCore contains deterministic folding, geometry, and configuration logic. Sources/BarFold contains macOS adapters and UI.
- Keep the control item visible. Separate normal-hidden and always-hidden sections. Quitting removes every owned status item.
- Never change another app's preferences or system-wide menu-bar spacing. Move an item only after explicit user interaction and accessibility authorization, using freshly validated visible coordinates.
- Screen recording is optional and used only for icon thumbnails. Do not capture the desktop or store screenshots. No telemetry or network code.
- Configuration belongs to Application Support/BarFold/config.json. Preserve damaged or unsupported configuration without overwriting it.
- Run swift run BarFoldCoreChecks, scripts/build-app.sh, and scripts/smoke.sh for behavior changes. Keep build, native smoke, and permission-dependent verification distinct.
- Do not commit build outputs, user configuration, third-party binaries, or reverse-engineering evidence.
