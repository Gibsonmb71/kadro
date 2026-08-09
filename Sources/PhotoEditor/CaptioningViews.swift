import AppKit
import SwiftUI

@MainActor
final class ImageLoaderViewModel: ObservableObject {
    @Published var image: NSImage?
    @Published var isLoading = false
    private let service = PhotoLoadingService.shared
    private var task: Task<Void, Never>?

    deinit {
        task?.cancel()
    }

    func load(url: URL?, maxPixelSize: Int = 2400) async {
        task?.cancel()
        image = nil
        guard let url else {
            isLoading = false
            return
        }

        isLoading = true
        let service = service
        task = Task { @MainActor [weak self] in
            let image = await service.loadImage(for: url, maxPixelSize: maxPixelSize)
            guard !Task.isCancelled else { return }
            self?.image = image
            self?.isLoading = false
        }
        await task?.value
    }
}

struct CaptioningView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: CaptioningViewModel
    @StateObject private var imageLoader = ImageLoaderViewModel()

    var body: some View {
        VStack(spacing: 0) {
            topToolbar
            Divider()

            HStack(spacing: 0) {
                photoPane
                Divider()
                PlayerSidebarView(viewModel: viewModel)
                    .frame(width: 290)
            }

            Divider()
            FilmstripView(viewModel: viewModel)
            Divider()
            keyboardBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .topLeading) {
            KeyboardEventCapture(viewModel: viewModel)
                .frame(width: 1, height: 1)
                .opacity(0)
        }
        .task(id: viewModel.currentPhoto?.id) {
            guard let photo = viewModel.currentPhoto else { return }
            await viewModel.ensureFlickrMetadata(for: photo.id)
            await imageLoader.load(url: photo.fileURL)
            let nearbyURLs = [
                viewModel.currentPhotoIndex - 1,
                viewModel.currentPhotoIndex + 1
            ]
            .filter { viewModel.session.photos.indices.contains($0) }
            .map { viewModel.session.photos[$0].fileURL }
            viewModel.imageService.preload(urls: nearbyURLs)
        }
        .sheet(isPresented: $viewModel.isSearchPresented) {
            PlayerSearchView(viewModel: viewModel)
        }
    }

    private var topToolbar: some View {
        HStack(spacing: 12) {
            Button {
                appState.closeSession()
            } label: {
                Label("Sessions", systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)

            Divider()
                .frame(height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.session.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(viewModel.currentPhoto?.flickrTitle ?? viewModel.currentPhoto?.filename ?? "No photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(viewModel.positionText)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)

            if let syncState = viewModel.currentSyncState {
                Label(syncState.title, systemImage: syncState.symbolName)
                    .font(.caption)
                    .foregroundStyle(syncState == .failed || syncState == .conflict ? .orange : .secondary)
                    .help("Flickr synchronization state")
            }

            if let syncError = viewModel.currentPhoto?.flickrSyncError,
               !syncError.isEmpty {
                Text(syncError)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .frame(maxWidth: 230, alignment: .leading)
                    .help(syncError)
            }

            Button {
                viewModel.toggleFlag()
            } label: {
                Label(
                    viewModel.currentPhoto?.isFlagged == true ? "Flagged" : "Flag",
                    systemImage: viewModel.currentPhoto?.isFlagged == true ? "flag.fill" : "flag"
                )
            }
            .buttonStyle(.bordered)
            .tint(viewModel.currentPhoto?.isFlagged == true ? .orange : nil)

            Button("Review") {
                appState.showReview()
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    private var photoPane: some View {
        ZStack {
            Color.black

            if let image = imageLoader.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(18)
                    .accessibilityLabel(viewModel.currentPhoto?.filename ?? "Photo")
            } else if imageLoader.isLoading {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "photo")
                        .font(.system(size: 38))
                    Text("Photo unavailable")
                        .font(.headline)
                    Text(viewModel.currentPhoto?.fileURL.path ?? "")
                        .font(.caption)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white.opacity(0.7))
                .padding(30)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var keyboardBar: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.activeTeamName.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(viewModel.nextRosterName.map { "Tab: \($0)" } ?? "Single roster")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(minWidth: 150, alignment: .leading)

            HStack(spacing: 0) {
                Text("#")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField(
                    "—",
                    text: Binding(
                        get: { viewModel.jerseyBuffer },
                        set: { value in
                            viewModel.jerseyBuffer = String(value.filter(\.isNumber).prefix(3))
                        }
                    )
                )
                .textFieldStyle(.plain)
                .font(.title2.monospacedDigit().weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(width: 92)
                .accessibilityLabel("Current jersey number")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(Rectangle().stroke(Color(nsColor: .separatorColor), lineWidth: 1))

            HStack(spacing: 15) {
                KeyHint(key: "Space", label: "Add Player")
                KeyHint(key: "Enter", label: "Save & Next")
            }

            Spacer(minLength: 8)

            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: 240, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(.regularMaterial)
    }
}

struct FilmstripView: View {
    @ObservedObject var viewModel: CaptioningViewModel

    private var visibleIndices: [Int] {
        guard !viewModel.session.photos.isEmpty else { return [] }
        let start = max(viewModel.currentPhotoIndex - 8, 0)
        let end = min(viewModel.session.photos.count, viewModel.currentPhotoIndex + 9)
        return Array(start..<end)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                ForEach(visibleIndices, id: \.self) { index in
                    let photo = viewModel.session.photos[index]
                    Button {
                        viewModel.navigate(to: index)
                    } label: {
                        FilmstripThumbnail(
                            photo: photo,
                            isCurrent: index == viewModel.currentPhotoIndex
                        )
                    }
                    .buttonStyle(.plain)
                    .help(photo.filename)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .frame(height: 78)
        .background(.bar)
    }
}

struct FilmstripThumbnail: View {
    let photo: SessionPhoto
    let isCurrent: Bool
    @StateObject private var imageLoader = ImageLoaderViewModel()

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black.opacity(0.86)
            if let image = imageLoader.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if imageLoader.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.white.opacity(0.5))
            }

            if photo.isFlagged {
                Image(systemName: "flag.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(4)
            }
        }
        .frame(width: 92, height: 58)
        .clipped()
        .overlay(Rectangle().stroke(isCurrent ? Color.accentColor : Color.clear, lineWidth: 2))
        .task(id: photo.id) {
            await imageLoader.load(url: photo.fileURL, maxPixelSize: 320)
        }
    }
}

struct KeyHint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct PlayerSidebarView: View {
    @ObservedObject var viewModel: CaptioningViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("People in this photo")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.currentAssignments.count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 11)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if viewModel.resolvedCurrentAssignments.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No players added")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Text("Type a jersey number, then press Space.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                    } else {
                        ForEach(viewModel.resolvedCurrentAssignments) { assignment in
                            HStack(spacing: 10) {
                                Text("#\(assignment.jerseyNumber)")
                                    .font(.body.monospaced().weight(.semibold))
                                    .frame(width: 48, alignment: .leading)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(assignment.name)
                                        .font(.callout)
                                        .lineLimit(1)
                                    Text(assignment.teamName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 4)

                                Button {
                                    viewModel.removeAssignment(id: assignment.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption.weight(.semibold))
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                                .help("Remove player")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)

                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
            }

            Divider()

            Button {
                viewModel.openSearch()
            } label: {
                Label("Add / Search Player", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(16)

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                Text("Generated Description")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView {
                    Text(!viewModel.currentDescription.isEmpty
                        ? viewModel.currentDescription
                        : "Description will appear as players are added.")
                        .font(.caption.monospaced())
                        .foregroundStyle(!viewModel.currentDescription.isEmpty ? .primary : .tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 135)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if viewModel.currentPhoto?.isFlickrBacked == true {
                Divider()
                FlickrPhotoDetailsView(viewModel: viewModel)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct FlickrPhotoDetailsView: View {
    @ObservedObject var viewModel: CaptioningViewModel
    @StateCompat private var isExpanded = false
    @StateCompat private var showingOriginal = false

    private var flickrURL: URL? {
        guard let userID = viewModel.session.flickrUserID,
              let photoID = viewModel.currentPhoto?.flickrPhotoID else {
            return nil
        }
        return URL(string: "https://www.flickr.com/photos/\(userID)/\(photoID)")
    }

    var body: some View {
        DisclosureGroup("Flickr", isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if let syncState = viewModel.currentSyncState {
                    Label(syncState.title, systemImage: syncState.symbolName)
                        .font(.caption)
                        .foregroundStyle(syncState == .failed || syncState == .conflict ? .orange : .secondary)
                }

                if let syncError = viewModel.currentPhoto?.flickrSyncError,
                   !syncError.isEmpty {
                    Text(syncError)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }

                if viewModel.originalFlickrDescription != nil {
                    Text("Original description available")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button("View Original Description") {
                            showingOriginal = true
                        }
                        .buttonStyle(.borderless)

                        Button("Restore Original") {
                            viewModel.restoreOriginalFlickrDescription()
                        }
                        .buttonStyle(.borderless)
                    }
                }

                if let flickrURL {
                    Button("View on Flickr") {
                        NSWorkspace.shared.open(flickrURL)
                    }
                    .buttonStyle(.borderless)
                }

                if let remoteDescription = viewModel.flickrConflictDescription {
                    Divider()
                    Text("Flickr changed this description remotely.")
                        .font(.caption.weight(.semibold))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Flickr Description")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(remoteDescription.isEmpty ? "(empty)" : remoteDescription)
                            .font(.caption.monospaced())
                            .lineLimit(4)
                        Text("Local Description")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(viewModel.currentDescription.isEmpty ? "(empty)" : viewModel.currentDescription)
                            .font(.caption.monospaced())
                            .lineLimit(4)
                    }
                    HStack(spacing: 10) {
                        Button("Keep Flickr") {
                            viewModel.keepFlickrDescription()
                        }
                        Button("Use Local") {
                            Task { await viewModel.useLocalDescriptionAfterConflict() }
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.top, 6)
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .popover(isPresented: $showingOriginal) {
            Text(viewModel.originalFlickrDescription?.isEmpty == false ? viewModel.originalFlickrDescription! : "(empty)")
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .padding(14)
                .frame(width: 300, height: 180, alignment: .topLeading)
        }
    }
}

struct PlayerSearchView: View {
    @ObservedObject var viewModel: CaptioningViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Search Players")
                    .font(.headline)
                Spacer()
                Text("Esc to dismiss")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("Type a name or jersey number", text: $viewModel.searchQuery)
                .textFieldStyle(.roundedBorder)
                .focused($searchFieldFocused)
                .onSubmit {
                    viewModel.selectSearchResult()
                }

            if viewModel.searchResults.isEmpty {
                Text("No matching players")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollViewReader { proxy in
                    List(Array(viewModel.searchResults.enumerated()), id: \.element.id) { index, player in
                        Button {
                            viewModel.searchSelection = index
                            viewModel.selectSearchResult()
                        } label: {
                            HStack(spacing: 10) {
                                Text("#\(player.jerseyNumber)")
                                    .font(.body.monospaced().weight(.semibold))
                                    .frame(width: 48, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(player.name)
                                        .foregroundStyle(.primary)
                                    Text(player.teamName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(index == viewModel.searchSelection ? Color.accentColor.opacity(0.16) : nil)
                        .id(index)
                    }
                    .listStyle(.inset)
                    .onChange(of: viewModel.searchSelection) { _, newValue in
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(newValue)
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 430, height: 440)
        .onAppear {
            searchFieldFocused = true
        }
        .onChange(of: viewModel.isSearchPresented) { _, isPresented in
            if !isPresented {
                dismiss()
            }
        }
    }
}

struct LegacyReviewView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: CaptioningViewModel
    @StateCompat private var filter: PhotoFilter = .notReviewed

    private var filteredPhotos: [SessionPhoto] {
        switch filter {
        case .all:
            return viewModel.session.photos
        case .notReviewed:
            return viewModel.session.photos.filter { $0.reviewStatus == .notReviewed }
        case .flagged:
            return viewModel.session.photos.filter(\.isFlagged)
        case .reviewed:
            return viewModel.session.photos.filter { $0.reviewStatus != .notReviewed }
        case .pendingSync:
            return viewModel.session.photos.filter {
                $0.flickrSyncState == .pending || $0.flickrSyncState == .syncing
            }
        case .syncFailed:
            return viewModel.session.photos.filter {
                $0.flickrSyncState == .failed || $0.flickrSyncState == .conflict
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    appState.returnToCaptioning()
                } label: {
                    Label("Captioning", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Review")
                        .font(.headline)
                    Text(viewModel.session.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                reviewCounts
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)

            Divider()

            HStack {
                if viewModel.session.sourceType == .flickrAlbum {
                    Picker("Filter", selection: $filter) {
                        ForEach(PhotoFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 190)
                } else {
                    Picker("Filter", selection: $filter) {
                        ForEach(PhotoFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 380)
                }
                Spacer()
                if viewModel.session.sourceType == .flickrAlbum {
                    Button("Sync Pending") {
                        viewModel.syncPendingFlickrUpdates()
                    }
                    .buttonStyle(.borderless)
                    Button("Retry Failed") {
                        viewModel.retryFlickrSync()
                    }
                    .buttonStyle(.borderless)
                }
                Text("\(filteredPhotos.count) photos")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 11)

            Divider()

            if filteredPhotos.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: filter == .notReviewed ? "checkmark.circle" : "photo.on.rectangle")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text(filter == .notReviewed ? "Nothing left to review" : "No matching photos")
                        .font(.headline)
                    Text("Use the filter above to find another part of the session.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredPhotos) { photo in
                    Button {
                        viewModel.navigate(toPhotoID: photo.id)
                        appState.returnToCaptioning()
                    } label: {
                        LegacyReviewPhotoRow(photo: photo, viewModel: viewModel)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var reviewCounts: some View {
        HStack(spacing: 14) {
            ReviewCount(label: "Total", value: viewModel.session.photos.count)
            ReviewCount(label: "Captioned", value: viewModel.session.captionedCount)
            ReviewCount(label: "Reviewed", value: viewModel.session.reviewedCount)
            ReviewCount(label: "Flagged", value: viewModel.session.flaggedCount)
            if viewModel.session.sourceType == .flickrAlbum {
                ReviewCount(
                    label: "Pending",
                    value: viewModel.session.photos.filter { $0.flickrSyncState == .pending || $0.flickrSyncState == .syncing }.count
                )
                ReviewCount(
                    label: "Synced",
                    value: viewModel.session.photos.filter { $0.flickrSyncState == .synced }.count
                )
                ReviewCount(
                    label: "Failed",
                    value: viewModel.session.photos.filter { $0.flickrSyncState == .failed || $0.flickrSyncState == .conflict }.count
                )
            }
        }
    }
}

struct ReviewCount: View {
    let label: String
    let value: Int

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.callout.monospacedDigit().weight(.semibold))
        }
    }
}

struct LegacyReviewPhotoRow: View {
    let photo: SessionPhoto
    @ObservedObject var viewModel: CaptioningViewModel
    @StateObject private var imageLoader = ImageLoaderViewModel()

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Color.black.opacity(0.85)
                if let image = imageLoader.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if imageLoader.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(width: 88, height: 58)
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(photo.filename)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if photo.isFlagged {
                        Image(systemName: "flag.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }
                HStack(spacing: 8) {
                    Text(photo.hasCaptionWork && photo.reviewStatus == .notReviewed
                        ? "Captioned · Not Reviewed"
                        : photo.reviewStatus.title)
                    if photo.isFlickrBacked {
                        Label(photo.flickrSyncState.title, systemImage: photo.flickrSyncState.symbolName)
                    }
                }
                .font(.caption)
                .foregroundStyle(photo.flickrSyncState == .failed || photo.flickrSyncState == .conflict ? .orange : (photo.reviewStatus == .notReviewed ? .orange : .secondary))

                if let syncError = photo.flickrSyncError, !syncError.isEmpty {
                    Text(syncError)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }

            Spacer()

            Text(photo.assignedPeople.isEmpty ? "—" : "\(photo.assignedPeople.count) player\(photo.assignedPeople.count == 1 ? "" : "s")")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
        .task(id: photo.id) {
            await imageLoader.load(url: photo.fileURL)
        }
    }
}
