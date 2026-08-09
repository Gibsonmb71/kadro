import Foundation

enum AppPaths {
    static var applicationSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("PhotoEditor", isDirectory: true)
    }

    static var sessionsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Sessions", isDirectory: true)
    }

    static var rosterLibraryFile: URL {
        applicationSupportDirectory.appendingPathComponent("Rosters.json")
    }

    static var flickrSyncQueueFile: URL {
        applicationSupportDirectory.appendingPathComponent("FlickrSyncQueue.json")
    }
}

struct Person: Codable, Identifiable, Hashable {
    let id: UUID
    var firstName: String
    var lastName: String
    var displayName: String?

    init(
        id: UUID = UUID(),
        firstName: String,
        lastName: String,
        displayName: String? = nil
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.displayName = displayName
    }

    var fullName: String {
        if let displayName, !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return displayName
        }

        return [firstName, lastName]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
    }
}

struct Roster: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var teamName: String
    var sport: String
    var season: String

    init(
        id: UUID = UUID(),
        name: String,
        teamName: String,
        sport: String = "",
        season: String = ""
    ) {
        self.id = id
        self.name = name
        self.teamName = teamName
        self.sport = sport
        self.season = season
    }
}

struct RosterEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let rosterID: UUID
    let personID: UUID
    var jerseyNumber: String

    init(
        id: UUID = UUID(),
        rosterID: UUID,
        personID: UUID,
        jerseyNumber: String
    ) {
        self.id = id
        self.rosterID = rosterID
        self.personID = personID
        self.jerseyNumber = jerseyNumber
    }
}

struct RosterLibrarySnapshot: Codable {
    var people: [Person] = []
    var rosters: [Roster] = []
    var entries: [RosterEntry] = []
}

struct PhotoPersonAssignment: Codable, Identifiable, Hashable {
    let id: UUID
    let personID: UUID
    let rosterID: UUID
    let rosterEntryID: UUID
    let jerseyNumber: String

    init(
        id: UUID = UUID(),
        personID: UUID,
        rosterID: UUID,
        rosterEntryID: UUID,
        jerseyNumber: String
    ) {
        self.id = id
        self.personID = personID
        self.rosterID = rosterID
        self.rosterEntryID = rosterEntryID
        self.jerseyNumber = jerseyNumber
    }
}

enum PhotoReviewStatus: String, Codable, CaseIterable, Identifiable {
    case notReviewed
    case reviewedWithPeople
    case reviewedWithNoPeople

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notReviewed:
            return "Not Reviewed"
        case .reviewedWithPeople:
            return "Reviewed"
        case .reviewedWithNoPeople:
            return "Reviewed · No Players"
        }
    }
}

enum FlickrUploadState: String, Codable {
    case notUploaded
    case queued
    case uploaded
    case failed
}

enum PhotoSourceType: String, Codable, CaseIterable, Identifiable {
    case localFolder
    case flickrAlbum

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localFolder:
            return "Local Folder"
        case .flickrAlbum:
            return "Flickr Album"
        }
    }
}

enum FlickrSyncState: String, Codable, CaseIterable, Identifiable {
    case notChanged
    case pending
    case syncing
    case synced
    case failed
    case conflict

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notChanged:
            return "Not Changed"
        case .pending:
            return "Pending"
        case .syncing:
            return "Syncing"
        case .synced:
            return "Synced"
        case .failed:
            return "Failed"
        case .conflict:
            return "Needs Attention"
        }
    }

    var symbolName: String {
        switch self {
        case .notChanged:
            return "minus"
        case .pending:
            return "clock"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .synced:
            return "checkmark"
        case .failed:
            return "exclamationmark.triangle"
        case .conflict:
            return "exclamationmark.2"
        }
    }
}

struct FlickrAlbum: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var photoCount: Int
    var coverURL: URL?
    var lastUpdated: Date?
    var ownerID: String
}

struct FlickrPhotoRecord: Codable, Hashable, Sendable {
    let id: String
    let albumID: String
    var title: String
    var displayURL: URL
    var thumbnailURL: URL?
    var lastUpdate: String?
}

struct FlickrPhotoInfo: Hashable, Sendable {
    let id: String
    var title: String
    var description: String
    var lastUpdate: String?
    var displayURL: URL?
    var thumbnailURL: URL?
}

struct FlickrUser: Hashable, Sendable {
    let id: String
    let username: String
}

struct SessionPhoto: Codable, Identifiable, Hashable {
    let id: UUID
    let stableIdentifier: String
    var fileURL: URL
    var fileBookmarkData: Data?
    var filename: String
    var assignedPeople: [PhotoPersonAssignment]
    var generatedDescription: String
    var isFlagged: Bool
    var reviewStatus: PhotoReviewStatus
    var notes: String?
    var flickrUploadState: FlickrUploadState
    var sourceType: PhotoSourceType
    var flickrPhotoID: String?
    var flickrAlbumID: String?
    var originalFlickrDescription: String?
    var flickrMetadataLoaded: Bool
    var flickrSyncState: FlickrSyncState
    var lastFlickrSyncDate: Date?
    var flickrSyncError: String?
    var flickrTitle: String?
    var flickrLastUpdate: String?
    var flickrImageURL: URL?
    var flickrThumbnailURL: URL?
    var flickrConflictDescription: String?

    var workingDescription: String {
        get { generatedDescription }
        set { generatedDescription = newValue }
    }

    /// A photo has caption work as soon as a player assignment or a generated
    /// description has been saved, even if the photographer has not pressed
    /// Enter to mark the frame complete yet.
    var hasCaptionWork: Bool {
        !assignedPeople.isEmpty || !generatedDescription.trimmed.isEmpty
    }

    var isFlickrBacked: Bool {
        sourceType == .flickrAlbum && flickrPhotoID != nil
    }

    init(
        id: UUID = UUID(),
        fileURL: URL,
        fileBookmarkData: Data? = nil
    ) {
        self.id = id
        self.stableIdentifier = fileURL.standardizedFileURL.path
        self.fileURL = fileURL
        self.fileBookmarkData = fileBookmarkData
        self.filename = fileURL.lastPathComponent
        self.assignedPeople = []
        self.generatedDescription = ""
        self.isFlagged = false
        self.reviewStatus = .notReviewed
        self.notes = nil
        self.flickrUploadState = .notUploaded
        self.sourceType = .localFolder
        self.flickrPhotoID = nil
        self.flickrAlbumID = nil
        self.originalFlickrDescription = nil
        self.flickrMetadataLoaded = false
        self.flickrSyncState = .notChanged
        self.lastFlickrSyncDate = nil
        self.flickrSyncError = nil
        self.flickrTitle = nil
        self.flickrLastUpdate = nil
        self.flickrImageURL = nil
        self.flickrThumbnailURL = nil
        self.flickrConflictDescription = nil
    }

    init(
        id: UUID = UUID(),
        flickrRecord: FlickrPhotoRecord,
        albumID: String
    ) {
        self.id = id
        self.stableIdentifier = "flickr:\(flickrRecord.id)"
        self.fileURL = flickrRecord.displayURL
        self.fileBookmarkData = nil
        self.filename = flickrRecord.title.trimmed.isEmpty ? flickrRecord.id : flickrRecord.title
        self.assignedPeople = []
        self.generatedDescription = ""
        self.isFlagged = false
        self.reviewStatus = .notReviewed
        self.notes = nil
        self.flickrUploadState = .notUploaded
        self.sourceType = .flickrAlbum
        self.flickrPhotoID = flickrRecord.id
        self.flickrAlbumID = albumID
        self.originalFlickrDescription = nil
        self.flickrMetadataLoaded = false
        self.flickrSyncState = .notChanged
        self.lastFlickrSyncDate = nil
        self.flickrSyncError = nil
        self.flickrTitle = flickrRecord.title
        self.flickrLastUpdate = flickrRecord.lastUpdate
        self.flickrImageURL = flickrRecord.displayURL
        self.flickrThumbnailURL = flickrRecord.thumbnailURL
        self.flickrConflictDescription = nil
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case stableIdentifier
        case fileURL
        case fileBookmarkData
        case filename
        case assignedPeople
        case generatedDescription
        case isFlagged
        case reviewStatus
        case notes
        case flickrUploadState
        case sourceType
        case flickrPhotoID
        case flickrAlbumID
        case originalFlickrDescription
        case flickrMetadataLoaded
        case flickrSyncState
        case lastFlickrSyncDate
        case flickrSyncError
        case flickrTitle
        case flickrLastUpdate
        case flickrImageURL
        case flickrThumbnailURL
        case flickrConflictDescription
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.fileURL = try container.decode(URL.self, forKey: .fileURL)
        self.stableIdentifier = try container.decodeIfPresent(String.self, forKey: .stableIdentifier)
            ?? fileURL.standardizedFileURL.path
        self.fileBookmarkData = try container.decodeIfPresent(Data.self, forKey: .fileBookmarkData)
        self.filename = try container.decodeIfPresent(String.self, forKey: .filename)
            ?? fileURL.lastPathComponent
        self.assignedPeople = try container.decodeIfPresent([PhotoPersonAssignment].self, forKey: .assignedPeople) ?? []
        self.generatedDescription = try container.decodeIfPresent(String.self, forKey: .generatedDescription) ?? ""
        self.isFlagged = try container.decodeIfPresent(Bool.self, forKey: .isFlagged) ?? false
        self.reviewStatus = try container.decodeIfPresent(PhotoReviewStatus.self, forKey: .reviewStatus) ?? .notReviewed
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes)
        self.flickrUploadState = try container.decodeIfPresent(FlickrUploadState.self, forKey: .flickrUploadState) ?? .notUploaded
        self.sourceType = try container.decodeIfPresent(PhotoSourceType.self, forKey: .sourceType)
            ?? (container.contains(.flickrPhotoID) ? .flickrAlbum : .localFolder)
        self.flickrPhotoID = try container.decodeIfPresent(String.self, forKey: .flickrPhotoID)
        self.flickrAlbumID = try container.decodeIfPresent(String.self, forKey: .flickrAlbumID)
        self.originalFlickrDescription = try container.decodeIfPresent(String.self, forKey: .originalFlickrDescription)
        self.flickrMetadataLoaded = try container.decodeIfPresent(Bool.self, forKey: .flickrMetadataLoaded) ?? false
        if let state = try container.decodeIfPresent(FlickrSyncState.self, forKey: .flickrSyncState) {
            self.flickrSyncState = state
        } else {
            switch flickrUploadState {
            case .queued:
                self.flickrSyncState = .pending
            case .uploaded:
                self.flickrSyncState = .synced
            case .failed:
                self.flickrSyncState = .failed
            case .notUploaded:
                self.flickrSyncState = .notChanged
            }
        }
        self.lastFlickrSyncDate = try container.decodeIfPresent(Date.self, forKey: .lastFlickrSyncDate)
        self.flickrSyncError = try container.decodeIfPresent(String.self, forKey: .flickrSyncError)
        self.flickrTitle = try container.decodeIfPresent(String.self, forKey: .flickrTitle)
        self.flickrLastUpdate = try container.decodeIfPresent(String.self, forKey: .flickrLastUpdate)
        self.flickrImageURL = try container.decodeIfPresent(URL.self, forKey: .flickrImageURL)
        self.flickrThumbnailURL = try container.decodeIfPresent(URL.self, forKey: .flickrThumbnailURL)
        self.flickrConflictDescription = try container.decodeIfPresent(String.self, forKey: .flickrConflictDescription)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(stableIdentifier, forKey: .stableIdentifier)
        try container.encode(fileURL, forKey: .fileURL)
        try container.encodeIfPresent(fileBookmarkData, forKey: .fileBookmarkData)
        try container.encode(filename, forKey: .filename)
        try container.encode(assignedPeople, forKey: .assignedPeople)
        try container.encode(generatedDescription, forKey: .generatedDescription)
        try container.encode(isFlagged, forKey: .isFlagged)
        try container.encode(reviewStatus, forKey: .reviewStatus)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encode(flickrUploadState, forKey: .flickrUploadState)
        try container.encode(sourceType, forKey: .sourceType)
        try container.encodeIfPresent(flickrPhotoID, forKey: .flickrPhotoID)
        try container.encodeIfPresent(flickrAlbumID, forKey: .flickrAlbumID)
        try container.encodeIfPresent(originalFlickrDescription, forKey: .originalFlickrDescription)
        try container.encode(flickrMetadataLoaded, forKey: .flickrMetadataLoaded)
        try container.encode(flickrSyncState, forKey: .flickrSyncState)
        try container.encodeIfPresent(lastFlickrSyncDate, forKey: .lastFlickrSyncDate)
        try container.encodeIfPresent(flickrSyncError, forKey: .flickrSyncError)
        try container.encodeIfPresent(flickrTitle, forKey: .flickrTitle)
        try container.encodeIfPresent(flickrLastUpdate, forKey: .flickrLastUpdate)
        try container.encodeIfPresent(flickrImageURL, forKey: .flickrImageURL)
        try container.encodeIfPresent(flickrThumbnailURL, forKey: .flickrThumbnailURL)
        try container.encodeIfPresent(flickrConflictDescription, forKey: .flickrConflictDescription)
    }
}

struct PhotoSession: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var folderURL: URL
    var folderBookmarkData: Data?
    var eventDate: Date?
    var sport: String?
    var opponent: String?
    var rosterIDs: [UUID]
    var descriptionPrefix: String
    var createdAt: Date
    var lastOpenedAt: Date
    var currentPhotoIndex: Int
    var activeRosterID: UUID?
    var photos: [SessionPhoto]
    var sourceType: PhotoSourceType
    var flickrUserID: String?
    var flickrUserName: String?
    var flickrAlbumID: String?
    var flickrAlbumTitle: String?

    init(
        id: UUID = UUID(),
        name: String,
        folderURL: URL,
        folderBookmarkData: Data? = nil,
        eventDate: Date? = nil,
        sport: String? = nil,
        opponent: String? = nil,
        rosterIDs: [UUID],
        descriptionPrefix: String,
        createdAt: Date = Date(),
        lastOpenedAt: Date = Date(),
        currentPhotoIndex: Int = 0,
        activeRosterID: UUID? = nil,
        photos: [SessionPhoto],
        sourceType: PhotoSourceType = .localFolder,
        flickrUserID: String? = nil,
        flickrUserName: String? = nil,
        flickrAlbumID: String? = nil,
        flickrAlbumTitle: String? = nil
    ) {
        self.id = id
        self.name = name
        self.folderURL = folderURL
        self.folderBookmarkData = folderBookmarkData
        self.eventDate = eventDate
        self.sport = sport
        self.opponent = opponent
        self.rosterIDs = rosterIDs
        self.descriptionPrefix = descriptionPrefix
        self.createdAt = createdAt
        self.lastOpenedAt = lastOpenedAt
        self.currentPhotoIndex = max(0, min(currentPhotoIndex, max(photos.count - 1, 0)))
        self.activeRosterID = activeRosterID ?? rosterIDs.first
        self.photos = photos
        self.sourceType = sourceType
        self.flickrUserID = flickrUserID
        self.flickrUserName = flickrUserName
        self.flickrAlbumID = flickrAlbumID
        self.flickrAlbumTitle = flickrAlbumTitle
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case folderURL
        case folderBookmarkData
        case eventDate
        case sport
        case opponent
        case rosterIDs
        case descriptionPrefix
        case createdAt
        case lastOpenedAt
        case currentPhotoIndex
        case activeRosterID
        case photos
        case sourceType
        case flickrUserID
        case flickrUserName
        case flickrAlbumID
        case flickrAlbumTitle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.folderURL = try container.decode(URL.self, forKey: .folderURL)
        self.folderBookmarkData = try container.decodeIfPresent(Data.self, forKey: .folderBookmarkData)
        self.eventDate = try container.decodeIfPresent(Date.self, forKey: .eventDate)
        self.sport = try container.decodeIfPresent(String.self, forKey: .sport)
        self.opponent = try container.decodeIfPresent(String.self, forKey: .opponent)
        self.rosterIDs = try container.decodeIfPresent([UUID].self, forKey: .rosterIDs) ?? []
        self.descriptionPrefix = try container.decodeIfPresent(String.self, forKey: .descriptionPrefix) ?? ""
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.lastOpenedAt = try container.decodeIfPresent(Date.self, forKey: .lastOpenedAt) ?? self.createdAt
        self.currentPhotoIndex = try container.decodeIfPresent(Int.self, forKey: .currentPhotoIndex) ?? 0
        self.activeRosterID = try container.decodeIfPresent(UUID.self, forKey: .activeRosterID)
        self.photos = try container.decodeIfPresent([SessionPhoto].self, forKey: .photos) ?? []
        self.sourceType = try container.decodeIfPresent(PhotoSourceType.self, forKey: .sourceType)
            ?? (container.contains(.flickrAlbumID) ? .flickrAlbum : .localFolder)
        self.flickrUserID = try container.decodeIfPresent(String.self, forKey: .flickrUserID)
        self.flickrUserName = try container.decodeIfPresent(String.self, forKey: .flickrUserName)
        self.flickrAlbumID = try container.decodeIfPresent(String.self, forKey: .flickrAlbumID)
        self.flickrAlbumTitle = try container.decodeIfPresent(String.self, forKey: .flickrAlbumTitle)

        self.currentPhotoIndex = max(0, min(self.currentPhotoIndex, max(self.photos.count - 1, 0)))
        if self.activeRosterID == nil {
            self.activeRosterID = self.rosterIDs.first
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(folderURL, forKey: .folderURL)
        try container.encodeIfPresent(folderBookmarkData, forKey: .folderBookmarkData)
        try container.encodeIfPresent(eventDate, forKey: .eventDate)
        try container.encodeIfPresent(sport, forKey: .sport)
        try container.encodeIfPresent(opponent, forKey: .opponent)
        try container.encode(rosterIDs, forKey: .rosterIDs)
        try container.encode(descriptionPrefix, forKey: .descriptionPrefix)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(lastOpenedAt, forKey: .lastOpenedAt)
        try container.encode(currentPhotoIndex, forKey: .currentPhotoIndex)
        try container.encodeIfPresent(activeRosterID, forKey: .activeRosterID)
        try container.encode(photos, forKey: .photos)
        try container.encode(sourceType, forKey: .sourceType)
        try container.encodeIfPresent(flickrUserID, forKey: .flickrUserID)
        try container.encodeIfPresent(flickrUserName, forKey: .flickrUserName)
        try container.encodeIfPresent(flickrAlbumID, forKey: .flickrAlbumID)
        try container.encodeIfPresent(flickrAlbumTitle, forKey: .flickrAlbumTitle)
    }

    var reviewedCount: Int {
        photos.filter { $0.reviewStatus != .notReviewed }.count
    }

    /// Captioned is intentionally separate from Reviewed. Right/left
    /// navigation and a crash can leave a generated caption saved while the
    /// photographer has not explicitly finished that frame with Enter.
    var captionedCount: Int {
        photos.filter { $0.reviewStatus != .notReviewed || $0.hasCaptionWork }.count
    }

    var flaggedCount: Int {
        photos.filter(\.isFlagged).count
    }
}

struct RecentSessionSummary: Identifiable, Hashable {
    let id: UUID
    let name: String
    let folderName: String
    let lastOpenedAt: Date
    let totalPhotoCount: Int
    let reviewedPhotoCount: Int
    let captionedPhotoCount: Int
    let flaggedPhotoCount: Int
    let sourceType: PhotoSourceType

    init(session: PhotoSession) {
        self.id = session.id
        self.name = session.name
        self.folderName = session.sourceType == .flickrAlbum
            ? "Flickr · \(session.flickrAlbumTitle ?? session.name)"
            : session.folderURL.lastPathComponent
        self.lastOpenedAt = session.lastOpenedAt
        self.totalPhotoCount = session.photos.count
        self.reviewedPhotoCount = session.reviewedCount
        self.captionedPhotoCount = session.captionedCount
        self.flaggedPhotoCount = session.flaggedCount
        self.sourceType = session.sourceType
    }
}

struct ResolvedRosterPlayer: Identifiable, Hashable {
    let id: UUID
    let entryID: UUID
    let personID: UUID
    let rosterID: UUID
    let jerseyNumber: String
    let name: String
    let teamName: String
    let rosterName: String
}

struct ResolvedAssignment: Identifiable, Hashable {
    let id: UUID
    let personID: UUID
    let jerseyNumber: String
    let name: String
    let teamName: String
    let rosterName: String
}

struct CSVImportPreview: Identifiable {
    let id = UUID()
    let headers: [String]
    let rows: [[String]]
}

struct CSVColumnMapping {
    var numberColumn: Int
    var firstNameColumn: Int?
    var lastNameColumn: Int?
    var nameColumn: Int?
}

enum PhotoFilter: String, CaseIterable, Identifiable {
    case all
    case notReviewed
    case flagged
    case reviewed
    case pendingSync
    case syncFailed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .notReviewed:
            return "Not Reviewed"
        case .flagged:
            return "Flagged"
        case .reviewed:
            return "Reviewed"
        case .pendingSync:
            return "Pending Sync"
        case .syncFailed:
            return "Sync Failed"
        }
    }
}

enum AppScreen {
    case start
    case setup
    case captioning
    case review
    case rosters
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedJerseyNumber: String {
        let digits = filter(\.isNumber)
        guard !digits.isEmpty else { return "" }
        return String(Int(digits) ?? 0)
    }
}
