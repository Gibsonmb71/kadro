import SwiftUI

private enum LibraryDestination: String, CaseIterable, Hashable, Identifiable {
    case sessions
    case rosters

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sessions:
            return "Sessions"
        case .rosters:
            return "Rosters"
        }
    }

    var systemImage: String {
        switch self {
        case .sessions:
            return "photo.on.rectangle"
        case .rosters:
            return "person.3"
        }
    }
}

/// The library shell for the app. SwiftUI owns the sidebar and split-view
/// presentation so Kadro automatically follows the active macOS design.
struct AppNavigationView: View {
    @EnvironmentObject private var appState: AppState
    @StateCompat private var selection: LibraryDestination = .sessions

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(LibraryDestination.allCases) { destination in
                        Label {
                            Text(destination.title)
                                .padding(.leading, 5)
                        } icon: {
                            Image(systemName: destination.systemImage)
                                .frame(width: 18, alignment: .center)
                        }
                            .tag(destination)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 360)
            .navigationTitle(AppBrand.name)
        } detail: {
            switch selection {
            case .sessions:
                StartView()
            case .rosters:
                RosterManagementView()
            }
        }
        .onAppear {
            synchronizeSelection(with: appState.screen)
        }
        .onChange(of: selection) { _, newSelection in
            switch newSelection {
            case .sessions:
                if appState.screen != .start {
                    appState.goHome()
                }
            case .rosters:
                if appState.screen != .rosters {
                    appState.showRosters(returnTo: .start)
                }
            }
        }
        .onChange(of: appState.screen) { _, newScreen in
            synchronizeSelection(with: newScreen)
        }
    }

    private func synchronizeSelection(with screen: AppScreen) {
        switch screen {
        case .rosters:
            selection = .rosters
        default:
            selection = .sessions
        }
    }
}
