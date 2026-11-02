import AppKit
import DLS
import SwiftUI

/// AppKit preferences shared by all workspace windows.
@MainActor enum AppearanceRuntime {
    private static var pointerMonitor: Any?
    static func apply(_ settings: DLSVisualPreferences) {
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
