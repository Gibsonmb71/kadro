import AppKit
import AuthenticationServices
import CryptoKit
import Foundation
import Security

struct FlickrConfiguration: Sendable {
    let apiKey: String
    let apiSecret: String
    let callbackScheme: String

    var callbackURL: String {
        "\(callbackScheme)://flickr/oauth-callback"
    }

    static func current() -> FlickrConfiguration? {
        let info = Bundle.main.infoDictionary ?? [:]
        let environment = ProcessInfo.processInfo.environment
        let stored = FlickrConsumerConfigurationStore().load()
        let apiKey = [
            stored?.apiKey,
            info["FlickrAPIKey"] as? String,
            environment["FLICKR_API_KEY"]
        ]
        .compactMap { $0 }
        .first { !$0.trimmed.isEmpty } ?? ""
        let apiSecret = [
            stored?.apiSecret,
            info["FlickrAPISecret"] as? String,
            environment["FLICKR_API_SECRET"]
        ]
        .compactMap { $0 }
        .first { !$0.trimmed.isEmpty } ?? ""
        let callbackScheme = [
            info["FlickrOAuthCallbackScheme"] as? String,
            AppBrand.oauthCallbackScheme,
            "photoeditor"
        ]
        .compactMap { $0 }
        .first { !$0.trimmed.isEmpty } ?? "photoeditor"

        guard !apiKey.trimmed.isEmpty, !apiSecret.trimmed.isEmpty else {
            return nil
        }

        return FlickrConfiguration(
            apiKey: apiKey,
            apiSecret: apiSecret,
            callbackScheme: callbackScheme
        )
    }
}

enum FlickrAuthenticationStatus: Equatable {
    case notConfigured
    case signedOut
    case authenticating
    case authenticated
}

struct FlickrCredentials: Codable, Hashable, Sendable {
    let token: String
    let secret: String
    let userID: String
    let username: String
}

struct FlickrConsumerConfiguration: Codable, Hashable, Sendable {
    let apiKey: String
    let apiSecret: String
}

private enum FlickrKeychainQueries {
    static func query(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func data(for query: [String: Any]) -> Data? {
        var data: CFTypeRef?
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        guard SecItemCopyMatching(lookup as CFDictionary, &data) == errSecSuccess else {
            return nil
        }
        return data as? Data
    }
}

enum FlickrServiceError: LocalizedError, Equatable {
    case configurationMissing
    case notAuthenticated
    case authenticationCancelled
    case invalidResponse
    case httpStatus(Int)
    case api(code: Int, message: String)
    case conflict(remoteDescription: String, remoteLastUpdate: String?)

    var errorDescription: String? {
        switch self {
        case .configurationMissing:
            return "Flickr is not configured. Add the API key and secret in Kadro Settings."
        case .notAuthenticated:
            return "Connect to Flickr before opening an album."
        case .authenticationCancelled:
            return "Flickr sign-in was cancelled."
        case .invalidResponse:
            return "Flickr returned an invalid response."
        case .httpStatus(let status):
            return "Flickr returned HTTP status \(status)."
        case .api(let code, let message):
            return "Flickr error \(code): \(message)"
        case .conflict:
            return "This Flickr photo changed remotely before the local description could be saved."
        }
    }

    var isPermanent: Bool {
        switch self {
        case .configurationMissing, .notAuthenticated, .authenticationCancelled, .invalidResponse, .conflict:
            return true
        case .api(let code, _):
            return [1, 2, 96, 97, 98, 99, 100].contains(code)
        case .httpStatus(let status):
            return (400..<500).contains(status) && status != 408 && status != 429
        }
    }
}

final class FlickrCredentialStore {
    private let service = "com.photoeditor.flickr.oauth"
    private let account = "access-token"

    func load() -> FlickrCredentials? {
        let query = FlickrKeychainQueries.query(service: service, account: account)
        guard let data = FlickrKeychainQueries.data(for: query) else { return nil }
        return try? JSONDecoder().decode(FlickrCredentials.self, from: data)
    }

    func save(_ credentials: FlickrCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let query = FlickrKeychainQueries.query(service: service, account: account)
        let values: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            values.forEach { addQuery[$0.key] = $0.value }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError(status: addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainError(status: updateStatus)
        }
    }

    func delete() {
        let query = FlickrKeychainQueries.query(service: service, account: account)
        SecItemDelete(query as CFDictionary)
    }

    private struct KeychainError: LocalizedError {
        let status: OSStatus

        var errorDescription: String? {
            "Could not save Flickr credentials in Keychain (status \(status))."
        }
    }
}

final class FlickrConsumerConfigurationStore {
    private let service = "com.photoeditor.flickr.configuration"
    private let account = "consumer-credentials"

    func load() -> FlickrConsumerConfiguration? {
        let query = FlickrKeychainQueries.query(service: service, account: account)
        guard let data = FlickrKeychainQueries.data(for: query) else { return nil }
        return try? JSONDecoder().decode(FlickrConsumerConfiguration.self, from: data)
    }

    func save(apiKey: String, apiSecret: String) throws {
        let credentials = FlickrConsumerConfiguration(apiKey: apiKey, apiSecret: apiSecret)
        let data = try JSONEncoder().encode(credentials)
        let query = FlickrKeychainQueries.query(service: service, account: account)
        let values: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            values.forEach { addQuery[$0.key] = $0.value }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainConfigurationError(status: addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainConfigurationError(status: updateStatus)
        }
    }

    private struct KeychainConfigurationError: LocalizedError {
        let status: OSStatus

        var errorDescription: String? {
            "Could not save Flickr app credentials in Keychain (status \(status))."
        }
    }
}

@MainActor
final class FlickrOAuthClient: NSObject {
    private let configuration: FlickrConfiguration?
    private let credentialStore: FlickrCredentialStore
    private var webAuthenticationSession: ASWebAuthenticationSession?
    private let presentationContextProvider = FlickrPresentationContextProvider()

    init(
        configuration: FlickrConfiguration?,
        credentialStore: FlickrCredentialStore = FlickrCredentialStore()
    ) {
        self.configuration = configuration
        self.credentialStore = credentialStore
    }

    var credentials: FlickrCredentials? {
        credentialStore.load()
    }

    var isConfigured: Bool {
        configuration != nil
    }

    func authenticate() async throws -> FlickrCredentials {
        guard let configuration else {
            throw FlickrServiceError.configurationMissing
        }

        if let existing = credentialStore.load() {
            return existing
        }

        let requestToken = try await requestToken(configuration: configuration)
        let authorizationURL = try makeAuthorizationURL(
            configuration: configuration,
            token: requestToken.token
        )
        let callbackURL = try await openAuthorizationPage(
            url: authorizationURL,
            callbackScheme: configuration.callbackScheme
        )

        guard let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let callbackItems = callbackComponents.queryItems,
              let verifier = callbackItems.first(where: { $0.name == "oauth_verifier" })?.value,
              let callbackToken = callbackItems.first(where: { $0.name == "oauth_token" })?.value,
              callbackToken == requestToken.token else {
            throw FlickrServiceError.invalidResponse
        }

        let credentials = try await accessToken(
            configuration: configuration,
            requestToken: requestToken,
            verifier: verifier
        )
        try credentialStore.save(credentials)
        return credentials
    }

    func disconnect() {
        webAuthenticationSession?.cancel()
        webAuthenticationSession = nil
        credentialStore.delete()
    }

    func signedRequest(
        url: URL,
        method: String,
        parameters: [String: String],
        token: String?,
        tokenSecret: String?,
        includeInBody: Bool
    ) throws -> URLRequest {
        guard let configuration else {
            throw FlickrServiceError.configurationMissing
        }

        var allParameters = parameters
        allParameters["oauth_consumer_key"] = configuration.apiKey
        allParameters["oauth_nonce"] = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        allParameters["oauth_signature_method"] = "HMAC-SHA1"
        allParameters["oauth_timestamp"] = String(Int(Date().timeIntervalSince1970))
        allParameters["oauth_version"] = "1.0"
        if let token {
            allParameters["oauth_token"] = token
        }

        let signature = OAuthSigner.signature(
            method: method,
            url: url,
            parameters: allParameters,
            consumerSecret: configuration.apiSecret,
            tokenSecret: tokenSecret ?? ""
        )
        allParameters["oauth_signature"] = signature

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")

        if includeInBody {
            request.httpBody = OAuthSigner.formEncoded(allParameters).data(using: .utf8)
        } else {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.percentEncodedQuery = OAuthSigner.formEncoded(allParameters)
            guard let encodedURL = components?.url else {
                throw FlickrServiceError.invalidResponse
            }
            request = URLRequest(url: encodedURL)
            request.httpMethod = method
        }

        return request
    }

    private func requestToken(configuration: FlickrConfiguration) async throws -> OAuthToken {
        let url = URL(string: "https://www.flickr.com/services/oauth/request_token")!
        let parameters = ["oauth_callback": configuration.callbackURL]
        let request = try signedRequest(
            url: url,
            method: "POST",
            parameters: parameters,
            token: nil,
            tokenSecret: nil,
            includeInBody: true
        )
        let data = try await perform(request)
        let values = try parseForm(data)
        guard let token = values["oauth_token"], let secret = values["oauth_token_secret"] else {
            throw FlickrServiceError.invalidResponse
        }
        return OAuthToken(token: token, secret: secret)
    }

    private func makeAuthorizationURL(configuration: FlickrConfiguration, token: String) throws -> URL {
        var components = URLComponents(string: "https://www.flickr.com/services/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "oauth_token", value: token),
            URLQueryItem(name: "perms", value: "write")
        ]
        guard let url = components?.url else {
            throw FlickrServiceError.invalidResponse
        }
        return url
    }

    private func accessToken(
        configuration: FlickrConfiguration,
        requestToken: OAuthToken,
        verifier: String
    ) async throws -> FlickrCredentials {
        let url = URL(string: "https://www.flickr.com/services/oauth/access_token")!
        let parameters = [
            "oauth_verifier": verifier
        ]
        let request = try signedRequest(
            url: url,
            method: "POST",
            parameters: parameters,
            token: requestToken.token,
            tokenSecret: requestToken.secret,
            includeInBody: true
        )
        let data = try await perform(request)
        let values = try parseForm(data)
        guard let token = values["oauth_token"],
              let secret = values["oauth_token_secret"],
              let userID = values["user_nsid"],
              let username = values["username"] else {
            throw FlickrServiceError.invalidResponse
        }
        return FlickrCredentials(token: token, secret: secret, userID: userID, username: username)
    }

    private func openAuthorizationPage(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { [weak self] callbackURL, error in
                self?.webAuthenticationSession = nil
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error {
                    let nsError = error as NSError
                    if nsError.domain == ASWebAuthenticationSessionError.errorDomain {
                        continuation.resume(throwing: FlickrServiceError.authenticationCancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                } else {
                    continuation.resume(throwing: FlickrServiceError.authenticationCancelled)
                }
            }
            session.presentationContextProvider = presentationContextProvider
            session.prefersEphemeralWebBrowserSession = false
            webAuthenticationSession = session
            guard session.start() else {
                webAuthenticationSession = nil
                continuation.resume(throwing: FlickrServiceError.authenticationCancelled)
                return
            }
        }
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FlickrServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw FlickrServiceError.httpStatus(httpResponse.statusCode)
        }
        return data
    }

    private func parseForm(_ data: Data) throws -> [String: String] {
        guard let string = String(data: data, encoding: .utf8) else {
            throw FlickrServiceError.invalidResponse
        }
        return string.split(separator: "&").reduce(into: [:]) { values, part in
            let pieces = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard let key = pieces.first else { return }
            let value = pieces.count > 1 ? pieces[1] : ""
            let decodedKey = key.replacingOccurrences(of: "+", with: " ")
                .removingPercentEncoding ?? key
            let decodedValue = value.replacingOccurrences(of: "+", with: " ")
                .removingPercentEncoding ?? value
            values[decodedKey] = decodedValue
        }
    }

    private struct OAuthToken {
        let token: String
        let secret: String
    }
}

final class FlickrPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow()
    }
}

enum OAuthSigner {
    static func signature(
        method: String,
        url: URL,
        parameters: [String: String],
        consumerSecret: String,
        tokenSecret: String
    ) -> String {
        let encodedPairs = sortedEncodedPairs(parameters)
        let encodedComponents = encodedPairs.map { pair in
            pair.0 + "=" + pair.1
        }
        let parameterString = encodedComponents.joined(separator: "&")

        let baseURL = "\(url.scheme ?? "https")://\(url.host ?? "")\(url.path.isEmpty ? "/" : url.path)"
        let baseString = [
            method.uppercased(),
            percentEncode(baseURL),
            percentEncode(parameterString)
        ].joined(separator: "&")
        let signingKey = "\(percentEncode(consumerSecret))&\(percentEncode(tokenSecret))"
        let key = SymmetricKey(data: Data(signingKey.utf8))
        let digest = HMAC<Insecure.SHA1>.authenticationCode(
            for: Data(baseString.utf8),
            using: key
        )
        return Data(digest).base64EncodedString()
    }

    static func formEncoded(_ parameters: [String: String]) -> String {
        sortedEncodedPairs(parameters)
            .map { pair in pair.0 + "=" + pair.1 }
            .joined(separator: "&")
    }

    private static func sortedEncodedPairs(_ parameters: [String: String]) -> [(String, String)] {
        var pairs: [(String, String)] = []
        pairs.reserveCapacity(parameters.count)
        for (key, value) in parameters {
            pairs.append((percentEncode(key), percentEncode(value)))
        }
        pairs.sort { lhs, rhs in
            lhs.0 == rhs.0 ? lhs.1 < rhs.1 : lhs.0 < rhs.0
        }
        return pairs
    }

    static func percentEncode(_ value: String) -> String {
        let allowed = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~".utf8)
        return value.utf8.reduce(into: "") { result, byte in
            if allowed.contains(byte) {
                result.append(Character(UnicodeScalar(byte)))
            } else {
                result += String(format: "%%%02X", byte)
            }
        }
    }
}

@MainActor
protocol FlickrService: AnyObject {
    var authenticationStatus: FlickrAuthenticationStatus { get }

    func authenticate() async throws
    func disconnect()
    func getCurrentUser() async throws -> FlickrUser
    func getAlbums() async throws -> [FlickrAlbum]
    func getAlbumPhotos(albumID: String) async throws -> [FlickrPhotoRecord]
    func getPhotoInfo(photoID: String) async throws -> FlickrPhotoInfo
    func setPhotoDescription(photoID: String, description: String) async throws
    func safelySetPhotoDescription(
        photoID: String,
        expectedLastUpdate: String?,
        description: String
    ) async throws -> FlickrPhotoInfo
}

@MainActor
final class FlickrAPIService: NSObject, ObservableObject, FlickrService {
    private var oauth: FlickrOAuthClient
    private var configuration: FlickrConfiguration?
    // Keep the REST path without a trailing slash. Flickr's OAuth examples
    // sign this exact base URL, so the request URL and signature base string
    // remain identical.
    private let baseURL = URL(string: "https://www.flickr.com/services/rest")!
    @Published private(set) var authenticationStatus: FlickrAuthenticationStatus

    init(configuration: FlickrConfiguration? = nil) {
        let resolvedConfiguration = configuration ?? FlickrConfiguration.current()
        self.configuration = resolvedConfiguration
        self.oauth = FlickrOAuthClient(configuration: resolvedConfiguration)
        if resolvedConfiguration == nil {
            self.authenticationStatus = .notConfigured
        } else if oauth.credentials != nil {
            self.authenticationStatus = .authenticated
        } else {
            self.authenticationStatus = .signedOut
        }
    }

    var configuredAPIKey: String {
        configuration?.apiKey ?? ""
    }

    var hasConfiguredConsumerSecret: Bool {
        configuration != nil
    }

    func configureConsumerCredentials(apiKey: String, apiSecret: String) throws {
        let cleanedKey = apiKey.trimmed
        let cleanedSecret = apiSecret.trimmed
        guard !cleanedKey.isEmpty, !cleanedSecret.isEmpty else {
            throw FlickrServiceError.configurationMissing
        }

        let current = configuration
        try FlickrConsumerConfigurationStore().save(
            apiKey: cleanedKey,
            apiSecret: cleanedSecret
        )

        if current?.apiKey != cleanedKey || current?.apiSecret != cleanedSecret {
            FlickrCredentialStore().delete()
        }

        let newConfiguration = FlickrConfiguration(
            apiKey: cleanedKey,
            apiSecret: cleanedSecret,
            callbackScheme: current?.callbackScheme ?? AppBrand.oauthCallbackScheme
        )
        configuration = newConfiguration
        oauth = FlickrOAuthClient(configuration: newConfiguration)
        authenticationStatus = oauth.credentials != nil ? .authenticated : .signedOut
    }

    func authenticate() async throws {
        authenticationStatus = .authenticating
        do {
            _ = try await oauth.authenticate()
            _ = try await getCurrentUser()
            authenticationStatus = .authenticated
        } catch let error as FlickrServiceError {
            if case .api(let code, _) = error, [96, 97, 98, 99].contains(code) {
                // Do not keep retrying an invalid or insufficient token.
                // The next explicit Connect action will start OAuth again.
                oauth.disconnect()
            }
            authenticationStatus = oauth.isConfigured ? .signedOut : .notConfigured
            throw error
        } catch {
            authenticationStatus = oauth.isConfigured ? .signedOut : .notConfigured
            throw error
        }
    }

    func disconnect() {
        oauth.disconnect()
        authenticationStatus = oauth.isConfigured ? .signedOut : .notConfigured
    }

    func getCurrentUser() async throws -> FlickrUser {
        let root = try await call(method: "flickr.test.login", parameters: [:])
        guard let user = root["user"] as? [String: Any],
              let id = string(user, "id"),
              let username = content(user["username"]) else {
            throw FlickrServiceError.invalidResponse
        }
        return FlickrUser(id: id, username: username)
    }

    func getAlbums() async throws -> [FlickrAlbum] {
        let credentials = try requireCredentials()
        var albums: [FlickrAlbum] = []
        var page = 1
        var pages = 1

        repeat {
            let root = try await call(
                method: "flickr.photosets.getList",
                parameters: [
                    "user_id": credentials.userID,
                    "page": String(page),
                    "per_page": "500",
                    "primary_photo_extras": "url_l,url_k,url_h,url_m,url_t,last_update"
                ]
            )
            guard let photosets = root["photosets"] as? [String: Any] else {
                throw FlickrServiceError.invalidResponse
            }
            pages = int(photosets, "pages") ?? 1
            if let values = photosets["photoset"] as? [[String: Any]] {
                albums.append(contentsOf: values.compactMap { parseAlbum($0, ownerID: credentials.userID) })
            }
            page += 1
        } while page <= pages

        return albums
    }

    func getAlbumPhotos(albumID: String) async throws -> [FlickrPhotoRecord] {
        let credentials = try requireCredentials()
        var photos: [FlickrPhotoRecord] = []
        var page = 1
        var pages = 1

        repeat {
            let root = try await call(
                method: "flickr.photosets.getPhotos",
                parameters: [
                    "photoset_id": albumID,
                    "user_id": credentials.userID,
                    "page": String(page),
                    "per_page": "500",
                    "media": "photos",
                    "extras": "original_format,url_o,url_k,url_h,url_l,url_m,url_t,last_update"
                ]
            )
            guard let photoset = root["photoset"] as? [String: Any],
                  let values = photoset["photo"] as? [[String: Any]] else {
                throw FlickrServiceError.invalidResponse
            }
            pages = int(photoset, "pages") ?? 1
            photos.append(contentsOf: values.compactMap { parsePhoto($0, albumID: albumID) })
            page += 1
        } while page <= pages

        return photos
    }

    func getPhotoInfo(photoID: String) async throws -> FlickrPhotoInfo {
        let root = try await call(
            method: "flickr.photos.getInfo",
            parameters: [
                "photo_id": photoID,
                "extras": "original_format,url_o,url_k,url_h,url_l,url_m,url_t"
            ]
        )
        guard let photo = root["photo"] as? [String: Any],
              let id = string(photo, "id") else {
            throw FlickrServiceError.invalidResponse
        }

        let dates = photo["dates"] as? [String: Any]
        let lastUpdate = string(dates, "lastupdate") ?? string(photo, "lastupdate")
        let urls = photo["urls"] as? [String: Any]
        let urlValues = urls?["url"] as? [[String: Any]]
        let displayURL = preferredDisplayURL(from: urlValues)

        return FlickrPhotoInfo(
            id: id,
            title: content(photo["title"]) ?? "",
            description: content(photo["description"]) ?? "",
            lastUpdate: lastUpdate,
            displayURL: displayURL,
            thumbnailURL: nil
        )
    }

    func setPhotoDescription(photoID: String, description: String) async throws {
        _ = try await call(
            method: "flickr.photos.setMeta",
            parameters: [
                "photo_id": photoID,
                "description": description
            ],
            httpMethod: "POST"
        )
    }

    func safelySetPhotoDescription(
        photoID: String,
        expectedLastUpdate: String?,
        description: String
    ) async throws -> FlickrPhotoInfo {
        let current = try await getPhotoInfo(photoID: photoID)
        if let expectedLastUpdate,
           let remoteLastUpdate = current.lastUpdate,
           expectedLastUpdate != remoteLastUpdate {
            throw FlickrServiceError.conflict(
                remoteDescription: current.description,
                remoteLastUpdate: current.lastUpdate
            )
        }
        try await setPhotoDescription(photoID: photoID, description: description)
        // setMeta updates Flickr's last-update value. Refresh it after the
        // write so a later local edit does not look like an unrelated remote
        // conflict. If that refresh is temporarily unavailable, retaining
        // the pre-write value is conservative: a future write will detect
        // the mismatch instead of silently overwriting it.
        return (try? await getPhotoInfo(photoID: photoID)) ?? current
    }

    private func requireCredentials() throws -> FlickrCredentials {
        guard let credentials = oauth.credentials else {
            throw FlickrServiceError.notAuthenticated
        }
        return credentials
    }

    private func call(
        method: String,
        parameters: [String: String],
        httpMethod: String = "GET"
    ) async throws -> [String: Any] {
        let credentials = try requireCredentials()
        var allParameters = parameters
        allParameters["method"] = method
        allParameters["api_key"] = configuration?.apiKey ?? ""
        allParameters["format"] = "json"
        allParameters["nojsoncallback"] = "1"

        let request = try oauth.signedRequest(
            url: baseURL,
            method: httpMethod,
            parameters: allParameters,
            token: credentials.token,
            tokenSecret: credentials.secret,
            includeInBody: httpMethod == "POST"
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FlickrServiceError.invalidResponse
        }
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if let root, string(root, "stat") == "fail" {
            throw FlickrServiceError.api(
                code: int(root, "code") ?? -1,
                message: string(root, "message") ?? "Unknown Flickr error"
            )
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw FlickrServiceError.httpStatus(httpResponse.statusCode)
        }
        guard let root else {
            throw FlickrServiceError.invalidResponse
        }
        return root
    }

    private func parseAlbum(_ value: [String: Any], ownerID: String) -> FlickrAlbum? {
        guard let id = string(value, "id") else { return nil }
        let extras = value["primary_photo_extras"] as? [String: Any]
        let coverURL = url(extras, "url_m") ?? url(extras, "url_t")
        return FlickrAlbum(
            id: id,
            title: content(value["title"]) ?? "Untitled Album",
            photoCount: int(value, "photos") ?? 0,
            coverURL: coverURL,
            lastUpdated: date(extras, "last_update"),
            ownerID: ownerID
        )
    }

    private func parsePhoto(_ value: [String: Any], albumID: String) -> FlickrPhotoRecord? {
        guard let id = string(value, "id"),
              let server = string(value, "server"),
              let secret = string(value, "secret") else {
            return nil
        }

        let displayURL = url(value, "url_h")
            ?? url(value, "url_k")
            ?? url(value, "url_l")
            ?? url(value, "url_m")
            ?? url(value, "url_o")
            ?? URL(string: "https://live.staticflickr.com/\(server)/\(id)_\(secret)_m.jpg")!
        let thumbnailURL = url(value, "url_t") ?? url(value, "url_s") ?? displayURL
        return FlickrPhotoRecord(
            id: id,
            albumID: albumID,
            title: content(value["title"]) ?? "",
            displayURL: displayURL,
            thumbnailURL: thumbnailURL,
            lastUpdate: string(value, "lastupdate")
        )
    }

    private func string(_ value: [String: Any]?, _ key: String) -> String? {
        guard let value = value?[key] else { return nil }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private func content(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let dictionary = value as? [String: Any] {
            return string(dictionary, "_content")
        }
        return nil
    }

    private func int(_ value: [String: Any]?, _ key: String) -> Int? {
        guard let value = value?[key] else { return nil }
        if let number = value as? Int { return number }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private func url(_ value: [String: Any]?, _ key: String) -> URL? {
        guard let string = string(value, key) else { return nil }
        return URL(string: string)
    }

    private func preferredDisplayURL(from values: [[String: Any]]?) -> URL? {
        values?
            .sorted { urlRank(string($0, "label")) < urlRank(string($1, "label")) }
            .compactMap { URL(string: string($0, "_content") ?? "") }
            .first
    }

    private func urlRank(_ label: String?) -> Int {
        let normalized = label?.lowercased() ?? ""
        if normalized.contains("large 1600") { return 0 }
        if normalized.contains("large 2048") { return 1 }
        if normalized == "large" { return 2 }
        if normalized.contains("medium 800") { return 3 }
        if normalized.contains("medium 640") { return 4 }
        if normalized == "medium" { return 5 }
        if normalized.contains("small") { return 6 }
        if normalized == "original" { return 7 }
        return 8
    }

    private func date(_ value: [String: Any]?, _ key: String) -> Date? {
        guard let seconds = string(value, key).flatMap(TimeInterval.init) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
