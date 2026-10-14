import Foundation

/// One-time import of the settings saved before the rename from MagicTapper,
/// so the new bundle identifier does not start over from defaults. Keys under
/// the old prefix move to the new one; other keys keep their names.
enum DefaultsMigration {
    static let legacyBase = "com.magictapper"
    static let base = "io.github.kkkevinky.tapper"
    static let doneKey = base + ".migratedFromMagicTapper"

    /// The old bundle identifier for this build: release and debug ids differ
    /// only by suffix, so the suffix carries over.
    static func legacyDomain(for bundleID: String?) -> String? {
        guard let bundleID, bundleID.hasPrefix(base) else { return nil }
        return legacyBase + ".app" + bundleID.dropFirst(base.count)
    }

    static func run(defaults: UserDefaults = .standard,
                    legacyDomain: String? = legacyDomain(for: Bundle.main.bundleIdentifier)) {
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }
        guard let legacyDomain, let legacy = defaults.persistentDomain(forName: legacyDomain) else { return }
        for (key, value) in legacy {
            let newKey = key.hasPrefix(legacyBase + ".") ? base + key.dropFirst(legacyBase.count) : key
            if defaults.object(forKey: newKey) == nil { defaults.set(value, forKey: newKey) }
        }
    }
}
