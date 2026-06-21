import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct ksshApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = StatusViewModel()

    var body: some Scene {
        MenuBarExtra("kssh", systemImage: "key.horizontal") {
            MenuBarView(viewModel: viewModel, store: viewModel.store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .managedWindowActivation()
        }

        Window("Create GPG Key", id: "create-gpg-key") {
            CreateGPGKeyView(viewModel: viewModel)
                .managedWindowActivation()
        }
        .windowResizability(.contentSize)

        Window("Manage Git Profiles", id: "manage-git-profiles") {
            ManageProfilesView(store: viewModel.store)
                .managedWindowActivation()
        }
        .windowResizability(.contentSize)
    }
}
