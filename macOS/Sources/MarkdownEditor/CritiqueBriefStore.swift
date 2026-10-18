import Foundation

/// Where each document's audience and goal is kept.
///
/// In user defaults beside the answered notes, and for the same reason: who a
/// draft is for is the author's instruction to Humanish, not part of the draft,
/// and writing it into the Markdown or a dotfile beside it would put an
/// editor's bookkeeping into a folder somebody syncs and commits.
///
/// Only the author's own words are kept here. The critic's guess lives in the
/// critique history it came from, so a guess is never mistaken for something
/// the author said.
enum CritiqueBriefStore {
    private static let key = "critiqueBriefs"

    /// What the author said, `""` if they cleared it to have the critic guess
    /// again, and nil if they have said nothing.
    ///
    /// Empty is kept apart from nil because the two mean different things
    /// until the next critique lands: nil shows the last guess as the reader
    /// still in force, and empty shows that the author has asked for a fresh
    /// one. Collapsing them would show the old guess straight back to somebody
    /// who had just deleted it.
    static func load(for url: URL?, defaults: UserDefaults = .standard) -> String? {
        guard let url else { return nil }
        return (defaults.dictionary(forKey: key) as? [String: String])?[url.path]
    }

    static func save(_ brief: String?, for url: URL?, defaults: UserDefaults = .standard) {
        guard let url else { return }
        var all = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        if let brief {
            all[url.path] = brief
        } else {
            all.removeValue(forKey: url.path)
        }
        defaults.set(
            CritiqueResolutionStore.trimmed(all, keeping: url.path),
            forKey: key
        )
    }
}
