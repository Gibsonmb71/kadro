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

            SidebarCommands()
            InspectorCommands()

            CommandMenu("Photo") {
                Button("Add/Search Player…") {
                    appState.captioningModel?.openSearch()
                }
                .keyboardShortcut("/", modifiers: [])
                .disabled(appState.screen != .captioning)

                Button("Flag Photo") {
                    appState.captioningModel?.toggleFlag()
                }
                .keyboardShortcut("f", modifiers: [])
                .disabled(appState.screen != .captioning)

                Button("Carry Previous Players") {
                    appState.captioningModel?.carryPlayersFromPreviousPhoto()
                }
                .keyboardShortcut("c", modifiers: [])
                .disabled(appState.screen != .captioning)

                Divider()

                Button("Save & Next") {
                    appState.captioningModel?.finishCurrentPhotoAndAdvance()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(appState.screen != .captioning)

                Button("Previous Photo") {
                    appState.captioningModel?.navigatePrevious()
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(appState.screen != .captioning)

                Button("Next Photo") {
                    appState.captioningModel?.navigateNext()
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(appState.screen != .captioning)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
