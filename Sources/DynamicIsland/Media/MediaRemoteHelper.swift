import Foundation
import os

/// Runs `mediaremote-adapter` under `/usr/bin/perl` and turns its stdout into a
/// stream of `NowPlaying` snapshots.
///
/// MediaRemote is entitlement-gated for third-party apps: loaded directly from
/// this (ad-hoc or Developer ID signed) bundle, `MRMediaRemoteGetNowPlayingInfo`
/// invokes its callback with nil. The same call from an Apple-signed process
/// returns full data. `/usr/bin/perl` is Apple-signed and entitled, so the
/// adapter framework is loaded *there* and the result piped back to us.
/// See CLAUDE.md, "MediaRemote is entitlement-gated".
@MainActor
final class MediaRemoteHelper {

    private let log = Logger(subsystem: "com.jeffreyotoo.DynamicIsland", category: "media")

    private var process: Process?
    private var reader: Task<Void, Never>?
    private var restarts = 0
    private var continuation: AsyncStream<NowPlaying>.Continuation?

    /// Last full state. The adapter may send partial payloads (`diff: true`),
    /// so snapshots are merged into this rather than replacing it.
    private var current = NowPlaying()

    /// Artwork briefly goes nil while the adapter re-reads a track's timeline.
    /// Dropping it would make the island flicker, so it is carried forward for
    /// as long as the track identity is unchanged.
    private var lastArtwork: (trackID: String, data: Data, mime: String?)?

    // MARK: - Locating the bundled helper

    struct Paths {
        let perl = "/usr/bin/perl"
        let script: String
        let framework: String
    }

    static func bundledPaths() -> Paths? {
        guard let script = Bundle.main.path(forResource: "mediaremote-adapter", ofType: "pl")
        else { return nil }
        let framework = Bundle.main.privateFrameworksPath.map {
            $0 + "/MediaRemoteAdapter.framework"
        }
        guard let framework, FileManager.default.fileExists(atPath: framework) else { return nil }
        return Paths(script: script, framework: framework)
    }

    // MARK: - Orphan reaping

    /// The helper does not die with us.
    ///
    /// It only notices our death when a write to the closed stdout pipe raises
    /// SIGPIPE -- and while nothing is playing it never writes, so it can linger
    /// forever. A crash or SIGKILL leaves one behind every time. perl has no
    /// equivalent of PR_SET_PDEATHSIG on macOS and the vendored script has no
    /// parent-watch option, so stale helpers are reaped explicitly at launch.
    ///
    /// Matched on our own bundled script path, and only when re-parented to
    /// launchd, so a second copy of the app running normally is left alone.
    static func reapOrphanedHelpers() -> Int {
        guard let paths = bundledPaths() else { return 0 }

        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-f", paths.script]
        let pipe = Pipe()
        pgrep.standardOutput = pipe
        pgrep.standardError = Pipe()
        guard (try? pgrep.run()) != nil else { return 0 }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        pgrep.waitUntilExit()

        let me = ProcessInfo.processInfo.processIdentifier
        var reaped = 0
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            guard let pid = Int32(line.trimmingCharacters(in: .whitespaces)), pid != me else { continue }
            guard parentProcessID(of: pid) == 1 else { continue }   // orphan only
            if kill(pid, SIGTERM) == 0 { reaped += 1 }
        }
        return reaped
    }

    private static func parentProcessID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        guard result == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    // MARK: - Lifecycle

    func start() -> AsyncStream<NowPlaying> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.stop() }
            }
            launch()
        }
    }

    func stop() {
        reader?.cancel()
        reader = nil
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        continuation?.finish()
        continuation = nil
    }

    private func launch() {
        guard let paths = Self.bundledPaths() else {
            log.error("adapter not found in bundle; media unavailable")
            // Publish an empty snapshot so the island shows no-media rather than
            // stalling on whatever was last seen.
            continuation?.yield(NowPlaying())
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: paths.perl)
        // --debounce coalesces bursts of updates (scrubbing, rapid track
        // changes) into one payload, which matters when each carries ~140KB of
        // base64 artwork.
        process.arguments = [paths.script, paths.framework, "stream", "--debounce=200"]

        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()   // discard: the adapter is chatty on stderr

        process.terminationHandler = { [weak self] proc in
            Task { @MainActor in self?.helperDied(status: proc.terminationStatus) }
        }

        do {
            try process.run()
        } catch {
            log.error("failed to launch helper: \(error.localizedDescription, privacy: .public)")
            scheduleRestart()
            return
        }

        self.process = process
        log.notice("helper started (pid \(process.processIdentifier, privacy: .public))")

        let handle = out.fileHandleForReading
        reader = Task.detached(priority: .utility) { [weak self] in
            // Lines carry base64 artwork and run to ~200KB, so this reads by
            // chunk and splits on newlines rather than trusting any line API.
            var buffer = Data()
            while !Task.isCancelled {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let line = buffer[buffer.startIndex..<newline]
                    buffer.removeSubrange(buffer.startIndex...newline)
                    guard !line.isEmpty else { continue }
                    let copy = Data(line)
                    await MainActor.run { self?.consume(line: copy) }
                }
            }
        }
    }

    private func helperDied(status: Int32) {
        guard continuation != nil else { return }   // deliberate stop
        log.error("helper exited with status \(status, privacy: .public)")
        process = nil
        scheduleRestart()
    }

    /// Exponential backoff, capped. A helper that cannot start must not become a
    /// busy loop respawning a process forever.
    private func scheduleRestart() {
        restarts += 1
        let delay = min(pow(2.0, Double(min(restarts, 6))) * 0.25, 30.0)
        log.notice("restarting helper in \(delay, privacy: .public)s (attempt \(self.restarts, privacy: .public))")
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, continuation != nil else { return }
            launch()
        }
    }

    // MARK: - Parsing

    private func consume(line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "data",
              let payload = object["payload"] as? [String: Any]
        else { return }

        // A healthy line means the helper is working; reset the backoff so a
        // later crash starts from a short delay again.
        restarts = 0

        let isDiff = object["diff"] as? Bool ?? false
        if !isDiff && payload.isEmpty {
            // Explicit "nothing is playing".
            current = NowPlaying()
            lastArtwork = nil
            continuation?.yield(current)
            return
        }

        var next = isDiff ? current : NowPlaying()
        apply(payload, to: &next)
        current = next
        continuation?.yield(next)
    }

    private func apply(_ payload: [String: Any], to snapshot: inout NowPlaying) {
        func string(_ key: String) -> String? { payload[key] as? String }
        func number(_ key: String) -> Double? { (payload[key] as? NSNumber)?.doubleValue }

        if let v = string("title") { snapshot.title = v }
        if let v = string("artist") { snapshot.artist = v }
        if let v = string("album") { snapshot.album = v }
        if let v = string("bundleIdentifier") { snapshot.sourceBundleID = v }
        if let v = payload["playing"] as? Bool { snapshot.isPlaying = v }
        if let v = number("duration") { snapshot.duration = v }
        if let v = number("elapsedTime") { snapshot.elapsed = v }
        if let v = number("playbackRate") { snapshot.playbackRate = v }
        if let v = number("timestamp") { snapshot.timestamp = Date(timeIntervalSince1970: v / 1000) }
        if let v = number("shuffleMode") { snapshot.shuffleMode = Int(v) }
        if let v = number("repeatMode") { snapshot.repeatMode = Int(v) }

        // Only adopt a new track identity when the payload actually carries
        // one. Diff payloads routinely contain just ["playing"] or
        // ["playbackRate","timestamp"], and re-deriving the id from metadata
        // there flips it from "14681::14717" to "title|artist|album" -- which
        // misses the artwork cache and makes the cover vanish the instant
        // playback is toggled.
        if let identifier = string("uniqueIdentifier") ?? string("contentItemIdentifier") {
            snapshot.trackID = identifier
        } else if snapshot.trackID == nil {
            let derived = [snapshot.title, snapshot.artist, snapshot.album]
                .compactMap { $0 }.joined(separator: "|")
            snapshot.trackID = derived.isEmpty ? nil : derived
        }

        if let base64 = string("artworkData"), let data = Data(base64Encoded: base64) {
            snapshot.artwork = data
            snapshot.artworkMIMEType = string("artworkMimeType")
            if let id = snapshot.trackID {
                lastArtwork = (id, data, snapshot.artworkMIMEType)
            }
        } else if let cached = lastArtwork, cached.trackID == snapshot.trackID {
            // Same track, artwork momentarily absent: keep showing what we had.
            snapshot.artwork = cached.data
            snapshot.artworkMIMEType = cached.mime
        } else if snapshot.artwork == nil {
            snapshot.artworkMIMEType = nil
        }
    }

    // MARK: - Transport

    /// MediaRemote command ids the adapter accepts. These still work directly,
    /// but routing them through the same entitled helper keeps one code path.
    enum Command: Int {
        case play = 0, pause = 1, togglePlayPause = 2, stop = 3
        case nextTrack = 4, previousTrack = 5
        case toggleShuffle = 6, toggleRepeat = 7
    }

    func send(_ command: Command) {
        guard let paths = Self.bundledPaths() else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: paths.perl)
        process.arguments = [paths.script, paths.framework, "send", String(command.rawValue)]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do { try process.run() } catch {
            log.error("transport command failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
