import AppKit
import SwiftUI

struct StartView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            List {
                Section("Recent Sessions") {
                    if appState.recentSessions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No sessions yet")
                                .font(.headline)
                            Text("Choose a photo folder and roster to begin captioning.")
                                .foregroundStyle(.secondary)
                            Button("New Photo Session") {
                                appState.startNewSession()
                            }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 22)
                    } else {
                        ForEach(appState.recentSessions) { session in
                            Button {
                                appState.openRecentSession(session)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "photo.on.rectangle")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(session.name)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text(session.folderName)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 3) {
                                        Text("\(session.reviewedPhotoCount) / \(session.totalPhotoCount) reviewed")
                                            .font(.callout.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                        if session.captionedPhotoCount > session.reviewedPhotoCount {
                                            Text("\(session.captionedPhotoCount) captioned")
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }
                                        HStack(spacing: 8) {
                                            if session.flaggedPhotoCount > 0 {
                                                Text("\(session.flaggedPhotoCount) flagged")
                                                    .foregroundStyle(.orange)
                                            }
                                            Text(session.lastOpenedAt, style: .relative)
                                                .foregroundStyle(.tertiary)
                                        }
                                        .font(.caption)
                                    }
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Photo Session") {
                        appState.startNewSession()
                    }
                    .keyboardShortcut(.defaultAction)
                }

                ToolbarItem {
                    Button {
                        appState.openSessionFile()
                    } label: {
                        Label("Open Session File…", systemImage: "folder")
                    }
                    .help("Open Session File…")
                }

                ToolbarItem {
                    Button {
                        appState.showRosters()
                    } label: {
                        Label("Manage Rosters", systemImage: "person.3")
                    }
                }

                ToolbarItem {
                    SettingsLink {
                        Label("Settings…", systemImage: "gearshape")
                    }
                    .help("Settings…")
                }
            }
        }
    }
}

struct SessionSetupView: View {
    @EnvironmentObject private var appState: AppState
    @StateCompat private var sessionName = ""
    @StateCompat private var selectedSource: PhotoSourceType = .localFolder
    @StateCompat private var folderSelection: FolderSelection?
    @StateCompat private var flickrAlbum: FlickrAlbum?
    @StateCompat private var eventDate = Date()
    @StateCompat private var sport = ""
    @StateCompat private var opponent = ""
    @StateCompat private var descriptionPrefix = ""
    @StateCompat private var selectedRosterIDs = Set<UUID>()
    @StateCompat private var importURL: URL?
    @StateCompat private var showingImport = false
    @StateCompat private var showingFlickrPicker = false
    @StateCompat private var showingFlickrWarning = false
    @StateCompat private var isStarting = false

    private var selectedRosters: [Roster] {
        appState.rosterStore.rosters.filter { selectedRosterIDs.contains($0.id) }
    }

    private var photoCount: Int {
        switch selectedSource {
        case .localFolder:
            guard let folderURL = folderSelection?.url else { return 0 }
            return appState.folderAccess.photoFiles(in: folderURL).count
        case .flickrAlbum:
            return flickrAlbum?.photoCount ?? 0
        }
    }

    private var sourceReady: Bool {
        switch selectedSource {
        case .localFolder:
            return folderSelection != nil
        case .flickrAlbum:
            return flickrAlbum != nil
        }
    }

    private var descriptionPreview: String {
        let sampleAssignments = selectedRosters.flatMap { roster in
            appState.rosterStore.entries(for: roster.id).prefix(2).map { entry in
                PhotoPersonAssignment(
                    personID: entry.personID,
                    rosterID: entry.rosterID,
                    rosterEntryID: entry.id,
                    jerseyNumber: entry.jerseyNumber
                )
            }
        }

        return DescriptionGenerator.generate(
            prefix: descriptionPrefix,
            assignments: Array(sampleAssignments.prefix(4))
        ) { assignment in
            appState.rosterStore.person(id: assignment.personID)?.fullName
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Photo Source") {
                    Picker("Source", selection: $selectedSource) {
                        ForEach(PhotoSourceType.allCases) { source in
                            Text(source.title).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)

                    if selectedSource == .localFolder {
                        LabeledContent("Folder") {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(folderSelection?.url.lastPathComponent ?? "No folder selected")
                                        .foregroundStyle(folderSelection == nil ? .secondary : .primary)
                                    if let folderSelection {
                                        Text(folderSelection.url.path)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }
                                Spacer(minLength: 8)
                                Button("Open Local Folder…") {
                                    selectedSource = .localFolder
                                    folderSelection = appState.folderAccess.choosePhotoFolder()
                                    if sessionName.isEmpty {
                                        sessionName = folderSelection?.url.lastPathComponent ?? ""
                                    }
                                }
                            }
                        }
                    } else {
                        LabeledContent("Album") {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(flickrAlbum?.title ?? "No album selected")
                                        .foregroundStyle(flickrAlbum == nil ? .secondary : .primary)
                                    if let flickrAlbum {
                                        Text("\(flickrAlbum.photoCount) photos")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 8)
                                Button("Open Flickr Album…") {
                                    selectedSource = .flickrAlbum
                                    showingFlickrPicker = true
                                }
                            }
                        }
                    }
                }

                Section("Event Details") {
                    TextField("Session name", text: $sessionName)
                    DatePicker("Event date", selection: $eventDate, displayedComponents: .date)
                    TextField("Sport", text: $sport, prompt: Text("Optional"))
                    TextField("Opponent", text: $opponent, prompt: Text("Optional"))
                }

                Section("Rosters") {
                    if appState.rosterStore.rosters.isEmpty {
                        Text("No rosters yet. Import a CSV or create one manually.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appState.rosterStore.rosters) { roster in
                            Toggle(isOn: Binding(
                                get: { selectedRosterIDs.contains(roster.id) },
                                set: { isSelected in
                                    if isSelected {
                                        selectedRosterIDs.insert(roster.id)
                                    } else {
                                        selectedRosterIDs.remove(roster.id)
                                    }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(roster.teamName.trimmed.isEmpty ? roster.name : roster.teamName)
                                    Text([roster.sport, roster.season].filter { !$0.trimmed.isEmpty }.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }

                    HStack {
                        Button("Import CSV…") {
                            chooseCSV()
                        }
                        Button("Manage Rosters") {
                            appState.showRosters(returnTo: .setup)
                        }
                    }
                }

                Section("Description Prefix") {
                    TextField(
                        "Optional event prefix",
                        text: $descriptionPrefix,
                        axis: .vertical
                    )
                    .lineLimit(2...4)

                    LabeledContent("Preview") {
                        Text(descriptionPreview.isEmpty ? "Your description will appear here." : descriptionPreview)
                            .font(.body.monospaced())
                            .foregroundStyle(descriptionPreview.isEmpty ? .tertiary : .primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle("New Photo Session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        appState.goHome()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 10) {
                        if sourceReady {
                            Text("\(photoCount) photos")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Button(isStarting ? "Opening…" : "Start Captioning") {
                            startSession()
                        }
                        .disabled(!sourceReady || selectedRosterIDs.isEmpty || isStarting)
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
        }
        .sheet(isPresented: $showingImport) {
            if let importURL {
                CSVImportPreviewView(url: importURL) { rosterID in
                    selectedRosterIDs.insert(rosterID)
                    showingImport = false
                }
            } else {
                Text("No CSV selected")
            }
        }
        .sheet(isPresented: $showingFlickrPicker) {
            FlickrAlbumPickerView(service: appState.flickrService) { album in
                flickrAlbum = album
                selectedSource = .flickrAlbum
                if sessionName.isEmpty {
                    sessionName = album.title
                }
            }
        }
        .alert("Edit existing Flickr descriptions?", isPresented: $showingFlickrWarning) {
            Button("Cancel", role: .cancel) { }
            Button("Start Captioning") {
                startFlickrSession()
            }
        } message: {
            Text("Descriptions edited in this session will be updated on the existing Flickr photos. Photos themselves, titles, tags, privacy, and albums will not be changed.")
        }
    }


    private func chooseCSV() {
        guard let url = appState.folderAccess.chooseCSVFile() else { return }
        importURL = url
        showingImport = true
    }

    private func startSession() {
        switch selectedSource {
        case .localFolder:
            guard let folderSelection else { return }
            _ = appState.createSession(
                name: sessionName,
                folderSelection: folderSelection,
                eventDate: eventDate,
                sport: sport,
                opponent: opponent,
                rosterIDs: selectedRosters.map(\.id),
                descriptionPrefix: descriptionPrefix
            )
        case .flickrAlbum:
            guard flickrAlbum != nil else { return }
            showingFlickrWarning = true
        }
    }

    private func startFlickrSession() {
        guard let flickrAlbum else { return }
        isStarting = true
        Task { @MainActor in
            _ = await appState.createFlickrSession(
                name: sessionName,
                album: flickrAlbum,
                eventDate: eventDate,
                sport: sport,
                opponent: opponent,
                rosterIDs: selectedRosters.map(\.id),
                descriptionPrefix: descriptionPrefix
            )
            isStarting = false
        }
    }
}

@MainActor
final class CSVImportPreviewModel: ObservableObject {
    let url: URL
    private let service = RosterImportService()
    @Published var preview: CSVImportPreview?
    @Published var errorMessage: String?
    @Published var rosterName: String
    @Published var teamName = ""
    @Published var sport = ""
    @Published var season = ""
    @Published var numberColumn = 0
    @Published var firstNameColumn: Int?
    @Published var lastNameColumn: Int?
    @Published var nameColumn: Int?

    init(url: URL) {
        self.url = url
        self.rosterName = url.deletingPathExtension().lastPathComponent

        do {
            let preview = try service.preview(fileURL: url)
            self.preview = preview
            let mapping = service.inferredMapping(for: preview.headers)
            self.numberColumn = mapping.numberColumn
            self.firstNameColumn = mapping.firstNameColumn
            self.lastNameColumn = mapping.lastNameColumn
            self.nameColumn = mapping.nameColumn
        } catch {
            self.preview = nil
            self.errorMessage = error.localizedDescription
        }
    }

    var mapping: CSVColumnMapping {
        CSVColumnMapping(
            numberColumn: numberColumn,
            firstNameColumn: firstNameColumn,
            lastNameColumn: lastNameColumn,
            nameColumn: nameColumn
        )
    }

    func importRoster(using store: RosterLibraryStore) -> UUID? {
        guard let preview, !preview.rows.isEmpty else {
            errorMessage = "The CSV does not contain any roster rows."
            return nil
        }

        return store.importRoster(
            preview: preview,
            mapping: mapping,
            name: rosterName,
            teamName: teamName,
            sport: sport,
            season: season
        )
    }
}

struct CSVImportPreviewView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: CSVImportPreviewModel
    let url: URL
    let onImported: (UUID) -> Void

    init(url: URL, onImported: @escaping (UUID) -> Void) {
        self.url = url
        self.onImported = onImported
        _model = StateObject(wrappedValue: CSVImportPreviewModel(url: url))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Import Roster CSV")
                        .font(.title2.weight(.semibold))
                    Text(url.lastPathComponent)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            } else if let preview = model.preview {
                rosterFields
                mappingFields(headers: preview.headers)
                previewTable(preview)
            }

            HStack {
                Spacer()
                Button("Import Roster") {
                    if let rosterID = model.importRoster(using: appState.rosterStore) {
                        onImported(rosterID)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.preview?.rows.isEmpty != false)
            }
        }
        .padding(24)
        .frame(minWidth: 760, minHeight: 560)
    }

    private var rosterFields: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
            GridRow {
                Text("Roster name").foregroundStyle(.secondary)
                TextField("Boys Soccer 2026-27", text: $model.rosterName)
                Text("Team name").foregroundStyle(.secondary)
                TextField("Ninety Six", text: $model.teamName)
            }
            GridRow {
                Text("Sport").foregroundStyle(.secondary)
                TextField("Optional", text: $model.sport)
                Text("Season").foregroundStyle(.secondary)
                TextField("Optional", text: $model.season)
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    private func mappingFields(headers: [String]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Map columns")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow {
                    columnPicker(title: "Jersey number", selection: $model.numberColumn, headers: headers)
                    optionalColumnPicker(title: "Full name", selection: $model.nameColumn, headers: headers)
                }
                GridRow {
                    optionalColumnPicker(title: "First name", selection: $model.firstNameColumn, headers: headers)
                    optionalColumnPicker(title: "Last name", selection: $model.lastNameColumn, headers: headers)
                }
            }
        }
    }

    private func columnPicker(title: String, selection: Binding<Int>, headers: [String]) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Picker("", selection: selection) {
                ForEach(headers.indices, id: \.self) { index in
                    Text(headers[index]).tag(index)
                }
            }
            .labelsHidden()
        }
    }

    private func optionalColumnPicker(title: String, selection: Binding<Int?>, headers: [String]) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Picker("", selection: selection) {
                Text("Not used").tag(nil as Int?)
                ForEach(headers.indices, id: \.self) { index in
                    Text(headers[index]).tag(Optional(index))
                }
            }
            .labelsHidden()
        }
    }

    private func previewTable(_ preview: CSVImportPreview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Preview")
                .font(.headline)
            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        ForEach(preview.headers.indices, id: \.self) { index in
                            Text(preview.headers[index])
                                .font(.caption.weight(.semibold))
                                .frame(width: 150, alignment: .leading)
                                .padding(8)
                                .background(Color(nsColor: .controlBackgroundColor))
                        }
                    }
                    ForEach(Array(preview.rows.prefix(10).enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(row.indices, id: \.self) { index in
                                Text(row[index])
                                    .font(.callout)
                                    .frame(width: 150, alignment: .leading)
                                    .padding(8)
                                    .overlay(Rectangle().stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 240)
            Text("Showing the first \(min(preview.rows.count, 10)) of \(preview.rows.count) rows")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct RosterManagementView: View {
    @EnvironmentObject private var appState: AppState
    @StateCompat private var selectedRosterID: UUID?
    @StateCompat private var importURL: URL?
    @StateCompat private var showingImport = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $selectedRosterID) {
                    ForEach(appState.rosterStore.rosters) { roster in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(roster.teamName.trimmed.isEmpty ? roster.name : roster.teamName)
                                .font(.headline)
                            Text(roster.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(roster.id)
                        .padding(.vertical, 3)
                    }
                }
                .listStyle(.sidebar)

                Divider()
                HStack {
                    Button {
                        selectedRosterID = appState.rosterStore.createRoster(
                            name: "New Roster",
                            teamName: ""
                        )
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("New Roster")

                    Button {
                        chooseCSV()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderless)
                    .help("Import CSV")

                    Spacer()
                }
                .padding(10)
            }
            .navigationTitle("Rosters")
        } detail: {
            if let selectedRosterID {
                RosterEditorView(store: appState.rosterStore, rosterID: selectedRosterID) {
                    self.selectedRosterID = nil
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "person.3")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    Text("Select a roster")
                        .font(.headline)
                    Text("Create a roster or import a CSV to reuse player identities across sessions.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    appState.leaveRosters()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
            }
        }
        .onAppear {
            if selectedRosterID == nil {
                selectedRosterID = appState.rosterStore.rosters.first?.id
            }
        }
        .sheet(isPresented: $showingImport) {
            if let importURL {
                CSVImportPreviewView(url: importURL) { rosterID in
                    selectedRosterID = rosterID
                    showingImport = false
                }
            }
        }
    }

    private func chooseCSV() {
        guard let url = appState.folderAccess.chooseCSVFile() else { return }
        importURL = url
        showingImport = true
    }
}

struct RosterEditorView: View {
    @ObservedObject var store: RosterLibraryStore
    let rosterID: UUID
    let onDelete: () -> Void
    @StateCompat private var name: String
    @StateCompat private var teamName: String
    @StateCompat private var sport: String
    @StateCompat private var season: String
    @StateCompat private var newNumber = ""
    @StateCompat private var newFirstName = ""
    @StateCompat private var newLastName = ""

    init(store: RosterLibraryStore, rosterID: UUID, onDelete: @escaping () -> Void) {
        self.store = store
        self.rosterID = rosterID
        self.onDelete = onDelete
        let roster = store.roster(id: rosterID)
        _name = StateCompat(wrappedValue: roster?.name ?? "")
        _teamName = StateCompat(wrappedValue: roster?.teamName ?? "")
        _sport = StateCompat(wrappedValue: roster?.sport ?? "")
        _season = StateCompat(wrappedValue: roster?.season ?? "")
    }

    var body: some View {
        if let roster = store.roster(id: rosterID) {
            Form {
                Section("Roster Details") {
                    TextField("Roster name", text: $name)
                    TextField("Team name", text: $teamName)
                    TextField("Sport", text: $sport)
                    TextField("Season", text: $season)
                    HStack {
                        Button("Save Details") {
                            store.updateRoster(Roster(
                                id: roster.id,
                                name: name,
                                teamName: teamName,
                                sport: sport,
                                season: season
                            ))
                        }
                        .buttonStyle(.borderedProminent)
                        Spacer()
                        Button("Delete Roster", role: .destructive) {
                            store.deleteRoster(id: rosterID)
                            onDelete()
                        }
                    }
                }

                Section("Add Player") {
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                        GridRow {
                            TextField("#", text: $newNumber)
                                .frame(width: 70)
                            TextField("First name", text: $newFirstName)
                            TextField("Last name", text: $newLastName)
                            Button("Add") {
                                addPlayer()
                            }
                            .buttonStyle(.bordered)
                            .disabled(newNumber.trimmed.isEmpty || (newFirstName.trimmed.isEmpty && newLastName.trimmed.isEmpty))
                        }
                    }
                }

                Section("Players · \(store.entries(for: rosterID).count)") {
                    if store.entries(for: rosterID).isEmpty {
                        Text("No players yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.entries(for: rosterID)) { entry in
                            HStack(spacing: 12) {
                                Text("#\(entry.jerseyNumber)")
                                    .font(.body.monospaced().weight(.semibold))
                                    .frame(width: 54, alignment: .leading)
                                Text(store.person(id: entry.personID)?.fullName ?? "Unknown player")
                                Spacer()
                                Button {
                                    store.removeEntry(id: entry.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                                .help("Remove player")
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(roster.teamName.trimmed.isEmpty ? roster.name : roster.teamName)
        } else {
            Text("Roster no longer exists")
        }
    }

    private func addPlayer() {
        _ = store.addPlayer(
            firstName: newFirstName,
            lastName: newLastName,
            jerseyNumber: newNumber,
            rosterID: rosterID
        )
        newNumber = ""
        newFirstName = ""
        newLastName = ""
    }
}

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @StateCompat private var flickrAPIKey = ""
    @StateCompat private var flickrAPISecret = ""
    @StateCompat private var flickrSettingsMessage = ""
    @StateCompat private var isConnectingFlickr = false

    var body: some View {
        Form {
            Section("Flickr") {
                LabeledContent("Connection") {
                    Text(connectionTitle)
                        .foregroundStyle(.secondary)
                }

                TextField("API key", text: $flickrAPIKey)
                    .textContentType(.username)
                SecureField("API secret", text: $flickrAPISecret)

                HStack {
                    Button("Save Flickr Credentials") {
                        saveFlickrCredentials()
                    }
                    .buttonStyle(.borderedProminent)

                    if !flickrSettingsMessage.isEmpty {
                        Text(flickrSettingsMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if appState.flickrService.authenticationStatus == .authenticated {
                    Button("Disconnect Flickr") {
                        appState.flickrService.disconnect()
                    }
                } else if appState.flickrService.authenticationStatus == .notConfigured {
                    Text("Enter your Flickr application key and secret above, then save them to enable album editing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button(isConnectingFlickr ? "Connecting…" : "Connect to Flickr…") {
                        connectFlickr()
                    }
                    .disabled(isConnectingFlickr)
                }
            }

            Section("Description Format") {
                Text("The default format is a prefix followed by one player per line, in the order entered:")
                    .foregroundStyle(.secondary)
                Text("Event prefix\n\n#12 First Last\n#19 First Last")
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }

            Section("Storage") {
                Text("Sessions and rosters are stored locally in Application Support. Original photo files are never modified.")
                    .foregroundStyle(.secondary)
                Text(AppPaths.applicationSupportDirectory.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 480)
        .padding()
        .onAppear {
            flickrAPIKey = appState.flickrService.configuredAPIKey
        }
    }

    private var connectionTitle: String {
        switch appState.flickrService.authenticationStatus {
        case .notConfigured:
            return "Not configured"
        case .signedOut:
            return "Not connected"
        case .authenticating:
            return "Connecting…"
        case .authenticated:
            return "Connected"
        }
    }

    private func saveFlickrCredentials() {
        do {
            try appState.flickrService.configureConsumerCredentials(
                apiKey: flickrAPIKey,
                apiSecret: flickrAPISecret
            )
            flickrAPISecret = ""
            flickrSettingsMessage = "Saved in Keychain · connect to Flickr next"
        } catch {
            flickrSettingsMessage = error.localizedDescription
        }
    }

    private func connectFlickr() {
        isConnectingFlickr = true
        flickrSettingsMessage = ""
        Task { @MainActor in
            do {
                try await appState.flickrService.authenticate()
                appState.flickrSyncQueue.resume()
                flickrSettingsMessage = "Connected to Flickr"
            } catch {
                flickrSettingsMessage = error.localizedDescription
            }
            isConnectingFlickr = false
        }
    }
}
