import SwiftUI

@MainActor
final class FlickrAlbumPickerModel: ObservableObject {
    let service: any FlickrService
    @Published var albums: [FlickrAlbum] = []
    @Published var searchQuery = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    init(service: any FlickrService) {
        self.service = service
    }

    var filteredAlbums: [FlickrAlbum] {
        let query = searchQuery.trimmed.lowercased()
        guard !query.isEmpty else { return albums }
        return albums.filter { $0.title.lowercased().contains(query) }
    }

    func load() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                try await service.authenticate()
                albums = try await service.getAlbums()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

struct FlickrAlbumPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: FlickrAlbumPickerModel
    let onSelect: (FlickrAlbum) -> Void

    init(service: any FlickrService, onSelect: @escaping (FlickrAlbum) -> Void) {
        self.onSelect = onSelect
        _model = StateObject(wrappedValue: FlickrAlbumPickerModel(service: service))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open Flickr Album")
                        .font(.headline)
                    Text("Choose an album to caption in place")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if !model.albums.isEmpty {
                TextField("Search albums", text: $model.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .padding(14)
            }

            Group {
                if model.isLoading {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Loading Flickr albums…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = model.errorMessage {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Could not load Flickr albums", systemImage: "exclamationmark.triangle")
                            .font(.headline)
                        Text(errorMessage)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Button("Try Again") {
                            model.load()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(24)
                } else if model.filteredAlbums.isEmpty {
                    ContentUnavailableView(
                        model.albums.isEmpty ? "No Flickr Albums" : "No Matching Albums",
                        systemImage: "rectangle.stack",
                        description: Text(model.albums.isEmpty ? "No albums were returned for this Flickr account." : "Try a different album name.")
                    )
                } else {
                    List(model.filteredAlbums) { album in
                        Button {
                            onSelect(album)
                            dismiss()
                        } label: {
                            FlickrAlbumRow(album: album)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.inset)
                }
            }
        }
        .frame(width: 560, height: 540)
        .task {
            model.load()
        }
    }
}

private struct FlickrAlbumRow: View {
    let album: FlickrAlbum

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: album.coverURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                default:
                    ZStack {
                        Color.black.opacity(0.08)
                        Image(systemName: "photo.on.rectangle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 76, height: 54)
            .clipped()

            VStack(alignment: .leading, spacing: 3) {
                Text(album.title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(album.photoCount) photos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}
