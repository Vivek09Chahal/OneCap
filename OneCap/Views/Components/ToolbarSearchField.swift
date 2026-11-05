import AppKit
import DLS
import SwiftUI

/// A native search field owned by an explicitly identified toolbar item.
/// Separate `.searchable` modifiers on swapped pages reuse SwiftUI's reserved
/// toolbar identifier, which can cause AppKit to insert a duplicate item.
struct ToolbarSearchField: NSViewRepresentable {
  @Environment(\.dlsTheme) private var theme
  @Binding var text: String
  let prompt: String
  var focusRequest = 0

  func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

  func makeNSView(context: Context) -> NSSearchField {
    NavigationTrace.mark("search field make BEGIN")
    defer { NavigationTrace.mark("search field make END") }
    let field = NSSearchField()
    field.controlSize = .small
    field.delegate = context.coordinator
    field.sendsSearchStringImmediately = true
    field.placeholderString = prompt
    field.setAccessibilityLabel(prompt)
    field.stringValue = text
    return field
  }

  func updateNSView(_ field: NSSearchField, context: Context) {
    NavigationTrace.mark("search field update BEGIN")
    defer { NavigationTrace.mark("search field update END") }
    context.coordinator.text = $text
    let font = theme.profile.nsFont(size: theme.profile.uiSize)
    if field.font != font { field.font = font }
    if field.placeholderString != prompt { field.placeholderString = prompt }
    if field.accessibilityLabel() != prompt { field.setAccessibilityLabel(prompt) }
    if field.stringValue != text { field.stringValue = text }
    if focusRequest > 0 && context.coordinator.lastFocusRequest != focusRequest {
      context.coordinator.lastFocusRequest = focusRequest
      let coordinator = context.coordinator
      DispatchQueue.main.async { [weak field, weak coordinator] in
        NavigationTrace.mark("search queued focus callback; active=\(coordinator?.isActive == true)")
        guard coordinator?.isActive == true,
              let field, let window = field.window,
              window.canBecomeKey, window.isVisible,
              !field.isHiddenOrHasHiddenAncestor else { return }
        NavigationTrace.mark("search BEFORE makeFirstResponder")
        let accepted = window.makeFirstResponder(field)
        NavigationTrace.mark("search AFTER makeFirstResponder; accepted=\(accepted)")
      }
    }
  }

  static func dismantleNSView(_ field: NSSearchField, coordinator: Coordinator) {
    NavigationTrace.mark("search dismantle BEGIN")
    defer { NavigationTrace.mark("search dismantle END") }
    coordinator.isActive = false
    field.delegate = nil
    if field.currentEditor() != nil { field.window?.makeFirstResponder(nil) }
  }

  @MainActor final class Coordinator: NSObject, NSSearchFieldDelegate {
    var text: Binding<String>
    var lastFocusRequest = 0
    var isActive = true

    init(text: Binding<String>) { self.text = text }

    func controlTextDidChange(_ notification: Notification) {
      guard isActive, let field = notification.object as? NSSearchField else { return }
      if text.wrappedValue != field.stringValue { text.wrappedValue = field.stringValue }
    }
  }
}
