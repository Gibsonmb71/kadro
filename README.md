# Kadro

Kadro is a native SwiftUI macOS utility for captioning Lightroom-exported sports photos and updating descriptions on existing Flickr albums.

## Run

Open [`Package.swift`](./Package.swift) in Xcode and run the `Kadro` executable target. The project also builds from the command line:

```sh
swift build
swift run Kadro
```

The local verification harness exercises the core workflow without opening a window:

```sh
swift run Kadro --self-test
```

## Flickr setup

Flickr support uses OAuth 1.0a with write permission. The easiest setup is **Kadro → Settings… → Flickr**: paste the consumer API key and API secret, then choose **Save Flickr Credentials**. They are stored in the macOS Keychain. The expected Info.plist keys are also supported for packaged deployments:

- `FlickrAPIKey`
- `FlickrAPISecret`
- `FlickrOAuthCallbackScheme` (defaults to `kadro`)

For a command-line run, `FLICKR_API_KEY` and `FLICKR_API_SECRET` can be used instead. The OAuth callback scheme must also be registered under `CFBundleURLTypes` for a packaged app. Access tokens and secrets are stored only in the macOS Keychain; they are not stored in session JSON, UserDefaults, or logs.

Opening a Flickr album keeps Flickr's album order, displays the hosted image sizes returned by Flickr, lazily captures each existing description, and queues description-only `flickr.photos.setMeta` updates. The original description is retained locally and can be restored from the Flickr disclosure in the caption sidebar. If Flickr is unavailable, local assignments and generated descriptions continue to save and pending updates remain durable for later retry.

## Keyboard workflow

On the captioning screen, the window-level AppKit event monitor keeps the workflow active even after clicking the image or sidebar:

- `0–9` — enter jersey number
- `Space` — add the active roster's player
- `Enter` — save, mark reviewed, and advance
- `Backspace` — remove one digit
- `Command-Z` — undo the latest player change
- `Left/Right` — navigate
- `/` — search all loaded rosters by name or number
- `F` — flag for review
- `C` — carry players from the immediately previous photo
- `Escape` — clear the number buffer or dismiss search
- `Tab` — switch active roster

## Local storage

Sessions are saved as JSON files under Application Support, with roster data in a separate local JSON library. The app stores file URLs and security-scoped folder bookmarks; it does not copy or modify the original photo files.

The `FlickrService` protocol isolates authentication, album/photo reads, metadata reads, and description writes from SwiftUI. `FlickrSyncQueue` serializes and persists pending description updates so the captioning workflow does not wait for network latency.
