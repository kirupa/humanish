import AppKit
import MarkdownEditorCore
import MarkdownEditorUI
import SwiftUI

enum WelcomeWindowPreferences {
    static let showsAtLaunchKey = "showsWelcomeWindowAtLaunch"

    /// Defaults to `true` so a fresh install lands on the welcome window.
    static var showsAtLaunch: Bool {
        UserDefaults.standard.object(forKey: showsAtLaunchKey) as? Bool ?? true
    }
}

/// Owns the launch/landing window.
///
/// This is a plain `NSWindow` rather than a SwiftUI `Window` scene because the
/// app delegate has to be able to present it during launch, which happens
/// outside any scene.
@MainActor
final class WelcomeWindowController: NSObject {
    static let shared = WelcomeWindowController()

    private static let contentSize = NSSize(width: 760, height: 470)

    private var window: NSWindow?

    /// Windows that already existed when the landing window was shown. Only a
    /// window created *after* that point should dismiss it, so switching back
    /// to an already-open document leaves the landing window alone.
    private var preexistingWindowNumbers: Set<Int> = []

    override private init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(anyWindowDidBecomeMain(_:)),
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )
    }

    func show() {
        RecentDocumentsModel.shared.refresh()

        let welcomeWindow = window ?? makeWindow()
        window = welcomeWindow
        preexistingWindowNumbers = Set(
            NSApp.windows
                .filter { $0 !== welcomeWindow }
                .map(\.windowNumber)
        )
        welcomeWindow.appearance = currentColorTheme.appKitAppearance
        NSApp.activate(ignoringOtherApps: false)
        welcomeWindow.makeKeyAndOrderFront(nil)
    }

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    func owns(_ candidate: NSWindow) -> Bool {
        candidate === window
    }

    func close() {
        window?.close()
    }

    private var currentColorTheme: EditorColorTheme {
        let defaults = UserDefaults.standard
        let color = defaults.string(forKey: EditorThemeColor.storageKey)
            .flatMap(EditorThemeColor.init(rawValue:))
        let mode = defaults.string(forKey: EditorAppearanceMode.storageKey)
            .flatMap(EditorAppearanceMode.init(rawValue:))
        return EditorColorTheme(
            color: color ?? .blue,
            mode: mode ?? .systemDefault
        )
    }

    private func makeWindow() -> NSWindow {
        let rootView = WelcomeView(
            recentDocuments: .shared,
            onNewDocument: { [weak self] in
                self?.newDocument()
            },
            onOpenDocument: { [weak self] in
                self?.showOpenPanel()
            },
            onOpenRecent: { [weak self] document in
                self?.open(document)
            }
        )

        let welcomeWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        welcomeWindow.title = "Welcome to Humanish"
        welcomeWindow.titleVisibility = .hidden
        welcomeWindow.titlebarAppearsTransparent = true
        welcomeWindow.isMovableByWindowBackground = true
        welcomeWindow.isReleasedWhenClosed = false
        welcomeWindow.standardWindowButton(.miniaturizeButton)?.isHidden = true
        welcomeWindow.standardWindowButton(.zoomButton)?.isHidden = true
        welcomeWindow.contentView = NSHostingView(rootView: rootView)
        welcomeWindow.setContentSize(Self.contentSize)
        welcomeWindow.center()
        return welcomeWindow
    }

    /// Dismisses the landing window as soon as a document window takes over.
    ///
    /// Panels are ignored so the Open panel raised from this very window does
    /// not dismiss it before the user has picked anything.
    @objc
    private func anyWindowDidBecomeMain(_ notification: Notification) {
        guard let welcomeWindow = window,
            welcomeWindow.isVisible,
            let notifiedWindow = notification.object as? NSWindow,
            notifiedWindow !== welcomeWindow,
            !(notifiedWindow is NSPanel),
            !preexistingWindowNumbers.contains(notifiedWindow.windowNumber)
        else {
            return
        }
        welcomeWindow.close()
    }

    private func newDocument() {
        guard !NSApp.sendAction(
            #selector(NSDocumentController.newDocument(_:)),
            to: nil,
            from: nil
        ) else {
            return
        }
        NSDocumentController.shared.newDocument(nil)
    }

    private func showOpenPanel() {
        guard !NSApp.sendAction(
            #selector(NSDocumentController.openDocument(_:)),
            to: nil,
            from: nil
        ) else {
            return
        }
        NSDocumentController.shared.openDocument(nil)
    }

    private func open(_ document: RecentDocument) {
        NSDocumentController.shared.openDocument(
            withContentsOf: document.url,
            display: true
        ) { openedDocument, _, error in
            MainActor.assumeIsolated {
                guard openedDocument == nil, let error else {
                    return
                }
                RecentDocumentsModel.shared.refresh()
                NSApp.presentError(error)
            }
        }
    }
}
