import Foundation
import MarkdownEditorCore

/// Where a document's past critiques are kept between launches.
///
/// On disk in Application Support rather than in user defaults, because each
/// revision carries a copy of the draft it was written about and defaults is
/// not a document store — it is read into memory at launch, in full, for every
/// process that touches it.
///
/// Not beside the document, for the same reason the answered findings are not:
/// a critique is not part of the draft, and an editor should not put its
/// bookkeeping into a folder somebody syncs, shares and commits.
enum CritiqueHistoryStore {
    private static let folderName = "Critiques"

    /// The app used to be called KONVO, and before that Markdown Editor, and
    /// its critiques were filed under those names.
    private static let previousAppFolders = ["KONVO", "Markdown Editor"]
    private static let appFolder = "Humanish"

    private static var directory: URL? {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first
        guard let base else { return nil }
        let current = base
            .appendingPathComponent(appFolder, isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
        moveCritiquesWrittenUnderTheOldName(to: current, from: base)
        return current
    }

    /// Carry the old folder over, once.
    ///
    /// A rename is not a reason to lose somebody's work. Every critique ever
    /// run is filed under the app's name, so without this the history panel
    /// would simply come up empty on the first launch after the rename — with
    /// no error, because an absent file is how "no critiques yet" looks.
    ///
    /// Moved rather than copied, and only when there is nothing at the new
    /// path: a second run must not undo edits made since the first.
    private static func moveCritiquesWrittenUnderTheOldName(
        to current: URL,
        from base: URL
    ) {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: current.path) else { return }
        for folder in previousAppFolders {
            let previous = base
                .appendingPathComponent(folder, isDirectory: true)
                .appendingPathComponent(folderName, isDirectory: true)
            guard manager.fileExists(atPath: previous.path) else { continue }
            try? manager.createDirectory(
                at: current.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? manager.moveItem(at: previous, to: current)
            return
        }
    }

    /// One file per document, named by a digest of its path.
    ///
    /// A digest rather than the path itself because a path contains slashes
    /// and can be longer than a filename may be. It also keeps the names of
    /// somebody's documents out of a directory listing, which is a small
    /// courtesy that costs nothing.
    static func fileURL(for documentURL: URL) -> URL? {
        guard let directory else { return nil }
        return directory.appendingPathComponent("\(digest(documentURL.path)).json")
    }

    static func load(for documentURL: URL?) -> CritiqueHistory {
        guard let documentURL, let url = fileURL(for: documentURL),
              let data = try? Data(contentsOf: url)
        else {
            return CritiqueHistory()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // A history written by a different build is not worth an error. The
        // worst case is that a few past critiques are forgotten, which costs
        // nothing anybody was relying on.
        return (try? decoder.decode(CritiqueHistory.self, from: data))
            ?? CritiqueHistory()
    }

    @discardableResult
    static func save(_ history: CritiqueHistory, for documentURL: URL?) -> Bool {
        guard let documentURL, let directory, let url = fileURL(for: documentURL) else {
            return false
        }
        if history.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return true
        }
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(history).write(to: url, options: .atomic)
            return true
        } catch {
            // Losing the history is not worth interrupting somebody's writing
            // over. The critique in front of them still works.
            return false
        }
    }

    /// A short, stable, filename-safe digest of a path.
    ///
    /// Deliberately not `hashValue`: Swift's hashing is seeded per process, so
    /// a name built from it would differ on every launch and every history
    /// would be written once and never found again.
    static func digest(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in Array(text.utf8) {
            hash ^= UInt64(byte)
            hash = hash &* 0x1000_0000_01b3
        }
        return String(hash, radix: 36)
    }
}
