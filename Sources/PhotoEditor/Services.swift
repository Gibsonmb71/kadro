import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct FolderSelection {
    let url: URL
    let bookmarkData: Data?
}

final class SessionPersistenceService {
    private let sessionsDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directoryURL: URL = AppPaths.sessionsDirectory) {
        self.sessionsDirectory = directoryURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func save(_ session: PhotoSession) throws {
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
        let data = try encoder.encode(session)
        try data.write(to: fileURL(for: session.id), options: .atomic)
    }

    func load(id: UUID) throws -> PhotoSession {
        let data = try Data(contentsOf: fileURL(for: id))
        return try decoder.decode(PhotoSession.self, from: data)
    }

    func load(fileURL: URL) throws -> PhotoSession {
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(PhotoSession.self, from: data)
    }

    func fileURL(for id: UUID) -> URL {
        sessionsDirectory.appendingPathComponent("\(id.uuidString).photosession")
    }

    func recentSessions() -> [RecentSessionSummary] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter { $0.pathExtension == "photosession" }
            .compactMap { try? load(fileURL: $0) }
            .map(RecentSessionSummary.init)
            .sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }
}

final class FolderAccessService {
    private let supportedExtensions: Set<String> = ["jpg", "jpeg", "heic", "png"]

    func choosePhotoFolder() -> FolderSelection? {
        let panel = NSOpenPanel()
        panel.title = "Choose Photo Folder"
        panel.message = "Select the folder containing your Lightroom exports."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return FolderSelection(url: url, bookmarkData: makeBookmark(for: url))
    }

    func chooseCSVFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Import Roster CSV"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    func chooseSessionFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Open Photo Session"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            .json,
            UTType(filenameExtension: "photosession") ?? .data
        ]

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    func resolveFolder(for session: PhotoSession) -> URL {
        if let bookmarkData = session.folderBookmarkData {
            var isStale = false
            if let resolvedURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                _ = resolvedURL.startAccessingSecurityScopedResource()
                return resolvedURL
            }
        }

        return session.folderURL
    }

    func photoFiles(in folderURL: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .nameKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    func makeBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }
}

enum DescriptionGenerator {
    static func generate(
        prefix: String,
        assignments: [PhotoPersonAssignment],
        resolveName: (PhotoPersonAssignment) -> String?
    ) -> String {
        let cleanedPrefix = prefix.trimmed
        var lines: [String] = []

        if !cleanedPrefix.isEmpty {
            lines.append(cleanedPrefix)
            if !assignments.isEmpty {
                lines.append("")
            }
        }

        for assignment in assignments {
            if let name = resolveName(assignment), !name.trimmed.isEmpty {
                lines.append("#\(assignment.jerseyNumber) \(name)")
            }
        }

        return lines.joined(separator: "\n")
    }
}

struct RosterImportService {
    func preview(fileURL: URL) throws -> CSVImportPreview {
        let text = try readText(fileURL: fileURL)
        let rawRows = parseCSV(text).filter { row in
            row.contains { !$0.trimmed.isEmpty }
        }

        guard !rawRows.isEmpty else {
            return CSVImportPreview(headers: [], rows: [])
        }

        let firstRow = rawRows[0]
        let firstCell = firstRow.first?.trimmed.replacingOccurrences(of: "\u{FEFF}", with: "") ?? ""
        let appearsToHaveHeader = Int(firstCell) == nil
        let columnCount = max(rawRows.map(\.count).max() ?? 0, 1)

        if appearsToHaveHeader {
            let headers = padded(firstRow, count: columnCount).enumerated().map { index, value in
                let cleanedValue = value.trimmed.replacingOccurrences(of: "\u{FEFF}", with: "")
                return cleanedValue.isEmpty ? "Column \(index + 1)" : cleanedValue
            }
            let rows = rawRows.dropFirst().map { padded($0, count: columnCount) }
            return CSVImportPreview(headers: headers, rows: Array(rows))
        }

        let headers = (0..<columnCount).map { index in
            switch index {
            case 0:
                return "Number"
            case 1:
                return "First Name / Name"
            case 2:
                return "Last Name"
            default:
                return "Column \(index + 1)"
            }
        }
        return CSVImportPreview(headers: headers, rows: rawRows.map { padded($0, count: columnCount) })
    }

    func inferredMapping(for headers: [String]) -> CSVColumnMapping {
        let normalized = headers.map { $0.lowercased().replacingOccurrences(of: "_", with: " ") }
        let number = normalized.firstIndex { value in
            value.contains("number") || value.contains("jersey") || value == "#"
        } ?? 0
        let first = normalized.firstIndex { value in value.contains("first") }
        let last = normalized.firstIndex { value in value.contains("last") || value.contains("surname") }
        let name = normalized.firstIndex { value in
            value == "name" || value.contains("full name") || value.contains("display")
        }

        return CSVColumnMapping(
            numberColumn: number,
            firstNameColumn: first,
            lastNameColumn: last,
            nameColumn: name
        )
    }

    private func padded(_ row: [String], count: Int) -> [String] {
        row + Array(repeating: "", count: max(0, count - row.count))
    }

    private func parseCSV(_ text: String) -> [[String]] {
        parseCSV(text, delimiter: detectDelimiter(in: text))
    }

    private func parseCSV(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var insideQuotes = false
        let normalizedText = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let characters = Array(normalizedText)

        var index = 0
        while index < characters.count {
            let character = characters[index]

            if character == "\"" {
                if insideQuotes, index + 1 < characters.count, characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 1
                } else {
                    insideQuotes.toggle()
                }
            } else if character == delimiter && !insideQuotes {
                row.append(cleanField(field))
                field = ""
            } else if character == "\n" && !insideQuotes {
                row.append(cleanField(field))
                field = ""
                if !row.isEmpty {
                    rows.append(row)
                }
                row = []
            } else {
                field.append(character)
            }

            index += 1
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(cleanField(field))
            rows.append(row)
        }

        return rows
    }

    private func detectDelimiter(in text: String) -> Character {
        let candidates: [Character] = [",", ";", "\t", "|"]
        var bestDelimiter = candidates[0]
        var bestScore = Int.min

        for (order, candidate) in candidates.enumerated() {
            let rows = parseCSV(text, delimiter: candidate).filter { row in
                row.contains { !$0.trimmed.isEmpty }
            }
            guard let firstRow = rows.first else { continue }

            let widths = rows.map(\.count)
            let mostCommonWidth = widths.reduce(into: [:]) { counts, width in
                counts[width, default: 0] += 1
            }.max { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value < rhs.value
            }?.key ?? 1
            let consistentRows = widths.filter { $0 == mostCommonWidth }.count

            // Prefer a delimiter that splits the first record and keeps the
            // remaining records at the same width. The order keeps comma as
            // the deterministic fallback for ambiguous single-row files.
            var score = 0
            score += firstRow.count > 1 ? 10_000 : 0
            score += mostCommonWidth > 1 ? 1_000 : 0
            score += consistentRows * 100
            score += mostCommonWidth * 10
            score -= order

            if score > bestScore {
                bestScore = score
                bestDelimiter = candidate
            }
        }

        return bestDelimiter
    }

    private func cleanField(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{FEFF}", with: "")
    }

    private func readText(fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        let encodings: [String.Encoding] = [
            .utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .unicode
        ]

        for encoding in encodings {
            if let text = String(data: data, encoding: encoding) {
                return text
            }
        }

        throw CocoaError(.fileReadInapplicableStringEncoding)
    }
}

@MainActor
final class RosterLibraryStore: ObservableObject {
    @Published private(set) var snapshot: RosterLibrarySnapshot
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL = AppPaths.rosterLibraryFile) {
        self.fileURL = fileURL
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if let data = try? Data(contentsOf: fileURL),
           let stored = try? decoder.decode(RosterLibrarySnapshot.self, from: data) {
            snapshot = stored
        } else {
            snapshot = RosterLibrarySnapshot()
        }
    }

    var rosters: [Roster] {
        snapshot.rosters.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func roster(id: UUID) -> Roster? {
        snapshot.rosters.first { $0.id == id }
    }

    func person(id: UUID) -> Person? {
        snapshot.people.first { $0.id == id }
    }

    func entries(for rosterID: UUID) -> [RosterEntry] {
        snapshot.entries.filter { $0.rosterID == rosterID }
    }

    func resolvedPlayer(for entry: RosterEntry) -> ResolvedRosterPlayer? {
        guard let person = person(id: entry.personID), let roster = roster(id: entry.rosterID) else { return nil }
        return ResolvedRosterPlayer(
            id: entry.id,
            entryID: entry.id,
            personID: entry.personID,
            rosterID: entry.rosterID,
            jerseyNumber: entry.jerseyNumber,
            name: person.fullName,
            teamName: roster.teamName.isEmpty ? roster.name : roster.teamName,
            rosterName: roster.name
        )
    }

    func player(number: String, rosterID: UUID) -> ResolvedRosterPlayer? {
        let normalized = number.normalizedJerseyNumber
        return entries(for: rosterID)
            .first { $0.jerseyNumber.normalizedJerseyNumber == normalized }
            .flatMap(resolvedPlayer(for:))
    }

    func searchPlayers(query: String, rosterIDs: [UUID]) -> [ResolvedRosterPlayer] {
        let cleanedQuery = query.trimmed.lowercased()
        let allowed = Set(rosterIDs)
        let players = snapshot.entries
            .filter { allowed.contains($0.rosterID) }
            .compactMap(resolvedPlayer(for:))

        guard !cleanedQuery.isEmpty else {
            return players
        }

        return players.filter { player in
            player.name.lowercased().contains(cleanedQuery)
                || player.teamName.lowercased().contains(cleanedQuery)
                || player.jerseyNumber.contains(cleanedQuery)
        }
    }

    @discardableResult
    func createRoster(
        name: String,
        teamName: String,
        sport: String = "",
        season: String = ""
    ) -> UUID {
        let roster = Roster(name: name.trimmed.isEmpty ? "Untitled Roster" : name.trimmed, teamName: teamName.trimmed, sport: sport.trimmed, season: season.trimmed)
        snapshot.rosters.append(roster)
        persist()
        return roster.id
    }

    func updateRoster(_ roster: Roster) {
        guard let index = snapshot.rosters.firstIndex(where: { $0.id == roster.id }) else { return }
        snapshot.rosters[index] = roster
        persist()
    }

    func deleteRoster(id: UUID) {
        snapshot.rosters.removeAll { $0.id == id }
        snapshot.entries.removeAll { $0.rosterID == id }
        persist()
    }

    @discardableResult
    func addPlayer(
        firstName: String,
        lastName: String,
        jerseyNumber: String,
        rosterID: UUID,
        displayName: String? = nil
    ) -> UUID? {
        let number = jerseyNumber.trimmed
        guard !number.isEmpty else { return nil }
        let personID = upsertPerson(firstName: firstName, lastName: lastName, displayName: displayName)
        let entry = RosterEntry(rosterID: rosterID, personID: personID, jerseyNumber: number)
        snapshot.entries.append(entry)
        persist()
        return entry.id
    }

    func removeEntry(id: UUID) {
        snapshot.entries.removeAll { $0.id == id }
        persist()
    }

    @discardableResult
    func importRoster(
        preview: CSVImportPreview,
        mapping: CSVColumnMapping,
        name: String,
        teamName: String,
        sport: String,
        season: String
    ) -> UUID {
        let rosterID = createRoster(name: name, teamName: teamName, sport: sport, season: season)

        for row in preview.rows {
            guard mapping.numberColumn < row.count else { continue }
            let number = row[mapping.numberColumn].trimmed
            guard !number.isEmpty else { continue }

            let firstName: String
            let lastName: String
            let displayName: String?

            if let nameColumn = mapping.nameColumn, nameColumn < row.count {
                let parts = splitName(row[nameColumn].trimmed)
                firstName = parts.first
                lastName = parts.last
                displayName = nil
            } else {
                firstName = mapping.firstNameColumn.flatMap { $0 < row.count ? row[$0].trimmed : nil } ?? ""
                lastName = mapping.lastNameColumn.flatMap { $0 < row.count ? row[$0].trimmed : nil } ?? ""
                displayName = nil
            }

            guard !firstName.isEmpty || !lastName.isEmpty else { continue }
            _ = addPlayer(
                firstName: firstName,
                lastName: lastName,
                jerseyNumber: number,
                rosterID: rosterID,
                displayName: displayName
            )
        }

        return rosterID
    }

    private func upsertPerson(firstName: String, lastName: String, displayName: String?) -> UUID {
        let normalizedFirst = firstName.trimmed.lowercased()
        let normalizedLast = lastName.trimmed.lowercased()
        if let existing = snapshot.people.first(where: {
            $0.firstName.trimmed.lowercased() == normalizedFirst
                && $0.lastName.trimmed.lowercased() == normalizedLast
        }) {
            return existing.id
        }

        let person = Person(firstName: firstName.trimmed, lastName: lastName.trimmed, displayName: displayName)
        snapshot.people.append(person)
        return person.id
    }

    private func splitName(_ value: String) -> (first: String, last: String) {
        let parts = value.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard let first = parts.first else { return ("", "") }
        return (first, parts.dropFirst().joined(separator: " "))
    }

    private func persist() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

final class PhotoLoadingService {
    static let shared = PhotoLoadingService()

    private let cache: NSCache<NSString, NSImage>

    init() {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 32
        cache.totalCostLimit = 256 * 1024 * 1024
        self.cache = cache
    }

    func loadImage(for url: URL, maxPixelSize: Int = 2400) async -> NSImage? {
        let cacheKey = "\(url.absoluteString)|\(maxPixelSize)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let data = await readDownsampledData(url: url, maxPixelSize: maxPixelSize)
        guard let data, let image = NSImage(data: data) else { return nil }
        let cost = max(image.size.width * image.size.height * 4, 1)
        cache.setObject(image, forKey: cacheKey, cost: Int(cost))
        return image
    }

    func preload(urls: [URL], maxPixelSize: Int = 720) {
        for url in urls {
            Task { _ = await loadImage(for: url, maxPixelSize: maxPixelSize) }
        }
    }

    private func readDownsampledData(url: URL, maxPixelSize: Int) async -> Data? {
        if url.isFileURL {
            return await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let data = try? Data(contentsOf: url)
                    continuation.resume(returning: Self.downsample(data: data, maxPixelSize: maxPixelSize))
                }
            }
        }

        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return Self.downsample(data: data, maxPixelSize: maxPixelSize)
    }

    private static func downsample(data: Data?, maxPixelSize: Int) -> Data? {
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return data
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return data
        }

        let bitmap = NSBitmapImageRep(cgImage: thumbnail)
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) ?? data
    }
}
