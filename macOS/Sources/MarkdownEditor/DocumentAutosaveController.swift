import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DocumentAutosaveController: ObservableObject {
    private static let delay: TimeInterval = 1.5

    private var generation = 0
    private var hasPendingSave = false

    /// Called just before each write, so whatever watches the file can tell
    /// this app's saves from another app's.
    var onSave: (() -> Void)?

    func scheduleSave(for fileURL: URL?) {
        generation += 1
        let scheduledGeneration = generation
        guard let fileURL else {
            hasPendingSave = false
            return
        }
        hasPendingSave = true

        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.delay
        ) { [weak self] in
            guard let self,
                self.generation == scheduledGeneration
            else {
                return
            }
            self.hasPendingSave = false
            self.save(fileURL)
        }
    }

    func saveNow(for fileURL: URL?) {
        guard hasPendingSave else {
            return
        }
        generation += 1
        hasPendingSave = false
        guard let fileURL else {
            return
        }
        save(fileURL)
    }

    func cancelPendingSave() {
        generation += 1
        hasPendingSave = false
    }

    private func save(_ fileURL: URL) {
        let standardizedURL = fileURL.standardizedFileURL
        guard let document = NSDocumentController.shared.document(
            for: standardizedURL
        ) else {
            presentMissingDocumentError(for: standardizedURL)
            return
        }

        // Recorded before the write rather than after it: `NSDocument` takes
        // its snapshot of the text synchronously here, while the completion
        // handler runs later, by which time somebody may have typed on.
        onSave?()
        document.save(
            to: standardizedURL,
            ofType: document.fileType ?? UTType.markdownDocument.identifier,
            for: .autosaveInPlaceOperation
        ) { error in
            if let error {
                document.presentError(error)
            }
        }
    }

    private func presentMissingDocumentError(for fileURL: URL) {
        NSApp.presentError(
            NSError(
                domain: "com.kirupa.markdown-editor.autosave",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Humanish couldn’t autosave "
                        + fileURL.lastPathComponent + ".",
                    NSLocalizedRecoverySuggestionErrorKey:
                        "Use File > Save to save the document manually."
                ]
            )
        )
    }
}
