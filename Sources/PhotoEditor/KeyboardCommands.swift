@preconcurrency import AppKit
import Foundation
import SwiftUI

@MainActor
final class CaptioningCommandController {
    weak var viewModel: CaptioningViewModel?

    init(viewModel: CaptioningViewModel) {
        self.viewModel = viewModel
    }

    func handle(keyCode: UInt16, characters: String, modifierRawValue: UInt) -> Bool {
        guard let viewModel else { return false }

        let modifiers = NSEvent.ModifierFlags(rawValue: modifierRawValue).intersection(.deviceIndependentFlagsMask)
        let hasCommand = modifiers.contains(.command)
        let hasControl = modifiers.contains(.control)
        let hasOption = modifiers.contains(.option)

        if viewModel.isSearchPresented {
            if keyCode == 53 {
                viewModel.dismissSearch()
                return true
            }
            if keyCode == 126 {
                viewModel.moveSearchSelection(by: -1)
                return true
            }
            if keyCode == 125 {
                viewModel.moveSearchSelection(by: 1)
                return true
            }
            if keyCode == 36 || keyCode == 76 {
                viewModel.selectSearchResult()
                return true
            }
            if !hasCommand, !hasControl, !hasOption, keyCode == 51 {
                if !viewModel.searchQuery.isEmpty {
                    viewModel.searchQuery.removeLast()
                }
                return true
            }
            if !hasCommand, !hasControl, !hasOption,
               characters.count == 1,
               characters.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }) {
                viewModel.searchQuery.append(characters)
                return true
            }
            return false
        }

        if hasCommand {
            if characters.lowercased() == "z" && !hasControl && !hasOption {
                viewModel.undo()
                return true
            }
            return false
        }

        guard !hasControl, !hasOption else { return false }

        if keyCode == 53 {
            viewModel.clearTransientInput()
            return true
        }
        if keyCode == 51 {
            viewModel.backspaceNumber()
            return true
        }
        if keyCode == 49 || characters == " " {
            viewModel.addPlayerFromBuffer()
            return true
        }
        if keyCode == 36 || keyCode == 76 || characters == "\r" || characters == "\n" {
            viewModel.finishCurrentPhotoAndAdvance()
            return true
        }
        if keyCode == 123 {
            viewModel.navigatePrevious()
            return true
        }
        if keyCode == 124 {
            viewModel.navigateNext()
            return true
        }
        if keyCode == 48 {
            viewModel.switchRoster()
            return true
        }

        if characters == "/" {
            viewModel.openSearch()
            return true
        }
        if characters.lowercased() == "f" {
            viewModel.toggleFlag()
            return true
        }
        if characters.lowercased() == "c" {
            viewModel.carryPlayersFromPreviousPhoto()
            return true
        }
        if characters.count == 1, characters.first?.isNumber == true {
            viewModel.handleNumber(characters)
            return true
        }
        if characters.count == 1, characters.first?.isLetter == true {
            viewModel.openSearch(initialQuery: characters)
            return true
        }

        return false
    }
}

struct KeyboardEventCapture: NSViewRepresentable {
    let viewModel: CaptioningViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.install(viewModel: viewModel)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    final class Coordinator {
        private var monitor: Any?

        func install(viewModel: CaptioningViewModel) {
            remove()
            let controller = MainActor.assumeIsolated {
                CaptioningCommandController(viewModel: viewModel)
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let consumed = MainActor.assumeIsolated {
                    controller.handle(
                        keyCode: event.keyCode,
                        characters: event.charactersIgnoringModifiers ?? "",
                        modifierRawValue: event.modifierFlags.rawValue
                    )
                }
                return consumed ? nil : event
            }
        }

        func remove() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            remove()
        }
    }
}
