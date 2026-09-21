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
```

All three print a `RESULT: PASS` / `FAIL` line and exit, so they are usable as
regression checks. Run them after any change to panel geometry or lifecycle.

Runtime toggles (status item menu, or `defaults write com.jeffreyotoo.DynamicIsland …`):

| key | effect |
|---|---|
| `DIForceSyntheticNotch` | pretend every screen is notchless |
| `DIDebugOverlay` | state + fps readout under the island |
| `DIHoverInDelayMS` / `DIHoverOutDelayMS` | hover timing (default 120 / 350) |

## Environment

Developed on macOS 26.7 (Tahoe), Xcode 27.0, Swift 6.4, arm64, Mac15,6.
Deployment target **macOS 15.0**, built against the macOS 27.0 SDK.
Full Swift 6 language mode, `SWIFT_STRICT_CONCURRENCY = complete`.
Ad-hoc local signing (`CODE_SIGN_IDENTITY = "-"`). Developer ID + notarization
+ Sparkle come later; the app can never ship on the App Store because of the
private-framework use planned for Milestones 2–3.

## Architecture

```
App/    entry point, delegate, status item, debug harnesses
Core/   geometry, state machine, panel lifecycle, screen observation
UI/     panel, container view, shape, SwiftUI views
```

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

## Budget

Under ~50MB RSS, near-zero CPU when idle. No polling loops anywhere: hover uses a
single `NSTrackingArea`, timing uses one cancellable `Task` at a time, and the
debug overlay's `CADisplayLink` runs only while the overlay is visible.
