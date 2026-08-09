import SwiftUI

/// A compact, keyboard-oriented control for the one piece of captioning UI
/// that deserves a little Kadro-specific treatment.
struct CaptionEntryControl: View {
    @ObservedObject var viewModel: CaptioningViewModel

    private var jerseyBinding: Binding<String> {
        Binding(
            get: { viewModel.jerseyBuffer },
            set: { value in
                viewModel.jerseyBuffer = String(value.filter(\.isNumber).prefix(3))
            }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.activeTeamName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(viewModel.nextRosterName.map { "Tab: \($0)" } ?? "Single roster")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 122, alignment: .leading)

            HStack(spacing: 4) {
                Text("#")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                TextField("—", text: jerseyBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .multilineTextAlignment(.center)
                    .frame(width: 72)
                    .accessibilityLabel("Current jersey number")
                    .help("Type a jersey number")
            }

            Divider()
                .frame(height: 24)

            HStack(spacing: 10) {
                KeyHint(key: "Space", label: "Add")
                KeyHint(key: "Return", label: "Save & Next")
            }

            .layoutPriority(1)

            Spacer(minLength: 4)

            HStack(spacing: 8) {
                addButton
                saveButton
            }

            if !viewModel.statusMessage.isEmpty, viewModel.statusMessage != "Ready" {
                Text(viewModel.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 180, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: 760)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Caption entry")
    }

    @ViewBuilder
    private var addButton: some View {
        if #available(macOS 26.0, *) {
            Button("Add") {
                viewModel.addPlayerFromBuffer()
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .fixedSize(horizontal: true, vertical: false)
            .help("Add the typed player (Space)")
        } else {
            Button("Add") {
                viewModel.addPlayerFromBuffer()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .fixedSize(horizontal: true, vertical: false)
            .help("Add the typed player (Space)")
        }
    }

    @ViewBuilder
    private var saveButton: some View {
        if #available(macOS 26.0, *) {
            Button("Save & Next") {
                viewModel.finishCurrentPhotoAndAdvance()
            }
            .buttonStyle(.glassProminent)
            .controlSize(.small)
            .fixedSize(horizontal: true, vertical: false)
            .help("Save this photo and advance (Return)")
        } else {
            Button("Save & Next") {
                viewModel.finishCurrentPhotoAndAdvance()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .fixedSize(horizontal: true, vertical: false)
            .help("Save this photo and advance (Return)")
        }
    }
}
