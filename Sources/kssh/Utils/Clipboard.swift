import AppKit
import SwiftUI

enum Clipboard {
    /// Writes a plain-text string to the general pasteboard. No-op on empty.
    static func copy(_ string: String) {
        guard !string.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}

extension View {
    /// Adds a right-click "Copy …" context menu that copies `value` to the clipboard.
    /// The menu item is disabled (and copy is a no-op) when `value` is empty.
    func copyable(_ value: String, label: String = "Copy") -> some View {
        contextMenu {
            Button {
                Clipboard.copy(value)
            } label: {
                Label(label, systemImage: "doc.on.doc")
            }
            .disabled(value.isEmpty)
        }
    }
}
