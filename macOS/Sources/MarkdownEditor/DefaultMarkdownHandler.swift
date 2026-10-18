import AppKit
import UniformTypeIdentifiers

/// Reads and changes which application macOS opens Markdown files with.
///
/// Being listed in Finder's Open With menu only requires the type declarations
/// in `Info.plist`; becoming the *default* is a user choice, which this offers
/// a way to make without leaving the app.
@MainActor
enum DefaultMarkdownHandler {
    static let markdownType = UTType("net.daringfireball.markdown")

    /// True when double-clicking a Markdown file in Finder opens this build.
    static var isCurrentApp: Bool {
        guard let markdownType,
            let current = NSWorkspace.shared.urlForApplication(toOpen: markdownType)
        else {
            return false
        }
        return current.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    /// Makes this build the default handler for `.md` and `.markdown`.
    ///
    /// On macOS 14 and newer this routes through `NSWorkspace`, which asks the
    /// user to confirm. Earlier releases fall back to Launch Services, which
    /// applies the change directly.
    static func makeCurrentAppDefault() async throws {
        guard let markdownType else {
            throw DefaultHandlerError.unknownContentType
        }

        if #available(macOS 14.0, *) {
            try await NSWorkspace.shared.setDefaultApplication(
                at: Bundle.main.bundleURL,
                toOpen: markdownType
            )
            return
        }

        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            throw DefaultHandlerError.unknownContentType
        }
        let status = LSSetDefaultRoleHandlerForContentType(
            markdownType.identifier as CFString,
            .all,
            bundleIdentifier as CFString
        )
        guard status == noErr else {
            throw DefaultHandlerError.launchServices(status)
        }
    }
}

enum DefaultHandlerError: LocalizedError {
    case unknownContentType
    case launchServices(OSStatus)

    var errorDescription: String? {
        "Humanish could not be made the default Markdown application."
    }

    var failureReason: String? {
        switch self {
        case .unknownContentType:
            "macOS does not recognize the Markdown content type on this system."
        case let .launchServices(status):
            "Launch Services reported error \(status)."
        }
    }

    var recoverySuggestion: String? {
        "Select a Markdown file in Finder, choose File ▸ Get Info, and set "
            + "\"Open with\" to Humanish."
    }
}
