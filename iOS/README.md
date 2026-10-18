# Humanish for iOS — Product Requirements Document

A clean native iPhone and iPad writing space built with SwiftUI and UIKit,
sharing its Markdown engine, formatting commands, and palettes as **compiled
Swift source** with the [macOS build](../macOS/README.md).

**Status:** Living document.
**Bundle identifier:** `com.kirupa.markdown-editor`
**Platform:** iOS 17.0 or newer, iPhone and iPad (`TARGETED_DEVICE_FAMILY = 1,2`)
**Repository:** <https://github.com/kirupa/markdown-editor>

> **Maintenance rule:** every change that adds, removes, or alters a
> user-visible capability must update the matching requirement here in the same
> commit, and add a line to [Release history](#10-release-history).

---

## Table of contents

1. [Product summary](#1-product-summary)
2. [What is shared, and what is not](#2-what-is-shared-and-what-is-not)
3. [Document lifecycle](#3-document-lifecycle)
4. [Editing modes and adaptive layout](#4-editing-modes-and-adaptive-layout)
5. [Formatting](#5-formatting)
6. [Images](#6-images)
7. [Themes](#7-themes)
8. [Architecture](#8-architecture)
9. [Build, run, and test](#9-build-run-and-test)
10. [Release history](#10-release-history)
11. [Verification status](#11-verification-status)
12. [Out of scope / not yet supported](#12-out-of-scope--not-yet-supported)

---

## 1. Product summary

The same product as the macOS app, on a touch screen: **the Markdown source is
always the canonical document**, the rendered view is an editable projection of
it, and every keystroke resolves back to exact Markdown text on disk.

This is not a reimplementation. The parser, the range mapping, the formatting
transforms, the image importer, the type scale, and all sixteen palettes are
*the same Swift files* the Mac compiles, in a package both apps depend on.

---

## 2. What is shared, and what is not

The repository now has three builds and two kinds of sharing.

| Build | Relationship to the core | How it is kept correct |
| --- | --- | --- |
| macOS | Compiles `Shared/` | Directly — it is the same source |
| **iOS** | **Compiles `Shared/`** | **Directly — it is the same source** |
| Web | Hand port to ES modules | Differential testing against the compiled Swift |

| ID | Requirement |
| --- | --- |
| S-1 | Markdown parsing, range mapping, formatting commands, image import, text codec, and diffing live in `MarkdownEditorCore` and are compiled unchanged for both platforms. |
| S-2 | Palettes, type scale, and the attributed-string builders live in `MarkdownEditorUI`, written against `PlatformColor`/`PlatformFont` aliases that resolve to AppKit on macOS and UIKit on iOS. |
| S-3 | `MarkdownDocument` — the `FileDocument` conformance, UTF-8 and BOM handling, and the `net.daringfireball.markdown` type — is shared, so a document behaves identically on both platforms. |
| S-4 | `EditorViewMode` and its SF Symbols are shared, because which modes exist is a product decision rather than a platform one. |
| S-5 | Only the interface layer is per-platform: `macOS/Sources/MarkdownEditor` (AppKit) and `iOS/Sources/MarkdownEditorIOS` (UIKit). |

### 2.1 The colour finding

Sharing these files surfaced something worth recording. `NSColor.blended(withFraction:of:)`
— which the palettes use to derive tints — does **not** interpolate in sRGB. It
converts to Apple's *Generic RGB* space (different primaries, gamma 1.8), mixes
there, and converts back. Black blended halfway with white is sRGB **0.573**,
not 0.5.

UIKit has no equivalent method, so iOS needed one. A naive sRGB interpolation
was wrong by up to **46/255**.

| ID | Requirement |
| --- | --- |
| S-6 | `PlatformColorBlending` reproduces AppKit's Generic RGB blending on iOS with hand-derived conversion matrices, including AppKit's gamut clipping and its identity short-circuit at fraction 0. |
| S-7 | Every one of the 176 colours the app actually displays is within **1/255** of the AppKit result; the worst case across arbitrary palette blends is 5/255. This is asserted by test, not assumed. |
| S-8 | macOS continues to call AppKit directly. The portable path is used on iOS and, behind a test hook, to verify the two agree. |

This mattered beyond iOS: `Web/public/css/themes.css` is *generated* by
compiling `EditorColorTheme.swift`, so the web build ships AppKit's numbers too.
Moving the file was verified by regenerating that CSS and confirming it came out
byte-identical.

---

## 3. Document lifecycle

| ID | Requirement |
| --- | --- |
| ID-1 | The app is a SwiftUI `DocumentGroup`, so it gets the system document browser, Files and iCloud Drive integration, rename, duplicate, and move for free. |
| ID-2 | Opening, saving, and the unsaved-changes prompt are the standard system behaviours. There is no custom save path and no custom autosave timer — iOS saves through `UIDocument`. |
| ID-3 | Documents are read and written as UTF-8, preserving a byte-order mark if the file had one, by the shared `MarkdownTextCodec`. |
| ID-4 | `.md` and `.markdown` files open in the app from Files, Mail, and any share sheet, via an imported `net.daringfireball.markdown` type declaration. |
| ID-5 | `LSSupportsOpeningDocumentsInPlace` and `UIFileSharingEnabled` are set, so files are edited where they live rather than copied into the app. |
| ID-6 | A new document starts as an empty Heading 1, matching the macOS and web builds. |
| ID-48 | While a document is open the app watches its file and notices when something else on the device writes it — Files, another editor, an iCloud sync from another device. |
| ID-49 | The check is repeated whenever the app returns to the foreground. This is the case that matters most on iOS: a suspended app is not listening, so a change made while it was in the background produced no event for anybody. |
| ID-50 | With no unsaved edits the newer text is applied and a bar says so, clearing itself after a few seconds. The caret is carried over rather than reset. |
| ID-51 | With unsaved edits nothing is applied. A bar offers **Show Newest** and **Keep Mine**, and the text held behind Show Newest is the copy that arrived, so it stays reachable even if the system has since written this device's version over the file. |
| ID-52 | The same shared banner and the same decision logic as macOS. There is one set of rules about whose text wins, not one per platform. |
| ID-53 | **Not** supported here, unlike macOS: suspending saves while the question is unanswered. iOS saves through `UIDocument` (ID-2) and a view cannot hold that off, so on this build the system may write this device's version to the file first. Show Newest still works — see ID-51 — but the file may need saving again afterwards. |

---

## 4. Editing modes and adaptive layout

| ID | Requirement |
| --- | --- |
| ID-7 | Three modes exist, the same three as every other build: **Rich Text**, **Markdown**, and **Split**. |
| ID-8 | Split is offered only when the horizontal size class is `.regular` — an iPad, or an iPhone in landscape on the largest models. Two panes on a phone screen would be two unusable panes. |
| ID-9 | If the size class changes to compact while Split is showing, the mode falls back to Rich Text rather than leaving an unreadable layout. The stored preference is left alone, so sliding an iPad app back to a regular width returns to Split. |
| ID-10 | The mode switch uses the shared SF Symbols, on the trailing side of the navigation bar: a segmented control where all three modes fit, and a menu on a compact width. It never takes the centre, which belongs to the document title and its rename menu. |
| ID-10a | The chosen mode is remembered in `UserDefaults` under `EditorViewMode.storageKey`. A document browser builds a fresh editor for every file, so without this someone who works in Markdown source would be put back into the rendered view each time. |
| ID-11 | Editing the rendered view edits the Markdown. Surface edits are mapped back through `MarkdownRenderModel.sourceRange(for:)`, so Markdown the renderer does not display is preserved untouched. |
| ID-12 | The raw Markdown pane shows representative typography — real heading sizes, monospaced body — while preserving every source character and marker. |
| ID-13 | Smart quotes and smart dashes are disabled in both panes. iOS substitutes typographic characters by default, which would silently corrupt Markdown punctuation. |

---

## 5. Formatting

| ID | Requirement |
| --- | --- |
| ID-14 | A horizontally scrolling formatting bar sits directly below the navigation bar, in the same position on both idioms. |
| ID-15 | The bar offers the complete set — Heading 1/2/3 and Body; bold, italic, underline, strikethrough, inline code; bulleted, numbered, and task lists; quote, fenced code block, divider; link and image. **The set is identical on a phone and an iPad.** A smaller screen is not a reason to be given a less capable editor. |
| ID-16 | The bar scrolls rather than wrapping or collapsing into an overflow menu, so no command is more than a swipe away. |
| ID-17 | Every button calls `MarkdownFormatting`. Nothing about what "bold" means is decided in the iOS layer. |
| ID-18 | Commands toggle: applying bold to already-bold text removes it, the same detection the other builds use. |
| ID-19 | Link insertion prompts for a destination, defaulting to `https://`, and uses the current selection as the label. |
| ID-65 | **Inside code, the inline styles and the link button do nothing, and are greyed while the caret is there.** Markdown is inert in a fenced block and between a code span's backticks, so the only thing bold could write there is two asterisks into the writer's code. The refusal is `MarkdownFormatting`'s, shared with the other builds; the bar only asks `isAvailable(_:context:)`. A block quote is *not* code — bold in a quote is ordinary Markdown and is written. See [`Contract/README.md`](../Contract/README.md#inside-code-the-inline-commands-do-nothing). |
| ID-66 | The bar reads the caret's context from **the blocks the selection's two ends fall in**, never from a render of the whole document: it is computed in a view body, several times per keystroke. The answer is the one the whole document gives — see [`Contract/README.md`](../Contract/README.md#inside-code-the-inline-commands-do-nothing). |

The bar is docked, not floating. The web build learned this the hard way on a
real iPhone — a bottom bar fights the keyboard accessory row and the home
indicator, and `visualViewport` does not reliably report either. A native app
could place a bar in `.keyboard` toolbar placement, but that only exists while
the keyboard is up; docking it below the navigation bar means its position is
never a function of the keyboard, which is the property that makes it reliable.

---

## 6. Images

| ID | Requirement |
| --- | --- |
| ID-20 | Add Image first asks where the image comes from: **Choose Photo…** (`PhotosPicker`), **Choose File…** (`fileImporter`), or **Image Address…**. |
| ID-21 | Both routes go through the **same shared `MarkdownImageImporter`** the Mac uses, so the `<document-stem>.assets/` convention, collision handling (`photo-2.jpg`), percent-encoding, and alt-text escaping are identical and a folder written on one platform opens correctly on the other. |
| ID-22 | A photo-library asset is not a file on disk. Its bytes are written to a temporary file first, imported from there, and the temporary file is removed whether or not the import succeeded. |
| ID-23 | Files chosen through `fileImporter` are accessed inside a security-scoped resource, balanced with `stopAccessingSecurityScopedResource` even on the error path. |
| ID-24 | Adding an image to a document that has never been saved is refused with an explanation, because the assets folder location is derived from the document's location. |
| ID-25 | Every failure is surfaced in an alert. Nothing fails silently. |
| ID-26 | The reference is inserted at the caret by the shared, unit-tested `MarkdownTextInsertion`, which clamps a stale selection rather than trapping and places the caret in UTF-16 units. |
| ID-27 | `NSPhotoLibraryUsageDescription` explains that the photo is copied into a folder beside the document. |
| ID-41 | **Image Address…** takes a URL and inserts a reference to it. Nothing is copied and no assets folder is created, so it works in a document that has never been saved. An empty address, or the bare `https://` placeholder, inserts nothing. |
| ID-42 | An **Image Size** button beside Add Image opens a sheet for the image the caret is on. It is disabled — visible but greyed — whenever the caret is not on an image, so the toolbar does not reflow. |
| ID-43 | The sheet's Width and Height drive each other through the shared `MarkdownImageTag.proportionalSize`, so setting one derives the other from the image's own pixel dimensions and the picture keeps its shape. The number typed is always kept exactly. |
| ID-44 | The natural size comes from `UIImage` reading the file beside the document, or from the shared remote-image cache once an address has downloaded. Before an address has loaded there is nothing to measure, so both fields stay independent and the sheet says so rather than guessing. |
| ID-45 | **Use the image's own size** clears both, converting the reference back to plain `![alt](path)` Markdown. |
| ID-46 | The sheet is **driven by the caret**, and is no longer the only way to size a picture: ID-54 to ID-56 added tap-to-select, drag-to-resize and long-press-to-move. The sheet remains, because it is the only route that accepts an exact number and the only one reachable without touching the picture. The Markdown written is byte-identical across all three builds, whichever route wrote it. |
| ID-47 | An image held at an `http`/`https` address is drawn as the real picture, from the shared `RemoteImageStore` the Mac uses. On a cache miss the placeholder is drawn and one download starts; when it arrives the editor re-styles in place, keeping the selection. The store's rules are shared, so they hold identically here: http/https only, one attempt per address per launch, a 25 MB ceiling enforced while streaming, bytes that must decode as an image, and no eviction. |
| ID-54 | Tapping a picture **selects** it and shows a frame with four corner handles. There is no pointer on iOS, so nothing can be said with a cursor shape: the handles have to be visible as soon as the picture is touched, because they are the only thing saying it can be resized. |
| ID-55 | Dragging a corner **resizes** the picture proportionally, previewed live and committed as one undoable edit on release. The target is grown to `EditorImageGeometry.touchTarget` (44pt) rather than the pointer build's 33pt, and capped the same way so a small picture keeps a middle to take hold of — four fixed targets meet in the middle of anything narrow, and a picture that can be resized but never moved is a worse fault than a target that is hard to hit. |
| ID-56 | A **long press** picks a picture up, and dragging moves it. Deliberately not travel alone, as on macOS: a short drag on a touch screen is how the document is scrolled, so treating it as a move would make a document with pictures impossible to read. A rule marks the paragraph boundary it would land on, and a translucent copy follows the finger. |
| ID-57 | The overlay claims **only its handles**. Everything else — including the middle of the picture — reaches the text view underneath, so scrolling, the caret and text selection behave exactly as they did before it existed. The tap and long-press recognisers run alongside UITextView's own rather than replacing them. |
| ID-58 | The geometry and the text transform are **shared, not re-implemented**: `EditorImageGeometry.touchHitRect` / `touchCorner` for the targets, `MarkdownImageTag.proportionalSize` for the size, and `MarkdownFormatting.moveImage` for the edit. A picture resized or moved on a phone lands exactly where it lands on a Mac. |
| ID-59 | The overlay is sized to the text view's **`contentSize`**, not its `bounds`. A `UITextView` is a scroll view, so its subviews live in content coordinates while `bounds` is only what is on screen. Sizing it to `bounds` leaves every handle below the first screenful outside the overlay, and UIKit refuses hit tests outside a view's bounds — so those handles could be seen and never touched. It reads as "resize doesn't work", but only after scrolling. Guarded by a test that reads the source, since nothing else can see it. |
| ID-60 | The text view's own gesture recognisers are made to **wait for the long press to fail**. UITextView's long press opens the selection loupe and cancels ours the moment it recognises, so a picture could never be picked up: measured on a device, the delegate approved the touch and the action never fired. Because ours only accepts a touch that lands on a picture, ordinary text selection is untouched. |
| ID-61 | A **committed move clears the selection**. The overlay caches the picture's rect and refreshes it only on a tap or a resize, so a move — which relays the picture somewhere else — leaves that rect describing the space the picture has left. Observed on a device: the frame and handles stayed about fifty points below the picture, over the text. A move that finds no destination puts the frame back, because nothing changed. The next tap re-establishes the selection. |
| ID-62 | Only the **long press** refuses a touch that misses a picture. The tap must not, because the tap is what deselects: filtering it leaves a selected picture wearing its frame no matter where you tap next. Both halves are guarded by tests that read the source, since neither is visible to a unit test of the geometry. |
| ID-63 | A resize **stops at the width a line actually gets**. There is no page margin on a phone — the document is as wide as the screen — so unlike the Mac the ceiling is the column itself and there is no bleed to give. The ceiling still matters: past it TextKit compresses the picture into the line it has and carries on making it taller, so the picture is distorted with nothing to say so. Read from the text container rather than assumed, because it changes with rotation and with the size class. |
| ID-64 | **A picture is never drawn out of shape**, which mattered most here. A picture with no size of its own defaults to 560 points wide, and a phone's column is about 368 — so every such picture was drawn squashed. Measured on a device: a 1600x300 picture drew 384x107, where its own shape at that width is 384x72. It is now scaled down on both sides instead, and drew 367x68. Only what is drawn changes; the document is untouched, so the same file on a Mac still shows the larger picture. |

---

## 7. Themes

| ID | Requirement |
| --- | --- |
| ID-28 | The same sixteen themes as every other build: eight kirupa.com colours on an independent light/dark axis, from the shared `EditorColorTheme`. |
| ID-28a | The theme is stored under the *shared* `EditorThemeColor.storageKey` and `EditorAppearanceMode.storageKey`, not keys invented here, so a Mac and an iPhone agree on what a stored theme means. |
| ID-28b | A dark theme overrides the window's `overrideUserInterfaceStyle`, not just SwiftUI's `preferredColorScheme`. In a `DocumentGroup` the navigation bar and status bar belong to UIKit, so without this a dark theme on a light device left the title unreadable. |
| ID-29 | The picker is a sheet with an appearance control, a swatch grid, and a live preview showing heading, body, secondary text, and inline code. |
| ID-30 | The choice is an application preference persisted in `UserDefaults`, not a document property — matching macOS. |
| ID-31 | The chosen appearance drives `preferredColorScheme` and the accent colour drives `tint`, so system controls match the document. |
| ID-32 | The app icon is generated by `../macOS/Scripts/make-icons.swift`, the same generator the Mac and web icons come from, so every platform shares one mark and there is no design tool in the loop. The artwork is `../macOS/Packaging/Logo.svg` — the kirupa mark — on white. It is full-bleed and square, because iOS applies its own rounded mask. Regenerate with `make icons` from `../macOS`. |
| ID-67 | The mark is drawn at **0.51 of the square**, against 0.66 of the plate on the Mac. Tighter on purpose: the Mac's plate is already inset inside its canvas, while iOS rounds the corners off the artwork itself, so the same fraction would put the mark hard against the visible edge. |
| ID-68 | It is sized and centred by the mark's **round body**, as though the leaves were not there — see `macOS/README.md` P-9 and P-11. The leaves stick out of the body at one corner, so placing by the artwork's bounding box would lean every platform the same way at once. |

---

## 8. Architecture

```
Shared/                            One SwiftPM package, two platforms
├── Sources/MarkdownEditorCore/    Pure Foundation. No AppKit, no UIKit, no SwiftUI.
│   ├── MarkdownFormatting         Source-to-source formatting transforms
│   ├── MarkdownRenderModel        Parser + bidirectional range mapping
│   ├── MarkdownIncrementalRenderer
│   │                              Re-renders the blocks an edit reaches
│   ├── MarkdownImageImporter      Assets folder resolution, copying, referencing
│   ├── MarkdownTextInsertion      Caret-relative literal insertion
│   ├── MarkdownTextCodec          UTF-8 and BOM handling
│   ├── MarkdownTextDifference     Minimal-replacement diffing
│   ├── RecentDocumentsCatalog     Recent-document ordering and pruning
│   └── FileTreeScanner            Directory listing and ordering
└── Sources/MarkdownEditorUI/      Cross-platform presentation
    ├── PlatformTypes              AppKit/UIKit aliases; the colour blending
    ├── PlatformTextView           NSTextView and UITextView conformances
    ├── EditorColorTheme           Palettes and derived colours
    ├── MarkdownTypography         Shared type scale
    ├── RichMarkdownStyler         Attributes from the render model, for a
    │                              block or the whole document
    ├── MarkdownSourceStyler       Representative source typography
    ├── MarkdownDocument           FileDocument conformance
    └── EditorViewMode             The three modes and their symbols

iOS/Sources/MarkdownEditorIOS/     UIKit + SwiftUI, iOS only
├── MarkdownEditorIOSApp           DocumentGroup scene, persisted theme store
├── DocumentEditorView             Adaptive layout, image import, alerts
├── EditorController               View mode, selection, errors, revisions
├── MarkdownFormattingBar          The scrolling formatting bar
├── MarkdownRichTextEditor         Editable rendered pane (UIViewRepresentable)
├── MarkdownSourceTextEditor       Raw Markdown pane (UIViewRepresentable)
└── ThemePickerSheet               Theme UI
```

**Key design decisions**

1. *Share source, do not port.* A port needs differential testing forever; the
   same file compiled twice cannot drift.
2. *The document stays in `DocumentGroup`.* `EditorController` deliberately does
   **not** hold the text, so undo, autosave, and the close prompt keep working
   the way the system expects.
3. *Platform differences are named, not scattered.* Everything AppKit and UIKit
   disagree about is in `PlatformTypes.swift`.
4. *Logic lives outside the UI.* Anything testable without an app is in
   `MarkdownEditorCore`, which is why the insertion arithmetic was moved there.

---

## 9. Build, run, and test

### 9.1 With Xcode (recommended)

```bash
git clone https://github.com/kirupa/markdown-editor.git
open markdown-editor/iOS/MarkdownEditor.xcodeproj
```

Pick an iPhone or iPad simulator and press **⌘R**. The project references
`../Shared` as a local Swift package; there is nothing to resolve and no
third-party dependency to fetch. To run on a device, set your own team under
Signing & Capabilities.

### 9.2 Without Xcode

```bash
cd markdown-editor/iOS
./Scripts/build-app.sh
```

Produces an ad-hoc-signed `build/Humanish.app` for the iOS Simulator.

This path exists because `xcodebuild` and `simctl` refuse to run until Xcode's
licence has been accepted — which needs an administrator password — while
`swiftc` does not. The script compiles the shared package for the simulator
through a SwiftPM destination file, gathers its objects into a static library,
compiles the app sources against it, assembles the bundle, compiles the asset
catalog, and signs ad hoc.

`actool` needs Xcode's first-launch packages — the ones the licence prompt
installs — so on a machine where those are missing the asset catalog is skipped
and the script says so explicitly rather than producing a silently icon-less
app. Building through Xcode always compiles it.

It also copies any `<Package>_<Target>.bundle` the shared package emitted into
the bundle root, which is where `Bundle.module` looks on iOS — an app bundle
there is flat, with no `Contents/Resources`. Nothing declares `resources:`
today, so this copies nothing; see `macOS/README.md` §16 for why it is worth
having in advance. The Xcode project handles this itself, so this only matters
on the no-Xcode path.

| Variable | Default | Effect |
| --- | --- | --- |
| `MDE_XCODE` | `/Applications/Xcode.app/Contents/Developer` | Where to find the iOS SDK |
| `MDE_TOOLCHAIN` | `/Library/Developer/CommandLineTools` | Which Swift toolchain compiles |
| `MDE_ARCH` | host architecture | Simulator architecture |
| `IOS_DEPLOYMENT_TARGET` | `17.0` | Minimum iOS version |

Install and launch it with:

```bash
xcrun simctl install booted "build/Humanish.app"
xcrun simctl launch booted com.kirupa.markdown-editor
```

### 9.3 Tests

```bash
macOS/Scripts/run-tests.sh
```

348 tests in 26 suites. The suite covers the shared package, so it exercises
the iOS build's entire Markdown engine — the iOS layer above it is views.

Around one in six is property-based rather than example-based: they run
every formatting command over every selection of every document in the shared
corpus, and render and style every prefix and suffix of it, asserting that
ranges stay in bounds and never split an emoji rather than asserting specific
output. See `macOS/README.md` §16.2 for what each kind of test is for and
§16.3 for the two properties that are deliberately scoped.

| Suite | Tests | Covers |
| --- | --- | --- |
| Markdown formatting | 42 | Every inline and block transform, toggle-off, renumbering, continuation |
| Cloud workspace | 39 | Firestore tree reads, writes, moves, and the prefix filter a range query needs |
| Markdown render model | 31 | Block and inline parsing, boundaries, escapes, range mapping |
| Incremental rendering | 16 | A block-at-a-time render equals a full one — text, spans, and both mappings at every offset — over the corpus, every caret position, structure-changing edits and a fuzzed edit stream; and a keystroke's work stays bounded however long the document is |
| Incremental styling | 2 | A block styled on its own matches the same stretch of the document styled whole, attribute for attribute, and typing leaves no seam where the block was spliced |
| Remote images | 29 | Which addresses are fetched, the size ceiling, decoding, failure caching |
| Image tags | 25 | `<img …>` parsing and writing, proportional sizing, aspect ratio |
| Editor scroll geometry | 18 | When a pane's figures may be trusted, and fraction ↔ offset conversion |
| Markdown text codec invariants | 14 | Byte-exact round trips over the corpus, line endings, byte order marks, malformed UTF-8 |
| Cloud paths | 14 | Stems, extensions, and parents, matched against PHP's real output |
| Editor color themes | 13 | All sixteen palettes: WCAG contrast for body, secondary, selected and code text; sRGB resolution |
| Rich Markdown styler | 11 | The styled string matches the model's length, no attribute run escapes it, proportional image sizing |
| Recent documents catalog | 10 | Ordering, de-duplication, caps, pruning |
| New document | 10 | Heading 1 seeding |
| Platform types | 9 | AppKit/UIKit parity, and the colour blending above |
| Markdown text insertion | 8 | Caret placement, clamping stale selections, UTF-16 offsets |
| Markdown render model invariants | 9 | Every span addresses real text, both mappings stay in bounds, every prefix and suffix renders |
| Markdown formatting invariants | 7 | Seventeen commands over every corpus selection: bounds, surrogate pairs, clamping, involution |
| Markdown image importer | 6 | Assets naming, collisions, symlink rejection, unsaved documents |
| File tree scanner | 6 | Ordering, hidden files, packages, symlinks |
| Cross-platform contract | 5 | The exported fixtures still match the compiled Swift |
| Markdown source styler | 7 | Styling is not undoable, and survives a text view that resets its undo manager mid-edit |
| Markdown text codec | 3 | UTF-8 round trip, BOM preservation, invalid input |
| Markdown text difference | 3 | Minimal replacement computation |
| Editor view mode | 2 | The three layouts round-trip through storage and have distinct icons |

---

## 10. Release history

| Change | Summary |
| --- | --- |
| Humanish | The app is named **Humanish** across all builds (`CFBundleDisplayName`, `CFBundleName`, and `build/Humanish.app`), keeping `com.kirupa.markdown-editor` as its bundle identifier so documents and preferences carry over unchanged. |
| The kirupa mark | The app icon is the kirupa logo on white, generated from `../macOS/Packaging/Logo.svg` by the same script as the Mac and web icons. It is drawn at 0.51 of the square, a little tighter than on the Mac because iOS rounds the artwork itself, and centred by the logo's round body rather than its bounding box, so the orange sits in the middle and the leaves hang off one corner ([ID-32, ID-67 and ID-68](#7-themes)). |
| Formatting that leaves code alone | The bar's inline styles and link button do nothing inside a fenced block or a code span, where bold could only write asterisks into the code, and **grey out** while the caret is there. A block quote is prose and formats as before. The bar reads only the blocks at the selection's ends, so no layout pass renders the document ([ID-65 and ID-66](#5-formatting)). |
| Render a block at a time, not the document | A keystroke re-parsed the whole document, styled the whole document, and assigned the result to `attributedText`, which throws away every glyph UIKit has laid out — so the longer the file, the slower it was to write in. Both panes now re-render only the block the edit landed in and splice it into the text storage: the rendered pane through the shared `MarkdownIncrementalRenderer`, the source pane by re-applying attributes over the enclosing block without touching its characters. Measured on the Mac, where the same shared engine runs: a keystroke in a 3.3 MB document went from about **14,000 ms** to **0.29 ms**, and two hundred keystrokes grew the process by about 3 MB where five used to grow it by over 110 MB. Incremental output is checked to be identical to a full render, offset for offset. See `macOS/README.md` §9.6.1. |
| Stop a picture being drawn out of shape | Dragging a picture wider than the line it sits on used to squeeze it while the height carried on growing, so it came out the wrong shape with nothing to say so. A resize now stops at the width the line actually gets. Worse and much more common: a picture with **no size of its own** defaults to 560 points and a phone's column is about 368, so every unsized picture in every document was drawn squashed — measured on a device at 384x107 where its shape is 384x72, and now 367x68 ([ID-64](#6-images)). The Mac gained a page wider than its text column at the same time and a picture there may spread 100 points into each margin; a phone has no margins to give, so this build takes the ceiling and not the bleed ([ID-63](#6-images)). |
| Select, resize and move a picture with a finger | Ported the Mac's picture handling to touch: tap to select, drag a 44pt corner to resize, long-press and drag to move, sharing `EditorImageGeometry` and `MarkdownFormatting.moveImage` so a picture lands in the same place on every build. Four faults only a running app could show, all found on a booted iPhone: the overlay sized to `bounds` instead of `contentSize` ([ID-59](#6-images)), UITextView's own long press cancelling ours ([ID-60](#6-images)), a stale selection frame left behind by a committed move ([ID-61](#6-images)), and a filter meant for the long press that also stopped a tap deselecting ([ID-62](#6-images)). All three gestures verified end to end on a simulator, including the Markdown written to disk. |
| Notice when something else changes the open document | The editor watches its file, and re-checks every time the app returns to the foreground — the case that matters here, because a suspended app hears nothing. With nothing unsaved the newer text is applied and a bar says so; with unsaved edits nothing is applied and the bar offers **Show Newest** or **Keep Mine**, holding the incoming copy in memory so it stays reachable. Shares the decision, the watcher, and the banner with macOS. One thing macOS does that this build cannot: hold off saving until the question is answered — iOS saves through `UIDocument` and a view cannot suspend that. Recorded as [ID-53](#3-document-lifecycle). |
| Ship resources if a target ever declares one | Both no-Xcode build scripts now copy the `<Package>_<Target>.bundle` SwiftPM emits for a target with `resources:` — into `Contents/Resources` on the Mac, the bundle root on iOS, which is where `Bundle.module` looks on each. Nothing declares a resource today, so both copy nothing; a target that gained one would previously have built and signed cleanly and trapped on launch. Verified by temporarily giving `MarkdownEditorUI` a resource and confirming it reached both apps. |
| Keep typing responsive on an illustrated document | Local images are decoded once and kept in memory rather than re-read on every keystroke. The cache is in the shared package, so this build gets it too: a document of forty photo-sized references styled in 65.7 ms per character on the Mac and now styles in 4.0 ms. Keyed on modification date and size, so a picture edited elsewhere is never drawn stale, and it releases everything under memory pressure — which matters more here than on the Mac. |
| Expand the regression net | 348 shared tests across 26 suites, up from 244 across 16. The new suites are property-based: every formatting command over every corpus selection, every prefix and suffix of the corpus through the renderer and the styler, all sixteen palettes held to WCAG contrast, and a byte-exact read/write path. All of it is shared code, so it covers this build's engine as much as the Mac's. |
| Stop the editor jumping while typing | Re-styling the rendered pane no longer loses the reader's place. Assigning `attributedText` resets `contentOffset`, so the offset is now carried across the assignment, using the same `EditorScrollGeometry` rules the Mac uses. |
| Draw images held at a web address | An `https://` image renders as the real picture instead of a placeholder glyph, and can now be measured for proportional resizing. Verified on a booted simulator: two remote images drawn, a broken address still a placeholder. |
| Share the Swift core between platforms | `Shared/` package; AppKit's Generic RGB blending reproduced portably; `themes.css` verified byte-identical |
| Add a native iOS app | iPhone and iPad `DocumentGroup` app compiling the shared package: three modes, adaptive split, full formatting bar, photo and Files image import, sixteen themes, generated app icon |
| Insert by address and resize | Add Image now offers Photo / File / **Image Address…**. A new **Image Size** sheet sets width and height proportionally, writing the same `<img …>` the Mac and the browser write. Verified on a booted iPhone 17 Pro simulator with real taps. |
| Run it on a simulator | Fixed three bugs only a running app could show: a missing `CFBundleExecutable`, a crash in the source pane from unbalanced undo registration, and a light navigation bar under a dark theme. Mode is now remembered, and the theme uses the shared storage keys. |

---

## 11. Verification status

Recorded plainly, because "it builds" and "it runs" are different claims.

**Verified by building:**

- The shared package compiles for `arm64-apple-ios17.0-simulator`.
- All seven iOS sources type-check against the real iOS SDK with **zero errors
  and zero warnings**.
- `xcodebuild -scheme MarkdownEditor` succeeds from a clone, compiling the
  asset catalogue.
- `Scripts/build-app.sh` produces a bundle whose Mach-O load command reports
  `platform IOSSIMULATOR, minos 17.0`, which `codesign --verify --strict`
  accepts.
- 317 shared tests pass, including the colour parity assertions.
- The macOS app still builds and runs unchanged after the restructure.

**Verified by running**, on an iPhone 17 Pro and an iPad Pro 11-inch simulator
(iOS 26.5), with a document opened from the app's container:

- The app installs, launches, and opens a `.md` file through the document
  browser.
- **All three picture gestures, end to end, with real touches** driven at the
  Simulator window and the resulting file read back from the app's container:
  a tap selects a picture and draws its frame; dragging a corner resizes it
  proportionally (640x420 became 256x168, and the file held
  `<img src="Parity.assets/photo.png" alt="photo" width="256" height="168">`);
  a long press and drag moves it above the first paragraph, and the file held
  the picture between the heading and that paragraph with a blank line either
  side and neither paragraph disturbed.
- Tapping the text away from a picture **deselects** it, so the frame does not
  outlive the selection.
- Rendered mode draws headings, bold, italic, strikethrough, inline code,
  links, a blockquote, both list kinds, and a fenced code block.
- Markdown mode draws the source with representative typography and every
  marker intact.
- Split mode lays out both panes side by side on the iPad, and is correctly
  absent on the iPhone.
- The formatting bar scrolls on the phone and fits whole on the iPad.
- The document title and its rename menu stay in the navigation bar.
- A dark theme repaints the document, the formatting bar, the navigation bar,
  and the status bar, including on a device whose system appearance is light.
- The chosen mode survives closing and reopening a document.

Three bugs were found this way that no compile-time check could have caught,
and all three are fixed: a missing `CFBundleExecutable` that made `simctl
install` reject the bundle; an unbalanced `enableUndoRegistration` that crashed
the Markdown pane the first time it was shown (see ID-40); and a light
navigation bar left behind by a dark theme.

The simulator *can* be tapped, which an earlier version of this file wrongly
said it could not. `xcrun simctl` has no tap command, but the Simulator is an
ordinary Mac window, so synthetic `CGEvent` mouse events land on it. Two
constants make the mapping work: the device screen is inset 74pt from the top of
the window (title bar plus bezel) and `(windowWidth - 402) / 2` from the left.
Typing goes through `System Events` keystroke.

Driven that way, the whole image flow was exercised on a booted iPhone 17 Pro:
Add Image → **Image Address…** → a typed URL → Insert produced an image; the
**Image Size** button, correctly disabled a moment earlier, became enabled;
the sheet took a width of 300; and the Markdown pane showed exactly
`<img src="https://example.com/pic.png" alt="image" width="300">`.

Remote drawing (ID-47) was verified the same way, on a document seeded into the
app's container holding three references to real addresses. Both live images —
one sized to 200, one at its natural size — drew the actual picture, and the
deliberately broken address kept the placeholder glyph. That is the whole of the
bug: before this change all three looked like the third one.

**Still not verified:** the photo picker and Files import (both need a real
picker), drag to resize, the theme sheet, and noticing a change made by another
app (ID-48 – ID-53). Nothing has run on real hardware.

On that last one, plainly: the shared decision, the watcher, and the banner are
covered by the shared suite, and this build compiles and bundles with them
wired in — but no one has watched a file change underneath a running iOS app.
The foreground re-check (ID-49) is the part most worth exercising on a device,
because it depends on `scenePhase` arriving the way the simulator suggests it
does. The macOS build of the same feature *is* exercised end to end against
real files, by `macOS/Scripts/check-session.swift`; that harness covers the
shared logic both builds use, but not this build's wiring to it.

One environment note: a freshly created simulator raised *Unable to Import
Document (com.apple.DocumentManager error 1)* and showed *Content Unavailable*
in its file browser. That is the Files daemon not having started, not the app —
shutting the device down and booting it again cleared it.

---

## 12. Out of scope / not yet supported

Known gaps, recorded deliberately so they are not mistaken for bugs:

| ID | Gap |
| --- | --- |
| ID-33 | No file explorer sidebar. iOS's document browser replaces it, but there is no in-app tree. |
| ID-34 | No welcome screen or recent-documents list. `DocumentGroup` provides its own browser. |
| ID-35 | No drag-and-drop or paste image import. The picker and Files both work; drop targets are not wired. |
| ID-36 | No keyboard shortcuts for formatting. A hardware keyboard on an iPad should get the macOS shortcuts. |
| ID-37 | No scroll or selection synchronization between the Split panes. macOS has both. |
| ID-38 | No Firebase or cloud storage **in the app**. A Firebase adapter now lives in `Shared/Firebase/` and compiles for iOS, so it is no longer true that this exists only in the web build — but no screen reaches it, and the app stores documents exactly as it did. The adapter is verified against an emulated Firestore by `Shared/Firebase/run-emulator-checks.sh`, shared with the Mac build and described in `macOS/README.md` §16.6, so what is missing is the UI rather than the plumbing. Two things gate it. Registering an Apple app in the Firebase console, without which sign-in cannot succeed; the app ID checked into the adapter is a placeholder that refuses itself rather than failing later as an OAuth error. And a real code-signing identity — on macOS that is now known to be a hard blocker, because FirebaseAuth needs the data-protection keychain and its entitlement is restricted (`macOS/README.md` §16.7). **Whether the same applies here is unmeasured.** The macOS probes narrowed the cause usefully for this question: what is missing is not a signature but a *keychain access group* for the data-protection keychain. That makes it more plausible still that iOS is unaffected, since an iOS app is always signed with an `application-identifier`, which carries a default keychain access group, and the Simulator relaxes entitlement checks — but that is reasoning, not a measurement, and this row will not claim otherwise until someone runs it. |
| ID-39 | Split is unavailable on compact-width iPhones, by design (ID-8). |
| ID-40 | Styling the source pane cannot use `disable`/`enableUndoRegistration` as a matched pair: UIKit calls `removeAllActions` when the text storage is replaced, which re-enables registration, so the balancing call raises. `MarkdownSourceStyler` now re-enables only when it still needs to. |
