import AppKit

/// Does MediaRemote actually work when loaded by *this* app?
///
/// The answer depends on the calling process's signature, so it can only be
/// asked from inside the real, ad-hoc-signed bundle. Running the same code under
/// `swift file.swift` proves nothing: that executes inside Apple-signed
/// `swift-frontend`, which is the very trick the perl workaround relies on.
///
///     DynamicIsland.app/Contents/MacOS/DynamicIsland -DIMediaTest YES
@MainActor
enum MediaRemoteProbe {

    static var requested: Bool { UserDefaults.standard.bool(forKey: "DIMediaTest") }

    private typealias GetInfo = @convention(c) (DispatchQueue, @escaping ([String: Any]?) -> Void) -> Void

    static func run() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        print("executable: \(Bundle.main.executablePath ?? "?")")
        print("bundle id:  \(Bundle.main.bundleIdentifier ?? "?")")

        guard let handle = dlopen(path, RTLD_NOW) else {
            print("dlopen FAILED: \(String(cString: dlerror()))")
            print("RESULT: FAIL -- cannot load MediaRemote at all")
            NSApp.terminate(nil); return
        }
        print("dlopen: ok")

        for name in ["MRMediaRemoteGetNowPlayingInfo",
                     "MRMediaRemoteRegisterForNowPlayingNotifications",
                     "MRMediaRemoteSendCommand"] {
            print("  \(name): \(dlsym(handle, name) != nil ? "found" : "MISSING")")
        }

        guard let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") else {
            print("RESULT: FAIL -- symbol missing")
            NSApp.terminate(nil); return
        }

        let getInfo = unsafeBitCast(sym, to: GetInfo.self)
        var fired = false
        getInfo(DispatchQueue.main) { info in
            fired = true
            if let info, !info.isEmpty {
                print("\ncallback: \(info.count) keys")
                let interesting = ["kMRMediaRemoteNowPlayingInfoTitle",
                                   "kMRMediaRemoteNowPlayingInfoArtist",
                                   "kMRMediaRemoteNowPlayingInfoAlbum"]
                for key in interesting {
                    if let v = info[key] { print("   \(key.replacingOccurrences(of: "kMRMediaRemoteNowPlayingInfo", with: "")) = \(v)") }
                }
                if let art = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
                    print("   ArtworkData = \(art.count) bytes")
                }
                print("\nRESULT: PASS -- direct MediaRemote works from this bundle")
            } else {
                print("\ncallback fired but info was \(info == nil ? "nil" : "empty")")
                print("RESULT: INCONCLUSIVE -- is anything actually playing?")
            }
            NSApp.terminate(nil)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if !fired {
                print("\nRESULT: FAIL -- callback never fired (entitlement-gated)")
                NSApp.terminate(nil)
            }
        }
    }
}
