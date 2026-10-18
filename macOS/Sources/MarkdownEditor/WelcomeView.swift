import AppKit
import MarkdownEditorCore
import MarkdownEditorUI
import SwiftUI

/// The landing page shown at launch: app identity, the two ways to get a
/// document on screen, and everything opened recently.
struct WelcomeView: View {
    @ObservedObject var recentDocuments: RecentDocumentsModel
    let onNewDocument: () -> Void
    let onOpenDocument: () -> Void
    let onOpenRecent: (RecentDocument) -> Void

    @AppStorage(EditorThemeColor.storageKey)
    private var themeColorRawValue = EditorThemeColor.blue.rawValue
    @AppStorage(EditorAppearanceMode.storageKey)
    private var appearanceModeRawValue =
        EditorAppearanceMode.systemDefault.rawValue
    @AppStorage(WelcomeWindowPreferences.showsAtLaunchKey)
    private var showsAtLaunch = true

    @State private var isDefaultMarkdownApp = true

    private var colorTheme: EditorColorTheme {
        EditorColorTheme(
            color: EditorThemeColor(rawValue: themeColorRawValue) ?? .blue,
            mode: EditorAppearanceMode(rawValue: appearanceModeRawValue)
                ?? .systemDefault
        )
    }

    private var primaryText: Color {
        Color(nsColor: colorTheme.primaryTextColor)
    }

    private var secondaryText: Color {
        Color(nsColor: colorTheme.secondaryTextColor)
    }

    var body: some View {
        HStack(spacing: 0) {
            identityPanel
            Rectangle()
                .fill(Color(nsColor: colorTheme.separatorColor))
                .frame(width: 1)
            recentPanel
        }
        .background(Color(nsColor: colorTheme.editorBackgroundColor))
        .tint(Color(nsColor: colorTheme.accentColor))
        .preferredColorScheme(colorTheme.colorScheme)
    }

    private var identityPanel: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Image(nsImage: logo)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: Self.logoSize, height: Self.logoSize)
                .accessibilityHidden(true)

            Text("Humanish")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(primaryText)
                .padding(.top, 14)

            Spacer(minLength: 24)

            VStack(spacing: 8) {
                WelcomeActionButton(
                    title: "New Document",
                    subtitle: "Start an empty Markdown file",
                    systemImage: "square.and.pencil",
                    colorTheme: colorTheme,
                    action: onNewDocument
                )
                .keyboardShortcut(.defaultAction)

                WelcomeActionButton(
                    title: "Open…",
                    subtitle: "Browse for an existing document",
                    systemImage: "folder",
                    colorTheme: colorTheme,
                    action: onOpenDocument
                )
            }

            Spacer(minLength: 24)

            VStack(spacing: 10) {
                if !isDefaultMarkdownApp {
                    Button("Make Default Markdown App") {
                        makeDefaultMarkdownApp()
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                }

                Toggle("Show this window at launch", isOn: $showsAtLaunch)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .foregroundStyle(secondaryText)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 30)
        .padding(.bottom, 20)
        .frame(width: 320)
        .background(colorTheme.sidebarBackground)
        .onAppear {
            isDefaultMarkdownApp = DefaultMarkdownHandler.isCurrentApp
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            isDefaultMarkdownApp = DefaultMarkdownHandler.isCurrentApp
        }
    }

    private func makeDefaultMarkdownApp() {
        Task {
            do {
                try await DefaultMarkdownHandler.makeCurrentAppDefault()
            } catch {
                NSApp.presentError(error)
            }
            isDefaultMarkdownApp = DefaultMarkdownHandler.isCurrentApp
        }
    }

    private var recentPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Recent Documents")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(primaryText)

                Spacer(minLength: 0)

                if recentDocuments.hasDocuments {
                    Button("Clear") {
                        recentDocuments.clear()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: colorTheme.accentColor))
                    .help("Forget every recent document")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 26)
            .padding(.bottom, 12)

            Rectangle()
                .fill(Color(nsColor: colorTheme.separatorColor))
                .frame(height: 1)

            if recentDocuments.hasDocuments {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(recentDocuments.documents) { document in
                            RecentDocumentRow(
                                document: document,
                                colorTheme: colorTheme,
                                onOpen: {
                                    onOpenRecent(document)
                                },
                                onRemove: {
                                    recentDocuments.remove(document.url)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyState: some View {
        VStack(spacing: 7) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(secondaryText)
                .accessibilityHidden(true)
            Text("No Recent Documents")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(primaryText)
            Text("Documents you open or save show up here.")
                .font(.system(size: 11))
                .foregroundStyle(secondaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The app's own icon, at the size the identity panel draws it.
    ///
    /// The plate inside a macOS icon is inset from its canvas by 8.6% a side —
    /// see `Scripts/make-icons.swift` — so this is the canvas, and the logo a
    /// reader sees is about 70pt of it.
    private static let logoSize: CGFloat = 84

    /// The logo, read from the bundle rather than drawn again here.
    ///
    /// `Scripts/make-icons.swift` generates the icon, so a second copy of the
    /// artwork in this view would be one more place to update and one more
    /// place to forget. `applicationIconName` resolves to whatever the bundle
    /// ships, which is the same mark as in the Dock and in Finder — the point
    /// of a logo being that it is the same everywhere.
    private var logo: NSImage {
        NSImage(named: NSImage.applicationIconName)
            ?? NSImage(
                systemSymbolName: "doc.richtext",
                accessibilityDescription: nil
            )
            ?? NSImage()
    }
}

private struct WelcomeActionButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let colorTheme: EditorColorTheme
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16))
                    .frame(width: 21)
                    .foregroundStyle(Color(nsColor: colorTheme.accentColor))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(
                            Color(nsColor: colorTheme.primaryTextColor)
                        )
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(
                            Color(nsColor: colorTheme.secondaryTextColor)
                        )
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        Color(nsColor: colorTheme.accentColor)
                            .opacity(isHovering ? 0.16 : 0.07)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        Color(nsColor: colorTheme.accentColor)
                            .opacity(isHovering ? 0.65 : 0.3),
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}

private struct RecentDocumentRow: View {
    let document: RecentDocument
    let colorTheme: EditorColorTheme
    let onOpen: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 15))
                    .frame(width: 18)
                    .foregroundStyle(foreground(opacity: 0.75))

                VStack(alignment: .leading, spacing: 1) {
                    Text(document.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(foreground(opacity: 1))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(document.folderDisplayPath)
                        .font(.system(size: 11))
                        .foregroundStyle(foreground(opacity: 0.7))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                if let modificationDate = document.modificationDate {
                    Text(
                        modificationDate.formatted(
                            date: .abbreviated,
                            time: .omitted
                        )
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(foreground(opacity: 0.7))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        isHovering
                            ? Color(nsColor: colorTheme.selectionBackgroundColor)
                            : Color.clear
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .help(document.url.path)
        .contextMenu {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([document.url])
            }
            Divider()
            Button("Remove from Recents", action: onRemove)
        }
        .accessibilityLabel(document.name)
        .accessibilityValue(document.folderDisplayPath)
    }

    private func foreground(opacity: Double) -> Color {
        let baseColor = isHovering
            ? colorTheme.selectionTextColor
            : colorTheme.primaryTextColor
        return Color(nsColor: baseColor).opacity(opacity)
    }
}
