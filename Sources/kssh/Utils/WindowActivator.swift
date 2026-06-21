import SwiftUI
import AppKit

/// Helpers for surfacing windows from an accessory (`LSUIElement`) menu-bar app.
///
/// As an `.accessory` app, kssh cannot bring a window to the front on its own — so
/// `openWindow(id:)` and `SettingsLink` create the window but it stays behind other
/// apps with no focus, looking like nothing happened. We temporarily switch to
/// `.regular`, activate the app (which fronts the window), and switch back to
/// `.accessory` once the user closes it so the app stays out of the Dock.
enum WindowActivator {
    /// Promotes the app so a just-opened window can be focused and brought forward.
    static func activate() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Returns the app to accessory mode if no visible windows remain. Called when a
    /// managed window closes. Deferred to the next runloop tick so the closing window
    /// is no longer counted.
    static func relinquishIfNoWindows() {
        DispatchQueue.main.async {
            let hasVisibleWindow = NSApp.windows.contains { window in
                window.isVisible && window.canBecomeMain && !(window is NSPanel)
            }
            if !hasVisibleWindow {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

extension View {
    /// Attaches activation lifecycle to a managed window: brings it to the front on
    /// appear and relinquishes accessory mode on disappear.
    func managedWindowActivation() -> some View {
        onAppear { WindowActivator.activate() }
            .onDisappear { WindowActivator.relinquishIfNoWindows() }
    }
}
