import Foundation

/// Behaviour knobs that are read from the app's own defaults domain, so they can
/// be changed with `defaults write io.github.kkkevinky.tapper <key> <value>` and an app
/// relaunch. A rebuild changes the ad-hoc signature, which makes macOS ask for
/// Accessibility again, so anything that may need field tuning lives here.
struct TouchTuning: Equatable {
    /// A contact that stays within `restMove` for this long is a resting finger:
    /// it no longer counts as a contact for tap decisions until it lifts.
    var restAge: TimeInterval
    /// Normalized movement that re-anchors the resting timer.
    var restMove: Float

    /// Light taps that the mouse only reports as hover/approach states
    /// (1, 2, 3, 5, 6) instead of touching (4) also count as taps.
    var hoverTapsEnabled: Bool
    /// A tap that never reached the touching state must reach this contact size...
    var hoverMinSize: Float
    /// ...and last at least this long from its first frame.
    var hoverMinDuration: TimeInterval

    /// "dockswipe" (follows the fingers like a trackpad), "instant" (switches as
    /// soon as the fingers have travelled swipeInstantDistance), "hotkey"
    /// (Control+arrow once per swipe) or "off". The engine only runs while the system's own
    /// Magic Mouse full-screen swipe is turned off.
    var swipeMode: String
    /// Horizontal centroid travel (normalized) before a swipe starts.
    var swipeStartDistance: Float
    /// Spaces switched per full surface width of finger travel (dockswipe mode).
    var swipeGain: Double
    /// Travel (normalized) that switches a space in hotkey mode.
    var swipeHotkeyDistance: Float
    /// Scales the release velocity handed to the Dock (progress per second,
    /// derived from the finger speed). The Dock decides from progress and
    /// velocity whether the switch completes, as with a real trackpad.
    var swipeVelocityScale: Double
    /// Reverses the finger direction, in case the surface axis is mirrored.
    var swipeInvert: Bool
    /// Drops the mouse's own scroll events while a swipe runs.
    var swipeSuppressScroll: Bool
    /// Post the companion gesture event after each Dock swipe event
    /// (InstantSpaceSwitcher needs it on 27.0; Mac Mouse Fix found it unnecessary).
    var swipeCompanion: Bool
    /// "auto", "on" or "off": attach the macOS 27 IOHID payload to Dock swipes.
    var swipePayload: String
    /// Palm and side-of-hand contacts never count for taps: anything that first
    /// lands behind palmZoneY (the rear of the shell, normalized y grows toward
    /// the front), or grows to palmTapSize / palmTapMajor (mm). Measured on this
    /// mouse: fingertips 0.4-1.4 / 7-13 mm at y 0.74-0.98, palm 2.5-5.5 / 19-26 mm.
    var palmZoneY: Float
    var palmTapSize: Float
    var palmTapMajor: Float
    /// Looser limits for swipes (swiping fingers press flatter, up to ~16 mm).
    var palmSwipeSize: Float
    var palmSwipeMajor: Float
    /// A slower tap on the right part of the shell becomes a right click.
    /// Off by default: only left-click taps; the physical right click and the
    /// two-finger tap still work.
    var rightTapEnabled: Bool
    /// Two fingers tapping together right-click, as on a trackpad.
    var twoFingerTapEnabled: Bool
    /// The two fingers must land within this time of each other, and lift
    /// within it too.
    var twoFingerTapGap: TimeInterval
    /// What a release with the fingers moving back does: "commit" (switch
    /// anyway; the only shape that behaved on 27.0.1), "cancelled" or "ended0".
    var swipeCancelStyle: String
    /// Dockswipe mode: finger travel (normalized) after which the switch is
    /// committed and the Dock starts following the fingers. Below it, lifting
    /// or turning back does nothing.
    var swipeCommitDistance: Float
    /// Travel (normalized) that triggers the switch in instant mode.
    var swipeInstantDistance: Float
    /// Release velocity used in instant mode (progress per second).
    var swipeInstantVelocity: Double
    /// Smallest release velocity toward the target (progress per second).
    var swipeMinEndVelocity: Double
    /// Re-send the end event 0.2 s and 0.5 s later.
    var swipeResendEnd: Bool

    static let defaultsPrefix = "io.github.kkkevinky.tapper.tune."

    static func load(from defaults: UserDefaults = .standard) -> TouchTuning {
        func double(_ key: String, _ fallback: Double) -> Double {
            (defaults.object(forKey: defaultsPrefix + key) as? NSNumber)?.doubleValue ?? fallback
        }
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            (defaults.object(forKey: defaultsPrefix + key) as? NSNumber)?.boolValue ?? fallback
        }
        return TouchTuning(
            restAge: double("restAge", 0.5),
            restMove: Float(double("restMove", 0.03)),
            hoverTapsEnabled: bool("hoverTaps", true),
            hoverMinSize: Float(double("hoverMinSize", 0.2)),
            hoverMinDuration: double("hoverMinDuration", 0.05),
            swipeMode: defaults.string(forKey: defaultsPrefix + "swipeMode") ?? "dockswipe",
            swipeStartDistance: Float(double("swipeStartDistance", 0.06)),
            swipeGain: double("swipeGain", 3.0),
            swipeHotkeyDistance: Float(double("swipeHotkeyDistance", 0.12)),
            swipeVelocityScale: double("swipeVelocityScale", 1.0),
            swipeInvert: bool("swipeInvert", false),
            swipeSuppressScroll: bool("swipeSuppressScroll", true),
            swipeCompanion: bool("swipeCompanion", true),
            swipePayload: defaults.string(forKey: defaultsPrefix + "swipePayload") ?? "auto",
            palmZoneY: Float(double("palmZoneY", 0.35)),
            palmTapSize: Float(double("palmTapSize", 2.2)),
            palmTapMajor: Float(double("palmTapMajor", 15)),
            palmSwipeSize: Float(double("palmSwipeSize", 3.0)),
            palmSwipeMajor: Float(double("palmSwipeMajor", 19)),
            rightTapEnabled: bool("rightTapEnabled", false),
            twoFingerTapEnabled: bool("twoFingerTapEnabled", true),
            twoFingerTapGap: double("twoFingerTapGap", 0.15),
            swipeCancelStyle: defaults.string(forKey: defaultsPrefix + "swipeCancelStyle") ?? "commit",
            swipeCommitDistance: Float(double("swipeCommitDistance", 0.10)),
            swipeInstantDistance: Float(double("swipeInstantDistance", 0.10)),
            swipeInstantVelocity: double("swipeInstantVelocity", 8),
            swipeMinEndVelocity: double("swipeMinEndVelocity", 2),
            swipeResendEnd: bool("swipeResendEnd", false)
        )
    }
}

/// Classifies resting fingers. Pure value type so it can be exercised with
/// recorded frame sequences outside the app.
struct RestingContactFilter {
    private struct Track {
        var anchorX: Float
        var anchorY: Float
        var anchorTime: TimeInterval
        var resting: Bool
    }

    private var tracks: [Int32: Track] = [:]

    /// Updates the tracks with one frame and returns the ids that are resting.
    /// Resting is sticky while the contact stays on the surface: a resting
    /// finger that later moves (a press, a slide) can never start a tap.
    /// Tracks of ids absent from the frame are dropped, because the framework
    /// reuses identifiers for the next finger that lands.
    /// - Parameter exempt: a contact that must not become resting (the finger
    ///   holding a synthesized drag).
    mutating func update(contacts: [(id: Int32, x: Float, y: Float)], now: TimeInterval,
                         restAge: TimeInterval, restMove: Float, exempt: Int32? = nil) -> Set<Int32> {
        let present = Set(contacts.map(\.id))
        tracks = tracks.filter { present.contains($0.key) }

        var resting = Set<Int32>()
        for contact in contacts {
            guard var track = tracks[contact.id] else {
                tracks[contact.id] = Track(anchorX: contact.x, anchorY: contact.y, anchorTime: now, resting: false)
                continue
            }
            if !track.resting {
                let moved = max(abs(contact.x - track.anchorX), abs(contact.y - track.anchorY))
                if moved > restMove || contact.id == exempt {
                    track.anchorX = contact.x
                    track.anchorY = contact.y
                    track.anchorTime = now
                } else if now - track.anchorTime >= restAge {
                    track.resting = true
                }
                tracks[contact.id] = track
            }
            if track.resting { resting.insert(contact.id) }
        }
        return resting
    }

    mutating func reset() {
        tracks.removeAll()
    }
}

/// Classifies palm and side-of-hand contacts by where they first land and how
/// large they grow. Sticky while the contact stays on the surface; ids absent
/// from a frame are forgotten because the framework reuses them.
struct PalmContactFilter {
    private struct Track {
        var firstY: Float
        var maxSize: Float
        var maxMajor: Float
    }

    private var tracks: [Int32: Track] = [:]

    mutating func update(contacts: [(id: Int32, y: Float, size: Float, major: Float)],
                         tuning: TouchTuning) -> (tap: Set<Int32>, swipe: Set<Int32>) {
        let present = Set(contacts.map(\.id))
        tracks = tracks.filter { present.contains($0.key) }

        var tap = Set<Int32>(), swipe = Set<Int32>()
        for contact in contacts {
            var track = tracks[contact.id] ?? Track(firstY: contact.y, maxSize: 0, maxMajor: 0)
            track.maxSize = max(track.maxSize, contact.size)
            track.maxMajor = max(track.maxMajor, contact.major)
            tracks[contact.id] = track

            let rear = track.firstY < tuning.palmZoneY
            if rear || track.maxSize >= tuning.palmTapSize || track.maxMajor >= tuning.palmTapMajor {
                tap.insert(contact.id)
            }
            if rear || track.maxSize >= tuning.palmSwipeSize || track.maxMajor >= tuning.palmSwipeMajor {
                swipe.insert(contact.id)
            }
        }
        return (tap, swipe)
    }

    mutating func reset() {
        tracks.removeAll()
    }
}
