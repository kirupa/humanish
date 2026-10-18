# Humanish for the Web — Product Requirements Document

The browser build of [Humanish](../macOS/README.md), published at
<https://www.kirupa.com/humanish/>. Same clean writing space and AI-assisted
review, same Markdown semantics, same keyboard shortcuts, same themes — served
by PHP with nothing installed on the host but PHP itself.

**Status:** Living document, kept in step with the macOS PRD.
**Requires:** PHP 8.1 or newer, and a browser released in the last two years.
**Dependencies:** none. No Composer, no npm, no bundler, no build step.
**Repository:** <https://github.com/kirupa/humanish>

> **Maintenance rule:** every change that adds, removes, or alters a
> user-visible capability must update the matching requirement here, add a line
> to [Release history](#16-release-history), and — when the behavior is shared —
> stay consistent with the [macOS PRD](../macOS/README.md).

---

## Table of contents

1. [Product summary](#1-product-summary)
2. [Goals and non-goals](#2-goals-and-non-goals)
3. [Platform and hosting requirements](#3-platform-and-hosting-requirements)
4. [Parity with the native builds](#4-parity-with-the-native-builds)
5. [The workspace](#5-the-workspace)
6. [Welcome screen](#6-welcome-screen)
7. [Document lifecycle](#7-document-lifecycle)
8. [Editing modes](#8-editing-modes)
9. [Markdown language support and formatting](#9-markdown-language-support-and-formatting)
10. [Images and assets](#10-images-and-assets)
11. [File explorer](#11-file-explorer)
11a. [Managing files and folders](#11a-managing-files-and-folders)
11b. [Cloud storage and accounts](#11b-cloud-storage-and-accounts)
11c. [AI assisted critique](#11c-ai-assisted-critique)
12. [Themes, typography, and layout](#12-themes-typography-and-layout)
13. [Keyboard shortcut reference](#13-keyboard-shortcut-reference)
14. [Architecture](#14-architecture)
15. [Run, deploy, and test](#15-run-deploy-and-test)
16. [Release history](#16-release-history)
17. [Out of scope / not yet supported](#17-out-of-scope--not-yet-supported)

---

## 1. Product summary

Humanish for the Web is a clean single-page space to write documents that AI
helps review, backed by files stored on a server. As on macOS, **the Markdown
source is always the canonical document**. The rendered view is an editable
projection of that source: edits made visually are translated back into source
text, and every character the author did not touch survives byte for byte.

| ID | Requirement |
| --- | --- |
| WG-1 | The Markdown source is the document. Rendering never rewrites source the author did not edit. |
| WG-2 | Files are read and written as UTF-8, preserving a byte order mark if the file had one. |
| WG-3 | The app is one HTML page, a handful of ES modules, two stylesheets, and one PHP endpoint. |
| WG-4 | No action fails silently. Every server and client error is presented in a modal alert with a recovery suggestion. |
| WG-5 | The editor never requires a build step, package manager, or rewrite rules. |

---

## 2. Goals and non-goals

### Goals

| ID | Goal |
| --- | --- |
| WG-6 | Reproduce the macOS editor's behavior closely enough that the same PRD describes both. |
| WG-7 | Deploy by copying a folder onto any PHP host. |
| WG-8 | Keep the Markdown logic *provably* identical to the macOS build rather than approximately similar (see [§4](#4-parity-with-the-native-builds)). |
| WG-9 | Work with the keyboard alone, and remain usable with a screen reader. |

### Non-goals

| ID | Non-goal |
| --- | --- |
| WNG-1 | Multi-user editing, accounts, or authentication. One workspace, and whoever can reach it. Accounts are built by way of Firebase and are currently **switched off** ([§11b](#11b-cloud-storage-and-accounts)). |
| WNG-2 | Real-time collaboration or conflict resolution. |
| WNG-3 | A database. State is the filesystem plus `localStorage`. |
| WNG-4 | A JavaScript framework or a CSS framework. |
| WNG-5 | Server-side rendering of Markdown. Rendering happens in the browser, from the same code the tests exercise. |

---

## 3. Platform and hosting requirements

| ID | Requirement |
| --- | --- |
| WP-1 | PHP 8.1 or newer with the standard library. No extensions beyond a default build are used. |
| WP-2 | Runs under Apache, nginx + PHP-FPM, PHP's built-in server, or any host that can execute a `.php` file. |
| WP-3 | Needs no URL rewriting. Every request is either a real file or `api.php?action=…`. |
| WP-4 | Needs no writable directory other than the workspace folder itself. |
| WP-5 | The browser must support ES modules, `contenteditable`, `beforeinput`, and CSS custom properties. |
| WP-6 | Client code is served as-is. Nothing is minified, transpiled, or bundled, so what runs is what is in the repository. |

---

## 4. Parity with the native builds

The [macOS](../macOS/README.md) and [iOS](../iOS/README.md) apps share their
Markdown engine as compiled Swift source, so they cannot drift from each other.
This build shares no runtime code with either — one side is Swift, the other
JavaScript — so its parity is *demonstrated* rather than assumed.

| ID | Requirement |
| --- | --- |
| WX-1 | `render-model.js` is a line-by-line port of `MarkdownRenderModel.swift`, and `formatting.js` of `MarkdownFormatting.swift`, preserving structure and naming so the two can be diffed by eye. |
| WX-2 | Ports rely on the fact that Swift's `NSString` offsets and JavaScript string indices are both UTF-16 code units, so every range in the Swift source is already correct in JavaScript with no conversion. |
| WX-3 | The ports were validated by differential testing against the compiled Swift: 14,148 formatting cases (every command against a corpus of documents and selections) and 41 documents through the render model, comparing rendered text, every style span, and every source ↔ rendered range mapping. Zero mismatches. |
| WX-4 | `themes.css` is **generated** by compiling the app's real `EditorColorTheme.swift` and printing the resulting colors, so derived values — blends, WCAG-contrast text picks — cannot drift. See `tools/generate-theme-css.swift`. That file now lives in `../Shared`; moving it was verified by regenerating this CSS and confirming it came out byte-identical. |
| WX-13 | The generated blends are AppKit's, which are computed in Apple's Generic RGB space rather than sRGB — black halfway to white is `0.573`, not `0.5`. This is a property of the palette, not of macOS, so the CSS is correct for every build. |
| WX-14 | The critique is ported the same way, in both languages. `critique-report.js`, `critique-anchoring.js`, `critique-score.js`, `critique-model.js` and `critique-anchor-tracking.js` are ports of their Swift originals; `CritiqueRequest.php`, `CritiqueProvider.php` and `KonvoSkill.php` are ports of theirs. The prompt is built on the server because the skill pass is 21KB and is a set of instructions a client should not be able to edit before sending. |
| WX-15 | The anchoring port relies on WX-2 as much as the formatting one does: a quote is found by UTF-16 offsets in both builds, so the same critique shades the same characters. What it cannot share is the *fold* -- Swift's `Character.lowercased()` and JavaScript's `String.toLowerCase()` are both full Unicode case folding, which is why the two agree, and that is an assumption worth writing down rather than an accident worth relying on. |
| WX-5 | The JavaScript suites assert the same expectations as the Swift suites, and both builds' tests must pass before a change ships. |

### Deliberate differences

These follow from the platform and are intentional.

| ID | Difference |
| --- | --- |
| WX-6 | Documents live in a server-side **workspace** folder rather than anywhere on disk ([§5](#5-the-workspace)). |
| WX-7 | Open and Save As use in-page prompts over workspace-relative paths, because the web has no `NSOpenPanel`/`NSSavePanel` for server files. |
| WX-8 | Adding an image uses a file input (or drag-and-drop, or paste), and the file is uploaded to the server rather than copied locally. |
| WX-9 | Images in the rendered view load through `api.php?action=asset`, since the browser cannot read a workspace path directly. |
| WX-10 | Recent documents, editor mode, sidebar state, pane widths, and theme live in `localStorage` instead of `UserDefaults`. |
| WX-11 | There is no "become the default handler" flow; that is a Finder concept. |
| WX-12 | `⌘W` closes the document, not the browser tab, which no page may do. |

---

## 5. The workspace

Everything the editor can see lives under one folder. This is the security
boundary and it is enforced on the server, not in the client.

| ID | Requirement |
| --- | --- |
| WW-1 | The workspace root is `~/kirupaMarkdown`, or the path in the `MARKDOWN_EDITOR_WORKSPACE` environment variable. |
| WW-1a | The folder is created on first run if it is not there, and seeded with the starter documents in `Web/seed`. Seeding happens only at creation, so an existing folder is never written into. |
| WW-1b | The default sits in the home directory rather than in the checkout, so updating the editor cannot touch documents and the folder can be moved into a sync service. Where there is no usable home directory, `Web/kirupaMarkdown` is used instead. |
| WW-2 | Every path from the client is workspace-relative. Absolute paths are rejected. |
| WW-3 | Paths are normalized before use: `.` segments are dropped, `..` segments are resolved, and repeated separators collapse. Any path that resolves outside the root is rejected. |
| WW-4 | Resolution is performed against the *real* path of the parent directory, so a symlink pointing outside the workspace cannot be used to escape it — while still allowing paths for files that do not exist yet. |
| WW-5 | Only `.md` and `.markdown` files may be opened, read, or written as documents. |
| WW-6 | If the workspace folder is missing or unreadable, the page itself says so, with the path and how to fix it, instead of failing inside a request the author cannot see. |
| WW-7 | Rejections are explicit errors with recovery text — never a silent empty result. |
| WW-8 | The workspace root may itself be a symlink, so it can point at a folder managed by a sync client. The root resolves to the real folder; escaping it still fails. |
| WW-9 | A workspace at iCloud Drive's root is displayed as *iCloud Drive*, not as the internal `com~apple~CloudDocs` folder name. |

### Putting the workspace in cloud storage

Because documents are plain files, syncing them is a matter of where the
workspace points — there is nothing to export or migrate.

```bash
MARKDOWN_EDITOR_WORKSPACE="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Notes" Web/serve.sh
MARKDOWN_EDITOR_WORKSPACE="$HOME/Dropbox/Notes" Web/serve.sh
```

A symlink works too, which is convenient on a server:

```bash
ln -s "$HOME/Dropbox/Notes" ~/kirupaMarkdown
```

Two things to know before relying on it:

- **A hosted deployment needs no sync at all.** Put the app on one machine and
  every device reaches the same files through a browser. Sync is only worth
  setting up when you also want the macOS app, or offline access to the files.
- **Two devices editing the same document at the same time will produce a
  conflict copy.** Autosave writes 1.5 seconds after typing stops, so the window
  is small but real. The editor does no merging; the sync client's conflict file
  is what you get. See [WNG-2](#2-goals-and-non-goals).

---

## 6. Welcome screen

| ID | Requirement |
| --- | --- |
| WV-1 | On launch the editor shows a welcome overlay with New Document, Open…, and a list of recent documents. |
| WV-2 | Recent documents are workspace-relative paths held in `localStorage`, most recent first, with duplicates collapsed. |
| WV-3 | Each row shows the file name and the containing folder, so two `index.md` files are distinguishable. |
| WV-4 | The list is capped at the same limit the macOS build uses. |
| WV-5 | A recent entry that no longer exists is removed from the list when opening it fails, and the failure is reported. |
| WV-6 | A "Show this window at launch" checkbox persists the preference; when off, the editor opens straight into an untitled document. |
| WV-7 | `File ▸ Open Recent…` reopens the welcome overlay at any time, and it can be dismissed without choosing anything. |
| WV-8 | The overlay is themed like the rest of the app. |
| WV-9 | The identity block is **the app icon and the app's name**, and nothing else. The tagline under the name is gone, for the reason the Mac build dropped its version line: a landing screen says what this is, and the name does that. |
| WV-10 | The icon shown is `icon.svg` — the same file the page links as its favicon, so the tab, the landing screen and a home-screen bookmark cannot show three different marks. It replaces an inline SVG that was drawn by hand in `welcome.js`: a second copy of the artwork that had already gone stale, and which was **rendering 52 × 5** — measured — because an inline `<svg>` in this flex column takes no intrinsic height. |
| WV-11 | `icon.svg` is **generated** by `../macOS/Scripts/make-icons.swift` from `Packaging/Logo.svg`, with the same plate geometry and the same measured placement as the Mac and iOS icons. Checked by rendering it: the plate is 0.828 of the canvas and the mark's round body 0.660 of the plate, centred to the pixel — the same three numbers the `.icns` reports. It is self-contained rather than referencing the logo, because a browser renders an SVG favicon in a restricted mode that fetches nothing external. |

---

## 7. Document lifecycle

| ID | Requirement |
| --- | --- |
| WD-1 | **New** (`⌘N`) starts an untitled document on an empty **Heading 1** line, with the caret already inside it. Pressing Return there drops to a body paragraph, because a heading is not a list and has nothing to continue. Almost every document opens with a title, so the common shape needs no formatting command at all; the heading is ordinary text and deleting the `# ` leaves a blank document. |
| WD-2 | **Open** (`⌘O`) prompts for a workspace-relative path; clicking a file in the explorer opens it directly. |
| WD-3 | **Save** (`⌘S`) writes UTF-8 to the document's path. An untitled document prompts for a path first. |
| WD-4 | **Save As** (`⇧⌘S`) always prompts, and the entered path must end in `.md` or `.markdown`. |
| WD-5 | **Close** (`⌘W`) returns to an untitled document. |
| WD-6 | Any action that would abandon unsaved edits — New, Open, Close, opening from the explorer or the welcome list — first asks *Do you want to save the changes you made to …?* with **Don't Save**, **Cancel**, and **Save**. Cancel, and dismissing with `Escape`, abort the action and leave the document untouched. |
| WD-7 | If the Save triggered from that prompt is itself cancelled or fails, the original action is abandoned too. Unsaved work is never lost to a dialog. |
| WD-8 | Leaving the page with unsaved changes triggers the browser's own confirmation. |
| WD-9 | **Autosave:** edits to a document that already has a path are written 1.5 seconds after typing stops, and immediately when the tab is hidden. Untitled documents are never written without a path. |
| WD-13 | A save records the text it actually sent, captured before the request, not the text on screen when the reply arrives. Anything typed while a save is in flight stays unsaved and schedules another one. Reading the text again afterwards used to cost a skipped autosave; with [live updates](#live-updates) it would cost those keystrokes, because a revision is told apart from this browser's own echo by comparing against the last text saved. |
| WD-10 | The status bar shows the document name, an "Edited" marker while dirty, and the result of the last save. |
| WD-11 | A byte order mark present when the file was read is written back; one that was absent is never added. |
| WD-12 | Undo (`⌘Z`) and Redo (`⇧⌘Z`) operate on the source text. Consecutive typing within 600 ms coalesces into one undo step, so undo moves in meaningful units. |

---

## 8. Editing modes

### 8.1 One view

Following the Mac ([macOS PRD I-142](../macOS/README.md#10a-ai-assisted-critique)),
there is **one view** and no switcher. The rendered document is what you edit.

A rendered view that is genuinely editable makes a second pane showing the same
document a second place to look rather than a second thing to see — and the
whole point of this editor is that the rendered view is not a preview. The raw
Markdown is still on disk, unchanged, and still one keystroke away in any text
editor.

| ID | Requirement |
| --- | --- |
| WE-16 | There is one view. It renders the document and is directly editable. |
| WE-17 | A line break **inside emphasis closes its markers and opens them again** on the next line, so breaking a bold word leaves both halves bold rather than showing `**` in the rendered view. Ported from `MarkdownFormatting.swift` and checked against all 451 committed `insertNewline` contract cases, character for character. |
| WE-2 | *Superseded.* Side by Side — rendered on the left, raw Markdown on the right — is gone, with the pane divider, the scroll link and the selection mirror that served it. |
| WE-3 | *Superseded.* The Markdown pane and its representative typography are gone; `source-renderer.js` is deleted rather than left unreferenced. |
| WE-4 | *Superseded.* There is no mode to persist. |
| WE-8 | *Superseded, with Side by Side.* |
| WE-9 | *Superseded, with Side by Side.* |
| WE-10 | *Superseded.* A command applies to the one surface there is. |
| WE-11 | *Superseded, with the Markdown pane.* |
| WE-15 | *Superseded.* The three icons are gone from the toolbar, and `⌃⌘1`/`⌃⌘2`/`⌃⌘3` with them. |

### 8.2 The rendered view

| ID | Requirement |
| --- | --- |
| WE-1 | Edit the rendered document directly. It is not a preview. |
| WE-5 | In Rich Text, markers (`**`, `#`, `` ` ``) are hidden and the styling they describe is shown instead. |
| WE-6 | Editing the rendered view maps the change back through the source ↔ rendered range mapping and rewrites only the affected source range. |
| WE-18 | **Removing a line break takes the heading or quote marker of the line it joins**, and deleting whole lines takes the first line's, as on the Mac ([I-330 to I-333](../macOS/README.md#62-rich-text-mode)), so a marker the view hid never surfaces as text. `sourceRangeReplacing` in `core/render-model.js` is a port of `sourceRange(replacing:with:)`, and every edit the surface reads — typing, delete in both directions, cut and paste — goes through it, as `toSourceEdit`. `contract-edits.test.js` replays the 273 cases in `Contract/edits.jsonl`, and the DOM suite *Line breaks removed through the surface* makes the reported edit and its neighbours on a real surface, read both ways the surface can read one: from the blocks around the caret and from the whole surface. |
| WE-7 | An image is one atomic, non-editable unit: the caret cannot enter it, and deleting it removes the whole `![…](…)`. |
| WE-8 | In Side by Side, scrolling either pane scrolls the other to the same normalized position, without feedback loops. |
| WE-9 | In Side by Side, moving the caret or selection in one pane mirrors it into the other through the same range mapping. |
| WE-10 | Formatting commands apply to whichever pane last had focus, so clicking a toolbar button never redirects the edit. |
| WE-11 | The Markdown pane shows every marker verbatim while giving headings, body text, and code their representative sizes and weights — size and weight only, matching `MarkdownSourceStyler`. |
| WE-12 | Copy and cut place Markdown source on the clipboard; paste inserts text as Markdown. |
| WE-13 | Input Method Editor composition is left alone until it commits, so non-Latin input works normally. |
| WE-15 | The three modes are chosen with icons rather than words — a page, two panes, and the Markdown mark. They sit left of the formatting controls in a bar those controls already fill, and at that size three words crowd out the tools people reach for far more often. Each keeps its full name as its accessible name and shows it, with the shortcut, on hover, so nothing is only available to someone who recognises the picture. |
| WE-14 | The rendered view always contains exactly the text the model says it should. This is asserted by tests that compare the DOM's plain text against the model, and round-trip every character offset through the DOM. |

---

## 9. Markdown language support and formatting

The supported language is exactly the macOS build's — see
[macOS PRD §7](../macOS/README.md#7-markdown-language-support). Summarized:

ATX headings 1–6, paragraphs, hard line breaks, `**bold**`, `*italic*`,
`~~strikethrough~~`, `<u>underline</u>`, `` `inline code` ``, fenced code blocks,
block quotes, bulleted, numbered, and task lists, links, images, horizontal
rules, and backslash escapes.

Every formatting command is available from the toolbar, the menu bar, and a
keyboard shortcut, and every one of them toggles:

| ID | Requirement |
| --- | --- |
| WF-1 | Inline styles (bold, italic, underline, strikethrough, inline code) wrap the selection, or insert an empty pair with the caret between the markers. |
| WF-2 | Applying an inline style to text that already has it removes the markers. |
| WF-3 | Headings replace whichever heading level a line already has; applying the same level again returns the line to body text. |
| WF-4 | List commands convert every line the selection touches, and re-number numbered lists from 1. |
| WF-5 | Applying the same list type again removes the markers. |
| WF-6 | Block quote prefixes each selected line with `> `, and toggles off. |
| WF-7 | Code block wraps the selection in fences on their own lines, and toggles off. |
| WF-8 | Horizontal rule inserts `---` on its own line. |
| WF-9 | Link prompts for a URL and wraps the selection, or inserts `[](url)` with the caret positioned to type the text. |
| WF-10 | Every command preserves the selection sensibly — text stays selected, and an inserted empty pair leaves the caret between the markers. |
| WF-11 | The toolbar highlights the inline styles, heading level, and list type active at the caret, and updates as the caret moves. |
| WF-12 | Commands operate on the source through the same pure functions the macOS build uses, so a command applied in either build produces byte-identical text. |
| WF-13 | **Inside code, the inline styles and the link command do nothing.** Markdown is inert in a fenced block and between a code span's backticks, so the only thing bold could write there is two asterisks into the writer's code. The commands return the document and the selection untouched. A block quote is *not* code: bold in a quote is ordinary Markdown, is written, and has its markers hidden exactly as in a paragraph. See [`Contract/README.md`](../Contract/README.md#inside-code-the-inline-commands-do-nothing). |
| WF-14 | A command withdrawn by WF-13 is **greyed in the toolbar and in the mobile format bar**, not hidden, and its `disabled` state is what the stylesheet dims — one source of truth, as with `aria-pressed`. Availability comes from the shared `isInlineStyleAvailable` / `isLinkAvailable` in `core/formatting.js`, from a context read off the live render model's spans at the selection's **two ends** (`spansAtSourceOffset`) — not `model.spans`, which builds every span in the document — so no caret move parses or walks the document. The toolbar's commands are handed the same live model, so ⌘B does not parse it either. |
| WF-15 | `code-context.js` is a port of `MarkdownCodeContext.swift` and is checked against it: `contract-inline.test.js` replays every `toggleInline` and `insertLink` case in `Contract/formatting.jsonl` — text *and* selection — so the browser and the Mac refuse in exactly the same places and nowhere else. This is the kind of rule a port gets silently wrong: nothing looks broken, because the only difference is a command that does nothing. |

---

## 10. Images and assets

| ID | Requirement |
| --- | --- |
| WI-1 | Imported images are copied into `<document-stem>.assets/` beside the document — `post.md` uses `post.assets/`. |
| WI-2 | The inserted reference is relative: `![alt](post.assets/photo.png)`. |
| WI-3 | Images can be added from the toolbar, `Insert ▸ Add Image…` (`⇧⌘I`), drag-and-drop onto either pane, or paste. All four paths run the same import. |
| WI-4 | Multiple files dropped or chosen at once are imported in order. |
| WI-5 | Supported formats: BMP, GIF, HEIC, HEIF, JPEG, JPG, PNG, SVG, TIF, TIFF, WEBP. Anything else is refused by name and by content. |
| WI-6 | Alt text defaults to the file's base name. |
| WI-7 | A name already taken in the assets folder gets `-2`, `-3`, … before the extension. An existing file is never overwritten. |
| WI-8 | Spaces and other characters that are unsafe in a URL are percent-encoded in the reference, while the file on disk keeps its original name. |
| WI-9 | The reference is inserted at the caret, or replaces the selection, in whichever pane has focus. A dropped image lands where it was dropped, including in the empty space beside a line. |
| WI-10 | An image cannot be imported into an untitled document; the editor says so and offers to save first. |
| WI-11 | If `<document-stem>.assets` exists but is a file or a symlink, the import is refused rather than following it. |
| WI-12 | Uploads are validated on the server: extension allowlist, real image content, and containment inside the workspace. A client that lies is rejected. |
| WI-13 | Rendered images load through `api.php?action=asset`, which serves only image extensions from inside the workspace, with `X-Content-Type-Options: nosniff`. |
| WI-14 | An image that cannot be loaded shows a labeled placeholder rather than a broken-image icon — and that placeholder contributes no characters to the document text. |
| WI-15 | `Add Image` first asks where the image comes from: **Choose File…** copies a file in beside the document (WI-3 … WI-13), **Image Address…** references one that is already on the web. Drag-and-drop and paste still go straight to the file route, since they already carry a file. |
| WI-16 | An image referenced by address is not copied or uploaded; the document points at the original URL. The address is percent-encoded so a space in it cannot break the reference, and a second prompt collects the alt text. |
| WI-17 | Clicking a rendered image selects it and opens a size panel under it, with width and height fields and a Reset button. Clicking elsewhere, or typing, clears the selection. |
| WI-18 | Editing either dimension derives the other from the image's own pixel size, so the aspect ratio is preserved. The number typed is kept exactly; the derived one is rounded, and never to zero — a very wide, very short image must not vanish. |
| WI-19 | A size is written as HTML: `<img src alt width height>`. Markdown has no syntax for dimensions, so this is the one place a reference changes form. Adding a size converts `![alt](path)` to a tag; Reset converts it back. The convention and the evidence behind it are in [`Contract/README.md`](../Contract/README.md). |
| WI-20 | Converting back to Markdown percent-encodes the path. An HTML attribute holds `my file.png` happily, but the same text in Markdown is not an image at all — GitHub renders it as literal text and the picture is lost. |
| WI-21 | An explicit size overrides the default display cap, bounded only by the width of the pane. A stale selection can never corrupt the document: if the recorded range is not exactly one image reference, the text is left untouched. |
| WI-22 | A selected image also carries four corner drag handles. Dragging one resizes the image live and always proportionally, whichever corner is used; the document is rewritten once on release, so a resize is a single undo step rather than one per pointer move. A focused handle also resizes with the arrow keys. The handles are siblings positioned over the image, never children of it, because everything inside a rendered image must contribute exactly zero characters to the document text (WI-14). |
| WI-23 | A picture can be **dragged to somewhere else in the document**. A press on its body stays a click until it has travelled 5pt, so selecting with an unsteady hand cannot rewrite the document. Past that, a rule across the column marks the paragraph boundary it would land on and the picture follows the pointer at reduced opacity. Releasing commits one edit through `moveImage`. |
| WI-24 | The drop lands on a **paragraph edge**, never between two characters. `chooseDropEdge` picks the nearer horizontal edge of the rendered line under the pointer, and `moveImage` snaps again on the text — so neither half can splice a picture into a word alone. |
| WI-25 | `moveImage` is checked against the compiled Swift, not only against hand-written examples: `contract-move-image.test.js` replays all 451 `moveImage` cases in `Contract/formatting.jsonl` and requires the same text and the same selection. Two rules here have no visible symptom when subtly wrong — the destination shifts by the removed block, and blank lines are collapsed — so a port can look right on a few examples and still disagree on a real document. |
| WI-26 | **The page is wider than the column the text is set in.** In Rich Text the surface is the page and its padding holds the column inside it, so the measure is exactly what it was; the margin either side is room a picture — and only a picture — may spread into, up to `--me-image-bleed-max` (100px) on each side. Matches `EditorPaneGeometry.maximumImageBleed` on the Mac. |
| WI-27 | A line holding **nothing but a picture** reaches into those margins as the picture outgrows the column, by the same arithmetic the native builds use, so the picture stays centred on the column. A picture inside a sentence does not: pulling that line out would drag the words with it. The renderer marks the line and passes the picture's width; the stylesheet does the arithmetic. |
| WI-28 | The bleed is **whatever room is left over**, up to the maximum — `clamp(0px, (100vw - var(--me-preview-width)) / 2, …)`, the same rule as `EditorPaneGeometry.imageBleed`. A phone gets none, and Split gets none either, because there the pane is exactly the column wide and an overhang would hang over the divider. |
| WI-29 | A resize **stops at the page**: the surface's width less the plain page padding. Deliberately measured rather than read from `--me-image-bleed`, because a custom property comes back from `getComputedStyle` as the tokens it was written with — that property reads back as the literal text `clamp( 0px, (100vw - 700px) / 2, 100px )` and parses as `NaN`. Shipping that would have collapsed the ceiling to the column, and a picture could never have been dragged into the margins at all. |

---

## 11. File explorer

| ID | Requirement |
| --- | --- |
| WL-1 | A sidebar lists the workspace tree, expandable folders first, then everything else, each alphabetical and case-insensitive. |
| WL-2 | Folders expand lazily; a folder's children are fetched the first time it opens. |
| WL-3 | Hidden entries — names beginning with `.` — are not listed. |
| WL-3a | A symlink is listed, but it cannot be expanded, so the tree can never wander outside the workspace by following one. Packages such as `Foo.app` are listed and not expandable for the same reason: they are directories the user means as files. |
| WL-4 | Markdown files open on click. Non-Markdown files report that they cannot be opened. |
| WL-5 | The current document's row is selected, and the tree expands to reveal it. |
| WL-6 | A Reveal button re-expands to the current document; a Refresh button re-reads the tree from disk. |
| WL-7 | The header is a dropdown listing the current folder and each ancestor up to the workspace root; choosing one re-roots the tree. |
| WL-8 | The sidebar can be hidden (`⌃⌘S`), and its width dragged; both persist. |
| WL-9 | Selection colors are derived from the active theme so the selected row is legible in all sixteen theme combinations. |

---

## 11a. Managing files and folders

The macOS build leaves this to Finder, which is one Cmd-Tab away. A browser has
no such neighbour, so the sidebar has to be a file manager too — otherwise the
workspace is a folder nobody can reorganize without leaving the app.

| ID | Requirement |
| --- | --- |
| WM-1 | The sidebar header has **New Document** and **New Folder** buttons; both are also in the File menu (`⌃⌘N` and `⇧⌘N`). |
| WM-2 | Right-clicking a row opens a context menu: Open, New Document…, New Folder…, Rename…, Duplicate, Delete…. Right-clicking empty space offers the two New items for the folder on screen. |
| WM-3 | New items are created in the selected folder, in the folder holding the selected file, or at the sidebar root — and the prompt names which. |
| WM-4 | A new document with no extension gets `.md`. It is created empty and opened immediately. |
| WM-5 | Names are validated on the server and refused with a reason: no slashes, no leading period, no control characters, not `.` or `..`, not empty, 255 bytes at most, valid UTF-8. |
| WM-6 | Creating, renaming, moving, or duplicating onto a name that already exists is refused. Nothing is ever overwritten. |
| WM-7 | Renaming a Markdown document to a name with no extension keeps the original one. Renaming it to a *different* extension is refused, because the editor could no longer open it. |
| WM-8 | A document's `<stem>.assets` folder follows it through a rename or a move, and the image references inside the document are rewritten to match — in both the percent-encoded and plain spellings. A duplicate gets its own copy of the folder. If the destination assets name is taken, the whole operation is refused and nothing moves. |
| WM-9 | The open document survives all of this. Renamed or moved, it follows the file. Deleted, its text stays on screen and becomes unsaved, and Save offers the path it used to have — deleting a file in the sidebar can never take away work still in front of you. |
| WM-10 | A row can be dragged onto a folder, or onto empty space to reach the root. The destination highlights, and a folder cannot be dropped into itself or its own descendants. |
| WM-11 | Delete asks first, says whether a folder takes its contents with it, and says it cannot be undone — there is no Trash on a server. A document's `.assets` folder is deliberately *not* deleted with it; it holds original images, and it is visible in the sidebar to remove separately. |
| WM-12 | Every operation acts on the item itself, never on what a symbolic link points at. Deleting a link removes the link; the folder behind it is untouched. |
| WM-13 | Duplicates are named `name-2`, then `name-3`, matching how imported images avoid collisions ([WI-7](#10-images-and-assets)). Folders are copied recursively. |
| WM-14 | After any change the sidebar reopens the containing folder, selects the new item, and scrolls it into view. |

---

## 11b. Cloud storage and accounts

> **Switched off.** The whole of this section is behind `CLOUD_ENABLED` in
> `storage.js`, and it is `false`. Nothing below is reachable in the shipped
> build. The requirements stay because the code stays: this is a feature that
> is not finished, not a feature that was wrong.

### Why it is hidden

The cloud path is written and tested against an emulated Firestore, and it is
not finished — the two console steps it needs are still outstanding
([§Setup steps](#setup-steps-that-cannot-be-done-from-this-repository)). A
half-present integration is worse than an absent one. It offers a door that
does not open, and every visitor pays for a Firebase SDK download from a CDN to
be told so.

| ID | Requirement |
| --- | --- |
| WR-39 | `CLOUD_ENABLED` is **one flag**, in the module that already owns which storage is in use. Everything downstream asks `cloudIsAvailable()` rather than testing for the cloud itself, so turning it on turns all of it on at once: the welcome screen's option, the File menu's two items, the status bar's indicator, and the session restore. |
| WR-40 | The flag is checked **before anything is loaded**, so a disabled cloud costs no Firebase SDK download and makes no request to a third party. Verified on screen: zero requests matching firebase, googleapis, gstatic or google. |
| WR-41 | With one place documents can go there is no choice to present, so the welcome screen shows one option rather than a list of one. **The reachability warning survives** — "anyone who can open this page can read and change these documents" is the more important half of that screen and is about the option that is left. |
| WR-42 | The File menu loses both storage items rather than showing them disabled. A menu item naming the only option available tells the reader nothing. |
| WR-43 | The status bar's storage indicator is hidden, and is written `hidden` in the markup rather than switched off by script ([WY-23](#tests)). It exists to answer "where is this going", and a badge that has said the same thing on every document anybody has opened stops being read long before it becomes wrong. |
| WR-44 | `storageChoices` takes `cloudAvailable` as a **parameter defaulting to the flag**, so the shape it returns with the cloud switched on stays under test while it is switched off. A hidden feature whose tests were deleted is a feature that comes back broken. |
| WR-45 | `useCloud()` throws if it is somehow reached with the flag off, rather than opening a sign-in window for a feature that is not on offer. |

### The requirements, for when it returns

| ID | Requirement |
| --- | --- |
| WR-1 | The welcome screen offers both storage options at once, with the active one marked **In use**. Where a document is saved is the one thing here that is hard to undo if it is not what you expected, so it is never a click away from being visible. |
| WR-2 | **On this server** is the fallback for being signed out, not the default: files in the workspace folder, exactly as before this section existed. Everything in [§5](#5-the-workspace) and [§11a](#11a-managing-files-and-folders) describes it. It has no accounts, so it says plainly that anyone who can open the page can read and change what is in it — on a laptop that means only you, and at a public address it means anybody. |
| WR-3 | **Your Google account** is the recommended option: sign in with Firebase Authentication and every document is stored in Firestore under that account, reachable from any device that signs in. |
| WR-4 | Switching storage closes the open document rather than carrying it across. A document from one place shown while saves go to the other is worse than closing it. |
| WR-5 | The status bar always says which storage is in use — `This device`, or `Cloud · your@email`. |
| WR-6 | Storage can also be switched from **File ▸ Connect Google Account…** and **File ▸ Use Files On This Device**. |
| WR-7 | Switching storage goes through the same unsaved-changes prompt as any other command that closes a document ([WD-6](#7-document-lifecycle)). |
| WR-8a | A visitor who has never chosen is asked Firebase first, before the server's workspace is used at all. Someone already signed in has documents of their own, and starting them in a workspace every other visitor can edit is the wrong guess to make silently. `restoreAccount()` never opens a pop-up, so this cannot delay or block the launch, and any failure falls through to the server rather than failing to start. |
| WR-8b | Until a choice has been made, the welcome screen is shown even when **Show this window at launch** is off. Turning that off means "don't show me this again", which is not the same as "decide for me". Once either option has been chosen the preference is honoured normally. |
| WR-8 | The remembered choice is restored at launch. Cloud is only restored if Firebase says the session is still valid; it never opens a sign-in window during boot, because an unrequested pop-up is blocked anyway. An expired session falls back to local storage and says so, rather than starting on an error. |
| WR-9 | Recent documents and the Saved for Later list are kept separately per storage mode. The same path names different documents in each, so one shared list would offer to open files that are not there. Local keeps the original keys, so an existing install loses nothing. |
| WR-10 | The Firebase SDK is only downloaded when an account is actually used. A local-only session fetches nothing from a CDN. |
| WR-11 | Every cloud failure is reported with a recovery step, never swallowed ([G-6](../macOS/README.md#2-goals-and-non-goals)). A closed sign-in window, a blocked pop-up, an unauthorised domain, a missing provider, unpublished rules, and a disabled Storage bucket each say what specifically to do. |

### How documents are stored

Firestore has no folders, so a tree is a reading of a `path` field on a flat
collection of nodes:

    users/{uid}/nodes/{documentId}      documentId = encodeURIComponent(path)

| Field | Meaning |
| --- | --- |
| `type` | `file`, `folder`, or `asset` |
| `path` | Workspace-relative path — the identity of the node |
| `parent` | The containing folder's path, `''` at the root |
| `name` | The last path component |
| `text`, `hasByteOrderMark`, `size` | Documents only |
| `storagePath`, `url`, `contentType` | Images only; the bytes live in Cloud Storage |

| ID | Requirement |
| --- | --- |
| WR-12 | Listing a folder is an equality query on `parent`, sorted in the client. Adding `orderBy` would make it a composite query that Firestore refuses to serve until an index is built by hand, so the app would not work the moment it was deployed. |
| WR-13 | Subtree operations use a range query on `path`, then **filter the result**. `path >= 'Notes'` also matches `Notes 2/Out.md` and `Notes.md`, because a range over strings knows nothing about separators — without the filter, renaming a folder would silently drag its similarly named siblings along. |
| WR-14 | Writes are committed in batches of 500, Firestore's limit. A batch is atomic; several are not, so every create is ordered before the delete it replaces. An interruption mid-move leaves documents duplicated rather than lost. |
| WR-15 | Naming rules match the local build exactly, verified against PHP's own output: duplicates become `stem-2.ext`, `PATHINFO` splits on the last dot wherever it is, and entries sort folders-first then `strnatcasecmp` order. |
| WR-16 | A document's `<stem>.assets` folder follows it through a rename, move, or duplicate, and the image references inside the document are rewritten — the same behaviour as [WM-8](#11a-managing-files-and-folders). A duplicated document gets its own copy of the image bytes, so deleting one cannot blank the other. |
| WR-17 | Deleting a document leaves its assets folder behind, as the local build does: it holds originals that may exist nowhere else. |
| WR-18 | Images go to Cloud Storage under `users/{uid}/`, capped at 10 MB. Firestore's 1 MiB document limit makes storing them inline too restrictive. Opening a document loads its image URLs first, so the renderer — which resolves image sources synchronously — has them ready. |
| WR-29 | **An image is uploaded with a real `image/*` content type, derived from its extension rather than taken on trust.** A `File` can arrive with an empty `type` — a drag from some applications, a paste, or a handle built by a script — and an upload with no type is stored as `application/octet-stream`, which the Storage rule refuses. The extension has already been checked against the accepted list by that point, so deriving the type from it is safe, and a declared type is only kept when it is itself an `image/*`. Without this, adding an image against published rules fails with a bare permission error and looks to the user like nothing happened. The same rule is applied identically by the native builds. |
| WR-30 | **The image URL cache follows a rename.** Image sources have to resolve synchronously ([WR-18](#11b-cloud-storage-and-accounts)), so URLs are cached by path when a document is read. Renaming a document or a folder moves the model in place without re-reading it, so every cached URL must be re-keyed at the same moment — including the sibling `<stem>.assets` folder, which is *not* a descendant of the document and so is missed by any subtree walk. Otherwise every image in a renamed document breaks until the page is reloaded. |
| WR-31 | **The client refuses an image that reaches the 10 MB limit, not one that exceeds it.** `storage.rules` allows `request.resource.size < 10 * 1024 * 1024`, so a file of exactly 10,485,760 bytes is refused by the server. Checking `>` accepted it here and then failed on upload with a bare permission error — the single outcome the client-side check exists to prevent. The native builds always drew the line correctly; this was the web build disagreeing with both them and the rule, and it only became reachable when the rules were published. |

### Live updates

A document open in a cloud account follows the account, not this browser. Both
phones and both laptops show the same thing without anyone reloading.

| ID | Requirement |
| --- | --- |
| WC-1 | Changes made elsewhere arrive on their own, through Firestore listeners rather than polling. A document saved on a phone appears on the laptop that has it open, and a file created on one device appears in the other's sidebar. |
| WC-2 | **Unsaved edits are never overwritten.** If a revision arrives while there are unsaved changes on screen, it is not applied. The document stays dirty, so the next save writes this browser's version: last write wins, and the person actually typing is the one who wins it. Everything else here is a convenience; this is the requirement the feature has to earn. What happens to the refused revision is [WC-10](#live-updates). |
| WC-3 | An adopted revision is one undo step, not a new history. `⌘Z` puts your text back, marks the document unsaved, and autosave sends it out again — so *no, mine* is a keystroke. An arriving change would otherwise be the only edit in the editor that could not be taken back. |
| WC-4 | A document deleted or moved on another device detaches: the text stays on screen and becomes permanently unsaved, so the next Save asks where to put it. This is the same path a local delete already used ([WF-9](#11a-managing-files-and-folders)). |
| WC-5 | This browser's own saves are silent. A write is recognised by comparing against the last text saved ([WD-13](#7-document-lifecycle)) rather than against the text on screen, which is what makes autosave-while-typing quiet: at that moment the two legitimately differ, and comparing against the screen would report every autosave as a change from another device. |
| WC-6 | Only what is on screen is watched: the open document, its images, and the folders the sidebar has expanded. The listener is the same equality query [WR-12](#11b-cloud-storage-and-accounts) already issues, so watching a folder costs what listing it once cost, needs no composite index, and grows with what is visible rather than with the size of the account. Collapsing a folder or closing a document detaches its listener. |
| WC-7 | **Local storage has no push channel, deliberately.** PHP on shared hosting offers no push, and polling the server on a timer would spend requests on a workspace only this browser can reach. The local backend answers the same three watch calls with a no-op, so nothing above it needs to know which storage is in use. Changes to a local document are caught by [WC-9](#live-updates) instead. |
| WC-8 | Watching is restarted when storage is switched, and stopped on the way out, so signing out cannot leave a listener running against the previous account. |
| WC-9 | **The open document is re-read whenever this tab comes back to the front** — a tab switch, a window focus, unlocking a phone. This is what notices a change for local storage, which pushes nothing (WC-7), and it also covers cloud mode, where the browser may have suspended a background tab and its listeners with it. One request per return, not one every few seconds forever, which is what WC-7 rejected. The answer goes through the same decision as a pushed revision, so there is one set of rules about whose text wins rather than two. A backend that cannot answer — offline, signed out — is silent: the next save reports the real problem, in context. |
| WC-10 | **A refused revision is kept and offered, not dropped.** A bar above the document says *Changed by something else. Your unsaved edits are kept.* and offers **Show Newest**, which displays the version that arrived, or **Keep Mine**, which puts the question away. This browser holds the only copy of what the other device wrote, so announcing it in a status flash and discarding it made the notice useless — there was no way to act on it. The bar clears when the document is closed or opened elsewhere, because a held revision belongs to the document it came from. |
| WC-11 | Show Newest discards the unsaved edits on this screen, and its tooltip says so. Keep Mine is the non-destructive choice and needs no confirmation: autosave already writes this browser's version, so keeping it means doing nothing. |

### Working offline

Cloud mode keeps a copy of what it has seen on the device, so losing the
network is not the same as losing the documents.

| ID | Requirement |
| --- | --- |
| WR-23 | Firestore is opened with a **persistent local cache** in IndexedDB, not the in-memory default. `getFirestore()` caches only for the life of the tab, so a reload with no signal would show an empty workspace — in cloud mode the server holds the only copy. Opened this way, a reload offline opens the same documents. |
| WR-24 | **The cache holds what this device has opened, not the whole account.** Firestore caches documents this client has read or written. A document written on another device and never opened here is not available offline. Calling the local copy a full backup would be wrong, and it is worth being plain about which half is true. |
| WR-25 | Edits made offline are queued locally and sent when the network returns. Firestore's writes resolve against the local cache immediately, so the editor behaves the same whether or not there is a connection, and [WC-2](#11b-cloud-storage-and-accounts) still decides who wins when a queued write meets a newer one. |
| WR-26 | **Images have a cache of their own,** because Firestore's persistence covers Firestore documents and nothing else — Cloud Storage objects are ordinary HTTPS downloads with no offline layer. Without one, an offline document opened with its text intact and every picture broken, which reads as damage rather than as unavailability. Image bytes are kept in IndexedDB and served as `blob:` URLs, so a document that has been opened once renders completely with no network. |
| WR-33 | **Entries are keyed by download URL, not by the path of the image.** Two things follow, and both are the reason for the choice. Renaming a document moves its images and the backend already carries each URL across, so a rename needs no cache bookkeeping at all. And a download URL carries a token that changes when the bytes behind it are replaced, so a replaced image *misses* rather than serving the picture it replaced: the cache cannot go stale, only empty. |
| WR-34 | **A miss is never a missing image.** If the bytes are not on the device, `imageURL` returns the download URL exactly as before, so the picture loads whenever the network is there. The cache can only improve on the previous behaviour, never fall short of it. |
| WR-35 | Bytes already on the device are adopted *before* a document is returned, so it renders complete rather than filling in afterwards. Bytes that are **not** there are downloaded in the background and not waited for: a miss only matters offline, and offline the download would fail anyway — blocking every document open on fetching its images would spend something real to buy something hypothetical. |
| WR-36 | An uploaded image is offline-ready immediately, cached from the bytes in hand rather than downloaded back from the server it was just sent to. |
| WR-37 | Deleting an image drops its bytes and releases its `blob:` URL. A browser that cannot store the bytes at all — private browsing, no quota, no IndexedDB — still renders normally for the session; only the offline guarantee is lost. |
| WR-38 | Cached images make the network cheaper as well as optional: an image is fetched once per device rather than once per document open. |
| WR-27 | Persistence is genuinely unavailable in some browsers — private browsing in parts of Safari and Firefox, and anywhere IndexedDB is switched off. That falls back to the in-memory cache with a console warning: offline support stops working, the editor still opens. Refusing to start would be the wrong trade. |
| WR-28 | The multi-tab manager is used, so two tabs of the editor share one cache. Without it only the first tab gets persistence and the others silently run without. |

### Where the image bytes live

Worth stating plainly, because it is the one piece of user data that is *not*
in Firestore.

| | Documents | Images |
| --- | --- | --- |
| Stored in | Firestore, `users/{uid}/nodes/{id}` | Cloud Storage, `users/{uid}/<path>#<timestamp>` |
| Firestore holds | the Markdown text itself | an `asset` node: `storagePath`, `url`, `contentType` |
| Size limit | 1 MiB per Firestore document, refused above ~900 KB | 10 MB per image, enforced in the client *and* in `storage.rules` |
| Offline | yes, once opened ([WR-23](#11b-cloud-storage-and-accounts)) | yes, once opened ([WR-26](#11b-cloud-storage-and-accounts)) |
| Governed by | `Web/firebase/firestore.rules` | `Web/firebase/storage.rules` |

Storing images inline in Firestore was considered and rejected: base64 inflates
bytes by about a third, against a hard 1 MiB document limit, which would cap an
image at roughly 700 KB *and* spend the same budget the document text needs. It
would buy offline images for free, which is the one real argument for it, but at
a size limit low enough to reject ordinary screenshots. That argument is now
spent anyway: [WR-26](#working-offline) buys offline images without the limit.

The Cache Storage API looks like the closer fit than IndexedDB for caching
downloads, and was rejected for a specific reason: the browser does not consult
it for an `<img src>` unless a service worker sits in front of every request.
A service worker brings its own scope, update lifecycle, and deployment story —
a large commitment for something needed in exactly one place. IndexedDB hands
back the bytes and the caller decides what to do with them.

The Markdown text never contains a Storage URL. It keeps the same relative
`<stem>.assets/name.png` reference the local and native builds write, and the
URL is resolved at render time from the `asset` node. That is what lets the same
document open in any of the four builds, and what lets a download URL be
rotated without rewriting anyone's prose.



`Web/public/app/cloud/config.js` contains the real Firebase configuration,
committed to a public repository on purpose. A Firebase web API key is an
identifier, not a credential: it names the project so the SDK knows where to
send requests, and every client that loads the app must have it. It grants
nothing on its own. [Google documents this
directly](https://firebase.google.com/docs/projects/api-keys).

What actually controls access is the Security Rules, which ship beside it:

- `Web/firebase/firestore.rules`
- `Web/firebase/storage.rules`

Both scope every document to the account that owns it, structurally — ownership
is the path, so it cannot be got wrong per-document. There is no rule that lets
one account reach another's documents.

### Setup steps that cannot be done from this repository

These are Firebase console actions. Until they are done, the cloud option will
fail, and it will say which of these is missing. They are kept here, done, so the
checks stay repeatable — a rule can be edited in the console at any time.

**Everything the web build needs is done, re-checked against the live project on
6 August 2026:** the rules are published, the Storage bucket exists, Google sign-in
is enabled, and `www.kirupa.com` is an authorised domain. One step remains, and it
affects the native builds only — registering an Apple app. The commands are below so
every check can be repeated rather than taken on trust.

| ID | Step |
| --- | --- |
| WR-32 | **Register an Apple app** under Project settings ▸ Your apps, with bundle ID `com.kirupa.markdown-editor`, and paste its app ID into `Shared/Firebase/Sources/MarkdownEditorFirebase/FirebaseConfiguration.swift`. **Outstanding, and no longer the only thing standing in the way of native sign-in — see [WR-32a](#setup-steps-that-cannot-be-done-from-this-repository).** A Firebase app ID belongs to a registered app; the value there now is this project's *web* app ID with `web` changed to `ios`, which is well-formed and is not a real app. It is checked before sign-in opens a browser, so the native apps report the missing console step rather than a generic OAuth failure. One registration covers both the macOS and iOS apps, which share a bundle ID. Nothing in the web build is affected. |
| WR-32a | **A real code-signing identity is required before FirebaseAuth can sign in on macOS at all**, and no change to this repository can substitute for it. FirebaseAuth persists its session to the macOS data-protection keychain, which requires the `keychain-access-groups` entitlement; that entitlement is *restricted*, so it must be authorized by a provisioning profile. Measured, not inferred, by `Shared/Firebase/Scripts/check-keychain.sh`: the same `signInAnonymously()` fails with `SecItemAdd (-34018)` as a bare executable **and** from inside an ad-hoc-signed `.app` — the exact form `macOS/Scripts/build-app.sh` produces — and a bundle that claims the entitlement without a profile is SIGKILLed at exec (exit 137). All three, every run. A fourth probe narrows *what* is refusing: the same ad-hoc-signed bundle writes to the **file-based** keychain and reads it back without complaint, and is refused only by the **data-protection** keychain — so the signature was never the problem, and what is missing is specifically a keychain access group. Adding `com.apple.security.app-sandbox`, the one relevant entitlement ad-hoc signing *can* grant, does not help, which rules out the only fix that would have needed no Apple account. Nor can FirebaseAuth be pointed at the keychain that works: it sets `kSecUseDataProtectionKeychain` unconditionally at both of the two places it builds a query, with no option or environment variable. Nor is there a degraded mode — since the throw happens while *persisting* the session, a session usable for the current launch would have meant "sign in every launch" rather than no cloud at all, but the probe finds no `currentUser` after the failure: FirebaseAuth unwinds the whole sign-in. **How much of an Apple account this takes is untested**: Xcode's automatic signing issues a development certificate from a *Personal Team* for a free Apple ID, which may suffice, and a paid membership certainly would; this machine has no signing identity at all, so the signed case could not be tried. Do this before [WR-32](#setup-steps-that-cannot-be-done-from-this-repository) — registering the app is wasted effort until sign-in can reach the keychain. Affects the **native macOS** build only: the web build does not use the Apple SDK, and the Firestore adapter underneath is unaffected and verified ([macOS README §16.6](../macOS/README.md#166-the-native-firestore-adapter-is-verified-against-a-real-firestore)). |
| WR-19 | **Publish the security rules.** `firebase deploy --only firestore:rules,storage`, or paste both files into the console. **Done — verified 6 August 2026.** An unauthenticated REST call carrying only the public API key now returns `403 PERMISSION_DENIED` where it previously returned `200` and an empty result: `curl "https://firestore.googleapis.com/v1/projects/kirupa-markdown/databases/(default)/documents/users/probe/nodes?key=<apiKey>"`. An unauthenticated write returns `403` as well, and both an object read and a bucket list on Cloud Storage return `403`. The database is no longer open. |
| WR-20 | **Enable the Google sign-in provider** under Authentication ▸ Sign-in method. **Done — confirmed 6 August 2026.** `curl -X POST "https://identitytoolkit.googleapis.com/v1/accounts:createAuthUri?key=<apiKey>" -H 'Content-Type: application/json' -d '{"providerId":"google.com","continueUri":"https://www.kirupa.com/humanish/"}'` returns a real `authUri` carrying the project's OAuth client ID. A disabled provider answers `OPERATION_NOT_ALLOWED` instead — which is still what anonymous and email/password return, so neither of those is available as a fallback. |
| WR-21 | **Add the authorised domains** under Authentication ▸ Settings: `www.kirupa.com` for the published build, and `127.0.0.1` for local preview if you reach it by IP. `localhost` is allowed by default, but `127.0.0.1` is a different host string to Firebase — reaching the preview at `http://localhost:8000` avoids needing this. **`www.kirupa.com` is done — confirmed 6 August 2026** by the same call as [WR-20](#setup-steps-that-cannot-be-done-from-this-repository): it accepted that origin as a `continueUri`, which an unauthorised domain is refused for. |
| WR-22 | **Enable Cloud Storage** for the project, or image upload will fail. **Done — the bucket exists as of 6 August 2026.** `curl "https://firebasestorage.googleapis.com/v0/b/kirupa-markdown.firebasestorage.app/o"` now answers `403` rather than `404`; a bucket that does not exist answers `404`, which is still what the `.appspot.com` spelling returns, confirming `.firebasestorage.app` is the right name and that it is the one both builds are configured with. `403` is the expected answer to an unauthenticated list and is what publishing [WR-19](#11b-cloud-storage-and-accounts) will make permanent. No bucket CORS configuration is needed: the upload endpoint already answers a cross-origin preflight with `access-control-allow-origin: *`. |

### What has not been verified

Honest limits on the testing behind this section:

- The Google sign-in round trip cannot run in headless Chrome, and no test
  writes to the real database. Sign-in against the real project, and reading
  and writing real documents in a real Google account, remain **unverified**.
  What is no longer unverified is everything underneath that: the store, the
  queries, batch atomicity, and live delivery all now run against a real
  Firestore in the emulators ([WY-19](#tests), [WY-20](#tests)), including a
  genuine two-client test of `onSnapshot`. What is left is the identity
  provider, not the data path.
  What is checked directly is that every symbol the app imports from the pinned
  SDK is actually exported by it ([WY-14](#tests)) — a real check now, run by
  `Web/tools/check-firebase-sdk.mjs`, rather than the one-off inspection this
  previously described.
- What *is* verified: the rules themselves, by Firebase's own engine in the
  emulators ([WY-17](#tests)) — 29 checks, thirteen mutants killed. That closes
  the gap this section described for several revisions as unclosable. It was
  recorded as blocked on the live project having only Google sign-in enabled,
  which is true and is beside the point: the emulators run the same engine on
  the same files and hand out tokens freely. The block was never tested, only
  assumed.
- What *is* verified besides: the pinned SDK loads and initialises against this
  project,
  the store adapter builds against a real Firestore handle, the backend answers
  `config()` identically to the local one, and the cloud backend passes 30 tests
  against an in-memory Firestore that enforces the same query semantics —
  including the prefix-boundary case in [WR-13](#11b-cloud-storage-and-accounts),
  proven by mutation testing to fail when that filter is removed.
- Local storage is proven untouched by this change: the file tree, document
  reads, and image URLs all still work through the new façade.
- Offline persistence is verified at the seam and not beyond it. Five tests
  assert that Firestore is opened with a persistent, multi-tab cache and that an
  unavailable IndexedDB falls back rather than failing — mutation tested, four
  of them fail if the persistent cache is removed. What no test covers is a real
  browser reloading with the network off, because that needs a signed-in account
  against a live database, which is the same thing blocking everything else here.

---

## 11c. AI assisted critique

A rail of comments down the right-hand side of the document: a model reads the
draft through the KONVO critique pass and writes notes on the passages that
prove each point, each one shaded in the text beside the card that describes it.

The macOS build's feature, brought over. It is the same shape, the same
severities, the same score and the same two actions, because it is the same
critique -- but where the key lives had to change, and that change is visible
enough to be worth stating before the requirements rather than after them.

| ID | Requirement |
| --- | --- |
| WA-1 | **AI Assisted Critique** (⌃⌘C, the toolbar's pen, or the rail's own button) reads the whole draft and returns findings. |
| WA-2 | Each finding carries a severity, a category, the passage it is about, the reader consequence, and either a fix or a direction. |
| WA-3 | Each finding's quoted passage is found again in the document and shaded in both editing surfaces. A quote that cannot be found is still shown as a card, saying so, rather than shaded onto something that merely looks similar. |
| WA-4 | Clicking a card selects its passage; putting the caret in a shaded passage opens its card. It does not yet scroll to the passage or answer the pointer -- see [WA-34](#deliberate-differences-from-the-mac). |
| WA-5 | A finding can be marked **Done** or **Dismissed**. Either removes its shading, straightens and fades its card, and sinks it below the outstanding ones under an **ANSWERED** heading. Only Done takes it off the score ([WA-6](#11c-ai-assisted-critique)). |
| WA-6 | A score out of 100 counts what still stands against the draft: every outstanding note, every **dismissed** one -- dismissing is a decision to leave the passage as it is, not a fix -- and each problem the summary lists, at the weight of a low note. Only **Done** clears a note. It decays rather than subtracting, so every fix is worth something and no draft reaches zero. This port used to count only what was outstanding, so dismissing every note printed "100 · Ready" over a draft nobody had touched. The Mac stopped doing that ([I-274, I-275](../macOS/README.md#10a-ai-assisted-critique)) and this build followed in the same change, because the score is ported and a port its original moves away from is not one. |
| WA-7 | The rail is in **reading order**, not severity order. Severity is the colour, the tag and the count at the top; it decides how a finding looks, not where it sits. |
| WA-8 | The marks follow the words as the draft is edited beneath them, including changes this browser did not make. A line break typed inside a passage ends the passage there. |
| WA-9 | Once the draft has moved, the rail says so and says how many notes still point at something. It says so on the edit that moves the draft, and stops on the edit that puts it back. It used to redraw only when an edit moved a mark, and a critique that finds nothing leaves no mark to move, so the draft could be rewritten under a *Ready* that no longer described it ([WA-35](#11c-ai-assisted-critique)). |
| WA-10 | Answering a note is remembered by what the note *says*, not by its identity, so a re-run does not resurrect a dismissal. |
| WA-11 | The comments can be set in any of fifteen hands, eight bundled and the rest offered only where they resolve. Each name in the picker is shown in its own face. |
| WA-12 | The first card is the summary -- what the piece is, what works, what does not -- and is entirely in the system face, because it is a summary *of* the handwritten notes rather than one of them. |
| WA-35 | **"Ready" is the critic's word, not the author's.** A hundred reads *Ready* only when a critique of the draft exactly as it stands found nothing. Reached by marking notes Done, or with the draft changed since, it reads **Looks ready**; the line under the bar says why, and while the draft is unchanged a **Critique again** button offers the run that would confirm it. When the draft has changed the stale notice already offers that, so the banner does not offer it twice. As [I-276](../macOS/README.md#10a-ai-assisted-critique). |
| WA-36 | **The line under the score says why the number is what it is**, when the notes do not: how many are answered, that **dismissed notes still count**, and -- once no note is left open -- that **the problems in the summary still count**. It says nothing when the number explains itself. "Everything answered." beside a hundred, which is what it used to say, was the rail agreeing with itself. The wording is the Mac's, because the rule is. |
| WA-37 | **A fresh critique reopens a Done note it raises again in the same words**, and keeps a dismissal ([WA-10](#11c-ai-assisted-critique)). Done says *fixed*; the same objection, from a critique of the draft as it stands, says it was not. Carried over, the Done would hold the score at a hundred that no number of re-runs could confirm. The Mac reaches the same answer by asking the critic about each earlier note ([I-280](../macOS/README.md#10a-ai-assisted-critique)), which this build does not do yet ([WA-39](#deliberate-differences-from-the-mac)). |
| WA-38 | **The summary is not padded to make a number.** The prompt asks for *up to* three problems in the round, not "two or three", and for none when nothing holds the draft back, since each one now costs the score. With none listed, the overall read stands on its own; it used to be filed under WHAT DOESN'T WORK with a red dash, which made "ready to publish" a problem. |
| WA-13 | Nothing about the critique fails silently. A missing key, a refused key, an unreachable model and a reply that is not a critique are four different messages, each with what to do about it. |

### Whose key

**The reader's.** A critique is read by a model, and reaching one costs money,
so it runs on the reader's account rather than on the site's.

That is not only a billing decision. This page is open to anyone who finds the
URL ([WS-6](#15-run-deploy-and-test)), and an app that critiques on the owner's
key is an app whose running cost is set by whoever else happens to visit. The
failure is quiet, it is somebody else's, and nobody notices until the bill.

| ID | Requirement |
| --- | --- |
| WA-14 | The key is entered by the reader and kept **in this browser**, in `localStorage`, one per provider so that trying another does not lose the first. |
| WA-15 | It is sent with each request for the server to spend and forget. It is not written to disk, not put in a session, and not logged — the catch-all handler logs a message and never the request. |
| WA-16 | It goes through the server rather than straight from the page, because two of the three providers refuse a cross-origin request outright. Proxying all three keeps one code path instead of three behaviours, and it is the same code the Mac's requests are ported from. |
| WA-30 | **`localStorage` is readable by any script on this origin.** That is the same exposure the rest of the app's preferences have and a good deal more consequence, and it is the least-bad option a page has. It is said here rather than left to be assumed, and it is the reader's own key rather than somebody else's. |
| WA-31 | The key field is a password field, and a stored key is shown back **masked** — the first six characters and the last four. That answers "is the right key in here", which is the only question worth asking of it, and a key printed in full on screen is a key that ends up in a screenshot. |
| WA-32 | The provider and the model are **validated on the server** against what this build knows. Otherwise a model name is a string from a page that ends up inside a request URL, which is a forgery waiting for somebody to find it. |
| WA-33 | Asking for a critique without a key opens the settings instead of spending a request to be told what the app already knows. |
| WA-17 | A server may hold a key of its own, for a private install where that is the point, but **only when `MDE_CRITIQUE_ALLOW_SERVER_KEY` is set**. The default is off: a host that already has `OPENAI_API_KEY` set for something else would otherwise opt in by accident, and the failure mode of that default is a bill. |
| WA-18 | `MDE_CRITIQUE_BASE_URL` redirects the request, because the OpenAI request shape is spoken by rather more than OpenAI — Azure, OpenRouter, a proxy, a model on the same machine. It is also how this build is exercised end to end without spending a request on a live account. |
| WA-29 | A model list is a set of claims about somebody else's service, and it had gone stale: the Gemini pair shipped here were **retired**, and the API says so as `is not found for API version v1beta` — which reads like a mistyped name rather than a model that no longer exists. `gemini-2.5-flash` and `gemini-3.6-flash` are the two verified answering. |
| WA-19 | The macOS build's fourth provider — a model already installed on the reader's machine, needing no key — is deliberately absent. A browser has no such thing, and offering it would put an option in a menu that could never work. |

### The KONVO skill

| ID | Requirement |
| --- | --- |
| WA-20 | The skill's `## Critique` section is sent with every request, so the critique is KONVO's whichever model answers rather than that model's own idea of what a critique is. |
| WA-21 | It is **vendored** into `Web/skill/` by `tools/vendor-konvo-skill.sh` and deployed with the private half of the app, out of reach of the web. The Mac reads a git checkout in the reader's home directory; a web server has neither that nor a way to pull one, and fetching it at request time would make every critique depend on GitHub being reachable and leave nothing to review in a diff. |
| WA-22 | The consequence is stated rather than implied: the web build's skill updates when that script is run and the result deployed, **not** when anybody presses something. The version panel names the commit that actually went out. |
| WA-23 | The pass is fenced and introduced as instructions; the draft is fenced and introduced as material. Both are fenced for the same reason from opposite directions -- a draft must never be read as instructions, and the skill must never be read as something to critique. |
| WA-24 | With no skill deployed the critique still runs, and says on screen that it is running without it. Refusing the whole request over a missing file would turn a degraded critique into no critique at all. |

### Deliberate differences from the Mac

| ID | Difference |
| --- | --- |
| WA-25 | The shading is painted with the **CSS Custom Highlight API** rather than by wrapping each passage in an element. Both surfaces are `contenteditable`: inserting a `<mark>` moves every offset after it, corrupts the mapping selections are read through, and lands in the browser's undo stack as though the author had typed it. A highlight paints over the text without touching the tree. |
| WA-26 | Where that API is missing -- Firefox before 140 -- the cards work and nothing is shaded. Degrading is correct here; the notes are still readable, and the alternative is an editor that corrupts documents on one browser. |
| WA-27 | No revision history yet. The Mac keeps every critique of a document and lets you page back through them; here a critique lasts until the document is closed. |
| WA-34 | No reveal and no hover tint yet. Pressing a note selects its passage and shades it more strongly; it does not take the reader to it, and hovering a note does nothing. Both are now written down in [`Contract/README.md`](../Contract/README.md) — what a press must do, where the passage has to be placed, and why the hover must never scroll — because the Mac build got each of them wrong in a way a port would repeat. The browser has the easier job of the two: `scrollIntoView` with `block: 'center'` is most of the reveal, and the CSS Custom Highlight API already carries a second highlight name for the hover wash. The trap that is *not* easier is the last one in that section — a click on the note's own text must reach the note, which on this side means watching out for `user-select` and for a child element answering the press. The open passage also needs its rule, not only a stronger wash: `text-decoration` will not do it under a highlight, so it wants a `box-shadow: inset 0 -2px` or a `::highlight` with an underline. |
| WA-39 | **What the Mac's critique has gained that this one has not yet.** A draft of under 30 words of prose is still sent ([I-273](../macOS/README.md#10a-ai-assisted-critique)). There is no audience-and-goal brief ([I-294](../macOS/README.md#10a-ai-assisted-critique)). A re-run starts again rather than carrying the notes forward and asking the critic which are fixed ([I-279](../macOS/README.md#10a-ai-assisted-critique)). A note cannot carry its fix as the words to put in, so there is no Apply ([I-288](../macOS/README.md#10a-ai-assisted-critique)). Notes arrive together when the reply is complete, not each as it is written ([I-301](../macOS/README.md#10a-ai-assisted-critique)). There is no quick pass ([I-309](../macOS/README.md#10a-ai-assisted-critique)). And a note's place is the critic's own label rather than one worked out from where the note is anchored ([I-324](../macOS/README.md#10a-ai-assisted-critique)). The score is the one part of that change that is here, because it is the one part that was already ported: the others are features this build never had, and the score was a rule it had and was now getting wrong. |
| WA-28 | No narrowed re-run yet. The Mac can re-read only the paragraphs that changed and keep the notes about the rest; here a re-run reads the whole draft. The server and the prompt already take a focus passage, so what is missing is the client half. |

### What has been verified

- **The reader's key, end to end.** With no key the rail says so and offers the
  panel; the server refuses the request with a sentence rather than a shrug.
  A key typed into the panel tested, saved, flipped the rail to ready, and ran
  a critique that anchored every quote.
- **One view.** The source pane, the divider and the switcher are gone from the
  markup, the toolbar, the menus and the mobile sheet, and the rendered view
  still shades a critique's passages exactly — measured on screen, the
  highlights landed on "In today's fast-paced world" and "Over 90% of companies
  use widgets daily".
- **The whole path, on the live site.** A draft posted to
  <https://www.kirupa.com/humanish/> came back with six findings through the
  KONVO critique pass, and **all six quotes were verbatim in the draft** — which
  is the property every highlight depends on and the one the prompt spends most
  of its words on.
- **The rail, in a browser**, against a stand-in model: score, cards, tilt,
  severity papers and tags, reading order, the two-way link between a card and
  its passage, Done and Dismiss, the score returning to 100 (as it then
  did for Dismiss too; see [WA-6](#11c-ai-assisted-critique)), answered notes
  sinking under their heading, the stale notice, and the marks staying on their
  sentences after text was inserted above them.
- **The score, in a browser**, against a stand-in model whose reply was changed
  between runs, in headless Chrome driven over the DevTools protocol. Two notes
  and one problem in the summary scored 86, *Nearly there*. Dismissing both left
  it at 86 and said *Dismissed notes and the problems in the summary still
  count*. Marking them Done instead gave 97, held there by the summary's
  problem. A re-run that raised the same two notes reopened both, at 89. Done
  on both, with nothing in the summary, gave 100 and *Looks ready*, the caption
  and **Critique again**. Pressing that against a reply with nothing to say gave
  100 and *Ready*, with the overall read on its own. Typing into that draft
  turned it back to *Looks ready* with the stale notice, and deleting what was
  typed returned it to *Ready*. That pair failed the first time it was tried,
  which is how the missing redraw in [WA-9](#11c-ai-assisted-critique) was
  found.
- **The degraded path**, by accident and then on purpose: a critique whose
  quotes are not in the document shows every card saying "Not found in the
  document", shows the quote itself because nothing is pointing at it, and says
  how many could not be matched.
- **All three providers' error paths, live.** A rejected OpenAI key, an
  Anthropic account out of credit and a retired Gemini model each came back as
  their own sentence rather than as a shrug.

### What has not been verified

- **OpenAI and Anthropic have never answered a critique here.** The keys on the
  host were rejected and out of credit respectively, and that was before the key
  became the reader's. Their request shapes are tested against recorded replies,
  and their live behaviour is not. A reader with a working key of either would be
  the first to find out.
- **Firefox.** The shading needs the CSS Custom Highlight API, which Firefox
  gained in 140; the fallback ([WA-26](#deliberate-differences-from-the-mac))
  is written but has not been watched degrade in a real Firefox.
- **A long draft.** Everything measured here has been a page. The 200,000-character
  ceiling is a guess about what is worth one request, not a measurement.

---

## 12. Themes, typography, and layout

| ID | Requirement |
| --- | --- |
| WT-1 | Eight colors — Blue, Yellow, Pink, Green, Purple, Pico-8, Black, Brown — on an independent Light/Dark axis: sixteen combinations, transcribed from kirupa.com. |
| WT-2 | `View ▸ Customize Theme…` opens a popover with color swatches, a Light/Dark toggle, a live preview, and **Cancel** / **Apply**. |
| WT-3 | The popover holds *draft* state: the preview updates as choices are made, Apply commits, Cancel restores what was active. |
| WT-4 | Each swatch is drawn in its own theme's colors. |
| WT-5 | The theme applies to the entire app — canvas, sidebar, both editor panes, inline code, fenced code, selection, and the welcome overlay. |
| WT-6 | The theme persists across reloads and is applied before first paint, so there is no flash of the wrong theme. |
| WT-7 | The theme is two attributes on `<html>`; `themes.css` does the rest. Nothing recolors elements in JavaScript. |
| WT-8 | Headings, body text, and code use the same size scale as the macOS build, in both panes. |
| WT-9 | A fenced code block is drawn as one continuous rounded rectangle behind all of its lines, not one box per line. |
| WT-10 | The rendered pane is centered within a readable measure whose width is draggable and persists. |
| WT-11 | Horizontal rules render as a centered em dash, matching the macOS build. |
| WT-12 | The sidebar divider and the pane divider are drag handles with `separator` roles. |
| WT-13 | On desktop the explorer is **closed by default** and floats over the document rather than taking part in the layout. Opening or closing it does not move the document by a single pixel. The first toolbar button toggles it, alongside `View ▸ Show File Explorer` (`⌃⌘S`), and the choice persists. |
| WT-14 | The chrome is deliberately quiet: the menu bar, toolbar, and status bar share the page's own background instead of sitting in tinted bands, toolbar groups are separated by space rather than rules, and a tool's icon stays secondary until it is hovered or active. The document is the only thing on the page asking to be looked at. |
| WT-15 | Because the explorer is out of the flow, the rendered measure is centered on the *page*, not in the space the explorer happens to leave over. Opening the explorer slides it over the left edge of a document that does not move. |
| WT-16 | Customize Theme has a **Font** menu offering the same faces as the critique's hand menu, from one catalog (`app/ui/typefaces.js`, using the Mac's ids), grouped System Sans / Bundled / From your computer with each name set in its own face. The page's body and headings take the face at its optical scale, and code stays monospaced. The face is part of the draft: it is previewed, committed on Apply, and kept as `editorTypeface`, separately from the critique's hand. On `<html>` it is two custom properties, `--me-page-font` and `--me-page-scale`. A face the machine lacks draws as System Sans at System Sans's size. A face with one weight gets the browser's synthesized bold and italic. |
| WT-17 | A face the app does not serve is offered **only if the browser will actually draw it**, and that is measured, not asked. `document.fonts.check()` only reports whether a face still has to load. A family no stylesheet declares never does, so WebKit and Chrome both answered yes for a family that does not exist, and the menus offered Noteworthy and friends on machines without them. `isDrawableFamily` sets a sample in the family ahead of each generic family and compares widths instead. That also governs QE Dave Mergens and QE Julian Dean, which are never served because their licence forbids it ([T-21 in the macOS PRD](../macOS/README.md#122-customize-theme-popover)). Installed, they appear in Chrome, where this was verified. Safari does not let pages use fonts somebody installed themselves, so they are not offered there, which is the truth about what it would draw. |
| WT-18 | Selected text is drawn on a pale, translucent tint of the accent and keeps its own colors: `::selection` sets `--me-text-selection-background` and no `color`. The tint is generated into `themes.css` from the shared Swift theme, which solves its opacity per theme (14–40%) so body text stays at 7.6:1 or better on it and code on a code block at 4.5:1. The Customize Theme preview's **Selected text** chip shows the same tint. Menus, tree rows, radio buttons and other selected controls keep the full accent and its black-or-white label (`--me-selection-*`). |
| WT-19 | Customize Theme has a **Size** slider beneath Font, from 75% to 150% in steps of 5%, with the percentage beside it — the Mac's T-23. It is part of the draft, stored as `editorTextScale` (the Mac's key), and on `<html>` it is `--me-text-scale`, which `app.css` multiplies into the rendered page's type, the gaps between paragraphs and headings, and the indents of lists, quotes and code. The column, the pictures and the Markdown source pane keep their size. A stored value that is out of range or not a number is clamped or reads as 100% (`app/core/text-scale.js`). The popover is a **fixed 316px wide** (never more than the window less 16px), so nothing it previews can widen it: sized to its preview, a larger size or a wider face widened it, and the slider with it, moving the thumb out from under the pointer mid-drag. The preview wraps instead, and the popover grows downward only, below the slider. |
| WT-20 | In the rendered pane a selection is drawn as **rounded bars fitted to the words, one per line, fading out past a line's end and in before the next line's start** — the Mac's T-24, with the shape ported line for line (`app/core/selection-geometry.js`, checked against the same cases as the Swift). Its hard ends stand **exactly on the carets** either side of the selection, with no padding, so a bar never reaches into a letter that is not selected, and its corners are rounded by a little over a fifth of the line height, at most 6px. The browser measures the selection per text node (`getClientRects`), the lines are grouped and each is given its band — the line height less a 2px gap, once per line, so a word in another face cannot make a line taller — and `app/ui/selection-highlight.js` draws the bars in a zero-height layer beside the editable surface, never inside it. The bars sit **over** the text and blend with it — `multiply` on a light page, `screen` on a dark one — in colours solved so that on the page they come out exactly the tint `::selection` would have drawn, while the letters keep their own colours; on a surface that draws its own selection `::selection` is transparent. Away from the focus the bars take `--me-inactive-text-selection-background`, the Mac's quieter tint. On the mobile layout, on a touch screen, where blending is unsupported, or after any error, the browser's own selection is drawn instead, with the same tint. |
| WT-21 | A block quote is drawn with **one bar down its left for a run of quoted lines**, not a dash beside each — the 3px border in the text colour at 28% that the macOS build now draws too ([Y-4 in the macOS PRD](../macOS/README.md#132-block-layout)). Every `>` line is a block of its own, and the gap between blocks was a margin, which a border does not cross. Between two quoted lines the same gap is padding instead, so the lines sit exactly as far apart as before and the border runs through it. A paragraph between two quotes still gives each its own bar. `tests/stylesheet.test.js` holds the rule in place. |

---

## 12a. Mobile layout

A phone cannot use the desktop chrome. A menu bar is a row of hover targets, the
toolbar is twenty ~30px buttons on one line, the sidebar is docked, and the
status bar spends a row on text nobody taps. `View ▸ Mobile Layout` (`⌃⌘M`)
swaps all of it for an arrangement built for a touch screen — the *same*
commands, not a reduced editor: a two-row header, the explorer as a drawer, and
sheets in place of menus.

| ID | Requirement |
| --- | --- |
| WB-1 | A single Mobile Layout toggle replaces the menu bar, the desktop toolbar, and the status bar with a two-row header: a slim top bar and, docked beneath it, the formatting row. Nothing about the open document changes. |
| WB-2 | The choice persists in `localStorage` and survives a reload at any window size. |
| WB-3 | With no stored choice, the layout is guessed once from the device: a viewport ≤ 820px wide **or** a coarse pointer. After the user chooses, the guess never overrides them again. |
| WB-4 | The top bar holds, left to right: a **Files** button, the document name (with a `•` while unsaved), **Undo**, the **theme** picker, a **save this file for later** checkbox, and an overflow button. |
| WB-5 | The formatting row spans the header's full width and scrolls horizontally: paragraph style, bold, italic, underline, strikethrough, inline code, bulleted / numbered / task list, quote, code block, link, image, horizontal rule. Buttons show the styles active at the caret, exactly as the desktop toolbar does. |
| WB-6 | The app is sized to the space the keyboard leaves, measured through `visualViewport` rather than assumed, so nothing is left underneath the keys and the browser never scrolls the page to reveal the caret. The top of the header stays clear of the notch via `env(safe-area-inset-top)`, and the end of a document clears the home indicator via `env(safe-area-inset-bottom)`. |
| WB-7 | The overflow button opens a bottom sheet with Rich Text / Markdown, New Document, Save, and **Desktop Layout** — the way back out once there is no menu bar. |
| WB-8 | The **save for later** checkbox adds the open document to a list that is separate from recents. Recents reorder and age out, so simply using the editor would lose whatever you meant to return to; this list only changes when asked, is not capped, and keeps its order. |
| WB-9 | The checkbox is disabled for an untitled document, which has no path to remember. |
| WB-10 | A saved document that is renamed or moved keeps its place in the list; one that is deleted, or whose folder is deleted, is dropped from it. |
| WB-11 | Saved documents appear as their own section above Recent Documents on the welcome screen, and the welcome panel — a fixed 760 × 600 two-column card — stacks into one column on a narrow or short viewport instead of squeezing the document list off-screen. It grew from 560 when the identity block started drawing a real icon: the old inline mark collapsed to 5px tall, so the column had been getting that space for free, and at 560 the **Show this window at launch** checkbox fell below the fold. Measured either way — the side column's scroll height against its client height, which is 0 over at 600. |
| WB-12 | The file explorer becomes an overlay drawer opened from the Files button and dismissed by tapping outside it. Its state is transient and does not overwrite the desktop sidebar preference. |
| WB-13 | Side by Side is unavailable, since a phone has no room for two columns; entering the mobile layout switches to Rich Text and leaving it restores Side by Side. |
| WB-14 | Every control is at least 36 × 36px, and buttons do not take focus, so a formatting tap acts on the live selection and does not dismiss the keyboard. |
| WB-28 | Keeping focus means cancelling `mousedown` and nothing else. A tap synthesizes `mousedown` before `click`, so cancelling it holds the selection on touch as well as with a mouse. Cancelling `touchstart` or `pointerdown` looks like the same idea and is not: it suppresses the whole compatibility chain, so `click` never fires and the control is dead on a phone. That is registered in one shared helper (`ui/keep-focus.js`) with one test, rather than re-derived at each button. |
| WB-29 | A control that keeps focus must still be draggable, because most of the formatting row's width is buttons and the row is scrolled by dragging along it. Cancelling `touchstart` would swallow that drag as well as the click. |
| WB-17 | The viewport is pinned: no pinch zoom, no double-tap zoom, and no dragging or rubber-banding the page behind the app. The app already fills the screen and every scroll happens inside a pane, so panning the page only slid the docked header out of reach. |
| WB-18 | Pinning takes three mechanisms because none alone is enough — the viewport meta tag for Android, `touch-action` for double-tap and pinch, and cancelled `gesture*` events plus two-finger drags for iOS Safari, which has ignored `user-scalable=no` since iOS 10. The `touch-action` is set on `<html>`, since the effective value is the intersection of an element's and all its ancestors'. |
| WB-19 | Leaving mobile restores the original meta tag and drops the listeners, so a phone deliberately switched to Desktop Layout keeps pinch zoom — the cramped desktop chrome is where zoom is actually wanted. |
| WB-20 | The formatting row is docked as the header's second row, directly beneath the top bar and directly above the document, and it stays there. Controls beyond the screen's width scroll horizontally, and the partly visible control at the edge is the affordance. |
| WB-21 | The row opts back into horizontal panning (`touch-action: pan-x`, which the root's `pan-x pan-y` permits — a root of `pan-y` would have intersected to allow nothing) and contains its own overscroll so a fling along it cannot pan the page or trigger a back-navigation. |
| WB-16 | A document scrolls all the way to its end with room to spare. The editor surface sizes to its content rather than to the pane, so its bottom padding lands at the end of the scroll range instead of inside a fixed frame where overflowing text scrolls straight past it. |
| WB-22 | Nothing focusable in the mobile layout uses text under 16px — not the editing surfaces, not the paragraph-style menu, not a field in any sheet, dialog, or the welcome panel. iOS Safari zooms the whole page in when you focus text smaller than that, and it does so regardless of `user-scalable=no`. Mobile body text is therefore 16px rather than the desktop 15px. |
| WB-23 | WB-22 exists because that one zoom is the cause of two symptoms that look unrelated: once the page is zoomed the layout viewport is wider than the screen, so the page slides sideways, and the fixed formatting bar is positioned against a viewport that no longer matches the screen, so it lands somewhere other than where it was put. Neither symptom is horizontal overflow — there is none at any iPhone width, even with unbreakable 90-character words and long bare URLs. |
| WB-24 | The formatting row does not move when the keyboard opens or closes. Its position is not a function of the keyboard, the accessory row above it, or the home indicator, so there is nothing to get wrong. |
| WB-25 | The `<html>` element carries a single `data-me-layout="mobile"` flag owned by the layout controller. The sheets, dialogs, and welcome panel render as siblings of the app root rather than inside it, so a rule scoped to the app cannot reach their controls; anything that must apply everywhere hangs off this flag. |
| WB-26 | The formatting row is docked in the header rather than floating above the keyboard, because the bottom of a phone screen is not a place a web page can rely on. The platform stacks its own furniture there — on iOS the keyboard's AutoFill and dismiss row, and the home indicator — a page cannot reserve space above it, and `visualViewport` does not reliably report it. Anything floating at the bottom ends up behind something. The header is the one region the platform leaves alone. |
| WB-27 | Docking costs the thumb-reach that put the tools at the bottom in the first place. That is the accepted trade: tools that are slightly further away beat tools that are partly unreachable, and the top of the screen is where a phone user already expects a document's controls. |
| WB-15 | Every mobile control calls the same command table the menus and desktop toolbar use, and all keyboard shortcuts keep working. There is no second implementation of any command. |

---

## 13. Keyboard shortcut reference

`⌘` is Command on macOS and Control elsewhere.

| Shortcut | Action |
| --- | --- |
| `⌘N` | New |
| `⌘O` | Open… |
| `⌃⌘N` | New Document in Folder… |
| `⇧⌘N` | New Folder… |
| `⌘S` | Save |
| `⇧⌘S` | Save As… |
| `⌘W` | Close document |
| `⌘Z` / `⇧⌘Z` | Undo / Redo |
| `⌘A` | Select All |
| `⇧⌘I` | Add Image… |
| `⌘K` | Link… |
| `⌃⌘H` | Horizontal Rule |
| `⌘B` / `⌘I` / `⌘U` | Bold / Italic / Underline |
| `⌃⌘K` | Strikethrough |
| `⌘E` / `⇧⌘E` | Inline Code / Code Block |
| `⌘0` | Body |
| `⌘1` … `⌘6` | Heading 1 … 6 |
| `⇧⌘7` / `⇧⌘8` / `⇧⌘9` | Bulleted / Numbered / Task list |
| `⌃⌘Q` | Block Quote |
| `⌃⌘S` | Show File Explorer |
| `⌃⌘C` | AI Assisted Critique |
| `⇧⌘C` | Show Critique |
| `⌃⌘M` | Mobile Layout |

---

## 14. Architecture

```
Web/
├── serve.sh                   Local preview: php -S, nothing else
├── deploy.sh                  Publish to a shared PHP host over FTPS
├── bootstrap.php              A nine-line autoloader — no Composer
├── seed/                      Starter documents, copied into a new workspace
├── src/                       The server
│   ├── Workspace.php          Path resolution and the security boundary
│   ├── WorkspaceError.php     Message + recovery suggestion, as JSON
│   ├── DocumentStore.php      UTF-8 read/write, BOM handling, .md validation
│   ├── FileTree.php           One directory level, sorted, filtered
│   ├── FileManager.php        Create, rename, move, duplicate, delete
│   ├── ImageImporter.php      Upload validation, assets folder, collisions
│   ├── Critique.php           Runs a critique; the API key never leaves here
│   ├── CritiqueProvider.php   Port of CritiqueProvider.swift: URL, headers, body
│   ├── CritiqueRequest.php    Port of CritiqueRequest.swift: the prompt
│   ├── KonvoSkill.php         Port of KonvoSkill.swift: the vendored pass
│   └── Api.php                One dispatch table for every action
├── skill/                     The KONVO critique pass, vendored and deployed
│   ├── critique-pass.md       The skill's ## Critique section, 21KB
│   └── version.txt            The commit it came from, so the app can say so
├── tools/
│   └── vendor-konvo-skill.sh  Re-vendors the pass from a skill checkout
├── public/                    The document root
│   ├── index.php              The only page
│   ├── api.php                The only endpoint
│   ├── icon.svg
│   ├── hands.css              @font-face only; outside the versioned tree
│   ├── fonts/                 The eight bundled hands, OFL and Apache
│   ├── css/
│   │   ├── themes.css         Generated from EditorColorTheme.swift
│   │   └── app.css            Layout, typography, components
│   └── app/
│       ├── core/              Ports of the Swift: rendering, formatting, critique
│       └── ui/                The DOM: surface, toolbar, menus, explorer, rail
│   ├── app/
│   │   ├── core/              Ported from Swift; no DOM, no network
│   │   │   ├── range.js               NSRange arithmetic
│   │   │   ├── render-model.js        ← MarkdownRenderModel.swift
│   │   │   ├── formatting.js          ← MarkdownFormatting.swift
│   │   │   ├── text-difference.js     ← TextDifference.swift
│   │   │   ├── recent-documents.js    ← RecentDocumentsCatalog.swift
│   │   │   └── saved-documents.js     Save-for-later list arithmetic
│   │   ├── dom-text.js        Text ↔ DOM offset mapping
│   │   ├── api.js             The storage contract; forwards to a backend
│   │   ├── backends/
│   │   │   ├── local.js               PHP: fetch, and no-op watchers
│   │   │   └── firestore.js           Cloud: the same shapes out of Firestore
│   │   ├── cloud/             Firebase: config, lazy SDK load, auth, store
│   │   ├── live.js            What to do when the server says it changed
│   │   ├── document.js        Document state, undo stack, autosave
│   │   ├── ui/                Surfaces, renderers, explorer, toolbar, menus,
│   │   │                      welcome, theme popover, dialogs, context menu,
│   │   │                      mobile bars and overflow sheet
│   │   └── main.js            Wiring: commands, modes, panes, startup
│   └── tests/                 The browser test page and the JS suites
└── tests/
    ├── run.mjs                Optional node runner for the same suites
    └── php/                   Server-side suites
```

| ID | Requirement |
| --- | --- |
| WA-1 | `app/core/` is pure: no DOM, no network, no globals. It is the ported Swift core and is tested in isolation. |
| WA-2 | The server is stateless. Every request is resolved against the workspace from scratch. |
| WA-3 | `api.php?action=…` is the entire protocol: `config`, `tree`, `read`, `exists`, `write`, `create`, `newDocument`, `newFolder`, `rename`, `move`, `duplicate`, `delete`, `upload`, `asset`. |
| WA-4 | Reads are GET; anything that writes requires POST. |
| WA-5 | Errors are `{ "error": …, "recovery": … }` with a non-200 status, and the client turns every one into a modal alert. |
| WA-6 | Both editor panes are the same `EditorSurface` controller, parameterized by a projection that says how to render, how to read text, and how to map ranges. The rendered and source panes differ only in that object. |
| WA-7 | An edit is applied by diffing the surface's text against what the model expects, mapping that difference to a source range, and replacing it — so the browser's own editing behavior is used, but the source stays canonical. |
| WA-9 | Storage is one interface with two implementations behind `api.js`, so nothing above it knows whether a document is on the server or in an account — including the watch calls, which the local backend answers with a no-op ([WC-7](#live-updates)). |
| WA-10 | What to do with a revision from elsewhere is a pure function of the model's state and the revision, separate from the subscription that delivers it. Every outcome — adopt, defer, detach, ignore — is decided in code reachable without a network, a DOM, or a timer, because that decision is where someone's work is at stake and it must be testable exhaustively. |
| WA-8 | `Workspace::resolve()` follows symlinks and is used for reading *through* a path; `Workspace::resolveEntry()` resolves every ancestor but leaves the final component alone, and is used for acting *on* an item. Renaming or deleting through the first would operate on a link's target instead of the link. |

---

## 15. Run, deploy, and test

### Local preview

```bash
git clone https://github.com/kirupa/humanish.git
cd humanish
Web/serve.sh
```

Then open <http://127.0.0.1:8000/>. The first run creates `~/kirupaMarkdown`
with a couple of starter documents and opens it; after that the folder is yours,
and the editor leaves it alone. Pass a port as the first argument, and point
`MARKDOWN_EDITOR_WORKSPACE` somewhere else to edit a different folder:

```bash
MARKDOWN_EDITOR_WORKSPACE=~/Documents/Notes Web/serve.sh 9000
```

### Deploying

If you control the document root, there is almost nothing to do:

1. Copy `Web/` to the server.
2. Point the document root at `Web/public`.
3. Make sure the workspace folder is writable by the web server. It is created
   on first request if it is missing.
4. There is no step 4. No build, no install, no configuration file.

Only `Web/public` needs to be reachable. `Web/src`, `Web/bootstrap.php`,
`Web/seed`, `Web/skill`, and `Web/tests` are read by PHP but never served.

Critiques need no server configuration at all: the key is the reader's, entered
in the app and kept in their browser ([§Whose key](#whose-key)).

A **private** install may prefer to hold one key for everybody. That is off
unless it is asked for, because a host that already has `OPENAI_API_KEY` set for
something else would otherwise start paying for every visitor's critiques
without anyone having decided to:

```apache
SetEnv MDE_CRITIQUE_ALLOW_SERVER_KEY 1
SetEnv MDE_CRITIQUE_KEY sk-...
```

Do that only behind `MDE_HTPASSWD`, or on a page nobody else can reach.

#### On shared hosting, where you cannot move the document root

Most shared hosts give you one document root and a URL subdirectory. The app
splits in two: what has to be reachable goes under the document root, and
everything else — including the documents — goes above it, where the web server
will not serve it however it is asked.

```
~/markdown-editor/        bootstrap.php, src/, seed/, skill/  ← above the document root
~/kirupaMarkdown/         the documents                       ← above the document root
~/public_html/humanish/   index.php, api.php, app/, css/      ← served, at /humanish/
```

Two `SetEnv` lines in `.htaccess` are the whole configuration:

```apache
SetEnv MARKDOWN_EDITOR_HOME /home/you/markdown-editor
SetEnv MARKDOWN_EDITOR_WORKSPACE /home/you/kirupaMarkdown
```

`Web/deploy.sh` does all of this over FTPS, including generating that
`.htaccess`. It takes its settings from the environment and its password from
`~/.netrc`, so no host name and no credential is ever written into the
repository. Run it with `--dry-run` first to see exactly what would be sent.

| ID | Requirement |
| --- | --- |
| WS-1 | `MARKDOWN_EDITOR_HOME` tells the two public entry points where the rest of the app lives. Unset, they use the layout in this repository, so a normal install needs no configuration. |
| WS-2 | Settings are read from `getenv()` *and* `$_SERVER`. `SetEnv` reaches only the second on some CGI and LiteSpeed builds, and `putenv` reaches only the first — reading one would work locally and fail on a host. |
| WS-3 | `deploy.sh` uploads from a staging copy containing only the files it lists, so a local edit, a test fixture, or a scratch document cannot reach the server by accident. `tests/` is never deployed. |
| WS-4 | The deployment is self-configuring: the generated `.htaccess` names the paths the app was actually installed at, so it cannot drift from them. |
| WS-5 | `deploy.sh` uses `lftp` when it is present, because `mirror --delete` stops a redeploy leaving the previous version's files behind, and falls back to `curl`, which is on every machine. |
| WS-6 | **The editor has no accounts, no sessions, and no permissions of its own.** Anyone who can reach the URL can read, change, and delete every document in the workspace. |
| WS-7 | Setting `MDE_HTPASSWD` puts the whole install behind HTTP Basic Auth, as a stopgap for a workspace that should not be open. Leaving it unset deploys the app to anyone who finds the URL, which is the right choice only for a workspace whose contents are meant to be public. |
| WS-9 | A deploy places `app/` and `css/` under `v/<content-hash>/` and writes `asset-base.php` beside `index.php`, so every module URL changes together. A query string only versions the URLs the page writes; the imports *inside* a module are static paths no query string reaches, and a cache holding a new `main.js` against a stale `welcome.js` loads a module graph that fails outright. Relative imports inherit the versioned directory, so this needs no build step. |
| WS-10 | The hash is of the contents, so an unchanged deploy re-uses the directory and nothing is re-downloaded, and `mirror --delete` removes the previous one. |
| WS-11 | `.htaccess` marks `.php` no-cache — the page naming the assets must never outlive them — and denies `asset-base.php`, which is data for `index.php` rather than a page. |
| WS-12 | `skill/` is deployed with the private half, so the KONVO critique pass is readable by PHP and not by URL. |
| WS-14 | `deploy.sh` can name a critique provider and model. **Never a key**: writing one into a generated `.htaccess` would put a secret in a file this script uploads and a misconfigured server could serve. |
| WS-13 | `fonts/` and `hands.css` stay *outside* the versioned asset tree. A stylesheet moved into `v/<hash>/css/` resolves its `url()` from three folders deep rather than one, so a font path that is right in the repository is a 404 on the deployed build — and only there. It also keeps 1.4MB of typefaces out of every deploy that changes a line of JavaScript; the versioned directory exists for the module graph, and a font has no imports to break. |
| WS-8 | Whether or not there is a password, the deployment still contains itself: the classes, the starter documents, and every document live above the document root, `.htaccess` refuses `.md` files and directory listings under the served folder, and the workspace boundary ([§5](#5-the-workspace)) is enforced on every request. An open install can be edited by anyone; it still cannot be read *around*. |

### Tests

| Command | Covers |
| --- | --- |
| Open `/tests/` in a browser | The full client suite, including the DOM tests. Needs only PHP. |
| Open `/tests/keystroke-cost.php` | Not a test: what one keystroke costs, on documents of 2,200, 11,000 and 55,000 lines. `?full=1` rebuilds the whole model and the whole DOM per keystroke instead, so a change to the drawing can be measured against what it replaced. The suite counts work rather than timing it, because a clock measures the machine it runs on; this is where a number comes from. It builds every source fresh inside the timer on purpose — deriving each one from the previous flattens it early and quietly understates the result, which the comment there explains. |
| `node Web/tests/run.mjs` | The same client suites minus the DOM ones, plus the rules-conformance suite, which reads the `.rules` files and so cannot run in the browser. Node is optional and used only for a fast terminal loop. |
| `php Web/tests/php/run.php` | Workspace path safety, document read/write, file tree, file management, image import and its content validation, and how settings are read from the environment. |
| `Web/firebase/run-rules-checks.sh` | The security rules, evaluated by Firebase's own engine in the emulators ([WY-17](#tests)). Needs a JDK and the Firebase CLI, so it is not part of the suite. |
| `Web/firebase/run-cloud-checks.sh` | The real cloud store against a real Firestore, and against the in-memory double the suite runs on ([WY-19](#tests)). Same requirements. |
| `node Web/tools/check-firebase-sdk.mjs` | Every symbol the app imports from the pinned Firebase build is actually exported by it. Needs the network, so it is not part of the suite; run it after changing `FIREBASE_VERSION`. |

| ID | Requirement |
| --- | --- |
| WY-1 | The client suites are the source of truth for the ported core and run in the browser, so the environment under test is the one that ships. |
| WY-2 | The browser page and the node runner import the same list of modules, so they cannot disagree about what "the test suite" is. Two lists are environment-specific and named as such: the DOM tests need a browser, and the rules-conformance tests need to read files from the repository. |
| WY-3 | The PHP suite runs without PHPUnit or any other dependency. |
| WY-4 | Path-traversal, symlink-escape, invalid-UTF-8, mislabeled-image, and scriptable-SVG rejection are covered by tests, not just by inspection. |
| WY-5 | The DOM tests assert the invariant everything else rests on: each surface's text equals the model's text exactly, and every character offset round-trips through the DOM. |
| WY-6 | The environment lookup is tested against `$_SERVER` as well as `getenv`, because that difference is invisible locally and breaks a deployment. |
| WY-7 | File management is covered by tests that assert what must *not* happen: renaming or deleting a symlink leaves its target alone, a folder cannot be moved into itself, nothing is overwritten, and the workspace root cannot be renamed or deleted. |
| WY-10 | Gesture locking is verified by performing the gesture, not by reading a property, and always against a control: the same synthesized 2.5× pinch and horizontal drag must leave mobile at scale 1 and offset 0 *and* must still zoom and pan the desktop layout. Without the control case a harness that silently fails to dispatch anything looks like a pass. |
| WY-9 | Layout regressions are checked by measuring geometry, not by reading the DOM: the last block of a scrolled-to-the-end document must sit above the pane's bottom edge, in every editor mode and both layouts. Assertions on structure alone passed while a bar covered the text. |
| WY-8 | The saved-for-later list is pure list arithmetic in its own module, so ticking an already-ticked box, a rename, a delete, and a hand-edited `localStorage` value are all covered by unit tests rather than by clicking. |
| WY-12 | Every branch that can lose work is mutation-tested, not merely covered: the guard is removed, the suite must go red, and the guard is put back. Thirteen mutants across the live-update path — adopting over unsaved edits, dropping the echo check, recording the wrong text as saved, forgetting to claim a watcher slot — are each killed by a named test, and a no-op mutant is included to prove the harness can still report a survivor. |
| WY-13 | The live-update tests run against an in-memory Firestore whose watchers behave like the real ones, delivering current contents the moment a listener attaches. That attach snapshot is the source of the only two hazards found in this feature, so a double that skipped it would have hidden both. |
| WY-11 | Touch behaviour is verified by tapping, never by calling `element.click()`. A programmatic click invokes the handler directly and passes whether or not a real tap ever reaches it, which is how every button in the mobile layout came to be dead while every assertion passed. The check that a control does not cancel the events a tap depends on is a unit test, because `dispatchEvent` produces untrusted events that never synthesize a click and so cannot reproduce the failure in a DOM test. |
| WY-14 | The pinned Firebase build is checked against the symbols the app imports from it, by `Web/tools/check-firebase-sdk.mjs`. This is the one failure the suite structurally cannot reach: every cloud test runs against an in-memory double, deliberately, so the real SDK is never loaded and a symbol it stopped exporting would pass everything and break only in a browser after signing in. The symbol list is read out of `app/cloud/` rather than written down, so it cannot drift from what the app does — 23 symbols across auth, Firestore, and Storage at the time of writing. Mutation tested: adding an import the SDK does not export makes it fail. |
| WY-15 | **The in-memory Firestore refuses what the published rules refuse**, so every write in every test is checked against them rather than only against what the client needs. Before the rules were published any write passed, which meant a write the server would reject could pass the entire suite — and the rules were published against code that was already written and already tested. Mutation tested: dropping `parent` from a folder write turns 10 tests red, and renaming the `asset` type to one the rules do not list turns 7 red. |
| WY-16 | **The transcription of the rules is checked against the rules files themselves**, because a transcription that drifts from its source reports conformance that is no longer being checked. The type list, the required fields, both size limits, the image-size *comparison operator*, and the deny-by-default catch-all are all read out of `Web/firebase/*.rules` at test time. Mutation tested: changing the text limit, loosening the image comparison to `<=`, or opening the catch-all each turns the suite red. |
| WY-17 | **The rules are also evaluated, not only transcribed.** [WY-16](#tests) checks that the numbers in `Web/firebase/*.rules` still match the client's; it cannot check whether a rule does what it says. `Web/firebase/run-rules-checks.sh` starts the Firestore, Storage and Auth emulators and puts 29 checks through Firebase's own rules engine over plain HTTP — no test library and no Firebase SDK, so the no-dependencies rule ([WY-3](#tests)) still holds. It covers ownership in both directions, every required field, every accepted and rejected node type, both deny-by-default catch-alls, and each of the three limits *from both sides of its edge*, which is the class of defect a transcription cannot reach. Mutation tested: thirteen mutants — loosening a `<` to `<=` in any of the three limits, dropping an ownership clause, removing the type allow-list, narrowing `create, update` to `create`, and opening either catch-all — are each killed, against a green control. |
| WY-18 | The rule checks sign in through the **Auth emulator**, which issues ID tokens to anyone that asks. This is the whole reason they exist: the live project has only the Google provider enabled ([WR-20](#setup-steps-that-cannot-be-done-from-this-repository)), so a script cannot obtain a token for it, and for several revisions that was recorded here as making the rules unverifiable. It made them unverifiable *against the live project*. The emulators run the same engine on the same files under a `demo-` project id, which the CLI never takes to the network. |
| WY-19 | **The in-memory double is checked against a real Firestore.** Every cloud test runs against `support/memory-store.js`, deliberately — it is what makes the backend's decisions testable offline. The cost is that those tests are worth exactly what the double's resemblance to Firestore is worth, and nothing measured it. `Web/firebase/run-cloud-checks.sh` puts the same sequences through the double and through the shipped `firestore-store.js` against an emulated Firestore, and compares. It also covers what only a real Firestore has: that the range query in `subtreeOf` genuinely over-matches, so its filter is load-bearing rather than decoration; that a batch is refused whole when one write in it breaks the rules, which is what the create-before-delete ordering rests on; and that a multi-batch commit loses nothing. Thirteen checks, four mutants killed, with a no-op mutant surviving to prove the harness can still report one. |
| WY-20 | **Live updates are verified between two independent clients.** `watchChildren` and `watchNode` had only ever run against a double that announces changes synchronously from the object that stored them, which is not evidence that anything is delivered. The checks open a second Firebase app with its own Firestore instance and its own cache, signed in as the same account, so a write through it reaches the first client the way a phone reaches a laptop — through the server. Attach snapshot, a new document, an edit, and a deletion are each waited for. This closes the gap [§11b](#what-has-not-been-verified) recorded as unverifiable. |
| WY-21 | The app imports Firebase from a pinned CDN URL, which node will not resolve, so the checks map that one prefix onto a fetched copy with a resolve hook (`sdk-boot.mjs`) rather than changing the app or reimplementing its loader. The app's own modules are what run, including `loadFirebase`'s caching and `openFirestore`'s fallback when persistence is unavailable — which in node it always is, so [WR-25](#working-offline)'s fallback is exercised on every run rather than only reasoned about. |
| WY-22 | **The stylesheet is checked against the markup it styles.** `tests/stylesheet.test.js` reads `app.css`, `themes.css`, and `index.php` and fails when they stop agreeing. Every `var(--me-*)` written without a fallback must be defined somewhere — in a theme, in `app.css`, or by `setProperty` in the app — because an undefined one is not a warning but an invalid declaration. And anything the app hides through the `hidden` attribute must not have a class that sets a `display`, unless the class also carries an explicit `[hidden] { display: none }`; `hidden` is only a UA-stylesheet rule and any author rule beats it. Elements built in JavaScript are covered by pairing a `x.className =` with an `x.hidden =` on the same receiver, which is how every builder here is written. |
| WY-24 | **The critique's ported logic is tested against the same expectations as the Swift.** Forty JavaScript tests over the decoder, the anchoring, the score, the ordering and the anchor tracking, and nineteen PHP tests over the prompt, the skill extraction, each provider's envelope, and what `describe` is allowed to reveal. The ones that matter most are the ones about failure, because these fail quietly: a brace inside a quoted passage must not end the JSON object early, an exact match must beat a relaxed one, an edit *at* the end of a marked passage must not drag the mark over what follows, and a resolution must be keyed by what a finding says rather than by its identity or every re-run resurrects every dismissal. |
| WY-25 | **What the tests could not have caught was caught by running it.** Three faults, all of them invisible to a unit test and two of them invisible locally: the View menu reads `critique.isVisible` while it is being *built*, so a rail declared later in the module put the whole app in the temporal dead zone and the page rendered blank; `curl_close()` is deprecated in PHP 8.5 and the notice is printed before the JSON body, so any host with `display_errors` on would have failed every critique with a parse error on a reply that was perfectly good; and the deploy moves stylesheets three folders deeper than the repository puts them, so the `url()` in eight `@font-face` rules would have 404'd on the live site and nowhere else. The end-to-end run used `MDE_CRITIQUE_BASE_URL` against a stand-in model, which is why it cost nothing to do. |
| WY-23 | **A full-window layer that paints must start hidden in the markup.** The narrow rule that would have caught the 28% dim: a class that is `position: fixed`/`absolute`, `inset: 0`, and carries a non-transparent background is the shape of element that covers everything, so the element wearing it has to be written with `hidden` rather than left for the code to switch off later. All four guards were mutation-checked by reintroducing the real bugs — the missing attribute, the missing override, the undefined variable, and the explorer rejoining the flow — with a green control either side. |

---

## 16. Release history

| Change | What shipped |
| --- | --- |
| Humanish | The editor is now called **Humanish**, and the published build lives at <https://www.kirupa.com/humanish/> (`public_html/humanish`), with <https://www.kirupa.com/markdown/> redirecting cleanly via HTTP 301. |
| Joining a line leaves its markers hidden | Pressing ⌫ on the blank line between a block quote and the paragraph under it wrote `## ` into the quote, as text: the blank line was an empty heading, and the edit removed only the line break in front of its hidden marker. Reported on the Mac; this build mapped edits the same way and had the same fault, and cutting a whole heading line left its `## ` on the line below here too. Removing a line break now takes the heading or quote marker of the line it joins, and deleting whole lines takes their own, by a port of the Mac's rule that a new contract fixture holds the two to ([WE-18](#82-the-rendered-view)). The surface now places an edit at the caret whichever way it reads one, as it already did when reading the whole surface, because a diff alone cannot tell ⌫ on a blank line from ⌫ at the start of the line below, and only the caret says which line the writer meant. 18 new tests; 508 pass in Node and 523 in the browser. |
| A score that means what it says, here too | This build's critique score is ported from the Mac's, and the Mac's rule changed after the port ([I-274 to I-276](../macOS/README.md#10a-ai-assisted-critique)). So this build was still scoring by the rule the Mac had dropped, and dismissing every note printed **100 · Ready**. Now only **Done** clears a note. A dismissed note still counts, and so does each problem the summary lists, at the weight of a low note ([WA-6](#11c-ai-assisted-critique)). A hundred reached by marking notes Done, or over a draft changed since, reads **Looks ready**, and a **Critique again** button under the score offers the run that would confirm it ([WA-35](#11c-ai-assisted-critique)). The line under the score says why the number is what it is ([WA-36](#11c-ai-assisted-critique)). A fresh critique reopens a Done note it raises again ([WA-37](#11c-ai-assisted-critique)), and Done's tooltip now says *The next critique checks it.* instead of promising the note will not be raised again. The prompt asks for *up to* three problems, not two or three, and for none when nothing holds the draft back. With none listed, the overall read stands alone instead of sitting under WHAT DOESN'T WORK ([WA-38](#11c-ai-assisted-critique)). Running it in a browser found that an edit which made a critique stale without moving a mark did not redraw the rail, so a clean critique's *Ready* outlived the draft it described ([WA-9](#11c-ai-assisted-critique)). [WA-39](#deliberate-differences-from-the-mac) lists what else the Mac's critique has gained that this one has not. 9 new tests; putting back the old rule and the old carry-over turns 3 of them red. All 496 tests in `node Web/tests/run.mjs` and all 505 on the browser page pass. 1 new PHP test; all 95 pass. |
| A quote with one bar | A block quote of several lines is drawn with **one bar down its left** instead of a dash beside every line ([WT-21](#12-themes-typography-and-layout)). Every `>` line is a block of its own, and the gap between two blocks was a margin, which the quote's border does not cross; between two quoted lines it is padding now. Measured in headless Chrome, three 18px dashes 7px apart became one 68px bar, over the same 68px the lines spanned before, so nothing moved. The macOS build draws the same bar, which it had not drawn at all ([Y-4 in the macOS PRD](../macOS/README.md#132-block-layout)), and the [Contract](../Contract/README.md#a-block-quote-has-one-bar) now says what every build has to match. The Contract also records two things the macOS build now does and this one does not yet: a word count with a reading time, and an unsaved draft named by its title. 1 new test, which fails against the old stylesheet; all 487 tests in `node Web/tests/run.mjs` pass. |
| The kirupa mark, and just the name | The landing screen shows the app icon and the app's name, and nothing else; the tagline under the name is gone. The icon is `icon.svg`, the same file as the favicon, so the tab and the landing screen cannot disagree, and it replaces a hand-drawn inline SVG that had been collapsing to 5px tall. `icon.svg` is now generated by `../macOS/Scripts/make-icons.swift` from the same artwork and placement as the Mac and iOS icons. The welcome card is 600px tall, up from 560, to make room for a real icon. See [WV-9 to WV-11](#6-welcome-screen) and [WB-11](#12a-mobile-layout). |
| Formatting that leaves code alone | The inline styles and the link command do nothing inside a fenced block or a code span, where Markdown is literal and bold could only write asterisks into the code, and their toolbar and mobile-bar buttons **grey out** there. A block quote is prose and formats as before. The check reads the live model's spans at the selection's two ends, and the commands are handed the same model, so neither a caret move nor ⌘B parses the document ([WF-13 to WF-15](#9-markdown-language-support-and-formatting)). |
| A selection that stops where it stops, and a popover that holds still | Selection bars in the rendered pane are **slightly less round** — a little over a fifth of the line height, at most 6px, down from a third and 8px — and their hard ends stand **exactly on the carets** either side of the selection instead of 2px past them, so a selection ending at "in\|line" no longer shades the "l" ([WT-20](#12-themes-typography-and-layout)). Dragging the Customize Theme **Size** slider no longer makes the popover jitter and widen. It was sized to its preview, so a larger size widened it, which moved the slider under the pointer and changed the size back; it is now a fixed 316px and the preview wraps ([WT-19](#12-themes-typography-and-layout)). Verified in headless Chrome with real mouse drags from 75% to 150% and back, in four faces: across 198 samples a drag, the popover's width and position and the slider's never moved, and the value only rose, then only fell. The old stylesheet, dragged the same way, took three to five widths a drag, and in Gloria Hallelujah the value moved against the drag. The bars' hard ends measured within 1/64px of their carets at 100%, and at 150% in Gloria Hallelujah. 3 new tests; all 461 web tests pass. |
| A size for every hand, and a selection that flows | Customize Theme has a **Size** slider under Font, 75% to 150%, which scales the rendered page's type, spacing and indents together ([WT-19](#12-themes-typography-and-layout)). Selected text in the rendered pane is drawn as **rounded bars fitted to the words**, each fading out past its line's end and the next fading in, so only the true start and end have hard edges; away from the focus it takes a quieter tint ([WT-20](#12-themes-typography-and-layout)). `themes.css` was regenerated, and its diff is one new variable in each of its 17 blocks. Verified in headless Chrome: the slider's range, steps, label and preview; the page at 150% (22.5px body, 45px heading, 30.6px bars); selections across soft wraps, a paragraph break, an empty line, bold, italic and inline code on one line, a code block and a picture, in Blue Light and Blue Dark, active and not — every text bar one line tall and no sideways scrolling; the bars moving with the text when the pane scrolls; and the browser's own selection returning on a touch screen and the overlay coming back without a reload. 26 new tests; all 458 web tests pass. |
| A selection you can read through | Selecting text laid the theme's full accent behind it and recolored the words black or white — in Blue Dark, black on `#518ac1`. Selection is now a pale, translucent tint of the accent and the words keep their own colors ([WT-18](#12-themes-typography-and-layout)); the Customize Theme preview's **Selected text** chip shows the same tint. Tree rows, menus and radio buttons are unchanged. `themes.css` was regenerated, and its diff is one new variable in each of its 17 blocks. Verified in headless Chrome: the computed `::selection` background is the new value, and a selection across body text, a link, inline code and a code block keeps its colors in Blue Dark, Brown Light and Black Light. All 432 web tests pass. |
| Two found hands, and no phantom faces | QE Dave Mergens and QE Julian Dean join the font menus wherever the browser can draw them. They are never served, because their licence forbids it ([WT-17](#12-themes-typography-and-layout)). Checking for them showed the old check was wrong for every face the app does not serve. It said yes to a family that does not exist, so a machine without Noteworthy was offered Noteworthy. The check now measures instead. Verified in Chrome with the fonts installed: both are offered, and a document set in QE Julian Dean is drawn in it at 1.57. In Safari's engine, which hides installed fonts from pages, a made-up family and both QE faces are correctly left out, while Noteworthy is still offered. 2 new tests. |
| Set the page in any of the critique's hands | Customize Theme has a **Font** menu with the same thirteen faces as the critique's hand menu, which now reads the same catalog rather than its own copy ([WT-16](#12-themes-typography-and-layout)). The page and the notes remain separate choices. Verified in a browser: the menu lists all thirteen, grouped; the preview follows the draft while the page waits for Apply; and after Apply a document is set in Patrick Hand at its optical size, with drawn bold and italic and its code still monospaced. 5 new tests. |
| A bold word you can break in half | Pressing Return in the middle of a bold word showed `**` in the rendered view, because emphasis is matched within a line and the break left the markers unpaired on both sides. They are closed before the break and reopened after it now, with the markers the document actually wrote — `_italic_` and `*italic*` are the same style, and swapping one for the other crosses the pair. A break at the edge of a run steps outside its markers rather than writing `****`, and a break at a space takes the space with it, since emphasis will not close after whitespace. The port is checked against all 451 committed `insertNewline` contract cases ([WE-17](#82-the-rendered-view)). |
| Firebase put away | Cloud storage is behind one flag and the flag is off ([§11b](#11b-cloud-storage-and-accounts)). The path is written and tested against an emulated Firestore, and the two console steps it needs are still outstanding — so it offered a door that did not open, and charged every visitor a Firebase SDK download from a CDN to find out. The flag is read before anything loads, so a disabled cloud now makes **zero** third-party requests, measured on screen rather than assumed. The welcome screen shows one option rather than a list of one, and keeps the reachability warning, which is the half that matters and is about the option that is left ([WR-41](#why-it-is-hidden)). The File menu loses both items rather than showing them disabled, and the status-bar indicator is hidden in the markup rather than by script. `storageChoices` takes the flag as a parameter defaulting to itself, so the switched-on shape stays under test — a hidden feature whose tests were deleted is a feature that comes back broken ([WR-44](#why-it-is-hidden)). |
| Bring your own key, and one view | Two changes the critique made necessary. The API key is now the **reader's**, entered in the app and kept in their browser rather than held by the server ([§Whose key](#whose-key)). A page open to anyone that critiques on the owner's key is a page whose running cost is set by whoever visits, and the failure is quiet and somebody else's until the bill arrives. The key still travels through the server, because two of the three providers refuse a cross-origin request outright, but it is spent and forgotten — not stored, not logged. The trade is written down rather than implied: `localStorage` is readable by any script on this origin, which is the least-bad option a page has ([WA-30](#whose-key)). A server key is still possible for a private install, behind an explicit `MDE_CRITIQUE_ALLOW_SERVER_KEY`, because a host with `OPENAI_API_KEY` already set for something else would otherwise opt in by accident ([WA-17](#whose-key)). And the provider and model are validated server-side, since a model name is otherwise a string from a page that ends up inside a request URL ([WA-32](#whose-key)). Separately, and following the Mac, there is now **one view** ([§8.1](#81-one-view)). Side by Side, the Markdown pane, the divider, the scroll link, the selection mirror, the three toolbar icons, `⌃⌘1`/`⌃⌘2`/`⌃⌘3` and `source-renderer.js` are all gone. A rendered view that is genuinely editable makes a second pane showing the same document a second place to look rather than a second thing to see. |
| The critique rail, on the web | The macOS build's AI assisted critique, brought over whole: a rail of notes down the right-hand side, each shaded onto the passage it is about, with a decaying score, Done and Dismiss, and thirteen hands to write in ([§11c](#11c-ai-assisted-critique)). The pure logic is ported line by line from the Swift and tested against the same expectations — the decoder, the anchoring, the score, the ordering and the anchor tracking, forty tests. Two things had to be decided rather than copied. The **key is the server's**, because a browser cannot hold a secret, which means whoever can reach the app can spend the key behind it and the PRD says so ([WA-14](#whose-key), [WA-15](#whose-key)); and the **skill is vendored and deployed** rather than pulled, because a web server has no checkout to pull into, so the version panel names the commit that actually went out instead of implying it is current ([WA-21](#the-konvo-skill), [WA-22](#the-konvo-skill)). The shading is painted with the CSS Custom Highlight API: both surfaces are `contenteditable`, so wrapping a passage in a `<mark>` would move every offset after it and land in the undo stack as though the author had typed it ([WA-25](#deliberate-differences-from-the-mac)). Running it end to end against a stand-in model found three faults no unit test would have: the View menu reads the rail's state *while it is being built*, so a rail declared further down the module left the whole app blank; `curl_close()` is deprecated in PHP 8.5 and its notice is printed **before** the JSON body, so a host with `display_errors` on would have failed every request with a parse error; and a stylesheet moved into `v/<hash>/` resolves `url()` from three folders deep instead of one, so the eight typefaces would have 404'd on the deployed build and only there — the faces now live in their own unversioned `hands.css` ([WA-11](#11c-ai-assisted-critique)). Run for real against kirupa.com afterwards, which found three more things. A 5xx status was the wrong way to carry an application error: **Cloudflare replaces a 5xx body from the origin with its own page**, so a carefully worded explanation of a bad key arrived as the string `error code: 502` — an app promising that nothing fails silently cannot use a status whose body is thrown away in transit, so these are 424 now ([WA-13](#11c-ai-assisted-critique)). The Gemini models the app has been offering since the feature shipped had been **retired**, which the API reports as `is not found`, reading like a typo rather than a model that no longer exists; fixed in the shared provider so all three builds moved together ([WA-29](#whose-key)). And the live keys tell their own story: OpenAI's is rejected, Anthropic's account is out of credit, and Gemini answers — so [§What has been verified](#what-has-been-verified) says which of the three has actually written a critique. |
| Give a picture the run of the page | The page is now wider than the column the text is set in, and a picture may spread up to 100px into the margin on each side while prose stays at the column ([WI-26](#10-images-and-assets)…[WI-29](#10-images-and-assets)). Matches the Mac, including the arithmetic. Measured in a real browser: a 842px picture in a 652px column overhung 95px each side with both centres at 732. Building it turned up a fault a unit test could not have: the ceiling was read from a custom property, and `getComputedStyle` hands those back unresolved, so `clamp( 0px, (100vw - 700px) / 2, 100px )` parsed as `NaN` and the ceiling silently collapsed to the column. |
| A calmer page | Four changes with one aim: put the document on its own. A selected image now has four corner drag handles and resizes proportionally from any of them, as one undo step rather than one per pointer move ([WI-22](#10-images-and-assets)). The explorer starts closed and floats over the document instead of taking part in the layout, so opening it no longer shoves the text sideways, and the rendered measure is centered on the page rather than in whatever the explorer leaves over ([WT-13](#12-themes-typography-and-layout), [WT-15](#12-themes-typography-and-layout)). The menu bar, toolbar, and status bar gave up their tinted bands and group rules for the page's own background ([WT-14](#12-themes-typography-and-layout)). Writing the styles turned up two bugs that had been shipping unnoticed. `#alertLayer` — fixed, inset 0, `rgb(0 0 0 / 0.28)`, the dimming behind a dialog — was written into the markup **without** the `hidden` attribute, and the dialog code only ever *unsets* it, so every page load was dimmed 28% until some dialog happened to open and close; a theme claiming `#ffffff` measured `rgb(184, 184, 184)` on screen, which is exactly 255 × 0.72. And `--me-border` and `--me-text` were used six times but defined nowhere, which does not warn — an undefined custom property makes the whole declaration invalid, so those borders were `currentColor` and that background was transparent. Neither is the kind of bug a behavioural test can see, so both are now guarded by reading the files ([WY-22](#tests), [WY-23](#tests)), and the handles by real trusted pointer input, since a synthetic event never exercises pointer capture. |
| Notice a change made outside this browser | Two gaps closed. Local storage pushes nothing at all by design ([WC-7](#live-updates)), so a document edited on the server's disk while it was open here went unnoticed until the next save quietly overwrote it; the open document is now re-read whenever the tab comes back to the front ([WC-9](#live-updates)) — one request per return, not the polling WC-7 rejected — which also covers cloud tabs the browser suspended in the background. And a revision that arrived while there were unsaved edits was announced in a status flash and then dropped, though this browser held the only copy of it; it is now kept and offered in a bar above the document, **Show Newest** or **Keep Mine** ([WC-10](#live-updates)). The tab-return trigger is injectable so `live.js` stays free of the DOM and testable under node; seven tests, mutation-checked (removing the trigger turns three red). |
| The server workspace is a fallback, not the default | A visitor who has never chosen is asked Firebase before the server's workspace is used at all, so someone already signed in lands in their own documents rather than in one every other visitor can edit ([WR-8a](#11b-cloud-storage-and-accounts)). Until a choice exists the welcome screen is shown even with **Show this window at launch** off ([WR-8b](#11b-cloud-storage-and-accounts)). This also fixes a wrong warning: *"Shared by everyone who visits this address"* was written on the branch for **cloud** being in use, so the only people who ever saw it were the ones it was not about, while everyone in the shared workspace read *"Kept on the machine serving this page"*. The copy is now a pure function of the option rather than of the selection, with eight mutants killed against a no-op control, and the mutant that survived under node — `rememberedMode()` reads `window.localStorage` — is killed by three browser tests instead. |
| Cloud path run against a real Firestore | The store, the queries, batch atomicity and live updates now run against an emulated Firestore, and the in-memory double the whole suite depends on is compared against it ([WY-19](#tests), [WY-20](#tests)). Live delivery is tested between two independent clients, which is the two-device case that had never been exercised. Four mutants killed against a no-op control. Two survivors on the first sweep were both real findings: a local write reaches a listener **not at all** — there is no second, confirmed snapshot, so a check allowing one passed whether the echo skip worked or not — and the emulator does not enforce Firestore's 500-write batch limit, so that constant is guarded by reading it out of the source instead. The comment in `firestore-store.js` describing a later server echo was wrong and has been corrected. |
| Rules evaluated, not just transcribed | The security rules are now checked by Firebase's own engine in the emulators — 29 checks, thirteen mutants killed ([WY-17](#tests), `Web/firebase/run-rules-checks.sh`). This had been recorded for several revisions as impossible because the live project allows only Google sign-in; the Auth emulator hands out tokens freely, and the constraint had never actually been tested. It found one thing no transcription could: past Firestore's 1,048,487-byte property cap a write fails `400 INVALID_ARGUMENT` rather than `403`, and because the rules count *characters* it is the client's UTF-8 **byte** check that keeps documents out of that band ([Contract/README.md](../Contract/README.md#the-firestore-data-model)). |
| Remote images on the native builds | An image referenced by web address drew as a placeholder glyph on macOS and iOS, because only local files were ever loaded. Both now download and draw it. **The web build was never affected** — a browser loads `<img src>` itself — so nothing here changed, but the rules the native builds now follow are written down in [Contract/README.md](../Contract/README.md#drawing-an-image-held-at-a-web-address) so a fourth port does not repeat the bug. |
| Sized images and insert by address | Add Image now asks first: browse for a file, or paste a web address. A selected image can be given a width and a height that stay in proportion. A size is written as `<img …>` because GitHub renders `![alt](a.png =300x200)` as literal text — see [Contract/README.md](../Contract/README.md#how-an-image-carries-a-size) for the evidence. Shipped on all three builds in the same change; the shared core is byte-identical, so a document sized on a phone opens sized in a browser. |
| Rules published | The Firestore and Storage rules are live, so the database is no longer readable by anyone with the API key ([WR-19](#setup-steps-that-cannot-be-done-from-this-repository)). Publishing them made one latent disagreement reachable: the web build accepted an image of exactly 10 MB that the rule refuses ([WR-31](#11b-cloud-storage-and-accounts)). The in-memory Firestore now enforces the rules on every write, and the transcription is checked against the rules files themselves ([WY-15](#tests), [WY-16](#tests)). |
| Cloud images | The Storage bucket now exists, and the two things that would have stopped an image reaching it were fixed before it was tried: an upload with no content type was refused by the Storage rule ([WR-29](#11b-cloud-storage-and-accounts)), and the image URL cache did not follow a rename, so images in a renamed document broke until reload ([WR-30](#11b-cloud-storage-and-accounts)). Both apply to the native builds too. |
| Offline images | Cloud Storage objects are now cached on the device and served as `blob:` URLs, so a cloud document opened once renders completely with no network ([WR-26](#working-offline)…[WR-38](#working-offline)). Firestore's persistent cache covers Firestore documents only, so before this an offline document opened with its text intact and every picture broken. Entries are keyed by download URL, which makes a rename free and makes a replaced image miss rather than serve the picture it replaced. Verified in a real browser with real IndexedDB, the network cut by the debugger, and a control proving it was actually off. |
| Offline cloud documents | Firestore now opens with a persistent, multi-tab local cache, so a cloud workspace survives a reload with no network and edits made offline are queued and sent on reconnect ([§Working offline](#working-offline)). Firestore was previously opened the default way, which caches only for the life of the tab. Images are not covered ([WR-26](#working-offline)), and the two console steps blocking the rest of the cloud path were re-checked and are still outstanding ([WR-19](#setup-steps-that-cannot-be-done-from-this-repository), [WR-22](#setup-steps-that-cannot-be-done-from-this-repository)). |
| Live updates | Cloud documents and folders now update on every signed-in device as they change, without a reload, and unsaved edits are never overwritten by one ([§Live updates](#live-updates)). The mode switch became icons ([WE-15](#8-editing-modes)), and a new document now starts on a Heading 1 line ([WD-1](#7-document-lifecycle)). |
| Touch controls | Every button in the mobile layout was inert on a real phone — header icons, popovers, formatting, image insert — and the formatting row could not be scrolled by dragging along it. The buttons cancelled `touchstart` to hold the editor's selection, which also suppresses the `click` a tap generates ([WB-28](#12a-mobile-layout), [WB-29](#12a-mobile-layout)). |
| Cloud storage | Documents can be stored in a Google account through Firebase Authentication and Firestore, chosen from the welcome screen or the File menu, with local files still the default and unchanged ([§11b](#11b-cloud-storage-and-accounts)). |
| Docked tools | The formatting bar moved from floating above the keyboard to the header's second row, where the platform's own bottom furniture cannot cover it ([WB-20](#12a-mobile-layout), [WB-26](#12a-mobile-layout)). |
| iOS zoom | Focusing any text under 16px made iOS Safari zoom the page in, which slid it sideways and pushed the formatting bar under the keyboard's controls. Nothing focusable is under 16px now ([WB-22](#12a-mobile-layout)). |
| Pinned viewport | Mobile no longer pans or zooms ([WB-17](#12a-mobile-layout)). |
| Document end | The last lines of a document sat under the formatting bar with no way to scroll to them ([WB-16](#12a-mobile-layout)). |
| Asset versioning | Deployed assets moved under `v/<hash>/` after a CDN cached one module and not another, breaking the live page ([WS-9](#15-run-deploy-and-test)). |
| Mobile layout | An arrangement with no menu bar: a top bar carrying Undo, the theme picker, and a save-for-later checkbox, a formatting bar, the explorer as a drawer, and a responsive welcome screen ([§12a](#12a-mobile-layout)). |
| Published build | A split layout for hosts that cannot repoint the document root, and `Web/deploy.sh` to publish over FTPS ([§15](#15-run-deploy-and-test)). |
| File management | A default `~/kirupaMarkdown` workspace, created and seeded on first run, plus create, rename, move, duplicate, and delete for files and folders from the sidebar ([§11a](#11a-managing-files-and-folders)). |
| Repository restructure | macOS and Web builds separated into `macOS/` and `Web/`. |
| Web build, initial release | The full editor: welcome screen, document lifecycle with autosave, three editing modes with a WYSIWYG rendered surface, every formatting command, image import from four sources, the file explorer, all sixteen themes, the menu bar and its shortcuts — on a PHP-only backend with no dependencies. |

---

## 17. Out of scope / not yet supported

Inherited from the macOS build:

- Tables, footnotes, definition lists, and other extended Markdown syntax
- Nested lists beyond a single level of markers
- Setext (underlined) headings
- Reference-style links and images
- Export to HTML, PDF, or anything else
- Spell checking beyond the browser's own
- Find and replace

Specific to the web build:

- Multiple documents open at once
- Undoing a file operation — delete is final ([WM-11](#11a-managing-files-and-folders))
- Moving files by dragging them out of, or into, the operating system's file manager
- Sharing a document, or any collaboration. Cloud storage is per-account and
  private to it ([§11b](#11b-cloud-storage-and-accounts))
- Collaborative editing. Cloud documents do update live on every signed-in
  device ([§Live updates](#live-updates)), but two people typing in the same
  document at the same moment are not merged: whole revisions replace whole
  revisions, and unsaved edits win over an arriving one until they are saved
  ([WC-2](#live-updates))
- Live updates for documents stored on the server. That is a deliberate
  limit of a PHP-only backend, not an oversight ([WC-7](#live-updates))
- Migrating documents between local and cloud storage. Switching mode changes
  which documents exist, it does not copy them ([WR-4](#11b-cloud-storage-and-accounts))
- Sign-in providers other than Google
- Offline use for documents stored **on the server**. The PHP backend needs the
  server to be reachable. Cloud documents *do* work offline once they have been
  opened on the device ([WR-23](#11b-cloud-storage-and-accounts))
- Pre-caching images the device has **not** opened. Image bytes are kept for
  offline use once a document has been opened ([WR-26](#11b-cloud-storage-and-accounts)),
  which is the same bargain Firestore's own cache strikes
  ([WR-24](#11b-cloud-storage-and-accounts)): the device holds what it has seen,
  not the whole account
- A native app shell for phones; the mobile layout ([§12a](#12a-mobile-layout))
  is the browser page rearranged, not a packaged app
- Syncing the saved-for-later list between devices — it lives in `localStorage`,
  so it is per-browser until there are accounts
- Enlarging the text on a phone. Pinning the viewport ([WB-17](#12a-mobile-layout))
  removes pinch zoom, and there is no in-app text size control to replace it, so
  the mobile build currently offers no way to make text bigger. Mobile body text
  is 16px rather than the desktop 15px ([WB-22](#12a-mobile-layout)), but that is
  a fixed floor set to stop iOS auto-zoom, not an adjustable size. Desktop Layout
  is the only workaround. A text size preference is the fix
