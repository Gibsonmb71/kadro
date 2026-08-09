import AppKit
import Foundation

@MainActor
final class CaptioningViewModel: ObservableObject {
    @Published var session: PhotoSession
    @Published var jerseyBuffer = ""
    @Published var isSearchPresented = false
    @Published var searchQuery = ""
    @Published var searchSelection = 0
    @Published var statusMessage = "Ready"
    @Published private(set) var isRefreshingFlickrImages = false

    let rosterStore: RosterLibraryStore
    let persistence: SessionPersistenceService
    let imageService: PhotoLoadingService
    let flickrService: (any FlickrService)?
    let flickrSyncQueue: FlickrSyncQueue?
    let undoManager = UndoManager()
    private var hasAutomaticallyRefreshedFlickrImages = false

    init(
        session: PhotoSession,
        rosterStore: RosterLibraryStore,
        persistence: SessionPersistenceService,
        imageService: PhotoLoadingService = PhotoLoadingService.shared,
        flickrService: (any FlickrService)? = nil,
        flickrSyncQueue: FlickrSyncQueue? = nil
    ) {
        self.session = session
        self.rosterStore = rosterStore
        self.persistence = persistence
        self.imageService = imageService
        self.flickrService = flickrService
        self.flickrSyncQueue = flickrSyncQueue

        if self.session.activeRosterID == nil {
            self.session.activeRosterID = self.session.rosterIDs.first
        }
        if self.session.currentPhotoIndex >= self.session.photos.count {
            self.session.currentPhotoIndex = max(self.session.photos.count - 1, 0)
        }
    }

    var currentPhoto: SessionPhoto? {
        guard session.photos.indices.contains(session.currentPhotoIndex) else { return nil }
        return session.photos[session.currentPhotoIndex]
    }

    var currentPhotoIndex: Int {
        session.currentPhotoIndex
    }

    var positionText: String {
        guard !session.photos.isEmpty else { return "0 / 0" }
        return "\(session.currentPhotoIndex + 1) / \(session.photos.count)"
    }

    var activeRoster: Roster? {
        guard let activeRosterID = session.activeRosterID else { return nil }
        return rosterStore.roster(id: activeRosterID)
    }

    var activeTeamName: String {
        activeRoster.map { $0.teamName.trimmed.isEmpty ? $0.name : $0.teamName } ?? "No Roster"
    }

    var nextRosterName: String? {
        guard session.rosterIDs.count > 1,
              let activeID = session.activeRosterID,
              let activeIndex = session.rosterIDs.firstIndex(of: activeID) else {
            return nil
        }

        let nextID = session.rosterIDs[(activeIndex + 1) % session.rosterIDs.count]
        guard let roster = rosterStore.roster(id: nextID) else { return nil }
        return roster.teamName.trimmed.isEmpty ? roster.name : roster.teamName
    }

    var currentAssignments: [PhotoPersonAssignment] {
        currentPhoto?.assignedPeople ?? []
    }

    var currentDescription: String {
        guard let photo = currentPhoto else { return "" }
        if !photo.generatedDescription.isEmpty {
            return photo.generatedDescription
        }
        return generatedDescription(for: photo)
    }

    var currentSyncState: FlickrSyncState? {
        currentPhoto?.isFlickrBacked == true ? currentPhoto?.flickrSyncState : nil
    }

    var originalFlickrDescription: String? {
        currentPhoto?.originalFlickrDescription
    }

    var flickrConflictDescription: String? {
        currentPhoto?.flickrConflictDescription
    }

    func replaceSession(_ changedSession: PhotoSession) {
        guard changedSession.id == session.id else { return }
        session = changedSession
    }

    var resolvedCurrentAssignments: [ResolvedAssignment] {
        currentAssignments.compactMap { assignment in
            guard let person = rosterStore.person(id: assignment.personID),
                  let roster = rosterStore.roster(id: assignment.rosterID) else {
                return nil
            }

            return ResolvedAssignment(
                id: assignment.id,
                personID: assignment.personID,
                jerseyNumber: assignment.jerseyNumber,
                name: person.fullName,
                teamName: roster.teamName.trimmed.isEmpty ? roster.name : roster.teamName,
                rosterName: roster.name
            )
        }
    }

    var searchResults: [ResolvedRosterPlayer] {
        rosterStore.searchPlayers(query: searchQuery, rosterIDs: session.rosterIDs)
    }

    func handleNumber(_ number: String) {
        guard number.count == 1, number.first?.isNumber == true else { return }
        guard jerseyBuffer.count < 3 else {
            statusMessage = "Jersey numbers can be up to three digits"
            return
        }
        jerseyBuffer.append(number)
        statusMessage = ""
    }

    func backspaceNumber() {
        guard !jerseyBuffer.isEmpty else { return }
        jerseyBuffer.removeLast()
    }

    func clearTransientInput() {
        if isSearchPresented {
            dismissSearch()
        } else {
            jerseyBuffer = ""
            statusMessage = "Ready"
        }
    }

    func addPlayerFromBuffer() {
        guard !jerseyBuffer.isEmpty else { return }
        let number = jerseyBuffer
        jerseyBuffer = ""
        if addPlayer(number: number) {
            statusMessage = "Added #\(number)"
        } else {
            statusMessage = "No player #\(number) in \(activeTeamName)"
        }
    }

    func finishCurrentPhotoAndAdvance() {
        if !jerseyBuffer.isEmpty {
            let number = jerseyBuffer
            jerseyBuffer = ""
            if !addPlayer(number: number) {
                statusMessage = "No player #\(number) in \(activeTeamName)"
            }
        }

        guard !session.photos.isEmpty else { return }
        var updated = session
        let index = updated.currentPhotoIndex
        let finishedPhotoID = updated.photos[index].id
        updated.photos[index].reviewStatus = updated.photos[index].assignedPeople.isEmpty
            ? .reviewedWithNoPeople
            : .reviewedWithPeople
        updated.photos[index].generatedDescription = generatedDescription(for: updated.photos[index])
        let shouldSyncToFlickr = updated.photos[index].isFlickrBacked
        if shouldSyncToFlickr {
            updated.photos[index].flickrSyncState = .pending
            updated.photos[index].flickrSyncError = nil
        }
        updated.currentPhotoIndex = min(index + 1, max(updated.photos.count - 1, 0))
        commit(updated)

        if shouldSyncToFlickr,
           let queue = flickrSyncQueue,
           updated.photos.indices.contains(index),
           updated.photos[index].flickrMetadataLoaded {
            let photo = updated.photos[index]
            queue.enqueue(
                sessionID: updated.id,
                photo: photo,
                description: photo.workingDescription,
                expectedLastUpdate: photo.flickrLastUpdate
            )
        } else if shouldSyncToFlickr {
            // Enter must never overwrite a Flickr description until the
            // current remote description has been captured. The metadata
            // task is independent of the next-photo navigation so a fast
            // keyboard sequence remains non-blocking.
            Task { [weak self] in
                await self?.ensureFlickrMetadata(for: finishedPhotoID)
            }
        }

        if index == updated.currentPhotoIndex {
            statusMessage = "Saved · Last photo"
        } else {
            statusMessage = "Saved · Next photo"
        }
    }

    func navigatePrevious() {
        guard !session.photos.isEmpty else { return }
        let destination = max(session.currentPhotoIndex - 1, 0)
        navigate(to: destination)
    }

    func navigateNext() {
        guard !session.photos.isEmpty else { return }
        let destination = min(session.currentPhotoIndex + 1, session.photos.count - 1)
        navigate(to: destination)
    }

    func navigate(to index: Int) {
        guard session.photos.indices.contains(index), index != session.currentPhotoIndex else { return }
        var updated = session
        updated.currentPhotoIndex = index
        commit(updated)
        jerseyBuffer = ""
        statusMessage = "Ready"
    }

    func navigate(toPhotoID id: UUID) {
        guard let index = session.photos.firstIndex(where: { $0.id == id }) else { return }
        navigate(to: index)
    }

    func ensureFlickrMetadata(for photoID: UUID) async {
        guard let index = session.photos.firstIndex(where: { $0.id == photoID }),
              session.photos[index].isFlickrBacked,
              !session.photos[index].flickrMetadataLoaded,
              let flickrPhotoID = session.photos[index].flickrPhotoID,
              let flickrService else {
            return
        }

        do {
            let info = try await flickrService.getPhotoInfo(photoID: flickrPhotoID)
            guard session.photos.indices.contains(index) else { return }

            var updated = session
            let previouslyObservedLastUpdate = updated.photos[index].flickrLastUpdate
            let hasLocalWork = updated.photos[index].reviewStatus != .notReviewed
                || !updated.photos[index].assignedPeople.isEmpty
                || !updated.photos[index].generatedDescription.isEmpty
            updated.photos[index].originalFlickrDescription = info.description
            updated.photos[index].flickrMetadataLoaded = true
            updated.photos[index].flickrTitle = info.title
            updated.photos[index].flickrLastUpdate = info.lastUpdate ?? updated.photos[index].flickrLastUpdate
            if let displayURL = info.displayURL {
                updated.photos[index].fileURL = displayURL
                updated.photos[index].flickrImageURL = displayURL
            }

            let remoteChangedSinceListing = hasLocalWork
                && previouslyObservedLastUpdate != nil
                && info.lastUpdate != nil
                && previouslyObservedLastUpdate != info.lastUpdate
            if remoteChangedSinceListing {
                updated.photos[index].flickrSyncState = .conflict
                updated.photos[index].flickrSyncError = "Flickr changed this photo before the local description was saved."
                updated.photos[index].flickrConflictDescription = info.description
                statusMessage = "Flickr changed this photo · review conflict"
            }

            let shouldQueue = !remoteChangedSinceListing
                && updated.photos[index].flickrSyncState == .pending
                && (updated.photos[index].reviewStatus != .notReviewed
                    || updated.photos[index].hasCaptionWork)
            let photo = updated.photos[index]
            commit(updated)

            if shouldQueue, let flickrSyncQueue {
                flickrSyncQueue.enqueue(
                    sessionID: updated.id,
                    photo: photo,
                    description: photo.workingDescription,
                    expectedLastUpdate: photo.flickrLastUpdate
                )
            }
        } catch {
            if session.photos.indices.contains(index) {
                statusMessage = "Flickr metadata unavailable; saved locally"
            }
        }
    }

    func restoreOriginalFlickrDescription() {
        guard session.photos.indices.contains(session.currentPhotoIndex),
              let original = currentPhoto?.originalFlickrDescription,
              let flickrSyncQueue else {
            statusMessage = "Original Flickr description is not available yet"
            return
        }

        var updated = session
        updated.photos[updated.currentPhotoIndex].workingDescription = original
        updated.photos[updated.currentPhotoIndex].flickrSyncState = .pending
        updated.photos[updated.currentPhotoIndex].flickrSyncError = nil
        let photo = updated.photos[updated.currentPhotoIndex]
        commit(updated)
        flickrSyncQueue.enqueue(
            sessionID: updated.id,
            photo: photo,
            description: original,
            expectedLastUpdate: photo.flickrLastUpdate
        )
        statusMessage = "Original description queued"
    }

    func keepFlickrDescription() {
        guard let remoteDescription = currentPhoto?.flickrConflictDescription else { return }
        let photoID = currentPhoto?.id
        var updated = session
        updated.photos[updated.currentPhotoIndex].workingDescription = remoteDescription
        updated.photos[updated.currentPhotoIndex].flickrConflictDescription = nil
        updated.photos[updated.currentPhotoIndex].flickrSyncState = .synced
        updated.photos[updated.currentPhotoIndex].flickrSyncError = nil
        commit(updated)
        if let photoID, let flickrSyncQueue {
            flickrSyncQueue.discard(sessionID: updated.id, photoID: photoID)
        }
        statusMessage = "Kept Flickr description"
    }

    func useLocalDescriptionAfterConflict() async {
        guard session.photos.indices.contains(session.currentPhotoIndex),
              let flickrPhotoID = currentPhoto?.flickrPhotoID,
              let flickrService,
              let flickrSyncQueue else { return }

        do {
            let info = try await flickrService.getPhotoInfo(photoID: flickrPhotoID)
            var updated = session
            updated.photos[updated.currentPhotoIndex].flickrLastUpdate = info.lastUpdate
            updated.photos[updated.currentPhotoIndex].flickrConflictDescription = nil
            updated.photos[updated.currentPhotoIndex].flickrSyncState = .pending
            updated.photos[updated.currentPhotoIndex].flickrSyncError = nil
            let photo = updated.photos[updated.currentPhotoIndex]
            commit(updated)
            flickrSyncQueue.enqueue(
                sessionID: updated.id,
                photo: photo,
                description: photo.workingDescription,
                expectedLastUpdate: info.lastUpdate
            )
            statusMessage = "Local description queued"
        } catch {
            statusMessage = "Could not refresh Flickr metadata"
        }
    }

    func retryFlickrSync() {
        flickrSyncQueue?.retryFailed(sessionID: session.id)
    }

    func syncPendingFlickrUpdates() {
        flickrSyncQueue?.syncPending(sessionID: session.id)
    }

    func refreshFlickrImages() {
        Task { @MainActor [weak self] in
            await self?.performFlickrImageRefresh()
        }
    }

    func refreshFlickrImagesIfNeeded() async {
        guard session.sourceType == .flickrAlbum,
              !hasAutomaticallyRefreshedFlickrImages else {
            return
        }
        hasAutomaticallyRefreshedFlickrImages = true
        await performFlickrImageRefresh()
    }

    private func performFlickrImageRefresh() async {
        guard !isRefreshingFlickrImages,
              session.sourceType == .flickrAlbum,
              let albumID = session.flickrAlbumID,
              let flickrService else {
            return
        }

        isRefreshingFlickrImages = true
        statusMessage = "Refreshing Flickr images…"
        defer { isRefreshingFlickrImages = false }

        do {
            try await flickrService.authenticate()
            let records = try await flickrService.getAlbumPhotos(albumID: albumID)
            let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
            var updated = session
            var refreshedCount = 0

            for index in updated.photos.indices {
                guard let photoID = updated.photos[index].flickrPhotoID,
                      let record = recordsByID[photoID] else {
                    continue
                }

                let changed = updated.photos[index].fileURL != record.displayURL
                    || updated.photos[index].flickrThumbnailURL != record.thumbnailURL
                updated.photos[index].fileURL = record.displayURL
                updated.photos[index].flickrImageURL = record.displayURL
                updated.photos[index].flickrThumbnailURL = record.thumbnailURL
                updated.photos[index].flickrTitle = record.title
                updated.photos[index].flickrLastUpdate = record.lastUpdate ?? updated.photos[index].flickrLastUpdate
                if changed {
                    refreshedCount += 1
                }
            }

            commit(updated)
            statusMessage = refreshedCount == 0
                ? "Flickr image URLs are already current"
                : "Refreshed \(refreshedCount) Flickr image\(refreshedCount == 1 ? "" : "s")"
        } catch {
            statusMessage = "Could not refresh Flickr images · \(error.localizedDescription)"
        }
    }

    func toggleFlag() {
        guard session.photos.indices.contains(session.currentPhotoIndex) else { return }
        var updated = session
        updated.photos[updated.currentPhotoIndex].isFlagged.toggle()
        commit(updated)
        statusMessage = updated.photos[updated.currentPhotoIndex].isFlagged ? "Flagged for review" : "Flag cleared"
    }

    func carryPlayersFromPreviousPhoto() {
        guard session.currentPhotoIndex > 0 else {
            statusMessage = "There is no previous photo"
            return
        }

        let previousAssignments = session.photos[session.currentPhotoIndex - 1].assignedPeople
        guard !previousAssignments.isEmpty else {
            statusMessage = "Previous photo has no players"
            return
        }

        let currentIDs = Set(currentAssignments.map(\.personID))
        let missing = previousAssignments.filter { !currentIDs.contains($0.personID) }
        guard !missing.isEmpty else {
            statusMessage = "Players already added"
            return
        }

        var updated = session
        updated.photos[updated.currentPhotoIndex].assignedPeople.append(contentsOf: missing)
        updated.photos[updated.currentPhotoIndex].generatedDescription = generatedDescription(for: updated.photos[updated.currentPhotoIndex])
        if updated.photos[updated.currentPhotoIndex].isFlickrBacked {
            updated.photos[updated.currentPhotoIndex].flickrSyncState = .pending
            updated.photos[updated.currentPhotoIndex].flickrSyncError = nil
        }
        commit(updated, actionName: "Carry Players")
        statusMessage = "Carried \(missing.count) player\(missing.count == 1 ? "" : "s")"
    }

    func removeAssignment(id: UUID) {
        guard session.photos.indices.contains(session.currentPhotoIndex) else { return }
        var updated = session
        updated.photos[updated.currentPhotoIndex].assignedPeople.removeAll { $0.id == id }
        updated.photos[updated.currentPhotoIndex].generatedDescription = generatedDescription(for: updated.photos[updated.currentPhotoIndex])
        if updated.photos[updated.currentPhotoIndex].isFlickrBacked {
            updated.photos[updated.currentPhotoIndex].flickrSyncState = .pending
            updated.photos[updated.currentPhotoIndex].flickrSyncError = nil
        }
        commit(updated, actionName: "Remove Player")
        statusMessage = "Player removed"
    }

    func openSearch(initialQuery: String = "") {
        jerseyBuffer = ""
        searchQuery = initialQuery
        searchSelection = 0
        isSearchPresented = true

        // The sheet and its focused TextField mount after this key event has
        // finished. On macOS, that presentation cycle can briefly write an
        // empty value back through the binding. Restore the opening letter
        // on the next run loop only when nothing newer has been typed.
        guard !initialQuery.isEmpty else { return }
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self,
                  self.isSearchPresented,
                  self.searchQuery.isEmpty else {
                return
            }
            self.searchQuery = initialQuery
        }
    }

    func dismissSearch() {
        isSearchPresented = false
        searchQuery = ""
        searchSelection = 0
    }

    func moveSearchSelection(by offset: Int) {
        let count = searchResults.count
        guard count > 0 else { return }
        searchSelection = (searchSelection + offset + count) % count
    }

    func selectSearchResult() {
        guard searchResults.indices.contains(searchSelection) else { return }
        let player = searchResults[searchSelection]
        if addPlayer(player: player) {
            statusMessage = "Added #\(player.jerseyNumber) \(player.name)"
        } else {
            statusMessage = "\(player.name) is already on this photo"
        }
        dismissSearch()
    }

    func switchRoster() {
        guard session.rosterIDs.count > 1 else { return }
        let currentID = session.activeRosterID ?? session.rosterIDs[0]
        guard let currentIndex = session.rosterIDs.firstIndex(of: currentID) else { return }
        let newID = session.rosterIDs[(currentIndex + 1) % session.rosterIDs.count]
        var updated = session
        updated.activeRosterID = newID
        commit(updated)
        jerseyBuffer = ""
        statusMessage = "Active roster: \(activeTeamName)"
    }

    func undo() {
        guard undoManager.canUndo else {
            statusMessage = "Nothing to undo"
            return
        }
        undoManager.undo()
        statusMessage = "Undid last player change"
    }

    func persist() {
        var updated = session
        updated.lastOpenedAt = Date()
        session = updated
        try? persistence.save(updated)
    }

    private func addPlayer(number: String) -> Bool {
        guard let activeRosterID = session.activeRosterID,
              let player = rosterStore.player(number: number, rosterID: activeRosterID),
              session.photos.indices.contains(session.currentPhotoIndex) else {
            return false
        }

        if currentAssignments.contains(where: { $0.personID == player.personID }) {
            statusMessage = "#\(player.jerseyNumber) is already on this photo"
            return false
        }

        var updated = session
        let assignment = PhotoPersonAssignment(
            personID: player.personID,
            rosterID: player.rosterID,
            rosterEntryID: player.entryID,
            jerseyNumber: player.jerseyNumber
        )
        updated.photos[updated.currentPhotoIndex].assignedPeople.append(assignment)
        updated.photos[updated.currentPhotoIndex].generatedDescription = generatedDescription(for: updated.photos[updated.currentPhotoIndex])
        if updated.photos[updated.currentPhotoIndex].isFlickrBacked {
            updated.photos[updated.currentPhotoIndex].flickrSyncState = .pending
            updated.photos[updated.currentPhotoIndex].flickrSyncError = nil
        }
        commit(updated, actionName: "Add Player")
        return true
    }

    private func addPlayer(player: ResolvedRosterPlayer) -> Bool {
        guard session.photos.indices.contains(session.currentPhotoIndex) else { return false }
        guard !currentAssignments.contains(where: { $0.personID == player.personID }) else { return false }

        var updated = session
        let assignment = PhotoPersonAssignment(
            personID: player.personID,
            rosterID: player.rosterID,
            rosterEntryID: player.entryID,
            jerseyNumber: player.jerseyNumber
        )
        updated.photos[updated.currentPhotoIndex].assignedPeople.append(assignment)
        updated.photos[updated.currentPhotoIndex].generatedDescription = generatedDescription(for: updated.photos[updated.currentPhotoIndex])
        if updated.photos[updated.currentPhotoIndex].isFlickrBacked {
            updated.photos[updated.currentPhotoIndex].flickrSyncState = .pending
            updated.photos[updated.currentPhotoIndex].flickrSyncError = nil
        }
        commit(updated, actionName: "Add Player")
        return true
    }

    private func generatedDescription(for photo: SessionPhoto) -> String {
        DescriptionGenerator.generate(
            prefix: session.descriptionPrefix,
            assignments: photo.assignedPeople
        ) { assignment in
            rosterStore.person(id: assignment.personID)?.fullName
        }
    }

    private func commit(_ candidate: PhotoSession, actionName: String? = nil) {
        let previous = session
        var updated = candidate
        updated.lastOpenedAt = Date()
        session = updated
        try? persistence.save(updated)

        guard let actionName else { return }
        undoManager.registerUndo(withTarget: self) { target in
            target.commit(previous, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }
}
