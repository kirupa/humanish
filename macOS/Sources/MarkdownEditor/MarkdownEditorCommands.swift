import MarkdownEditorCore
import MarkdownEditorUI
import SwiftUI

private struct MarkdownEditorSessionKey: FocusedValueKey {
    typealias Value = MarkdownEditorSession
}

private struct EditorColorThemeSelectionKey: FocusedValueKey {
    typealias Value = Binding<EditorColorTheme>
}

extension FocusedValues {
    var markdownEditorSession: MarkdownEditorSession? {
        get { self[MarkdownEditorSessionKey.self] }
        set { self[MarkdownEditorSessionKey.self] = newValue }
    }

    var editorColorThemeSelection: Binding<EditorColorTheme>? {
        get { self[EditorColorThemeSelectionKey.self] }
        set { self[EditorColorThemeSelectionKey.self] = newValue }
    }
}

struct MarkdownEditorCommands: Commands {
    @FocusedValue(\.markdownEditorSession)
    private var session
    @FocusedValue(\.runCritique)
    private var runCritique: (() -> Void)?
    @FocusedValue(\.runQuickCritique)
    private var runQuickCritique: (() -> Void)?
    @FocusedObject private var critique: CritiqueModel?
    @AppStorage(CritiqueSidebar.compactNotesKey) private var compactNotes = false

    @FocusedValue(\.editorColorThemeSelection)
    private var colorThemeSelection

    /// Greys a command out where it could not work.
    ///
    /// With no focused document nothing is greyed: the menu is drawn once for
    /// the whole app, and a document that is not open cannot be said to have
    /// the caret in code.
    private func isUnavailable(_ style: MarkdownInlineStyle) -> Bool {
        session.map { !$0.isAvailable(style) } ?? false
    }

    private func canStepTextScale(larger: Bool) -> Bool {
        guard let current = colorThemeSelection?.wrappedValue.textScale else {
            return false
        }
        return EditorColorTheme.steppedTextScale(from: current, larger: larger)
            != current
    }

    private func stepTextScale(larger: Bool) {
        guard let selection = colorThemeSelection else { return }
        selection.wrappedValue.textScale = EditorColorTheme.steppedTextScale(
            from: selection.wrappedValue.textScale,
            larger: larger
        )
    }

    /// Apply on the open note, from the keyboard: the same single change the
    /// note's own Apply makes, and the same beep when the words under it have
    /// moved on.
    private func applySelectedSuggestion() {
        guard let critique, let session, let id = critique.selectedFindingID else { return }
        if !critique.applySuggestion(for: id, using: session.replace) {
            NSSound.beep()
        }
    }

    private func toggleCritique() {
        guard let critique else { return }
        if critique.isPresented {
            critique.dismiss()
        } else {
            critique.reveal()
        }
    }

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Divider()
            DefaultMarkdownHandlerButton()
        }

        CommandGroup(after: .newItem) {
            Button("Open Folder…") {
                session?.chooseExplorerFolder()
            }
            .keyboardShortcut("o", modifiers: [.command, .option])
            .disabled(session == nil)

            Button("Reload from Disk") {
                session?.reloadFromDisk()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(session?.fileURL == nil)
        }

        CommandGroup(after: .sidebar) {
            Button(
                session?.isExplorerVisible == true
                    ? "Hide File Explorer"
                    : "Show File Explorer"
            ) {
                session?.toggleExplorer()
            }
            .keyboardShortcut("s", modifiers: [.control, .command])
            .disabled(session == nil)

            // ⌃⌘I is the Mac's key for the panel on a window's trailing
            // edge. The rail's ✕ was the only way to close it and the
            // toolbar's sparkles the only way back, and the second only
            // when a critique had been saved.
            Button(critique?.isPresented == false ? "Show Critique" : "Hide Critique") {
                toggleCritique()
            }
            .keyboardShortcut("i", modifiers: [.control, .command])
            .disabled(critique == nil)

            Divider()

            // How the page looks lives in View, where a Mac writer looks for
            // it. Theme Color and Background used to sit in the Markdown menu
            // between the critique and Bold, which is a menu about what the
            // document *says*.
            Button("Make Text Bigger") { stepTextScale(larger: true) }
                .keyboardShortcut("+")
                .disabled(!canStepTextScale(larger: true))
            Button("Make Text Smaller") { stepTextScale(larger: false) }
                .keyboardShortcut("-")
                .disabled(!canStepTextScale(larger: false))
            Button("Actual Size") {
                colorThemeSelection?.wrappedValue.textScale = 1
            }
            .keyboardShortcut("0")
            .disabled(
                colorThemeSelection == nil
                    || colorThemeSelection?.wrappedValue.textScale == 1
            )

            Divider()

            Menu("Theme Color") {
                ForEach(EditorThemeColor.allCases) { themeColor in
                    Button {
                        colorThemeSelection?.wrappedValue.color = themeColor
                    } label: {
                        if colorThemeSelection?.wrappedValue.color
                            == themeColor {
                            Label(themeColor.title, systemImage: "checkmark")
                        } else {
                            Text(themeColor.title)
                        }
                    }
                }
                .disabled(colorThemeSelection == nil)
            }

            Menu("Background") {
                ForEach(EditorAppearanceMode.allCases) { mode in
                    Button {
                        colorThemeSelection?.wrappedValue.mode = mode
                    } label: {
                        if colorThemeSelection?.wrappedValue.mode == mode {
                            Label(mode.title, systemImage: "checkmark")
                        } else {
                            Text(mode.title)
                        }
                    }
                }
                .disabled(colorThemeSelection == nil)
            }

            Divider()
        }

        CommandGroup(before: .windowList) {
            Button("Welcome to Humanish") {
                WelcomeWindowController.shared.show()
            }
            Divider()
        }

        CommandMenu("Markdown") {
            Button("Bold") {
                session?.toggleInline(.bold)
            }
            .keyboardShortcut("b")
            .disabled(isUnavailable(.bold))
            Button("Italic") {
                session?.toggleInline(.italic)
            }
            .keyboardShortcut("i")
            .disabled(isUnavailable(.italic))
            Button("Underline") {
                session?.toggleInline(.underline)
            }
            .keyboardShortcut("u")
            .disabled(isUnavailable(.underline))
            Button("Strikethrough") {
                session?.toggleInline(.strikethrough)
            }
            .disabled(isUnavailable(.strikethrough))

            Menu("Code") {
                Button("Inline Code (Single Line)") {
                    session?.toggleInline(.inlineCode)
                }
                .disabled(isUnavailable(.inlineCode))
                Button("Fenced Code Block (Multi-Line)") {
                    session?.insertFencedCodeBlock()
                }
            }

            // ⌘1 to ⌘6 for the levels and ⌥⌘0 for a paragraph: the
            // shortcuts Bear, Ulysses and iA Writer have taught writers, and
            // the menu had none at all. ⌘0 itself is View ▸ Actual Size.
            Menu("Heading") {
                Button("Paragraph") {
                    session?.applyHeading(level: 0)
                }
                .keyboardShortcut("0", modifiers: [.command, .option])
                Divider()
                ForEach(1...6, id: \.self) { level in
                    Button("Heading \(level)") {
                        session?.applyHeading(level: level)
                    }
                    .keyboardShortcut(
                        KeyEquivalent(Character(String(level)))
                    )
                }
            }
            .disabled(session == nil)

            Divider()

            Button("Bulleted List") {
                session?.toggleList(.bulleted)
            }
            Button("Numbered List") {
                session?.toggleList(.numbered)
            }
            Button("Task List") {
                session?.toggleList(.task)
            }
            Button("Quote") {
                session?.toggleQuote()
            }
            .keyboardShortcut("'")
            Button("Horizontal Rule") {
                session?.insertHorizontalRule()
            }
        }

        CommandMenu("Insert") {
            Button("Link…") {
                session?.chooseLink()
            }
            .keyboardShortcut("k")
            .disabled(session.map { !$0.isLinkAvailable } ?? false)
            Button("Image…") {
                session?.chooseAndInsertImage()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(session == nil)
            Button("Image Size…") {
                session?.chooseImageSize()
            }
            .keyboardShortcut("i", modifiers: [.command, .option, .shift])
            .disabled(session == nil)
        }

        // Its own menu, out of Markdown: the critique was the first two items
        // of a menu otherwise about formatting, and the keys for working
        // through its notes had nowhere to live.
        CommandMenu("Critique") {
            Button("AI Assisted Critique") { runCritique?() }
                .keyboardShortcut("c", modifiers: [.control, .command])
                .disabled(runCritique == nil)
            // The same chord with Option: the same thing, lighter. Option is
            // the modifier the Mac already uses for "the other version of
            // this command", so the pair is learned as one.
            Button("Quick Critique Pass") { runQuickCritique?() }
                .keyboardShortcut("c", modifiers: [.option, .control, .command])
                .disabled(runQuickCritique == nil)

            Divider()

            // ⌥⌘ and the arrows: free in the text view, which binds ⌘ and
            // ⌥ with them to caret moves but not the two together.
            Button("Next Note") { critique?.selectNext() }
                .keyboardShortcut(.downArrow, modifiers: [.option, .command])
                .disabled(critique?.canStepNotes != true)
            Button("Previous Note") { critique?.selectPrevious() }
                .keyboardShortcut(.upArrow, modifiers: [.option, .command])
                .disabled(critique?.canStepNotes != true)

            Divider()

            // Not ⌘↩ and ⌘⌫: ⌘⌫ deletes to the start of the line in every
            // Mac text view, and taking it would cost the writer that.
            Button("Mark Note Done") { critique?.answerSelected(.completed) }
                .keyboardShortcut(.return, modifiers: [.option, .command])
                .disabled(critique?.canAnswerSelected != true)
            Button("Dismiss Note") { critique?.answerSelected(.dismissed) }
                .keyboardShortcut(.delete, modifiers: [.option, .command])
                .disabled(critique?.canAnswerSelected != true)
            Button("Apply Suggestion") { applySelectedSuggestion() }
                .keyboardShortcut(.return, modifiers: [.shift, .option, .command])
                .disabled(critique?.canApplySelected != true || session == nil)

            Divider()

            Toggle("Compact Notes", isOn: $compactNotes)
        }
    }
}


/// The focused document's critique command.
///
/// Routed through the focus system rather than a notification. A notification
/// reaches every open document at once, and each one then has to work out
/// whether it was the intended target — which cannot be done reliably for a
/// document that has never been saved, because it has no URL to be recognised
/// by. Two unsaved windows would both run a critique, and both would spend
/// credits.
struct CritiqueActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

/// The focused document's quick critique pass, routed the same way as
/// `CritiqueActionKey` for the same reason.
struct QuickCritiqueActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var runCritique: CritiqueActionKey.Value? {
        get { self[CritiqueActionKey.self] }
        set { self[CritiqueActionKey.self] = newValue }
    }

    var runQuickCritique: QuickCritiqueActionKey.Value? {
        get { self[QuickCritiqueActionKey.self] }
        set { self[QuickCritiqueActionKey.self] = newValue }
    }
}
