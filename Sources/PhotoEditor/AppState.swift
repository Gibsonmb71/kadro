import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var screen: AppScreen = .start
    @Published var captioningModel: CaptioningViewModel?
    @Published var recentSessions: [RecentSessionSummary] = []
    @Published var appError: String?
    private var rosterReturnScreen: AppScreen = .start

    let rosterStore: RosterLibraryStore
    let persistence: SessionPersistenceService
    let folderAccess: FolderAccessService
    let flickrService: FlickrAPIService
    let flickrSyncQueue: FlickrSyncQueue

    init(
        rosterStore: RosterLibraryStore? = nil,
        persistence: SessionPersistenceService? = nil,
        folderAccess: FolderAccessService? = nil
    ) {
        self.rosterStore = rosterStore ?? RosterLibraryStore()
        let resolvedPersistence = persistence ?? SessionPersistenceService()
        self.persistence = resolvedPersistence
        self.folderAccess = folderAccess ?? FolderAccessService()
        let resolvedFlickrService = FlickrAPIService()
        self.flickrService = resolvedFlickrService
        self.flickrSyncQueue = FlickrSyncQueue(
            service: resolvedFlickrService,
            persistence: resolvedPersistence
        )
        refreshRecentSessions()
    }

    func refreshRecentSessions() {
        recentSessions = persistence.recentSessions()
    }

    func startNewSession() {
        appError = nil
        screen = .setup
    }

    func openRecentSession(_ summary: RecentSessionSummary) {
        do {
            var session = try persistence.load(id: summary.id)
            session.folderURL = folderAccess.resolveFolder(for: session)
            let model = makeCaptioningModel(session: session)
            captioningModel = model
            model.persist()
            screen = .captioning
            reconnectFlickrIfNeeded(for: session.id)
        } catch {
            appError = "Could not open \(summary.name): \(error.localizedDescription)"
        }
    }

    func openSessionFile() {
        guard let fileURL = folderAccess.chooseSessionFile() else { return }
        do {
            var session = try persistence.load(fileURL: fileURL)
            session.folderURL = folderAccess.resolveFolder(for: session)
            let model = makeCaptioningModel(session: session)
            captioningModel = model
            model.persist()
            screen = .captioning
            reconnectFlickrIfNeeded(for: session.id)
        } catch {
            appError = "Could not open the session file: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func createSession(
        name: String,
        folderSelection: FolderSelection,
        eventDate: Date?,
        sport: String,
        opponent: String,
        rosterIDs: [UUID],
        descriptionPrefix: String
    ) -> Bool {
        let photos = folderAccess.photoFiles(in: folderSelection.url).map { SessionPhoto(fileURL: $0) }
        guard !photos.isEmpty else {
            appError = "That folder does not contain any JPEG, HEIC, or PNG photos."
            return false
        }

        let session = PhotoSession(
            name: name.trimmed.isEmpty ? folderSelection.url.lastPathComponent : name.trimmed,
            folderURL: folderSelection.url,
            folderBookmarkData: folderSelection.bookmarkData,
            eventDate: eventDate,
            sport: sport.trimmed.isEmpty ? nil : sport.trimmed,
            opponent: opponent.trimmed.isEmpty ? nil : opponent.trimmed,
            rosterIDs: rosterIDs,
            descriptionPrefix: descriptionPrefix,
            photos: photos
        )

        do {
            try persistence.save(session)
            captioningModel = makeCaptioningModel(session: session)
            screen = .captioning
            refreshRecentSessions()
            flickrSyncQueue.resume()
            return true
        } catch {
            appError = "Could not save the new session: \(error.localizedDescription)"
            return false
        }
    }

    func createFlickrSession(
        name: String,
        album: FlickrAlbum,
        eventDate: Date?,
        sport: String,
        opponent: String,
        rosterIDs: [UUID],
        descriptionPrefix: String
    ) async -> Bool {
        do {
            if flickrService.authenticationStatus != .authenticated {
                try await flickrService.authenticate()
                flickrSyncQueue.resume()
                guard flickrService.authenticationStatus == .authenticated else {
                    throw FlickrServiceError.notAuthenticated
                }
            }

            let records = try await flickrService.getAlbumPhotos(albumID: album.id)
            guard !records.isEmpty else {
                appError = "That Flickr album does not contain any photos."
                return false
            }

            let photos = records.map {
                SessionPhoto(flickrRecord: $0, albumID: album.id)
            }
            let user = try? await flickrService.getCurrentUser()
            let albumURL = URL(string: "flickr://album/\(album.id)")!
            let session = PhotoSession(
                name: name.trimmed.isEmpty ? album.title : name.trimmed,
                folderURL: albumURL,
                eventDate: eventDate,
                sport: sport.trimmed.isEmpty ? nil : sport.trimmed,
                opponent: opponent.trimmed.isEmpty ? nil : opponent.trimmed,
                rosterIDs: rosterIDs,
                descriptionPrefix: descriptionPrefix,
                photos: photos,
                sourceType: .flickrAlbum,
                flickrUserID: user?.id ?? album.ownerID,
                flickrUserName: user?.username,
                flickrAlbumID: album.id,
                flickrAlbumTitle: album.title
            )

            try persistence.save(session)
            captioningModel = makeCaptioningModel(session: session)
            screen = .captioning
            refreshRecentSessions()
            flickrSyncQueue.resume()
            return true
        } catch {
            appError = "Could not open the Flickr album: \(error.localizedDescription)"
            return false
        }
    }

    func showReview() {
        captioningModel?.persist()
        screen = .review
    }

    func returnToCaptioning() {
        screen = .captioning
    }

    func closeSession() {
        captioningModel?.persist()
        captioningModel = nil
        refreshRecentSessions()
        screen = .start
    }

    func showRosters(returnTo screen: AppScreen = .start) {
        rosterReturnScreen = screen
        self.screen = .rosters
    }

    func leaveRosters() {
        screen = rosterReturnScreen
    }

    func goHome() {
        screen = .start
        refreshRecentSessions()
    }

    private func makeCaptioningModel(session: PhotoSession) -> CaptioningViewModel {
        let model = CaptioningViewModel(
            session: session,
            rosterStore: rosterStore,
            persistence: persistence,
            flickrService: flickrService,
            flickrSyncQueue: flickrSyncQueue
        )
        flickrSyncQueue.onPhotoChange = { [weak model] changedSession in
            guard changedSession.id == model?.session.id else { return }
            model?.replaceSession(changedSession)
        }
        return model
    }

    private func reconnectFlickrIfNeeded(for sessionID: UUID) {
        guard captioningModel?.session.id == sessionID,
              captioningModel?.session.sourceType == .flickrAlbum else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self,
                  self.captioningModel?.session.id == sessionID else {
                return
            }

            do {
                try await flickrService.authenticate()
                flickrSyncQueue.resume()
            } catch {
                // Cached Flickr sessions remain usable offline. Local edits
                // stay in the durable queue until the account is available.
                captioningModel?.statusMessage = "Saved locally · Flickr sync unavailable"
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            switch appState.screen {
            case .start, .rosters:
                AppNavigationView()
            case .setup:
                SessionSetupView()
            case .captioning:
                if let model = appState.captioningModel {
                    CaptioningView(viewModel: model)
                } else {
                    StartView()
                }
            case .review:
                if let model = appState.captioningModel {
                    ReviewView(viewModel: model)
                } else {
                    StartView()
                }
            }
        }
        .frame(minWidth: 980, minHeight: 680)
        .alert(
            AppBrand.name,
            isPresented: Binding(
                get: { appState.appError != nil },
                set: { if !$0 { appState.appError = nil } }
            ),
            presenting: appState.appError
        ) { _ in
            Button("OK") { appState.appError = nil }
        } message: { error in
            Text(error)
        }
    }
}
