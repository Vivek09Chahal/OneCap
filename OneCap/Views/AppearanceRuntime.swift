import AppKit
import DLS
import SwiftUI

/// AppKit preferences shared by all workspace windows.
@MainActor enum AppearanceRuntime {
    private static var pointerMonitor: Any?
    private static var originalIcon: NSImage?

    static func icon(named name: String) -> NSImage {
        if name == "Default" { return originalIcon ?? NSImage(named: NSImage.applicationIconName) ?? NSImage() }
        return NSImage(size: NSSize(width: 256, height: 256), flipped: false) { rect in
            NSColor(calibratedRed: 0.22, green: 0.26, blue: 0.66, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 16, dy: 16), xRadius: 48, yRadius: 48).fill()
            let symbol = NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 140, weight: .medium))
            symbol?.draw(in: rect.insetBy(dx: 52, dy: 60))
            return true
        }
    }

    static func apply(_ settings: DLSVisualPreferences) {
        if originalIcon == nil { originalIcon = NSImage(named: NSImage.applicationIconName)?.copy() as? NSImage }
        NSApp.applicationIconImage = settings.dockIcon == "Default" ? originalIcon : icon(named: settings.dockIcon)
        UserDefaults.standard.set(settings.fontSmoothing ? 2 : 0, forKey: "AppleFontSmoothing")
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor); self.pointerMonitor = nil }
        NSCursor.arrow.set()
        if settings.pointerCursors {
            pointerMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
                MainActor.assumeIsolated {
                    if let element = event.window?.accessibilityHitTest(NSEvent.mouseLocation) as? any NSAccessibilityProtocol,
                       let role = element.accessibilityRole()?.rawValue,
                       ["AXButton", "AXLink", "AXPopUpButton", "AXCheckBox", "AXRadioButton", "AXMenuButton", "AXDisclosureTriangle"].contains(role) {
                        DispatchQueue.main.async { NSCursor.pointingHand.set() }
                    } else if NSCursor.current == .pointingHand {
                        let hit = event.window?.contentView?.hitTest(event.locationInWindow)
                        if hit is NSTextView || hit is NSTextField {
                            DispatchQueue.main.async { NSCursor.iBeam.set() }
                        } else {
                            DispatchQueue.main.async { NSCursor.arrow.set() }
                        }
                    }
                }
                return event
            }
        }
        for window in NSApp.windows { window.contentView?.needsDisplay = true }
    }
}

struct AppearanceRuntimeModifier: ViewModifier {
    @AppStorage(DLSVisualPreferences.storageKey) private var data = Data()
    func body(content: Content) -> some View {
        content.task(id: data) { AppearanceRuntime.apply(DLSVisualPreferences.decode(data)) }
    }
}

extension View {
    func appearanceRuntimePreferences() -> some View { modifier(AppearanceRuntimeModifier()) }
    @ViewBuilder func appearanceSidebar(_ theme: DLSTheme) -> some View {
        if theme.preferences.translucentSidebar {
            self.background(theme.colors.sidebar.opacity(0.85)).background(.ultraThinMaterial)
        }
        else { self.background(theme.colors.sidebar) }
    }
}

/// Honor the per-app smoothing preference in native code editors.
final class AppearanceTextView: NSTextView {
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let smooth = DLSVisualPreferences.saved.fontSmoothing
        NSGraphicsContext.current?.shouldAntialias = smooth
        NSGraphicsContext.current?.cgContext.setShouldSmoothFonts(smooth)
        super.draw(dirtyRect)
    }
}
