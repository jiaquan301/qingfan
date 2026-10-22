import AppKit
import CoreGraphics

// Report all application windows, including windows hidden behind another app.
// The calling script captures a specific window ID rather than assuming that
// the application's pixels appear in a full-screen screenshot.
let entries = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for item in entries {
    let owner = item[kCGWindowOwnerName as String] as? String ?? ""
    if owner.lowercased().contains("qingfan") || owner.contains("青番") {
        let number = item[kCGWindowNumber as String] as? Int ?? 0
        let layer = item[kCGWindowLayer as String] as? Int ?? -1
        let onScreen = item[kCGWindowIsOnscreen as String] as? Bool ?? false
        let alpha = item[kCGWindowAlpha as String] as? Double ?? 0
        let bounds = item[kCGWindowBounds as String] ?? [:]
        print("QINGFAN_MAC_WINDOW id=\(number) onscreen=\(onScreen) layer=\(layer) alpha=\(alpha) bounds=\(bounds)")
    }
}
