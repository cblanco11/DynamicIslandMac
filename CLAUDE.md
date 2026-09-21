# DynamicIsland

A background macOS app that renders an interactive "Dynamic Island" over the
MacBook notch. No Dock icon, no menu bar — a status item and one overlay panel
per screen.

## Build & run

XcodeGen owns the project. `project.yml` is the source of truth; the
`.xcodeproj` is generated and **not** checked in.

```
make build     # regenerate + xcodebuild (must be zero warnings)
make run       # build, kill any running copy, launch the .app
make stop
make clean
make log       # log stream for subsystem com.jeffreyotoo.DynamicIsland
make test      # all headless regression harnesses (must all print RESULT: PASS)
make snapshots # render the island to PNGs under .build/
```

Debug entry points (NSUserDefaults-style args, so they work on the binary directly):

```
DynamicIsland -DIExportSnapshot /tmp/island   # render island PNGs and exit
DynamicIsland -DISelfTest YES                 # window-server click-routing probe
DynamicIsland -DILifecycleTest YES            # rebuild idempotency, debounce, wake
DynamicIsland -DIExportMorph /tmp/morph       # filmstrip comparing morph springs
DynamicIsland -DICaptureMorph /tmp/live       # capture a REAL morph, frame by frame
DynamicIsland -DIMediaTest YES                # can THIS bundle read MediaRemote directly?
DynamicIsland -DIMediaStream YES              # live now-playing via the bundled helper
DynamicIsland -DIClickTest YES                # clicks + transport in a non-key panel
```

All three print a `RESULT: PASS` / `FAIL` line and exit, so they are usable as
regression checks. Run them after any change to panel geometry or lifecycle.

Runtime toggles (status item menu, or `defaults write com.jeffreyotoo.DynamicIsland …`):

| key | effect |
|---|---|
| `DIForceSyntheticNotch` | pretend every screen is notchless |
| `DIDebugOverlay` | state + fps readout under the island |
| `DIHoverInDelayMS` / `DIHoverOutDelayMS` | hover timing (default 120 / 350) |
| `DIMorphDuration` / `DIMorphBounce` | morph spring, floats (default 0.45 / 0.30) |

## Environment

Developed on macOS 26.7 (Tahoe), Xcode 27.0, Swift 6.4, arm64, Mac15,6.
Deployment target **macOS 15.0**, built against the macOS 27.0 SDK.
Full Swift 6 language mode, `SWIFT_STRICT_CONCURRENCY = complete`.
Ad-hoc local signing (`CODE_SIGN_IDENTITY = "-"`). Developer ID + notarization
+ Sparkle come later; the app can never ship on the App Store because of the
private-framework use planned for Milestones 2–3.

## Architecture

```
App/         entry point, delegate, status item, debug harnesses
Core/        geometry, state machine, panel lifecycle, screen observation
Activities/  ActivityProvider protocol, Activity model, registry
Media/       MediaRemote helper process, NowPlaying model, artwork tint
UI/          panel, container view, shape, SwiftUI views
Vendor/      mediaremote-adapter submodule, pinned
```

### Interaction model

```
closed  -- nothing playing; the island is exactly the notch, and inert
peek    -- resting: artwork left, waveform (or a play glyph when paused) right
hover   -- cursor over the island: a small growth that adds the title
expanded-- opened by a CLICK, not by hovering
```

Hover deliberately does **not** open the player. Hovering the top of the screen
is something people do by accident all day; the full player is only ever a
decision. Clicking again, or moving away, closes it.

### Activities

`ActivityProvider` is the seam every feature goes through; media is one
implementation, not a special case. Providers push **whole snapshots**, not
deltas, so a provider that crashes and restarts cannot leak stale entries -- its
next snapshot replaces everything it had. `ActivityKind` is a closed enum so
island views stay pure functions of state and `IslandContentView` stays
exhaustive: adding a provider is a compile error until the island can draw it.

`ActivityRegistry` merges providers and ranks by priority, then recency, then
registration order, so the result is stable rather than arbitrary.

- `IslandState` — explicit `.closed / .peek(Activity) / .expanded` enum.
- `IslandController` — one per screen. `@MainActor @Observable`. Owns the state,
  hover timing and the interactive frame. Views are pure functions of it.
- `PanelManager` — one `IslandPanel` per screen, rebuilt on display changes.
  Sole owner of controllers; calls `tearDown()` when a display departs.
- `ScreenObserver` — debounced `didChangeScreenParameters`, plus wake/space
  notifications.
- `IslandShape` — path is a pure function of `rect`, so animating the frame
  animates the morph. One geometry change, never a cross-fade.

### Window rules

```
styleMask           [.borderless, .nonactivatingPanel]
level               .statusBar + 1          (raw 26; menu bar is 24)
isFloatingPanel     true
hidesOnDeactivate   false
collectionBehavior  [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
isOpaque            false
backgroundColor     .clear
hasShadow           false
canBecomeKey/Main   false   — hovering must not disturb the user's focused window
```

`applyWindowRules()` is re-applied on wake, not only at construction.

**The panel's frame is the interactive region.** Because the window server routes
clicks by frame (see the first gotcha), the panel is sized to the island plus its
12pt shoulder margin and resized to follow it -- but only at transition
boundaries, never per frame. It grows to the target before the shape starts
expanding and shrinks only after the shape has finished collapsing, both driven
by `IslandController.onGeometryChange`. Two resizes per hover cycle, so the morph
is still one uninterrupted geometry animation inside a stationary window.

Residual cost: the 12pt shoulder margin either side of the island does cover the
menu bar and does swallow clicks there. On a notched Mac that strip is unusable
anyway. While expanded the panel covers ~404pt of menu bar, but only for as long
as the user is actively hovering it.

## Gotchas

Each entry records the macOS version it was verified on and how to degrade.

### `hitTest` does not produce click pass-through — verified macOS 26.7

**The window server routes clicks by window frame, not by AppKit view hit
testing and not by alpha.** Returning nil from `contentView.hitTest(_:)` only
stops *this app's* views from handling the event; the event is still consumed by
the window and never reaches the application underneath.

Measured with `NSWindow.windowNumber(at:belowWindowWithWindowNumber:)` via
`-DISelfTest YES`, across three configurations:

| config | result |
|---|---|
| A — `NSHostingView` + `hitTest` returning nil outside the island | panel captured **every** probe point |
| B — bare fully-transparent `NSView`, no `hitTest` override | identical to A |
| C — `ignoresMouseEvents = true` (control) | every point resolved to the window beneath |

C differing from A is what validates the oracle: it really is measuring click
routing. B matching A rules out `NSHostingView`'s layer and rules out alpha.

Consequence: a panel sized to the maximum expanded bounds swallows clicks across
its whole frame — including a large stretch of the menu bar. The interactive
region must be expressed as **window geometry**, not as view hit testing.
`hitTest` is still worth keeping to refine behaviour *within* the window (the
concave shoulders), but it cannot be the pass-through mechanism.

### `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` — verified macOS 26.7

- Returned **nil** whenever the menu bar is hidden or auto-hidden. Without a
  cache a probe taken at that moment silently demotes a real notch to a
  synthetic one, so `ScreenGeometry` keeps a last-known-good rect per display and
  prefers it over synthesising.
- On the built-in display these are **global, Y-up** coordinates
  (`auxTopLeft = (0, 950, 663, 32)` against `frame = (0, 0, 1512, 982)`). AppKit
  documents them only as "the screen's coordinate space", which is ambiguous for
  a secondary display, so `measure(_:)` detects which interpretation it received
  rather than assuming. Notch **width** is always derived as
  `frame.width - left.width - right.width`, which is coordinate-space independent.
- The **menu bar is 33pt while the notch is 32pt** on Mac15,6. `safeAreaInsets.top`
  is the notch height, not the menu bar height; they are not interchangeable.

Degradation: no notch, or no auxiliary areas and no cache → synthesise a
185 × 32 rect centred at the top of the screen.

### Measured geometry, Mac15,6 (MacBook Pro 14")

```
frame          (0, 0, 1512, 982) @2x
visibleFrame   (0, 62, 1512, 887)
safeAreaInsets top = 32
notch          185 x 32 at x 663…848, centre x 755.5   (screen centre is 756)
```

### Swift 6: no MainActor state in `deinit` — verified Swift 6.4

A nonisolated `deinit` cannot touch `@MainActor`, non-`Sendable` stored
properties, which rules out the usual "remove my NotificationCenter observer in
deinit" pattern. `IslandController` and `ScreenObserver` expose explicit
`tearDown()` instead, called by their owner. If a controller is ever dropped
without `tearDown()`, its observer leaks.

### An `LSUIElement` app is invisible to screenshots

It cannot be granted screen-capture visibility (it is not a listed application),
so the island never appears in a screen capture. `-DIExportSnapshot` makes the
app render its own view hierarchy through `ImageRenderer` instead, which
exercises the real `IslandView` / `IslandShape`. Hover behaviour is verified from
the persisted `state ->` log lines (logged at `.default`, not `.info`, so
`log show` retains them).

### A full-screen app's menu-bar overlay also sits at level 26 -- verified macOS 26.7

With TextEdit full-screen, its own menu-bar overlay window is at the same level
as the island panel. Ordering within a level decides the winner, so the island is
ordered front (`orderFrontRegardless`) on every rebuild and reassert. Verified:
the island both draws over and receives hover events above a full-screen app.

### Never resize the panel while the morph is running -- verified macOS 26.7

Resizing the window mid-animation makes Core Animation composite the **old
backing store with centre gravity** until SwiftUI's next draw. The island drops
to the middle of the newly-taller panel -- exactly
`(panelHeight - islandHeight) / 2` -- and then climbs back to the top as the
shape grows. On screen that reads as the island detaching from the notch and
expanding upward into it.

Neither `layerContentsPlacement = .topLeft` nor
`layerContentsRedrawPolicy = .duringViewResize` overrides it, on the view or the
hosting view; the compositing happens at the window backing store.

The fix is structural: `IslandController.isPreparingExpansion` grows the panel
the instant the cursor arrives, **before** the hover delay, while the island is
still closed and completely static. The panel shrinks again only after the
collapse has fully settled. No window resize ever overlaps an animation.

Regression check: `-DICaptureMorph` drives the real hover path, captures the
live view every display tick, and asserts the island's top edge never leaves the
top of the screen. It is in `make test`.

**Note on measuring this:** `cacheDisplay` reflects that same compositing, so
the harness shows the artifact rather than hiding it -- but it also means a
reading taken during a resize describes the composite, not SwiftUI's layout.
Confirm any suspected layout bug against a *static* frame (a closed island in an
oversized panel) or an `ImageRenderer` pass before changing layout code.

### The morph is symmetric; it does not *look* symmetric -- and why

Measured off the real spring curve via `-DIExportMorph`, the island grows by an
identical amount left and right at every frame, and its horizontal growth
(97.7pt *each side*) exceeds its vertical growth (88.2pt total). There is no
anchoring bug.

It still reads as "dropping out of the notch", for two reasons:

- The sideways growth happens against the **dark menu bar** -- black on dark
  grey, almost no contrast -- while the downward growth appears over bright
  wallpaper. The only high-contrast motion is downward.
- The original spring settled in **242ms with effectively no overshoot**, so
  there was no lingering motion at the left and right edges for the eye to
  catch.

Hence the default spring has bounce (`Spring(duration: 0.45, bounce: 0.30)`,
+4.5pt overshoot each side). Overshoot is doing perceptual work here, not
decoration. Retune live with `DIMorphDuration` / `DIMorphBounce`.

`IslandMetrics.settleDuration(from:to:spring:)` derives the panel-shrink delay
from the spring by simulation rather than hardcoding it -- the previous
hardcoded 420ms silently stopped matching the curve. The panel must never shrink
before the shape has finished collapsing or the island is clipped mid-morph.

### MediaRemote is entitlement-gated -- verified macOS 26.7

`MRMediaRemoteGetNowPlayingInfo` invokes its callback with **nil** when called
from this bundle, and returns full data from an Apple-signed process. Measured
A/B/A seconds apart with the same media state:

| caller | result |
|---|---|
| Apple-signed `swift-frontend` (`swift file.swift`) | 32 keys |
| ad-hoc-signed `DynamicIsland.app` | nil |
| Apple-signed `swift-frontend` again | 32 keys |

**Do not test this with `swift somefile.swift`.** That runs inside an
Apple-signed process and will tell you direct access works. It only works there
because of the very entitlement the app lacks. Use `-DIMediaTest YES`, which
runs inside the real bundle.

Hence `MediaRemoteHelper`: `/usr/bin/perl` is Apple-signed and entitled, so the
adapter framework is loaded there and the JSON piped back. Degradation: if the
bundled helper is missing, the provider publishes an empty snapshot and the
island shows no media rather than stalling on stale data.

### The media helper does not die with its parent -- verified macOS 26.7

The helper only notices our death when a write to the closed stdout pipe raises
SIGPIPE, and while nothing is playing it never writes -- so it lingers forever,
re-parented to launchd. Every crash or `SIGKILL` leaks one. macOS has no
`PR_SET_PDEATHSIG` and the vendored script has no parent-watch option.

Two defences, both needed:
- `MediaRemoteHelper.reapOrphanedHelpers()` at launch kills perl processes
  running *our* bundled script whose parent is 1. Scoping it to orphans means a
  second copy of the app running normally is left alone.
- `AppDelegate.installSignalHandlers()` handles SIGTERM/SIGINT, which otherwise
  skip `applicationWillTerminate` entirely.

### Stream payloads are large and partial

Lines reach ~200KB because artwork arrives as base64 in every full payload, so
the reader splits a byte buffer on newlines rather than trusting a line API.
`diff: true` payloads carry only changed fields and must be merged into running
state, not substituted for it. Artwork briefly disappears during timeline
scrubs, so it is carried forward while the track identity is unchanged.

`--debounce=200` is not optional for the CPU budget: without it the app burned
0.39s of CPU per 60s idle, with it 0.01s.

### Clicks work in a non-key panel, but layering is easy to get wrong

The panel is `.nonactivatingPanel` and returns false from `canBecomeKey`.
Verified on macOS 26.7 that both `onTapGesture` **and** SwiftUI `Button`s still
receive clicks there, so nothing special is needed for key-window state.

What *did* break: a transparent tap layer placed above the content in the
`ZStack` swallowed every click before the transport buttons saw one, leaving the
controls silently dead. The click target is now the `IslandShape` itself,
**below** the content; peek and hover pass clicks through with
`allowsHitTesting(false)`, and the expanded player does its own hit testing with
a body-level tap to dismiss (SwiftUI gives buttons priority over an ancestor's
gesture).

This cannot be tested from outside -- screen-capture tools will not drive clicks
into an `LSUIElement` app -- so `-DIClickTest YES` synthesises events through
`NSWindow.sendEvent` and asserts both the open/close toggle and that a transport
command actually fires.

### Watch for vacuous passes in the morph harness

`mouseEntered()` returns early when there is no activity, so a capture run
without one leaves the island in `.closed` and the top-edge assertion passes
having tested nothing. The harness seeds a synthetic `NowPlaying` and drives
closed -> peek -> hover -> expanded -> hover, covering every resize.

## Budget

Under ~50MB RSS, near-zero CPU when idle. No polling loops anywhere: hover uses a
single `NSTrackingArea`, timing uses one cancellable `Task` at a time, and the
debug overlay's `CADisplayLink` runs only while the overlay is visible.

Media adds a child process but not a polling loop: the stream is event-driven and
debounced, playback position is extrapolated from `elapsedTime` + `timestamp`
rather than polled, and the `TimelineView`s driving the progress bar and the
playing indicator only schedule while playback is actually running.

Measured with media connected and playback paused: **0.01s CPU per 60s idle**,
15MB `phys_footprint`.
