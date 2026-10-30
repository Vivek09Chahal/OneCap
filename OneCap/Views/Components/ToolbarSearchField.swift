import AppKit
import SwiftUI

/// A native search field owned by an explicitly identified toolbar item.
/// Separate `.searchable` modifiers on swapped pages reuse SwiftUI's reserved
/// toolbar identifier, which can cause AppKit to insert a duplicate item.
struct ToolbarSearchField: NSViewRepresentable {
  @Binding var text: String
  let prompt: String
  var focusRequest = 0

  func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

  func makeNSView(context: Context) -> NSSearchField {
    let field = NSSearchField()
    field.delegate = context.coordinator
    field.sendsSearchStringImmediately = true
    field.placeholderString = prompt
    field.setAccessibilityLabel(prompt)
    field.stringValue = text
    return field
  }

  func updateNSView(_ field: NSSearchField, context: Context) {
    context.coordinator.text = $text
    if field.placeholderString != prompt { field.placeholderString = prompt }
    if field.accessibilityLabel() != prompt { field.setAccessibilityLabel(prompt) }
    if field.stringValue != text { field.stringValue = text }
    if focusRequest > 0 && context.coordinator.lastFocusRequest != focusRequest {
      context.coordinator.lastFocusRequest = focusRequest
      DispatchQueue.main.async { [weak field] in
        guard let field else { return }
        field.window?.makeFirstResponder(field)
      }
    }
  }

  @MainActor final class Coordinator: NSObject, NSSearchFieldDelegate {
    var text: Binding<String>
    var lastFocusRequest = 0

    init(text: Binding<String>) { self.text = text }

    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSSearchField else { return }
      if text.wrappedValue != field.stringValue { text.wrappedValue = field.stringValue }
    }
  }
}
