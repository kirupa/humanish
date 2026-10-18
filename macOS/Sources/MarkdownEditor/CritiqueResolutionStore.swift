import Foundation
import MarkdownEditorCore

/// Where a document's answered findings are kept between runs.
///
/// In user defaults rather than beside the document, because a critique is not
/// part of the draft. Writing a dotfile next to somebody's Markdown — or worse,
/// into it — would put an editor's bookkeeping into a folder they sync, share,
/// and commit.
///
/// The cost is that the decisions are per-machine, and that moving the file
/// while it is closed loses them — a move Humanish sees, a Save As or a rename of
/// the open document, takes them along. Both are the right trade for a record
/// of "I already read that one": losing it costs a dismissal, and the
/// alternative costs the tidiness of somebody's project.
enum CritiqueResolutionStore {
    private static let key = "critiqueResolutions"
    /// How many documents are remembered.
    ///
    /// Without a cap this grows for the life of the install. A hundred
    /// documents is far more than anyone has open in a working week, and the
    /// entry that falls off the end costs a dismissal on a file untouched for
    /// months.
    private static let documentLimit = 100

    static func load(
        for url: URL?,
        defaults: UserDefaults = .standard
    ) -> CritiqueResolutions {
        guard let url else { return CritiqueResolutions() }
        let all = defaults.dictionary(forKey: key) as? [String: [String: String]]
        return CritiqueResolutions(storage: all?[url.path] ?? [:])
    }

    static func save(
        _ resolutions: CritiqueResolutions,
        for url: URL?,
        defaults: UserDefaults = .standard
    ) {
        guard let url else { return }
        var all = defaults.dictionary(forKey: key) as? [String: [String: String]] ?? [:]
        if resolutions.isEmpty {
            all.removeValue(forKey: url.path)
        } else {
            all[url.path] = resolutions.storage
        }
        defaults.set(trimmed(all, keeping: url.path), forKey: key)
    }

    /// Keeps a per-document store bounded, never dropping the document in hand.
    /// Shared with `CritiqueBriefStore`, which is bounded the same way.
    static func trimmed<Value>(
        _ all: [String: Value],
        keeping current: String,
        limit: Int = documentLimit
    ) -> [String: Value] {
        guard all.count > limit else { return all }
        // Nothing here records when a document was last touched, so the
        // honest rule is "keep the one being used and an arbitrary rest"
        // rather than pretending to an order that was never recorded.
        var kept: [String: Value] = [:]
        if let mine = all[current] { kept[current] = mine }
        for (path, entries) in all where path != current {
            guard kept.count < limit else { break }
            kept[path] = entries
        }
        return kept
    }
}
