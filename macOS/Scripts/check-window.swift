// Does a real document window contain the rail it is showing?
//
// The geometry is unit-tested — `EditorPaneGeometry` answers how wide a window
// has to be and how narrow it may be dragged, and none of that needs a screen.
// What those tests cannot see is the wiring: whether the answer reaches the
// window. The bug this check exists for lived entirely in that gap. Every
// number was right and nothing asked the window to use them, so a document
// opened at the view's minimum width with the critique rail laid out past the
// trailing edge — header visible, body text and "Run critique" button outside
// the window.
//
// So this builds the real `MarkdownEditorView`, puts it in a real `NSWindow`
// the size a fresh document window is born, and reads the frame back.
//
// The window is fully transparent and ordered to the back, because the person
// who owns this machine is usually using it. It cannot be placed off-screen
// instead: a window that intersects no display has no `screen`, and the screen
// is half of what is being tested.
//
// Built by Scripts/run-window-checks.sh against the real app sources.

import AppKit
import MarkdownEditorCore
import MarkdownEditorUI
import SwiftUI

@MainActor
private var failures = 0
@MainActor
private var checks = 0

@MainActor
func check(
    _ label: String,
    _ passed: Bool,
    _ detail: @autoclosure () -> String = ""
) {
    checks += 1
    if passed {
        print("  ok   \(label)")
    } else {
        failures += 1
        let extra = detail()
        print("  FAIL \(label)\(extra.isEmpty ? "" : " — \(extra)")")
    }
}

/// The editor with its document in SwiftUI state, as `DocumentGroup` holds
/// it, so that typing reaches `onChange` the way it does in the app. A binding
/// over a captured variable takes the edit without telling SwiftUI, and the
/// editor never hears about its own text changing.
struct EditorHost: View {
    @State var document: MarkdownDocument
    let fileURL: URL?
    @State private var themeColor = EditorThemeColor.blue.rawValue
    @State private var appearance = EditorAppearanceMode.light.rawValue

    var body: some View {
        MarkdownEditorView(
            document: $document,
            fileURL: fileURL,
            themeColorRawValue: $themeColor,
            appearanceModeRawValue: $appearance,
            typefaceRawValue: .constant(EditorTypeface.sans.rawValue),
            textScale: .constant(1)
        )
    }
}

/// A real editor in a real window, of a given content width.
@MainActor
struct EditorWindow {
    let window: NSWindow
    let hosting: NSHostingView<EditorHost>

    /// `owner` stands in for the `NSDocument` behind a real document window,
    /// attached the way `DocumentGroup` attaches its own: through a window
    /// controller, before the editor is in the window.
    init(
        contentWidth: CGFloat,
        documentURL: URL?,
        text: String,
        owner: NSDocument? = nil
    ) {
        let view = EditorHost(
            document: MarkdownDocument(text: text), fileURL: documentURL
        )

        let frame = NSRect(x: 0, y: 0, width: contentWidth, height: 620)
        hosting = NSHostingView(rootView: view)
        hosting.frame = frame

        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        if let owner {
            owner.addWindowController(NSWindowController(window: window))
        }
        window.contentView = hosting
        // On a real screen, because the screen is what growth is clamped
        // against — but invisible, and behind everything else.
        if let screen = NSScreen.main {
            window.setFrameOrigin(
                NSPoint(x: screen.visibleFrame.minX, y: screen.visibleFrame.minY)
            )
        }
        window.alphaValue = 0
        window.orderBack(nil)
    }

    var contentWidth: CGFloat {
        window.contentRect(forFrameRect: window.frame).width
    }

    /// The editor's text view, found in the view tree.
    var textView: NSTextView? {
        func find(in view: NSView) -> NSTextView? {
            if let textView = view as? RichMarkdownTextView { return textView }
            for subview in view.subviews {
                if let found = find(in: subview) { return found }
            }
            return nil
        }
        return find(in: hosting)
    }

    func settle(for seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(
                mode: .default, before: Date().addingTimeInterval(0.02)
            )
        }
        hosting.layoutSubtreeIfNeeded()
    }

    /// The window's content, drawn.
    func draw() -> NSBitmapImageRep? {
        guard let rep = hosting.bitmapImageRepForCachingDisplay(
            in: hosting.bounds
        ) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep
    }

    /// How much of the trailing `width` points is something other than the
    /// page's own paper.
    ///
    /// How the rail is found. It is ordinary SwiftUI and leaves no `NSView`
    /// behind, so a check that hunted the view tree for a 356-point subview
    /// reported it missing while it was on screen — the widths it could see
    /// were the scroll view's and the host's and nothing else.
    func trailingInk(width: CGFloat, of rep: NSBitmapImageRep) -> Int {
        let scale = CGFloat(rep.pixelsWide) / hosting.bounds.width
        let paper = EditorColorTheme(color: .blue, mode: .light)
            .editorBackgroundColor.usingColorSpace(.sRGB)!
        var ink = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
            for x in stride(
                from: max(0, rep.pixelsWide - Int(width * scale)),
                to: rep.pixelsWide,
                by: 2
            ) {
                guard let colour = rep.colorAt(x: x, y: y)?
                    .usingColorSpace(.sRGB) else { continue }
                let difference =
                    abs(colour.redComponent - paper.redComponent)
                    + abs(colour.greenComponent - paper.greenComponent)
                    + abs(colour.blueComponent - paper.blueComponent)
                if difference > 0.12 { ink += 1 }
            }
        }
        return ink
    }

    /// Writes what was drawn, when the environment asks for it.
    func writePNG(_ rep: NSBitmapImageRep, named variable: String) {
        guard let path = ProcessInfo.processInfo.environment[variable]
        else { return }
        try? rep.representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: path))
        print("  wrote \(path)")
    }
}

/// Stands where `NSDocument` stands in the app, and counts the saves it is
/// asked for instead of writing. The autosave looks its file's document up
/// before saving, and one it cannot find gets an alert — which here would
/// stop the checks where they stand rather than fail them.
final class SaveRecorder: NSDocument {
    private(set) var saves = 0

    override func save(
        to url: URL,
        ofType typeName: String,
        for saveOperation: NSDocument.SaveOperationType,
        completionHandler: @escaping (Error?) -> Void
    ) {
        saves += 1
        completionHandler(nil)
    }
}

@main
@MainActor
enum Harness {
    /// What the app itself uses. Repeated here rather than read from `Layout`,
    /// which is internal to the view file, and a check that recomputed the
    /// numbers from the same source could not catch them changing.
    static let column: CGFloat = 700
    static let rail: CGFloat = 356
    static let columnMinimum: CGFloat = 360
    static let documentMinimum: CGFloat = 620

    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let text = """
            # Understanding caching

            Caching is important because the cache stores data for later reads.
            When a request arrives the system looks in the cache first, and only
            falls through to the slower store when it finds nothing there.

            ## What goes wrong

            Invalidation is the hard part. A stale entry is worse than no entry,
            because the system is confident about something that stopped being
            true.

            """
        let documentURL = directory.appendingPathComponent("scroll-test.md")
        try? text.write(to: documentURL, atomically: true, encoding: .utf8)

        print("A window born too narrow for its comments")

        // 900 points: wider than the minimum, narrower than the pair, and the
        // width the reported bug was photographed at.
        let narrow = EditorWindow(
            contentWidth: 900, documentURL: documentURL, text: text
        )
        narrow.settle(for: 1.6)

        let wanted = EditorPaneGeometry.idealContentWidth(
            columnWidth: column, railWidth: rail, railIsOpen: true
        )
        check(
            "it is widened to hold the document and the whole rail",
            narrow.contentWidth >= wanted,
            "the window is \(narrow.contentWidth) points of content, "
                + "and needs \(wanted)"
        )
        check(
            "and no wider than that",
            narrow.contentWidth <= wanted,
            "it grew to \(narrow.contentWidth)"
        )
        check(
            "it is still on the screen it started on",
            NSScreen.main.map { $0.visibleFrame.intersects(narrow.window.frame) }
                ?? false,
            "the window is at \(narrow.window.frame)"
        )

        // The rail is really laid out in the room that was made for it, rather
        // than the window having been widened around an empty strip.
        if let rep = narrow.draw() {
            check(
                "and the rail is drawn in the room that was made for it",
                narrow.trailingInk(width: rail - 16, of: rep) > 500,
                "only \(narrow.trailingInk(width: rail - 16, of: rep)) points "
                    + "of rail ink in the trailing \(rail)"
            )
            narrow.writePNG(rep, named: "MDE_WINDOW_PNG")
        } else {
            check("the window can be drawn", false)
        }

        print("")
        print("The title bar says how long the draft is")

        // Through the real view to the real window, which is the part a unit
        // test of `DocumentLength` cannot see: the count has to reach the
        // subtitle, and a selection made in the text view has to reach the
        // count. Spelled out rather than computed with `DocumentLength`, so a
        // change to the count shows up here as well as in its own tests.
        check(
            "the subtitle gives the words and a reading time",
            narrow.window.subtitle == "64 words · 1 min read",
            "it reads \"\(narrow.window.subtitle)\""
        )
        if let textView = narrow.textView {
            // "Invalidation is the hard part." — five words. Found in the
            // view's own text, which hides the `#` marks, so a range taken
            // from the source would select something else.
            let sentence = (textView.string as NSString).range(
                of: "Invalidation is the hard part."
            )
            textView.setSelectedRange(sentence)
            narrow.settle(for: 0.5)
            check(
                "a selection is counted on its own",
                narrow.window.subtitle == "5 of 64 words",
                "it reads \"\(narrow.window.subtitle)\""
            )
            textView.setSelectedRange(NSRange(location: sentence.location, length: 0))
            narrow.settle(for: 0.5)
            check(
                "and a caret goes back to the whole draft",
                narrow.window.subtitle == "64 words · 1 min read",
                "it reads \"\(narrow.window.subtitle)\""
            )
        } else {
            check("the editor has a text view", false)
        }

        print("")
        print("A draft never saved is named by its title")

        // Through the real view to a real `NSDocument`, the one name both the
        // title bar and Save read. The model's half is unit-tested as
        // `DocumentTitle`; what this can see is the rename reaching the
        // document, and only the documents it should.
        let draftText = """
            # Field notes on speed

            Caching is important because the cache stores data for later reads.

            """
        let owner = NSDocument()
        let untitled = owner.displayName ?? ""
        let draft = EditorWindow(
            contentWidth: 1_100, documentURL: nil, text: draftText, owner: owner
        )
        draft.settle(for: 1.0)
        check(
            "it opens named by its title, as typed",
            owner.displayName == "Field notes on speed"
                && draft.window.title == "Field notes on speed",
            "the document is \"\(owner.displayName ?? "")\", "
                + "the window \"\(draft.window.title)\""
        )
        if let textView = draft.textView {
            let speed = (textView.string as NSString).range(of: "speed")
            textView.insertText(
                ": a field guide",
                replacementRange: NSRange(location: NSMaxRange(speed), length: 0)
            )
            draft.settle(for: 0.6)
            check(
                "a new title renames it, made safe to save",
                owner.displayName == "Field notes on speed - a field guide",
                "it is \"\(owner.displayName ?? "")\""
            )
            let words = (textView.string as NSString).range(
                of: "Field notes on speed: a field guide"
            )
            textView.insertText("", replacementRange: words)
            draft.settle(for: 0.6)
            check(
                "and a title taken away gives the placeholder back",
                owner.displayName == untitled && draft.window.title == untitled,
                "the document is \"\(owner.displayName ?? "")\", "
                    + "the window \"\(draft.window.title)\""
            )

            owner.fileURL = documentURL
            let saved = owner.displayName ?? ""
            textView.insertText(
                "A saved title",
                replacementRange: NSRange(location: words.location, length: 0)
            )
            draft.settle(for: 0.6)
            check(
                "once saved, the file's name is left alone",
                owner.displayName == saved,
                "it became \"\(owner.displayName ?? "")\""
            )
        } else {
            check("the draft has a text view", false)
        }

        // A duplicate is named "… copy" so that saving it cannot overwrite its
        // original. Named by its title it would propose the original's name.
        let original = NSDocument()
        original.displayName = "Field notes copy"
        let copy = EditorWindow(
            contentWidth: 1_100, documentURL: nil, text: draftText, owner: original
        )
        copy.settle(for: 1.0)
        check(
            "a duplicate keeps the name it was given",
            original.displayName == "Field notes copy",
            "it became \"\(original.displayName ?? "")\""
        )

        // Reopened after a quit, a draft is handed back under the name it had,
        // which macOS 27.2 then replaced with a suggestion of its own at the
        // first autosave unless the app named it again. What shows here is the
        // claim: a draft reopened under its own title follows the title.
        let reopened = NSDocument()
        reopened.displayName = "Field notes on speed"
        let again = EditorWindow(
            contentWidth: 1_100, documentURL: nil, text: draftText, owner: reopened
        )
        again.settle(for: 1.0)
        if let textView = again.textView {
            let speed = (textView.string as NSString).range(of: "speed")
            textView.insertText(
                ", revisited",
                replacementRange: NSRange(location: NSMaxRange(speed), length: 0)
            )
            again.settle(for: 0.6)
            check(
                "a draft reopened under its title goes on being named by it",
                reopened.displayName == "Field notes on speed, revisited",
                "it is \"\(reopened.displayName ?? "")\""
            )

            reopened.displayName = "My own name"
            let revisited = (textView.string as NSString).range(of: "revisited")
            textView.insertText("reread", replacementRange: revisited)
            again.settle(for: 0.6)
            check(
                "and a name its writer gives it is theirs to keep",
                reopened.displayName == "My own name",
                "it became \"\(reopened.displayName ?? "")\""
            )
        } else {
            check("the reopened draft has a text view", false)
        }

        print("")
        print("How narrow it may then be dragged")

        check(
            "the floor rises to hold the rail while it is open",
            narrow.window.contentMinSize.width
                == EditorPaneGeometry.minimumContentWidth(
                    columnMinimum: columnMinimum,
                    documentMinimum: documentMinimum,
                    railWidth: rail,
                    railIsOpen: true
                ),
            "the window's minimum is \(narrow.window.contentMinSize.width)"
        )

        // Back to the width the bug was photographed at. The automatic sizing
        // covers the moment a window opens and nothing more, so this is the
        // half of the rule that has to hold afterwards: the column gives way
        // and the rail stays whole.
        narrow.window.setContentSize(NSSize(width: 900, height: 620))
        narrow.settle(for: 0.8)
        check(
            "dragged back to 900, the rail is still drawn whole",
            narrow.draw().map { narrow.trailingInk(width: rail - 16, of: $0) > 500 }
                ?? false,
            "the trailing \(rail) points are empty, so the rail was cut"
        )
        if let rep = narrow.draw() {
            narrow.writePNG(rep, named: "MDE_WINDOW_NARROW_PNG")
        }

        print("")
        print("A window that is already wide enough")

        let wide = EditorWindow(
            contentWidth: 1_400, documentURL: documentURL, text: text
        )
        let before = wide.window.frame
        wide.settle(for: 1.6)
        check(
            "is not narrowed to the ideal width",
            wide.contentWidth == 1_400,
            "it became \(wide.contentWidth)"
        )
        check(
            "and is not moved",
            wide.window.frame.origin == before.origin,
            "it moved from \(before.origin) to \(wide.window.frame.origin)"
        )

        print("")
        print("Opening the rail on a window already on screen")

        // The second of the two moments, driven through the real delegate. The
        // rail opens from the toolbar, ⌃⌘C or a critique starting, and none of
        // those can be pressed from here without spending a critique, so this
        // tells the delegate what `updateNSView` would and reads the frame.
        //
        // The window is first seen with the rail open and room for it, as a
        // real one is, so its one first look is spent before the rail closes.
        // Seen with the rail shut instead, that look would still be owed when
        // the rail opened and would widen the window on its own — and this
        // section would pass with the rail-opening path removed. It did, once.
        if let screen = NSScreen.main {
            let start = NSRect(
                x: screen.visibleFrame.minX + 40,
                y: screen.visibleFrame.minY + 40,
                width: wanted,
                height: 500
            )
            let plain = NSWindow(
                contentRect: start,
                styleMask: [.titled, .resizable],
                backing: .buffered,
                defer: false
            )
            plain.isReleasedWhenClosed = false
            plain.alphaValue = 0
            plain.orderBack(nil)
            let chrome = WindowChromeDelegate()
            chrome.attach(to: plain)
            func content() -> CGFloat {
                plain.contentRect(forFrameRect: plain.frame).width
            }
            func frame(content width: CGFloat) -> NSRect {
                var frame = plain.frame
                frame.size.width = plain.frameRect(
                    forContentRect: NSRect(x: 0, y: 0, width: width, height: 100)
                ).width
                return frame
            }
            let shutWidth = EditorPaneGeometry.idealContentWidth(
                columnWidth: column, railWidth: rail, railIsOpen: false
            )

            chrome.noteContent(width: wanted, railIsOpen: true)
            // Long enough for the first-seen pass `attach` queues to run too.
            let settle = Date().addingTimeInterval(0.3)
            while Date() < settle {
                RunLoop.current.run(
                    mode: .default, before: Date().addingTimeInterval(0.02)
                )
            }
            check(
                "seen with room for the rail, the window is left as it was",
                content() == wanted,
                "it became \(content())"
            )

            chrome.noteContent(width: shutWidth, railIsOpen: false)
            check(
                "closing the rail leaves the width alone",
                content() == wanted,
                "it became \(content())"
            )

            // Narrowed by hand while the rail is shut: the case a window's
            // first look cannot cover, because it has already had it.
            let narrow = frame(content: 700)
            plain.setFrame(narrow, display: false)
            chrome.noteContent(width: shutWidth, railIsOpen: false)
            check(
                "narrowed while it is shut, the window stays narrow",
                plain.frame == narrow,
                "it went from \(narrow) to \(plain.frame)"
            )

            chrome.noteContent(width: wanted, railIsOpen: true)
            check(
                "opening the rail widens it to hold the pair",
                content() == wanted,
                "it is \(content()), and needs \(wanted)"
            )
            check(
                "at the trailing edge, so the writing does not move",
                plain.frame.minX == narrow.minX,
                "it moved from \(narrow.minX) to \(plain.frame.minX)"
            )

            // Narrowed by hand while the rail stays open: the width now belongs
            // to the reader, and later updates must not take it back.
            let narrowed = frame(content: 800)
            plain.setFrame(narrowed, display: false)
            chrome.noteContent(width: wanted, railIsOpen: true)
            check(
                "and not again while it stays open",
                plain.frame == narrowed,
                "it went from \(narrowed) to \(plain.frame)"
            )
            plain.close()
        } else {
            check("there is a screen to widen against", false)
        }

        print("")
        print("Closing a document window")

        // macOS 27.2 keeps a closed document's window alive, editor and all,
        // and never sends the editor `onDisappear`. So it went on autosaving
        // and watching its file behind a window nobody could see, and twice
        // that ended in "Humanish couldn't autosave" over the writer's next
        // document. The windows here are kept alive the same way: by holding
        // on to them.
        func recorded(_ name: String) -> (url: URL, document: SaveRecorder)? {
            let url = directory.appendingPathComponent(name).standardizedFileURL
            try? text.write(to: url, atomically: true, encoding: .utf8)
            let document = SaveRecorder()
            document.fileURL = url
            NSDocumentController.shared.addDocument(document)
            guard NSDocumentController.shared.document(for: url) === document
            else { return nil }
            return (url, document)
        }

        if let typed = recorded("typed.md") {
            let window = EditorWindow(
                contentWidth: 1_100, documentURL: typed.url, text: text
            )
            window.window.isReleasedWhenClosed = false
            window.settle(for: 1.0)
            if let textView = window.textView {
                func type(_ words: String) {
                    let end = NSMaxRange(
                        (textView.string as NSString).range(of: "later reads.")
                    )
                    textView.insertText(
                        words, replacementRange: NSRange(location: end, length: 0)
                    )
                }
                // So that nothing saved after the close can be put down to
                // the recorder not being where the autosave looks.
                type(" Typed.")
                window.settle(for: 2.0)
                check(
                    "an edit is autosaved while its window is open",
                    typed.document.saves == 1,
                    "it was saved \(typed.document.saves) times"
                )

                // ⌘W a moment after the last word, inside the autosave's
                // delay: the document has saved itself by the time its
                // window closes, and the editor's own save is left over.
                type(" And again.")
                window.window.close()
                // At once, while `close()` is still running. Taken down a
                // moment later instead, once the window had left the screen,
                // the editor left its layers' surfaces behind: about 15 MB a
                // close, every close.
                check(
                    "closing the window takes the editor out of it at once",
                    window.textView == nil,
                    "the closed window still holds a text view"
                )
                window.settle(for: 2.0)
                check(
                    "and the autosave it had waiting is dropped",
                    typed.document.saves == 1,
                    "it was saved \(typed.document.saves) times"
                )
            } else {
                check("the closing editor has a text view", false)
            }
        } else {
            check("the autosave can find the document it saves", false)
        }

        // Rewritten by another app after its window has closed: the editor
        // used to take the new version in and autosave it, to a document that
        // was no longer open.
        if let watched = recorded("watched.md") {
            let window = EditorWindow(
                contentWidth: 1_100, documentURL: watched.url, text: text
            )
            window.window.isReleasedWhenClosed = false
            window.settle(for: 1.0)
            window.window.close()
            try? (text + "\nAdded by another app.\n")
                .write(to: watched.url, atomically: true, encoding: .utf8)
            window.settle(for: 3.0)
            check(
                "a file another app changes after its window closes is left alone",
                watched.document.saves == 0,
                "it was saved \(watched.document.saves) times"
            )
        } else {
            check("the autosave can find the document it saves", false)
        }

        print("")
        if failures == 0 {
            print("\(checks)/\(checks) checks passed")
            exit(0)
        }
        print("\(failures) of \(checks) checks failed")
        exit(1)
    }
}
