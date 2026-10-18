import MarkdownEditorUI
import SwiftUI

/// Picks which of the two app declarations below runs.
///
/// They differ in one line. On macOS 27 SwiftUI opens an untitled document
/// from inside its own `applicationDidFinishLaunching`, before the app
/// delegate is consulted and without calling
/// `applicationShouldOpenUntitledFile(_:)` or `applicationOpenUntitledFile(_:)`.
/// The welcome window (W-1) then never appeared, and launch spent about half a
/// second building an editor window nobody asked for. From macOS 15 a scene
/// can be told not to open anything at launch; a scene builder accepts
/// `if #available` only without an `else`, so the choice is made here rather
/// than inside `body`.
@main
@MainActor
enum MarkdownEditorMain {
    static func main() {
        if #available(macOS 15, *) {
            QuietLaunchMarkdownEditorApp.main()
        } else {
            MarkdownEditorApp.main()
        }
    }
}

/// macOS 13 and 14, where AppKit's own launch paths are what the app delegate
/// intercepts.
struct MarkdownEditorApp: App {
    @NSApplicationDelegateAdaptor(MarkdownEditorAppDelegate.self)
    private var appDelegate

    var body: some Scene {
        DocumentWindows()

        // The standard place: Humanish ▸ Settings, ⌘,. A reader looking for a
        // preference looks there before anywhere else.
        Settings {
            CritiqueSettingsView()
        }
    }
}

@available(macOS 15, *)
struct QuietLaunchMarkdownEditorApp: App {
    @NSApplicationDelegateAdaptor(MarkdownEditorAppDelegate.self)
    private var appDelegate

    var body: some Scene {
        // With the welcome window switched off, launch is left exactly as
        // SwiftUI does it, which is what W-5 promises. Restored documents and
        // documents opened from Finder arrive either way: this only decides
        // whether SwiftUI opens one of its own.
        DocumentWindows()
            .defaultLaunchBehavior(
                WelcomeWindowPreferences.showsAtLaunch ? .suppressed : .automatic
            )

        Settings {
            CritiqueSettingsView()
        }
    }
}

struct DocumentWindows: Scene {
    @AppStorage(EditorThemeColor.storageKey)
    private var themeColorRawValue = EditorThemeColor.blue.rawValue
    @AppStorage(EditorAppearanceMode.storageKey)
    private var appearanceModeRawValue =
        EditorAppearanceMode.systemDefault.rawValue
    @AppStorage(EditorColorTheme.typefaceStorageKey)
    private var typefaceRawValue = EditorTypeface.sans.rawValue
    @AppStorage(EditorColorTheme.textScaleStorageKey)
    private var textScale = 1.0

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { configuration in
            MarkdownEditorView(
                document: configuration.$document,
                fileURL: configuration.fileURL,
                themeColorRawValue: $themeColorRawValue,
                appearanceModeRawValue: $appearanceModeRawValue,
                typefaceRawValue: $typefaceRawValue,
                textScale: $textScale
            )
        }
        // The window opens big enough to hold what it opens showing: the
        // writing column and the comments rail beside it, capped to the
        // screen it lands on.
        //
        // Only used when there is nothing to restore: SwiftUI applies this to
        // a genuinely new window and leaves a restored one at the size it was
        // last left, which is the behaviour a reader who has resized a window
        // expects and the reason this is not done by setting a frame.
        .defaultSize(Layout.defaultWindowContentSize)
        .commands {
            // Edit ▸ Find, Spelling and Grammar, Substitutions and the rest.
            // Leaving it out left ⌘F and ⌘G with no menu item to send them
            // and no way at all to switch on spell checking.
            TextEditingCommands()
            MarkdownEditorCommands()
        }
    }
}
