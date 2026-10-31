import SwiftUI
import AppKit

@main
@MainActor
struct OpenCodeHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var workspace = Workspace.shared
    @StateObject private var settings = HubSettings.shared

    var body: some Scene {
        WindowGroup("OpenCode Hub") {
            RootView()
                .environmentObject(workspace)
                .environmentObject(AppLog.shared)
                .environmentObject(settings)
                .frame(minWidth: 1040, minHeight: 680)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .sidebar) {
                Button("Refresh") { workspace.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
                Button("Reveal opencode.json") {
                    workspace.reveal(workspace.config.url)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(workspace)
                .environmentObject(AppLog.shared)
                .environmentObject(settings)
                .frame(width: 560)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
