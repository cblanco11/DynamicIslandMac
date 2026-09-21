import AppKit

/// Runs the real bundled helper for a few seconds and reports what arrives.
///
///     DynamicIsland.app/Contents/MacOS/DynamicIsland -DIMediaStream YES
@MainActor
enum MediaProbe {

    static var requested: Bool { UserDefaults.standard.bool(forKey: "DIMediaStream") }

    static func run() {
        guard let paths = MediaRemoteHelper.bundledPaths() else {
            print("RESULT: FAIL -- adapter not found in bundle")
            NSApp.terminate(nil); return
        }
        print("perl:      \(paths.perl)")
        print("script:    \(paths.script)")
        print("framework: \(paths.framework)\n")

        let helper = MediaRemoteHelper()
        var count = 0
        var sawContent = false
        var artworkBytes = 0

        Task {
            for await snapshot in helper.start() {
                count += 1
                if snapshot.hasContent { sawContent = true }
                artworkBytes = max(artworkBytes, snapshot.artwork?.count ?? 0)
                print("[\(count)] playing=\(snapshot.isPlaying) "
                      + "title=\(snapshot.title ?? "-") | artist=\(snapshot.artist ?? "-")")
                print("     album=\(snapshot.album ?? "-")  source=\(snapshot.sourceBundleID ?? "-")")
                print("     elapsed=\(snapshot.elapsed.map { String(format: "%.1f", $0) } ?? "-")"
                      + "/\(snapshot.duration.map { String(format: "%.1f", $0) } ?? "-")s"
                      + "  artwork=\(snapshot.artwork?.count ?? 0)b (\(snapshot.artworkMIMEType ?? "-"))"
                      + "  track=\(snapshot.trackID?.prefix(24) ?? "-")")
                if count >= 6 { break }
            }
        }

        Task {
            try? await Task.sleep(for: .seconds(8))
            helper.stop()
            print("\nsnapshots: \(count), artwork seen: \(artworkBytes)b")
            print(sawContent && artworkBytes > 0
                  ? "RESULT: PASS -- live now-playing with artwork from the bundled helper"
                  : count > 0
                    ? "RESULT: INCONCLUSIVE -- stream ran but no content (is anything playing?)"
                    : "RESULT: FAIL -- no snapshots")
            NSApp.terminate(nil)
        }
    }
}
