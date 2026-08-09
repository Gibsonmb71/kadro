import AppKit
import SwiftUI

struct ReviewView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: CaptioningViewModel
    @StateCompat private var filter: PhotoFilter = .notReviewed

    private var availableFilters: [PhotoFilter] {
        if viewModel.session.sourceType == .flickrAlbum {
            return [.notReviewed, .flagged, .pendingSync, .syncFailed, .reviewed, .all]
        }

        return [.notReviewed, .flagged, .reviewed, .all]
    }

    private var filteredPhotos: [SessionPhoto] {
        photos(matching: filter)
    }

    private var pendingSyncCount: Int {
        viewModel.session.photos.filter {
            $0.flickrSyncState == .pending || $0.flickrSyncState == .syncing
        }.count
    }

    private var failedSyncCount: Int {
        viewModel.session.photos.filter {
            $0.flickrSyncState == .failed || $0.flickrSyncState == .conflict
        }.count
    }

    private var captionedButNotReviewedCount: Int {
        viewModel.session.photos.filter {
            $0.hasCaptionWork && $0.reviewStatus == .notReviewed
        }.count
    }

    private var reviewProgress: Double {
        guard !viewModel.session.photos.isEmpty else { return 0 }
        return Double(viewModel.session.reviewedCount) / Double(viewModel.session.photos.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                reviewSidebar
                Divider()
                resultsPane
            }
        }
        .navigationTitle("Review")
        .navigationSubtitle(sessionSourceDescription)
        .toolbarRole(.editor)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    appState.returnToCaptioning()
                } label: {
                    Label("Captioning", systemImage: "chevron.left")
                }
                .help("Return to captioning")
            }

            ToolbarItem(placement: .status) {
                HStack(spacing: 8) {
                    Text("\(viewModel.session.reviewedCount) / \(viewModel.session.photos.count)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    ProgressView(value: reviewProgress, total: 1)
                        .frame(width: 110)
                        .controlSize(.small)
                }
                .help("Photos reviewed")
            }

            if viewModel.session.sourceType == .flickrAlbum {
                ToolbarItemGroup(placement: .primaryAction) {
                    if pendingSyncCount > 0 {
                        Button("Sync Pending") {
                            viewModel.syncPendingFlickrUpdates()
                        }
                    }
                    if failedSyncCount > 0 {
                        Button("Retry Failed") {
                            viewModel.retryFlickrSync()
                        }
                    }
                }

                if #available(macOS 26.0, *) {
                    ToolbarSpacer(.fixed)
                }
            }
        }
        .onAppear {
            normalizeFilter()
        }
    }

    private func photos(matching filter: PhotoFilter) -> [SessionPhoto] {
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

    private var reviewSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Review Queue")
                .font(.headline)
                .padding(.horizontal, 10)

            Text("Find unfinished work and return to captioning.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 14)

            VStack(spacing: 2) {
                ForEach(availableFilters) { item in
                    ReviewFilterRow(
                        filter: item,
                        count: photos(matching: item).count,
                        isSelected: filter == item
                    ) {
                        filter = item
                    }
                }
            }

            Divider()
                .padding(.vertical, 16)

            VStack(alignment: .leading, spacing: 8) {
                Text("Progress")
                    .font(.subheadline.weight(.semibold))

                HStack {
                    Text("Reviewed")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(viewModel.session.reviewedCount) / \(viewModel.session.photos.count)")
                        .font(.callout.monospacedDigit().weight(.medium))
                }

                ProgressView(value: reviewProgress, total: 1)
                    .controlSize(.small)

                if captionedButNotReviewedCount > 0 {
                    Text("\(captionedButNotReviewedCount) captioned, not finished")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 10)

            if viewModel.session.sourceType == .flickrAlbum {
                Divider()
                    .padding(.vertical, 16)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Flickr Sync")
                        .font(.subheadline.weight(.semibold))

                    if pendingSyncCount > 0 {
                        Label("\(pendingSyncCount) waiting to sync", systemImage: "clock")
                            .foregroundStyle(.secondary)
                    } else if failedSyncCount > 0 {
                        Label("\(failedSyncCount) need attention", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    } else {
                        Label("All saved changes synced", systemImage: "checkmark")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .padding(.horizontal, 10)
            }

            Spacer()

            Text("Select a photo to open it in captioning.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
        }
        .padding(.vertical, 16)
        .frame(width: 220, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var resultsPane: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(filter.title)
                        .font(.title3.weight(.semibold))
                    Text(photoCountDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if viewModel.session.sourceType == .flickrAlbum {
                    if pendingSyncCount > 0 {
                        Button("Sync Pending") {
                            viewModel.syncPendingFlickrUpdates()
                        }
                        .buttonStyle(.bordered)
                    }
                    if failedSyncCount > 0 {
                        Button("Retry Failed") {
                            viewModel.retryFlickrSync()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 15)

            if filter == .syncFailed && failedSyncCount > 0 {
                HStack(spacing: 7) {
                    Image(systemName: "info.circle")
                    Text("Failed writes stay saved locally. Open a photo to retry or resolve a remote conflict.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.bottom, 12)
            }

            Divider()

            if filteredPhotos.isEmpty {
                emptyState
            } else {
                List(filteredPhotos) { photo in
                    ReviewPhotoRow(photo: photo, viewModel: viewModel)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.navigate(toPhotoID: photo.id)
                            appState.returnToCaptioning()
                        }
                        .accessibilityAddTraits(.isButton)
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            filter == .notReviewed ? "Review Queue Is Clear" : "No Matching Photos",
            systemImage: filter == .notReviewed ? "checkmark.circle" : "photo.on.rectangle",
            description: Text(
                filter == .notReviewed
                    ? "All photos in this session have been reviewed."
                    : "Choose another queue from the sidebar."
            )
        )
    }

    private var sessionSourceDescription: String {
        if viewModel.session.sourceType == .flickrAlbum {
            return "Flickr · \(viewModel.session.flickrAlbumTitle ?? viewModel.session.name)"
        }
        return viewModel.session.folderURL.lastPathComponent
    }

    private var photoCountDescription: String {
        let count = filteredPhotos.count
        return "\(count) photo\(count == 1 ? "" : "s")"
    }

    private func normalizeFilter() {
        if !availableFilters.contains(filter) {
            filter = .notReviewed
        }
    }
}

struct ReviewFilterRow: View {
    let filter: PhotoFilter
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: iconName)
                    .frame(width: 16)
                    .foregroundStyle(iconColor)

                Text(filter.title)
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                isSelected ? Color.accentColor.opacity(0.14) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        switch filter {
        case .all:
            return "square.grid.2x2"
        case .notReviewed:
            return "circle"
        case .flagged:
            return "flag"
        case .reviewed:
            return "checkmark.circle"
        case .pendingSync:
            return "clock"
        case .syncFailed:
            return "exclamationmark.triangle"
        }
    }

    private var iconColor: Color {
        switch filter {
        case .flagged:
            return .orange
        case .syncFailed:
            return count > 0 ? .orange : .secondary
        case .pendingSync:
            return count > 0 ? .blue : .secondary
        default:
            return .secondary
        }
    }
}

struct ReviewPhotoRow: View {
    let photo: SessionPhoto
    @ObservedObject var viewModel: CaptioningViewModel
    @StateObject private var imageLoader = ImageLoaderViewModel()

    private var photoPosition: String {
        guard let index = viewModel.session.photos.firstIndex(where: { $0.id == photo.id }) else {
            return ""
        }
        return "\(index + 1)"
    }

    private var statusTitle: String {
        if photo.hasCaptionWork && photo.reviewStatus == .notReviewed {
            return "Captioned · Not Reviewed"
        }
        return photo.reviewStatus.title
    }

    private var statusIcon: String {
        photo.reviewStatus == .notReviewed ? "circle" : "checkmark.circle"
    }

    private var statusColor: Color {
        photo.reviewStatus == .notReviewed ? .orange : .secondary
    }

    private var assignmentSummary: String {
        let names = photo.assignedPeople.compactMap { assignment in
            viewModel.rosterStore.person(id: assignment.personID)?.fullName
        }
        if names.isEmpty {
            return photo.reviewStatus == .reviewedWithNoPeople
                ? "No players identified"
                : "No players identified yet"
        }

        let visibleNames = names.prefix(3).joined(separator: " · ")
        if names.count > 3 {
            return "\(visibleNames) · +\(names.count - 3) more"
        }
        return visibleNames
    }

    var body: some View {
        HStack(spacing: 14) {
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
            .frame(width: 116, height: 76)
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(photo.filename)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if photo.isFlagged {
                        Label("Flagged", systemImage: "flag.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }

                Text(assignmentSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label(statusTitle, systemImage: statusIcon)
                        .foregroundStyle(statusColor)
                    if photo.isFlickrBacked {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Label(photo.flickrSyncState.title, systemImage: photo.flickrSyncState.symbolName)
                            .foregroundStyle(photo.flickrSyncState == .failed || photo.flickrSyncState == .conflict ? .orange : .secondary)
                    }
                }
                .font(.caption)

                if let syncError = photo.flickrSyncError, !syncError.isEmpty {
                    Text(syncError)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 4) {
                if !photoPosition.isEmpty {
                    Text(photoPosition)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 7)
        .task(id: photo.id) {
            let fallbackURLs = photo.flickrThumbnailURL.map { [$0] } ?? []
            await imageLoader.load(url: photo.fileURL, fallbackURLs: fallbackURLs, maxPixelSize: 360)
        }
    }
}
