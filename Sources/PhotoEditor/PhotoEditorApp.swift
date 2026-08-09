import Darwin
import SwiftUI

@main
struct KadroApp: App {
    @StateObject private var appState = AppState()

    init() {
        if CommandLine.arguments.contains("--self-test") {
            MainActor.assumeIsolated {
                KadroSelfTest.run()
            }
            Darwin.exit(0)
        }
    }

    var body: some Scene {
        WindowGroup("Sessions") {
            RootView()
                .environmentObject(appState)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Photo Session") {
                    appState.startNewSession()
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("Open Session File…") {
                    appState.openSessionFile()
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
