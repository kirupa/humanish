import AppKit
import MarkdownEditorUI
import SwiftUI

/// The things this window's title bar does that it would not do on its own:
/// fill the screen when double-clicked, move when dragged, and name the file it
/// is showing — plus the size Zoom goes to, which is asked of the same delegate.
///
/// They are here together because they are the same click, asked about in the
/// same geometry, and splitting them across files would mean two event
/// monitors racing for the same mouse-down.
///
/// A double-click fills the screen rather than zooming: see `TitleBarFill`.
/// Zoom — the green button's, and Window ▸ Zoom — keeps its own meaning, the
/// best size for the content, which is what the rest of this comment is about.
///
/// macOS asks the window's delegate `windowWillUseStandardFrame(_:defaultFrame:)`
/// and, with no answer, offers the whole screen. That is the wrong answer here
/// twice over: it is far more window than a document column needs, and with the
/// comments open it does not follow the content at all — the rail is a fixed
/// width docked to the document, so "everything" is a specific number rather
/// than "as much as possible".
///
/// It also widens the window to that same number when it is first seen, and
/// when the comments open on one that was already there — the one thing the
/// green button could never do: zoom is something a reader has to ask for, and
/// a document whose comments squeeze the writing has already got it wrong by
/// the time they could. A new window mostly needs nothing here, because it
/// opens at `Layout.defaultWindowContentSize`; this covers the windows that
/// size does not reach — one restored at a narrower width, and one whose
/// comments open after it was narrowed, or its column widened, while they were
/// shut.
///
/// Attached as a modifier on the editor, which is the only place that knows the
/// column's current width and whether the comments are open.
struct WindowChrome: ViewModifier {
    let contentWidth: CGFloat
    let railIsOpen: Bool
    let fileURL: URL?
    let onClose: () -> Void

    func body(content: Content) -> some View {
        content.background(
            WindowChromeTarget(
                contentWidth: contentWidth,
                railIsOpen: railIsOpen,
                fileURL: fileURL,
                onClose: onClose
            )
        )
    }
}

extension View {
    /// Give this window a title bar that moves when dragged, fills the screen
    /// when double-clicked and can name the file it is showing, a Zoom that
    /// goes to `contentWidth` points of content — and, while `railIsOpen`, a
    /// width that holds that content rather than clipping it. `onClose` runs
    /// as the window closes, which nothing in SwiftUI reliably says: see
    /// `WindowChromeDelegate.watchForClose(of:)`.
    func windowChrome(
        contentWidth: CGFloat,
        railIsOpen: Bool,
        fileURL: URL?,
        onClose: @escaping () -> Void
    ) -> some View {
        modifier(
            WindowChrome(
                contentWidth: contentWidth,
                railIsOpen: railIsOpen,
                fileURL: fileURL,
                onClose: onClose
            )
        )
    }
}

/// The bridge to the window. Draws nothing.
private struct WindowChromeTarget: NSViewRepresentable {
    let contentWidth: CGFloat
    let railIsOpen: Bool
    let fileURL: URL?
    let onClose: () -> Void

    func makeCoordinator() -> WindowChromeDelegate { WindowChromeDelegate() }

    func makeNSView(context: Context) -> NSView {
        let view = AttachingView()
        view.coordinator = context.coordinator
        return view
    }

    /// The window's delegate slot is weak, so leaving it holding this
    /// coordinator once SwiftUI lets go of it would leave the slot empty and
    /// SwiftUI's own delegate unasked about everything after.
    static func dismantleNSView(
        _ nsView: NSView,
        coordinator: WindowChromeDelegate
    ) {
        coordinator.detach()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.fileURL = fileURL
        context.coordinator.onClose = onClose
        // The window may arrive after the first layout pass, so this is also
        // where a late one gets picked up.
        (nsView as? AttachingView)?.attachIfPossible()
        // Last, because it is the one thing here that needs the window: this
        // is where a rail that has just opened asks for room.
        context.coordinator.noteContent(
            width: contentWidth,
            railIsOpen: railIsOpen
        )
    }

    /// A view whose only job is to notice it has a window.
    final class AttachingView: NSView {
        weak var coordinator: WindowChromeDelegate?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attachIfPossible()
        }

        func attachIfPossible() {
            guard let window, let coordinator else { return }
            coordinator.attach(to: window)
        }
    }
}

/// Answers the zoom question, and passes every other question along.
///
/// A window has one delegate and SwiftUI's `DocumentGroup` has already claimed
/// it — for window restoration, for the document's edited state, for the close
/// behaviour. Replacing it outright would break all of that silently, so this
/// stands in front and forwards everything it does not answer itself, through
/// the ordinary Objective-C forwarding that `NSWindow` uses to ask in the first
/// place.
/// Main-actor isolated in full: every entry point is one — a window delegate
/// callback, a local event monitor, or a menu action — and saying so once here
/// beats scattering the annotation over each of them.
@MainActor
final class WindowChromeDelegate: NSObject, NSWindowDelegate {
    var contentWidth: CGFloat = 0

    /// Whether the comments rail is in the row.
    ///
    /// Closing it does **not** narrow the window again, and that is a choice
    /// rather than an omission. A window is a thing somebody placed; taking
    /// 356 points off it because a panel closed would move the writing they
    /// are reading to pay for a panel they just dismissed. The width that is
    /// left is not empty desk either — with the rail gone the page takes back
    /// its bleed margins, so wide pictures have somewhere to go. Zoom is still
    /// there for anyone who does want the window sized to the writing alone:
    /// `windowWillUseStandardFrame` answers with exactly that number.
    private(set) var railIsOpen = false

    /// The document on screen, so the title menu can name it and reveal it.
    ///
    /// Kept here rather than read from the window: SwiftUI's `DocumentGroup`
    /// does not set `representedURL`, so the window itself does not know.
    var fileURL: URL? {
        didSet { window?.representedURL = fileURL }
    }

    /// The delegate that was there first. Strong on purpose: `window.delegate`
    /// is a weak reference, so once this object takes that slot nothing else
    /// holds SwiftUI's delegate and it would be deallocated — taking window
    /// restoration and the document's close handling with it.
    private var next: NSWindowDelegate?
    private weak var window: NSWindow?

    func attach(to window: NSWindow) {
        // Idempotent: `viewDidMoveToWindow` and `updateNSView` both call this,
        // and a second attach would make this object its own `next` and
        // forward to itself for ever.
        guard window.delegate !== self else { return }
        self.window = window
        next = window.delegate
        window.delegate = self
        watchForTitleBarClicks()
        watchForClose(of: window)
        // One turn of the runloop later, because SwiftUI sizes and orders this
        // window *after* the view is in it: measured now, the frame is the one
        // about to be replaced, and widening it would be undone a moment later.
        DispatchQueue.main.async { [weak self] in
            self?.sizeToContentIfNeeded()
        }
    }

    /// Gives the delegate slot back to whoever had it first.
    ///
    /// A turn of the runloop later rather than now. This view comes down as
    /// the window closes, from inside the notification telling SwiftUI's
    /// delegate so, and trading delegates halfway through could keep it from
    /// hearing that. Until then this object stays in the slot and passes it
    /// all on. (Measured: by then AppKit has usually emptied a closed
    /// window's slot itself, and there is nothing left to give back.)
    func detach() {
        DispatchQueue.main.async { [self] in
            guard let window, window.delegate === self else { return }
            window.delegate = next
        }
    }

    // MARK: - Closing

    /// What the editor does as this window closes.
    var onClose: (() -> Void)?

    /// Watches for the window closing, because nothing else says so.
    ///
    /// Measured on macOS 27.2: a closed document's window outlives its
    /// document. `NSApplication` still lists it, invisible, with the whole
    /// editor inside, and SwiftUI never calls the content's `onDisappear`.
    /// It is not the editor holding on: a bare `Text` as the scene's content
    /// stays alive the same way, held from inside SwiftUI and AppKit.
    ///
    /// So the editor kept doing everything it had been doing. An edit made by
    /// another app to a file already closed here was applied to the closed
    /// editor, which then tried to autosave a document that no longer existed
    /// and put up "Humanish couldn't autosave". Typing and pressing ⌘W inside the
    /// autosave delay did the same, over a file that had in fact saved.
    ///
    /// Selector-based, under a name of its own: `windowWillClose(_:)` is the
    /// delegate method this object forwards to SwiftUI's delegate, and
    /// answering it here would stop that.
    private func watchForClose(of window: NSWindow) {
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.willCloseNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowIsClosing(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
    }

    @objc private func windowIsClosing(_ notification: Notification) {
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.willCloseNotification,
            object: nil
        )
        // Each watches every mouse-down in the app, for a title bar that is
        // no longer on screen. The deinit that would remove them waits on
        // SwiftUI letting go of the window, which it does not.
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let rightMonitor { NSEvent.removeMonitor(rightMonitor) }
        monitor = nil
        rightMonitor = nil
        onClose?()
        // Have SwiftUI take the editor down now, while the window is still
        // on screen, rather than on its next pass, after it has gone.
        // Measured: the layers of a window already ordered out are never
        // given back. Each close of a 21,500-word document kept another
        // 15 MB, outside the heap, with no end to it; laid out and committed
        // here, eight closes in a row level off at 16 MB in all.
        let window = notification.object as? NSWindow
        window?.contentView?.layoutSubtreeIfNeeded()
        CATransaction.flush()
    }

    // MARK: - Making room for the comments

    /// Whether the window has been measured against its content since it
    /// appeared.
    private var hasSizedToContent = false

    /// Take the current content, and widen the window if it has just become
    /// too narrow for it.
    func noteContent(width: CGFloat, railIsOpen: Bool) {
        let railJustOpened = railIsOpen && !self.railIsOpen
        contentWidth = width
        self.railIsOpen = railIsOpen
        sizeToContentIfNeeded(force: railJustOpened)
    }

    /// Widen the window so the rail it is showing is inside it, beside a
    /// column at the width the reader set rather than one squeezed to make room.
    ///
    /// Every document window is born with the rail presented —
    /// `CritiqueModel.isDismissed` starts false and `attach(to:)` resets it.
    /// Before any sizing existed a window opened too narrow for the pair and
    /// the rail was laid out past the trailing edge: measured on
    /// `scroll-test.md`, the panel's header showed, its body text and its
    /// "Run critique" button did not. The rising minimum width and the column
    /// clamp now keep the rail whole at any width, and a new window opens at
    /// `Layout.defaultWindowContentSize`; what is left for this is the column.
    /// A window restored narrower than the pair, or one narrowed — or its
    /// column widened — while the comments were shut, would otherwise show the
    /// rail by taking the room from the writing.
    ///
    /// Twice, and only twice: when the window is first seen on screen, and at
    /// the moment the rail opens on one that was already there. Not on every
    /// update — the column's width changes on every drag of the gripper, and a
    /// window that grew to "ideal" each time would be a window that cannot be
    /// made smaller. Between those two moments the width belongs to the reader.
    ///
    /// Not animated, deliberately. The rail itself appears in one frame —
    /// nothing wraps `reveal()` in `withAnimation` — so a window that took a
    /// fifth of a second to catch up would spend that fifth of a second
    /// showing exactly the clipped rail this is here to prevent.
    private func sizeToContentIfNeeded(force: Bool = false) {
        guard railIsOpen, contentWidth > 0, let window else { return }
        // `isVisible` is what makes "first seen" precise. A window still being
        // assembled has neither its final frame nor a screen, and counting
        // that as the one look would spend it on a measurement of nothing.
        guard force || (!hasSizedToContent && window.isVisible) else { return }
        guard let screen = window.screen ?? NSScreen.main else { return }
        // Before the work, not after: `setFrame` lays the content out again,
        // which can re-enter this through `updateNSView`. Only once the window
        // is really on screen, though — a forced pass over one still being
        // assembled must not spend the single look this window gets.
        if window.isVisible { hasSizedToContent = true }

        // Content points to window points: the difference is the window's own
        // frame, which is not a constant — a title bar's height depends on
        // whether the window has a toolbar, and on the system's text size.
        let target = window.frameRect(
            forContentRect: NSRect(
                x: 0, y: 0, width: contentWidth, height: 100
            )
        ).width
        let fitted = EditorPaneGeometry.widenedFrame(
            window.frame,
            toWidth: target,
            within: screen.visibleFrame
        )
        // A window already wide enough is left alone entirely, rather than set
        // to the frame it is already in.
        guard fitted != window.frame else { return }
        window.setFrame(fitted, display: true)
    }

    // MARK: - Clicks in the title bar

    private var monitor: Any?
    private var rightMonitor: Any?

    /// Fill the screen on a double-click, and move the window on a drag.
    ///
    /// Both are things the system does for an ordinary window and does not do
    /// for this one. The double-click, because macOS only acts on it when
    /// "Double-click a window's title bar to" is set to something, and measured
    /// on this machine it is not — `AppleMiniaturizeOnDoubleClick` is 0 and
    /// `AppleActionOnDoubleClick` is unset, so the gesture does nothing at all,
    /// in every app.
    ///
    /// Dragging, because SwiftUI fills the title bar with a hosting view that
    /// swallows the mouse. Measured before this: of a 900-point bar, only a
    /// 15-point sliver by the traffic lights and an 8-point sliver at the far
    /// right actually moved the window — every grab in the middle 75% did
    /// nothing whatsoever.
    ///
    /// The right-hand monitor is a second one rather than a wider match on the
    /// first, because a right-click has no `clickCount` worth reading and
    /// mixing the two made the conditions hard to follow.
    ///
    /// A *local* monitor, so it only ever sees this app's own events.
    private func watchForTitleBarClicks() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) {
            [weak self] event in
            guard let self else { return event }
            if self.fillIfTitleBarDoubleClick(event) { return nil }
            // Command-click, which is how every Mac title bar has opened its
            // path menu since long before this app existed. Checked before the
            // drag, because a command-drag would otherwise move the window and
            // the menu would never appear.
            if event.modifierFlags.contains(.command),
               self.showTitleMenuIfTitleBar(event) { return nil }
            if self.dragWindowIfTitleBar(event) { return nil }
            // Returned unchanged otherwise: this reads the event rather than
            // consuming it, so a click on a toolbar button still reaches it.
            return event
        }
        rightMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.rightMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            return self.showTitleMenuIfTitleBar(event) ? nil : event
        }
    }

    /// Moves the window with the mouse, the way the title bar is supposed to.
    ///
    /// `performDrag(with:)` hands the whole gesture to AppKit, so the window
    /// gets the system's own behaviour for free: it snaps to screen edges,
    /// tiles against other windows, and moves between displays correctly. Doing
    /// the arithmetic here instead would be a worse version of all three.
    ///
    /// Returns whether the event was taken. A click that lands on a control is
    /// not, so the toolbar keeps working.
    ///
    /// `@MainActor` because it is: a local event monitor is called on the main
    /// thread, and this is where that fact is written down for the compiler.

    @discardableResult
    private func dragWindowIfTitleBar(_ event: NSEvent) -> Bool {
        guard event.clickCount == 1, claimsTitleBarClick(event),
              let window
        else { return false }
        window.performDrag(with: event)
        return true
    }

    /// What the last double-click did, so the next one can undo it.
    private var fill = TitleBarFill()

    /// Fills the screen, or puts the window back where it was before it did.
    ///
    /// All the room there is — the screen's visible frame, so the menu bar and
    /// the Dock stay reachable — rather than `zoom(nil)`, which goes to the
    /// best size for the content: the document plus its comments, a window
    /// barely different from the one a document opens in.
    @discardableResult
    private func fillIfTitleBarDoubleClick(_ event: NSEvent) -> Bool {
        guard event.clickCount == 2, claimsTitleBarClick(event),
              let window
        else { return false }
        // A full-screen window already has all of it, and its frame is the
        // system's to manage.
        guard !window.styleMask.contains(.fullScreen),
              let screen = window.screen ?? NSScreen.main
        else { return true }
        // Where a window that already fills the screen goes when there is
        // nowhere earlier to return to: the size a new one opens at.
        let fallback = window.frameRect(
            forContentRect: NSRect(
                x: 0,
                y: 0,
                width: contentWidth > 0 ? contentWidth : Layout.defaultWindowWidth,
                height: Layout.defaultWindowHeight
            )
        ).size
        let target = fill.toggle(
            from: window.frame,
            available: screen.visibleFrame,
            fallbackSize: fallback
        )
        window.setFrame(target, display: true, animate: true)
        fill.settle(at: window.frame)
        return true
    }

    /// Whether a click belongs to the title bar itself rather than to a control
    /// sitting in it.

    private func claimsTitleBarClick(_ event: NSEvent) -> Bool {
        guard let window, event.window === window,
              // The title bar's own view, found through a button AppKit always
              // puts there.
              let titleBar = window.standardWindowButton(.closeButton)?.superview
        else { return false }
        return EditorPaneGeometry.titleBarClaimsClick(
            at: event.locationInWindow,
            titleBar: titleBar.convert(titleBar.bounds, to: nil),
            controls: controlFrames(in: window)
        )
    }

    // MARK: - The title menu

    /// The menu a title bar offers when its name is clicked.
    ///
    /// Every Mac document window has one: ⌘-click or right-click the title and
    /// you get the folder it is in, so you can walk up the path or jump to it
    /// in the Finder. This window did not, because `DocumentGroup` never sets
    /// `representedURL` and AppKit builds that menu from it.
    ///
    /// Setting the URL restores the system's own path menu. **Copy Path** and
    /// **Reveal in Finder** are added above it, because those are the two
    /// things people actually want from a title bar and neither is reachable
    /// from the stock menu — it navigates, it does not tell you where you are
    /// or take you there.
    ///
    /// An untitled document has no path, so it gets a disabled line saying so
    /// rather than a menu of items that cannot work.

    @discardableResult
    private func showTitleMenuIfTitleBar(_ event: NSEvent) -> Bool {
        guard claimsTitleBarClick(event), let window else { return false }
        let menu = NSMenu()

        guard let fileURL else {
            let unsaved = NSMenuItem(
                title: "Not saved yet", action: nil, keyEquivalent: ""
            )
            unsaved.isEnabled = false
            menu.addItem(unsaved)
            NSMenu.popUpContextMenu(menu, with: event, for: window.contentView ?? NSView())
            return true
        }

        let copy = NSMenuItem(
            title: "Copy Path",
            action: #selector(copyPath),
            keyEquivalent: ""
        )
        copy.target = self
        menu.addItem(copy)

        let reveal = NSMenuItem(
            title: "Reveal in Finder",
            action: #selector(revealInFinder),
            keyEquivalent: ""
        )
        reveal.target = self
        menu.addItem(reveal)

        // The folders above it, so the menu can also be walked upwards the way
        // every other Mac title menu can.
        //
        // Built here rather than copied from the window's own icon button:
        // AppKit fills that menu in only while it is being shown, so reading it
        // from a right-click elsewhere in the bar finds it empty. Measured —
        // the first version copied it and got nothing.
        let ancestors = EditorPaneGeometry.folderChain(from: fileURL)
        if !ancestors.isEmpty {
            menu.addItem(.separator())
            for folder in ancestors {
                let item = NSMenuItem(
                    title: folder.lastPathComponent,
                    action: #selector(openFolder(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = folder
                item.image = NSWorkspace.shared.icon(forFile: folder.path)
                item.image?.size = NSSize(width: 16, height: 16)
                menu.addItem(item)
            }
        }

        NSMenu.popUpContextMenu(menu, with: event, for: window.contentView ?? NSView())
        return true
    }

    @objc private func openFolder(_ sender: NSMenuItem) {
        guard let folder = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(folder)
    }

    /// The path, as text, on the pasteboard.
    ///
    /// The POSIX path rather than the `file://` URL: it is what a terminal, a
    /// build script and every other Mac application expect, and it is what
    /// Finder's own "Copy … as Pathname" puts there.
    @objc private func copyPath() {
        guard let fileURL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        // The URL as well as the string, so dropping into something that wants
        // a file reference works rather than pasting a path into it.
        pasteboard.writeObjects([fileURL as NSURL])
        pasteboard.setString(fileURL.path, forType: .string)
    }

    @objc private func revealInFinder() {
        guard let fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    /// Whether something clickable sits under this point in the title bar.
    ///
    /// Asked of the controls' own frames rather than by hit-testing, which
    /// cannot answer it here: SwiftUI draws the whole bar through one
    /// `ToolbarItemHostingView`, so a hit test at the theme button, at the
    /// document's title and at empty space away from both all return the same
    /// view. Measured — the first version trusted the hit test and zoomed the
    /// window every time the theme button was double-clicked.
    ///
    /// The title text is deliberately not counted. It is not a control, and
    /// in every other Mac application double-clicking it acts on the window.
    private func controlFrames(in window: NSWindow) -> [CGRect] {
        var frames: [CGRect] = []
        for item in window.toolbar?.items ?? [] {
            guard let view = item.view else { continue }
            frames.append(view.convert(view.bounds, to: nil))
        }
        // The traffic lights, which are the window's rather than the toolbar's.
        let standard: [NSWindow.ButtonType] = [
            .closeButton, .miniaturizeButton, .zoomButton,
            .toolbarButton, .documentIconButton, .fullScreenButton,
        ]
        for kind in standard {
            guard let button = window.standardWindowButton(kind) else { continue }
            frames.append(button.convert(button.bounds, to: nil))
        }
        return frames
    }

    /// `isolated deinit`, so the monitors can be removed at all.
    ///
    /// They are `Any?` — what `addLocalMonitorForEvents` returns — which is not
    /// `Sendable`, so an ordinary nonisolated deinit cannot touch them. Leaving
    /// them unremoved would mean every closed window keeps a monitor watching
    /// every mouse-down in the app for ever.
    isolated deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let rightMonitor { NSEvent.removeMonitor(rightMonitor) }
    }

    // MARK: - The one question this answers

    func windowWillUseStandardFrame(
        _ window: NSWindow,
        defaultFrame: NSRect
    ) -> NSRect {
        guard contentWidth > 0 else { return defaultFrame }

        // Content points to window points: the difference is the window's own
        // frame, which is not a constant — a title bar's height depends on
        // whether the window has a toolbar, and on the system's text size.
        let asFrame = window.frameRect(
            forContentRect: NSRect(
                x: 0, y: 0, width: contentWidth, height: 100
            )
        )
        let width = min(asFrame.width, defaultFrame.width)

        // Full height, which is what zoom means vertically: a document is as
        // long as it is, so there is no height that "fits the content".
        //
        // Horizontally the window stays where it is unless that would push it
        // off the screen, because zoom is a resize and a window that jumps
        // across the desk to grow is disorienting.
        let x = min(
            max(window.frame.minX, defaultFrame.minX),
            defaultFrame.maxX - width
        )
        return NSRect(
            x: x,
            y: defaultFrame.minY,
            width: width,
            height: defaultFrame.height
        )
    }

    // MARK: - Everything else

    override func responds(to selector: Selector!) -> Bool {
        if super.responds(to: selector) { return true }
        return next?.responds(to: selector) ?? false
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        if next?.responds(to: selector) == true { return next }
        return super.forwardingTarget(for: selector)
    }
}
