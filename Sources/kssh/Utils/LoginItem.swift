import Foundation
import ServiceManagement

/// Thin wrapper around `SMAppService.mainApp` (macOS 13+) for launch-at-login. Kept
/// isolated so the ServiceManagement dependency stays in one place. All calls are no-ops
/// that swallow errors into a boolean result — the UI just reflects the resulting state.
enum LoginItem {
    /// Whether kssh is currently registered to launch at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers or unregisters the app as a login item. Returns the resulting enabled
    /// state (re-read from the service) so the caller can sync its toggle even on failure.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Registration can fail (e.g. unsigned/dev builds). Fall through and report
            // the actual current status rather than the requested one.
        }
        return isEnabled
    }
}
