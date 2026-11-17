import AppKit
import SwiftUI

/// Native SwiftUI fields on macOS 12+, with AppKit focus/commit callbacks on Big Sur.
struct CompatibleTextField: View {
    let placeholder: String
    @Binding var text: String
    var bordered = true
    var onCommit: () -> Void = {}
    var onFocus: (Bool) -> Void = { _ in }

    var body: some View {
        if #available(macOS 12, *) {
            ModernTextField(placeholder: placeholder, text: $text, bordered: bordered,
                            onCommit: onCommit, onFocus: onFocus)
        } else {
            AppKitTextField(placeholder: placeholder, text: $text, bordered: bordered,
                            onCommit: onCommit, onFocus: onFocus)
        }
    }
}

@available(macOS 12, *)
private struct ModernTextField: View {
    let placeholder: String
    @Binding var text: String
    let bordered: Bool
    let onCommit: () -> Void
    let onFocus: (Bool) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if bordered {
                TextField(placeholder, text: $text).textFieldStyle(.roundedBorder)
            } else {
                TextField(placeholder, text: $text).textFieldStyle(.plain)
            }
        }
        .focused($focused)
        .onSubmit(onCommit)
        .onChange(of: focused) { onFocus($0) }
    }
}

private struct AppKitTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var bordered = true
    var onCommit: () -> Void = {}
    var onFocus: (Bool) -> Void = { _ in }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.bezelStyle = .roundedBezel
        field.isBezeled = bordered
        field.drawsBackground = bordered
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.commit)
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = placeholder
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AppKitTextField
        init(_ parent: AppKitTextField) { self.parent = parent }
        func controlTextDidChange(_ obj: Notification) { if let field = obj.object as? NSTextField { parent.text = field.stringValue } }
        func controlTextDidBeginEditing(_ obj: Notification) { parent.onFocus(true) }
        func controlTextDidEndEditing(_ obj: Notification) { parent.onFocus(false) }
        @objc func commit() { parent.onCommit() }
    }
}
