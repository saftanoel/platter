import AppKit
import Combine

struct Track: Equatable {
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    var artwork: NSImage?
    /// Content-stable identity for `artwork`, used to key the palette and record-texture
    /// caches. Never key those on the image object: `ObjectIdentifier` is its address,
    /// and a freed cover's address gets handed straight to the next one, so the cache
    /// returns the previous track's colours.
    var artworkID: String = ""

    static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.title == rhs.title && lhs.artist == rhs.artist && lhs.isPlaying == rhs.isPlaying
    }

    static let empty = Track(title: "", artist: "", album: "", isPlaying: false, artwork: nil, artworkID: "")
}

/// Polls Music.app and Spotify over AppleScript for now-playing metadata.
/// Neither app requires login for this — matches how the original vinylformac.com app works.
///
/// Performance notes: the scripts are compiled once and reused (recompiling per poll
/// dominated CPU), app-running checks go through the bundle-identifier lookup rather
/// than enumerating every running app, and `track` is only republished when a value
/// actually changes so SwiftUI does not redraw the full-screen scene on every tick.
final class NowPlayingPoller: ObservableObject {
    @Published private(set) var track: Track = .empty

    #if HARNESS
    /// Test seam for the offline render harness, which needs to drive the scene without
    /// a music player running. Compiled out of the shipping build.
    func stageTrack(_ staged: Track) { track = staged }
    #endif

    private var timer: Timer?
    private var lastArtworkKey: String?

    private enum Source {
        case spotify, music

        var bundleID: String {
            switch self {
            case .spotify: return "com.spotify.client"
            case .music: return "com.apple.Music"
            }
        }

        var name: String {
            switch self {
            case .spotify: return "Spotify"
            case .music: return "Music"
            }
        }
    }

    /// Compiled once on first use. Compiling AppleScript source is expensive, so the
    /// same compiled object is reused for the life of the process.
    private lazy var compiledScripts: [String: NSAppleScript] = [:]

    func start(interval: TimeInterval = 2.0) {
        poll()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        // Tolerance lets the system coalesce our wake-ups with other timers.
        timer.tolerance = interval * 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        if let result = query(.spotify), result.isPlaying {
            apply(result, source: .spotify)
            return
        }
        if let result = query(.music), result.isPlaying {
            apply(result, source: .music)
            return
        }
        // Nothing playing — keep the last artwork but mark it paused.
        if track.isPlaying {
            track.isPlaying = false
        }
    }

    private func apply(_ result: (title: String, artist: String, album: String, isPlaying: Bool), source: Source) {
        let key = "\(source.name)|\(result.title)|\(result.artist)"

        // Only touch @Published state when something really changed; each assignment
        // invalidates the SwiftUI scene on every screen.
        if track.title != result.title { track.title = result.title }
        if track.artist != result.artist { track.artist = result.artist }
        if track.album != result.album { track.album = result.album }
        if track.isPlaying != result.isPlaying { track.isPlaying = result.isPlaying }

        guard key != lastArtworkKey else { return }
        lastArtworkKey = key
        fetchArtwork(source: source) { [weak self] image in
            DispatchQueue.main.async {
                self?.track.artwork = image
                self?.track.artworkID = image == nil ? "" : key
            }
        }
    }

    private func isRunning(_ source: Source) -> Bool {
        // Cheap targeted lookup. Enumerating NSWorkspace.runningApplications went
        // through LaunchServices for every app on the system, twice per poll.
        !NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleID).isEmpty
    }

    private func query(_ source: Source) -> (title: String, artist: String, album: String, isPlaying: Bool)? {
        guard isRunning(source) else { return nil }
        let src = source == .spotify ? Self.spotifyScript : Self.musicScript
        guard let output = runScript(src, cacheKey: "state-\(source.name)") else { return nil }
        let parts = output.components(separatedBy: "|||")
        guard parts.count == 4 else { return nil }
        return (parts[0], parts[1], parts[2], parts[3] == "playing")
    }

    private func fetchArtwork(source: Source, completion: @escaping (NSImage?) -> Void) {
        let src = source == .spotify ? Self.spotifyArtworkURLScript : Self.musicArtworkScript
        guard let output = runScript(src, cacheKey: "art-\(source.name)"), !output.isEmpty else {
            completion(nil)
            return
        }

        switch source {
        case .spotify:
            guard let url = URL(string: output) else {
                completion(nil)
                return
            }
            // Network fetch stays off the main thread.
            URLSession.shared.dataTask(with: url) { data, _, _ in
                completion(data.flatMap(NSImage.init(data:)))
            }.resume()

        case .music:
            let path = output
            if let data = FileManager.default.contents(atPath: path) {
                completion(NSImage(data: data))
                try? FileManager.default.removeItem(atPath: path)
            } else {
                completion(nil)
            }
        }
    }

    /// NSAppleScript is not thread-safe, so these stay on the main thread; the win
    /// comes from compiling once rather than on every call.
    private func runScript(_ source: String, cacheKey: String) -> String? {
        let script: NSAppleScript
        if let cached = compiledScripts[cacheKey] {
            script = cached
        } else {
            guard let created = NSAppleScript(source: source) else { return nil }
            created.compileAndReturnError(nil)
            compiledScripts[cacheKey] = created
            script = created
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if error != nil { return nil }
        return result.stringValue
    }

    private static let spotifyScript = """
    tell application "Spotify"
        set trackName to name of current track
        set trackArtist to artist of current track
        set trackAlbum to album of current track
        set playState to player state as string
        return trackName & "|||" & trackArtist & "|||" & trackAlbum & "|||" & playState
    end tell
    """

    private static let spotifyArtworkURLScript = """
    tell application "Spotify"
        return artwork url of current track
    end tell
    """

    private static let musicScript = """
    tell application "Music"
        set trackName to name of current track
        set trackArtist to artist of current track
        set trackAlbum to album of current track
        set playState to player state as string
        return trackName & "|||" & trackArtist & "|||" & trackAlbum & "|||" & playState
    end tell
    """

    private static let musicArtworkScript = """
    tell application "Music"
        set tmpPath to (POSIX path of (path to temporary items)) & "vinylmac_art.jpg"
        try
            set theArtwork to data of artwork 1 of current track
            set fileRef to open for access tmpPath with write permission
            set eof fileRef to 0
            write theArtwork to fileRef
            close access fileRef
            return tmpPath
        on error
            try
                close access tmpPath
            end try
            return ""
        end try
    end tell
    """
}
