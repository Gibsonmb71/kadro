import Foundation
import SwiftUI

struct FlickrSyncJob: Codable, Identifiable, Hashable {
    let id: UUID
    let sessionID: UUID
    let photoID: UUID
    let flickrPhotoID: String
    var description: String
    var expectedLastUpdate: String?
    var retryCount: Int
    var nextAttemptAt: Date
    var lastError: String?
    var permanentFailure: Bool

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        photoID: UUID,
        flickrPhotoID: String,
        description: String,
        expectedLastUpdate: String?
    ) {
        self.id = id
        self.sessionID = sessionID
        self.photoID = photoID
        self.flickrPhotoID = flickrPhotoID
        self.description = description
        self.expectedLastUpdate = expectedLastUpdate
        self.retryCount = 0
        self.nextAttemptAt = Date()
        self.lastError = nil
        self.permanentFailure = false
    }
}

@MainActor
final class FlickrSyncQueue: ObservableObject {
    private let service: any FlickrService
    private let persistence: SessionPersistenceService
    private let queueURL: URL
    private var jobs: [FlickrSyncJob]
    private var runningJobID: UUID?
    private var retryTask: Task<Void, Never>?

    var onPhotoChange: ((PhotoSession) -> Void)?

    init(
        service: any FlickrService,
        persistence: SessionPersistenceService,
        queueURL: URL = AppPaths.flickrSyncQueueFile
    ) {
        self.service = service
        self.persistence = persistence
        self.queueURL = queueURL
        self.jobs = (try? Self.loadJobs(from: queueURL)) ?? []

        for job in jobs where !job.permanentFailure {
            updatePhotoState(job: job, state: .pending, error: nil)
        }
        persistJobs()
        processNext()
    }

    var pendingCount: Int {
        jobs.count
    }

    var failedCount: Int {
        jobs.filter { $0.lastError != nil || $0.permanentFailure }.count
    }

    func enqueue(
        sessionID: UUID,
        photo: SessionPhoto,
        description: String,
        expectedLastUpdate: String?
    ) {
        guard let flickrPhotoID = photo.flickrPhotoID else { return }

        jobs.removeAll { job in
            job.sessionID == sessionID
                && job.photoID == photo.id
                && job.id != runningJobID
        }

        jobs.append(
            FlickrSyncJob(
                sessionID: sessionID,
                photoID: photo.id,
                flickrPhotoID: flickrPhotoID,
                description: description,
                expectedLastUpdate: expectedLastUpdate
            )
        )
        updatePhotoState(job: jobs[jobs.count - 1], state: .pending, error: nil)
        persistJobs()
        processNext()
    }

    func discard(sessionID: UUID, photoID: UUID) {
        jobs.removeAll { $0.sessionID == sessionID && $0.photoID == photoID && $0.id != runningJobID }
        persistJobs()
        processNext()
    }

    func retryFailed(sessionID: UUID? = nil) {
        for index in jobs.indices where (sessionID == nil || jobs[index].sessionID == sessionID) {
            guard jobs[index].lastError != nil || jobs[index].permanentFailure else { continue }
            jobs[index].retryCount = 0
            jobs[index].nextAttemptAt = Date()
            jobs[index].lastError = nil
            jobs[index].permanentFailure = false
            updatePhotoState(job: jobs[index], state: .pending, error: nil)
        }
        persistJobs()
        processNext()
        if service.authenticationStatus == .authenticated {
            Task { [weak self] in
                await self?.reconcilePendingMetadata(sessionID: sessionID)
            }
        }
    }

    func syncPending(sessionID: UUID? = nil) {
        for index in jobs.indices where (sessionID == nil || jobs[index].sessionID == sessionID) {
            jobs[index].nextAttemptAt = Date()
            jobs[index].permanentFailure = false
            jobs[index].lastError = nil
            updatePhotoState(job: jobs[index], state: .pending, error: nil)
        }
        prepareCaptionedPhotosForSync(sessionID: sessionID)
        persistJobs()
        processNext()
        if service.authenticationStatus == .authenticated {
            Task { [weak self] in
                await self?.reconcilePendingMetadata(
                    sessionID: sessionID,
                    includeCaptionedWork: true
                )
            }
        }
    }

    func resume() {
        processNext()
        guard service.authenticationStatus == .authenticated else { return }
        Task { [weak self] in
            await self?.reconcilePendingMetadata(includeCaptionedWork: true)
        }
    }

    private func processNext() {
        guard runningJobID == nil,
              service.authenticationStatus == .authenticated else {
            return
        }

        guard let index = jobs.firstIndex(where: {
            !$0.permanentFailure && $0.nextAttemptAt <= Date()
        }) else {
            scheduleNextAttempt()
            return
        }

        let job = jobs[index]
        runningJobID = job.id
        updatePhotoState(job: job, state: .syncing, error: nil)

        Task { [weak self] in
            guard let self else { return }
            await self.perform(job)
        }
    }

    private func perform(_ job: FlickrSyncJob) async {
        do {
            let info = try await service.safelySetPhotoDescription(
                photoID: job.flickrPhotoID,
                expectedLastUpdate: job.expectedLastUpdate,
                description: job.description
            )
            finishSuccess(job, remoteInfo: info)
        } catch let error as FlickrServiceError {
            switch error {
            case .conflict(let remoteDescription, let remoteLastUpdate):
                finishConflict(
                    job,
                    remoteDescription: remoteDescription,
                    remoteLastUpdate: remoteLastUpdate
                )
            default:
                finishFailure(job, error: error)
            }
        } catch {
            finishFailure(job, error: error)
        }
    }

    private func finishSuccess(_ job: FlickrSyncJob, remoteInfo: FlickrPhotoInfo) {
        let hasNewerJob = jobs.contains {
            $0.sessionID == job.sessionID
                && $0.photoID == job.photoID
                && $0.id != job.id
        }

        if !hasNewerJob {
            updatePhotoState(job: job, state: .synced, error: nil) { photo in
                photo.lastFlickrSyncDate = Date()
                photo.flickrLastUpdate = remoteInfo.lastUpdate ?? photo.flickrLastUpdate
                photo.flickrSyncError = nil
                photo.flickrConflictDescription = nil
            }
        } else if let newerIndex = jobs.firstIndex(where: {
            $0.sessionID == job.sessionID && $0.photoID == job.photoID && $0.id != job.id
        }) {
            jobs[newerIndex].expectedLastUpdate = remoteInfo.lastUpdate
            jobs[newerIndex].nextAttemptAt = Date()
        }

        jobs.removeAll { $0.id == job.id }
        runningJobID = nil
        persistJobs()
        processNext()
    }

    private func finishConflict(
        _ job: FlickrSyncJob,
        remoteDescription: String,
        remoteLastUpdate: String?
    ) {
        updatePhotoState(job: job, state: .conflict, error: "Flickr changed this photo before the local update.") { photo in
            photo.flickrConflictDescription = remoteDescription
            photo.flickrLastUpdate = remoteLastUpdate ?? photo.flickrLastUpdate
        }
        jobs.removeAll { $0.id == job.id }
        runningJobID = nil
        persistJobs()
        processNext()
    }

    private func finishFailure(_ job: FlickrSyncJob, error: Error) {
        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else {
            runningJobID = nil
            processNext()
            return
        }

        let flickrError = error as? FlickrServiceError
        jobs[index].retryCount += 1
        jobs[index].lastError = error.localizedDescription
        jobs[index].permanentFailure = flickrError?.isPermanent ?? false
        let delay = min(pow(2.0, Double(jobs[index].retryCount)), 300.0)
        jobs[index].nextAttemptAt = Date().addingTimeInterval(delay)
        updatePhotoState(job: jobs[index], state: .failed, error: error.localizedDescription)
        runningJobID = nil
        persistJobs()
        processNext()
    }

    private func scheduleNextAttempt() {
        retryTask?.cancel()
        guard let nextDate = jobs
            .filter({ !$0.permanentFailure })
            .map(\.nextAttemptAt)
            .min() else {
            return
        }

        let interval = max(0.5, nextDate.timeIntervalSinceNow)
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            self?.processNext()
        }
    }

    private func reconcilePendingMetadata(
        sessionID: UUID? = nil,
        includeCaptionedWork: Bool = false
    ) async {
        guard service.authenticationStatus == .authenticated else { return }

        let summaries = persistence.recentSessions().filter { summary in
            summary.sourceType == .flickrAlbum && (sessionID == nil || summary.id == sessionID)
        }

        for summary in summaries {
            guard var session = try? persistence.load(id: summary.id) else { continue }
            let pendingIndices = session.photos.indices.filter { index in
                let photo = session.photos[index]
                let eligibleWork = photo.reviewStatus != .notReviewed
                    || (includeCaptionedWork && photo.hasCaptionWork)
                return photo.isFlickrBacked
                    && eligibleWork
                    && photo.flickrSyncState == .pending
                    && !hasJob(sessionID: session.id, photoID: photo.id)
            }

            for index in pendingIndices {
                guard let flickrPhotoID = session.photos[index].flickrPhotoID else { continue }

                // The current photo or a nearby photo may already have its
                // metadata captured. It is safe to enqueue it immediately;
                // only uncaptured photos need the lazy getInfo request below.
                if session.photos[index].flickrMetadataLoaded {
                    let photo = session.photos[index]
                    enqueue(
                        sessionID: session.id,
                        photo: photo,
                        description: photo.workingDescription,
                        expectedLastUpdate: photo.flickrLastUpdate
                    )
                    continue
                }

                do {
                    let info = try await service.getPhotoInfo(photoID: flickrPhotoID)
                    let previousLastUpdate = session.photos[index].flickrLastUpdate
                    let hasLocalWork = session.photos[index].reviewStatus != .notReviewed
                        || !session.photos[index].assignedPeople.isEmpty
                        || !session.photos[index].generatedDescription.isEmpty

                    session.photos[index].originalFlickrDescription = info.description
                    session.photos[index].flickrMetadataLoaded = true
                    session.photos[index].flickrTitle = info.title
                    session.photos[index].flickrLastUpdate = info.lastUpdate ?? previousLastUpdate

                    if hasLocalWork,
                       let previousLastUpdate,
                       let remoteLastUpdate = info.lastUpdate,
                       previousLastUpdate != remoteLastUpdate {
                        session.photos[index].flickrSyncState = .conflict
                        session.photos[index].flickrSyncError = "Flickr changed this photo before the local description was saved."
                        session.photos[index].flickrConflictDescription = info.description
                        try? persistence.save(session)
                        onPhotoChange?(session)
                        continue
                    }

                    try? persistence.save(session)
                    onPhotoChange?(session)
                    let photo = session.photos[index]
                    enqueue(
                        sessionID: session.id,
                        photo: photo,
                        description: photo.workingDescription,
                        expectedLastUpdate: photo.flickrLastUpdate
                    )
                } catch {
                    // Keep the locally pending state. The next resume or
                    // explicit Sync Pending action will retry metadata capture.
                }
            }
        }
    }

    private func hasJob(sessionID: UUID, photoID: UUID) -> Bool {
        jobs.contains { $0.sessionID == sessionID && $0.photoID == photoID }
    }

    /// A generated description can exist before Enter if the photographer
    /// navigated away or the app was interrupted. An explicit Sync Pending
    /// action should pick up that durable local work too.
    private func prepareCaptionedPhotosForSync(sessionID: UUID?) {
        let summaries = persistence.recentSessions().filter { summary in
            summary.sourceType == .flickrAlbum && (sessionID == nil || summary.id == sessionID)
        }

        for summary in summaries {
            guard var session = try? persistence.load(id: summary.id) else { continue }
            var changed = false
            for index in session.photos.indices {
                let photo = session.photos[index]
                guard photo.isFlickrBacked,
                      photo.hasCaptionWork,
                      photo.flickrSyncState == .notChanged else {
                    continue
                }
                session.photos[index].flickrSyncState = .pending
                session.photos[index].flickrSyncError = nil
                changed = true
            }
            if changed {
                try? persistence.save(session)
                onPhotoChange?(session)
            }
        }
    }

    private func updatePhotoState(
        job: FlickrSyncJob,
        state: FlickrSyncState,
        error: String?,
        mutate: ((inout SessionPhoto) -> Void)? = nil
    ) {
        guard var session = try? persistence.load(id: job.sessionID),
              let index = session.photos.firstIndex(where: { $0.id == job.photoID }) else {
            return
        }

        session.photos[index].flickrSyncState = state
        session.photos[index].flickrSyncError = error
        mutate?(&session.photos[index])
        try? persistence.save(session)
        onPhotoChange?(session)
    }

    private func persistJobs() {
        try? FileManager.default.createDirectory(
            at: queueURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(jobs) {
            try? data.write(to: queueURL, options: .atomic)
        }
    }

    private static func loadJobs(from url: URL) throws -> [FlickrSyncJob] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([FlickrSyncJob].self, from: data)
    }
}
