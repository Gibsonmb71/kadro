import Foundation

@MainActor
enum KadroSelfTest {
    static func run() {
        do {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("Kadro-self-test-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let csvURL = directory.appendingPathComponent("soccer.csv")
            let csv = "number,name\n11,Efren Lardizibal\n7,Hayes Franklin\n"
            try csv.data(using: .utf8)?.write(to: csvURL)

            let importService = RosterImportService()
            let preview = try importService.preview(fileURL: csvURL)
            let alternateCSVFixtures: [(name: String, contents: String, expectedHeaders: [String], expectedFirstRow: [String])] = [
                (
                    name: "semicolon.csv",
                    contents: "number;firstName;lastName\r11;Efren;Lardizibal\r7;Hayes;Franklin\r",
                    expectedHeaders: ["number", "firstName", "lastName"],
                    expectedFirstRow: ["11", "Efren", "Lardizibal"]
                ),
                (
                    name: "tab.tsv",
                    contents: "number\tname\n11\tEfren Lardizibal\n7\tHayes Franklin\n",
                    expectedHeaders: ["number", "name"],
                    expectedFirstRow: ["11", "Efren Lardizibal"]
                ),
                (
                    name: "quoted.csv",
                    contents: "number,name\n11,\"Efren Lardizibal\"\n7,\"Hayes Franklin\"\n",
                    expectedHeaders: ["number", "name"],
                    expectedFirstRow: ["11", "Efren Lardizibal"]
                ),
                (
                    name: "football-crlf.csv",
                    contents: "#,First name,Last name\r\n2,Markevius,Jones\r\n2,Madden,Davis\r\n4,Dalton,Williams\r\n",
                    expectedHeaders: ["#", "First name", "Last name"],
                    expectedFirstRow: ["2", "Markevius", "Jones"]
                )
            ]

            for fixture in alternateCSVFixtures {
                let fixtureURL = directory.appendingPathComponent(fixture.name)
                try fixture.contents.write(to: fixtureURL, atomically: true, encoding: .utf8)
                let fixturePreview = try importService.preview(fileURL: fixtureURL)
                require(
                    fixturePreview.headers == fixture.expectedHeaders,
                    "CSV delimiter detection for \(fixture.name): \(fixturePreview.headers)"
                )
                require(
                    fixturePreview.rows.first == fixture.expectedFirstRow,
                    "CSV row parsing for \(fixture.name): \(String(describing: fixturePreview.rows.first))"
                )
            }

            let utf16URL = directory.appendingPathComponent("utf16.csv")
            guard let utf16Data = "number,name\n11,Efren Lardizibal\n".data(using: .utf16) else {
                require(false, "UTF-16 fixture encoding")
                return
            }
            try utf16Data.write(to: utf16URL)
            let utf16Preview = try importService.preview(fileURL: utf16URL)
            require(utf16Preview.headers == ["number", "name"], "UTF-16 CSV decoding")

            let store = RosterLibraryStore(fileURL: directory.appendingPathComponent("Rosters.json"))
            let rosterID = store.importRoster(
                preview: preview,
                mapping: importService.inferredMapping(for: preview.headers),
                name: "Boys Soccer 2026-27",
                teamName: "Ninety Six",
                sport: "Soccer",
                season: "2026-27"
            )
            require(store.entries(for: rosterID).count == 2, "CSV roster import")
            require(store.player(number: "11", rosterID: rosterID)?.name == "Efren Lardizibal", "CSV name mapping")

            let session = PhotoSession(
                name: "Self Test",
                folderURL: directory,
                rosterIDs: [rosterID],
                descriptionPrefix: "NSHS 2026-2027 Boys Soccer @ Emerald High School, August 8, 2026",
                photos: [
                    SessionPhoto(fileURL: directory.appendingPathComponent("IMG_0001.jpg")),
                    SessionPhoto(fileURL: directory.appendingPathComponent("IMG_0002.jpg"))
                ]
            )
            let persistence = SessionPersistenceService(directoryURL: directory.appendingPathComponent("Sessions"))
            let viewModel = CaptioningViewModel(session: session, rosterStore: store, persistence: persistence)
            let keyboard = CaptioningCommandController(viewModel: viewModel)
            func send(_ keyCode: UInt16, _ characters: String) {
                _ = keyboard.handle(keyCode: keyCode, characters: characters, modifierRawValue: 0)
            }

            send(0, "1")
            send(0, "1")
            send(49, " ")
            send(0, "7")
            send(36, "\r")

            require(viewModel.currentPhotoIndex == 1, "Enter advances to next photo")
            require(viewModel.session.photos[0].assignedPeople.count == 2, "keyboard player assignment")
            require(viewModel.session.photos[0].reviewStatus == .reviewedWithPeople, "photo review state")
            require(
                viewModel.session.photos[0].generatedDescription.contains("#11 Efren Lardizibal")
                    && viewModel.session.photos[0].generatedDescription.contains("#7 Hayes Franklin"),
                "description generation"
            )

            let loaded = try persistence.load(id: session.id)
            require(loaded.currentPhotoIndex == 1, "session index persistence")
            require(loaded.photos[0].assignedPeople.count == 2, "assignment persistence")

            send(0, "h")
            require(viewModel.isSearchPresented && viewModel.searchQuery == "h", "letter opens player search")
            send(0, "a")
            require(viewModel.searchQuery == "ha", "letter continues player search")
            send(53, "")
            require(!viewModel.isSearchPresented, "Escape dismisses player search")

            viewModel.carryPlayersFromPreviousPhoto()
            require(viewModel.currentAssignments.count == 2, "carry previous players")
            viewModel.carryPlayersFromPreviousPhoto()
            require(viewModel.currentAssignments.count == 2, "carry skips duplicates")
            viewModel.undo()
            require(viewModel.currentAssignments.isEmpty, "undo carry")

            let flickrRecord = FlickrPhotoRecord(
                id: "123456789",
                albumID: "987654321",
                title: "IMG_1234",
                displayURL: URL(string: "https://live.staticflickr.com/1/123456789_secret_m.jpg")!,
                thumbnailURL: URL(string: "https://live.staticflickr.com/1/123456789_secret_t.jpg"),
                lastUpdate: "1700000000"
            )
            var flickrPhoto = SessionPhoto(flickrRecord: flickrRecord, albumID: flickrRecord.albumID)
            flickrPhoto.originalFlickrDescription = "Existing Flickr description"
            flickrPhoto.flickrMetadataLoaded = true
            flickrPhoto.flickrSyncState = .pending
            flickrPhoto.flickrLastUpdate = "1700000000"
            flickrPhoto.workingDescription = "New local description"

            let flickrSession = PhotoSession(
                name: "Flickr Self Test",
                folderURL: URL(string: "flickr://album/987654321")!,
                rosterIDs: [rosterID],
                descriptionPrefix: "Prefix",
                photos: [flickrPhoto],
                sourceType: .flickrAlbum,
                flickrUserID: "owner-id",
                flickrUserName: "owner",
                flickrAlbumID: flickrRecord.albumID,
                flickrAlbumTitle: "Test Album"
            )
            let flickrPersistence = SessionPersistenceService(directoryURL: directory.appendingPathComponent("FlickrSessions"))
            try flickrPersistence.save(flickrSession)
            let loadedFlickrSession = try flickrPersistence.load(id: flickrSession.id)
            require(loadedFlickrSession.sourceType == .flickrAlbum, "Flickr session source persistence")
            require(loadedFlickrSession.photos[0].stableIdentifier == "flickr:123456789", "Flickr photo identity persistence")
            require(loadedFlickrSession.photos[0].originalFlickrDescription == "Existing Flickr description", "original Flickr description persistence")
            require(loadedFlickrSession.photos[0].workingDescription == "New local description", "working Flickr description persistence")
            require(loadedFlickrSession.photos[0].flickrSyncState == .pending, "Flickr sync state persistence")

            let offlineService = SelfTestFlickrService()
            let queueURL = directory.appendingPathComponent("FlickrSyncQueue.json")
            let queue = FlickrSyncQueue(
                service: offlineService,
                persistence: flickrPersistence,
                queueURL: queueURL
            )
            queue.enqueue(
                sessionID: flickrSession.id,
                photo: loadedFlickrSession.photos[0],
                description: "New local description",
                expectedLastUpdate: "1700000000"
            )
            require(queue.pendingCount == 1, "durable Flickr queue enqueue")
            let queuedSession = try flickrPersistence.load(id: flickrSession.id)
            require(queuedSession.photos[0].flickrSyncState == .pending, "queued Flickr photo state persistence")
            let restoredQueue = FlickrSyncQueue(
                service: offlineService,
                persistence: flickrPersistence,
                queueURL: queueURL
            )
            require(restoredQueue.pendingCount == 1, "durable Flickr queue restore")

            require(
                OAuthSigner.percentEncode("Ladies + Gentlemen") == "Ladies%20%2B%20Gentlemen",
                "OAuth RFC 3986 encoding"
            )
            let requestParameters = OAuthSigner.formEncoded([
                "photo_id": "123456789",
                "description": "A description with spaces"
            ])
            require(requestParameters.contains("description=A%20description%20with%20spaces"), "Flickr description request encoding")
            require(!requestParameters.contains("title="), "Flickr description request does not include title")

            print("Kadro self-test passed: CSV import, keyboard flow, Flickr persistence/queue, OAuth encoding, and description generation")
        } catch {
            fputs("Kadro self-test failed: \(error.localizedDescription)\n", stderr)
            Darwin.exit(1)
        }
    }

    private static func require(_ condition: Bool, _ message: String) {
        guard condition else {
        fputs("Kadro self-test failed: \(message)\n", stderr)
            Darwin.exit(1)
        }
    }
}

@MainActor
private final class SelfTestFlickrService: FlickrService {
    let authenticationStatus: FlickrAuthenticationStatus = .signedOut

    func authenticate() async throws {
        throw FlickrServiceError.notAuthenticated
    }

    func disconnect() {}

    func getCurrentUser() async throws -> FlickrUser {
        throw FlickrServiceError.notAuthenticated
    }

    func getAlbums() async throws -> [FlickrAlbum] {
        throw FlickrServiceError.notAuthenticated
    }

    func getAlbumPhotos(albumID: String) async throws -> [FlickrPhotoRecord] {
        throw FlickrServiceError.notAuthenticated
    }

    func getPhotoInfo(photoID: String) async throws -> FlickrPhotoInfo {
        throw FlickrServiceError.notAuthenticated
    }

    func setPhotoDescription(photoID: String, description: String) async throws {
        throw FlickrServiceError.notAuthenticated
    }

    func safelySetPhotoDescription(
        photoID: String,
        expectedLastUpdate: String?,
        description: String
    ) async throws -> FlickrPhotoInfo {
        throw FlickrServiceError.notAuthenticated
    }
}
