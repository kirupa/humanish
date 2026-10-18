# The Windows build

Nothing here yet. This is the brief for the session that writes it.

## Read this first: where to run

**A WinUI 3 app cannot be built on macOS.** The Windows App SDK builds against
the Windows SDK and produces a Windows binary; there is no cross-compilation
path and no way to run the result. Neither `dotnet build` on macOS nor a CI
runner changes that. So:

> **Run that session on a Windows machine**, with Visual Studio 2022 (or the
> Build Tools) plus the ".NET Desktop Development" and "Windows App SDK"
> workloads, and .NET 8 or later.

What *can* be done from anywhere, including macOS, is the half of this
application that is not Windows at all — the Markdown logic, the path
arithmetic, the cloud data model. That is most of the interesting code, it is
already specified as executable fixtures in [`../Contract/`](../Contract/), and
it is the reason this file recommends the split below.

## Is the PRD the source of truth?

Partly, and it is worth being precise about which part, because building from
the wrong document wastes a lot of time.

The three existing READMEs — [root](../README.md), [macOS](../macOS/README.md),
[Web](../Web/README.md) — are genuine product requirements documents, and they
are the source of truth for **what the product is**: what a user can do, what
the storage model is, what is deliberately excluded, and why particular
decisions were made. Read them.

They are **not** sufficient on their own to build a matching implementation,
because each one describes a single build, in terms of that build's platform.
"The Rich Text pane is an `NSTextView` subclass" tells a Windows developer
nothing checkable. And where they do describe behaviour, prose cannot say
whether your version matches — the web build's README once claimed parity with
the Mac build, verified by 14,148 differential test cases, but the harness that
produced that number was never committed, so the claim could not be repeated.

That gap is what [`../Contract/`](../Contract/) closes. It holds the compiled
Swift's actual behaviour dumped as language-neutral fixtures: 9,471 formatting
cases, every render-model span with its source mapping, and 123 path cases.

So, concretely:

| For | Read |
| --- | --- |
| What the product does and why | the three READMEs |
| Exactly what your code must return | `Contract/*.jsonl`, `*.json` |
| The data model shared with the other builds | [`Contract/README.md`](../Contract/README.md) |
| What is genuinely up to you | `Contract/README.md` § "What is deliberately per-platform" |

## The recommended shape

Two projects, and the split is the whole point:

```
Windows/
  MarkdownEditor.Core/          net8.0 class library — no Windows references at all
  MarkdownEditor.Core.Tests/    runs the Contract fixtures
  MarkdownEditor.App/           WinUI 3 — Windows only
```

`MarkdownEditor.Core` holds the Markdown formatting commands, the render model,
path arithmetic, and the cloud node/workspace logic. It targets plain `net8.0`,
references nothing from the Windows App SDK, and therefore **builds and tests on
any machine** — including the one this repository is usually worked on. It is
also the only part with a right answer, so it is the only part that can be
verified, and it should be finished and green before any XAML is written.

This mirrors what the other two builds already do:
`Shared/Sources/MarkdownEditorCore` is dependency-free and shared by macOS and
iOS; `Web/public/app/` keeps its model modules free of DOM access so they run
under node. In both cases that separation is what made the build testable at
all. It is not architecture for its own sake — it is the difference between a
suite that runs in a third of a second and one that needs a UI.

## Suggested order

1. **Paths first.** Port `Shared/Sources/MarkdownEditorCloud/CloudPath.swift`
   and make `Contract/paths.json` pass. It is small, everything else depends on
   it, and `documentId` is the single function that decides whether your build
   and the existing ones can see each other's documents.
2. **Formatting.** Port `MarkdownFormatting.swift` against
   `Contract/formatting.jsonl`. 9,471 cases; expect the astral and CRLF
   documents to find real bugs. `moveImage` is in there too — see
   "[Direct manipulation of pictures](#direct-manipulation-of-pictures)".
   Port `MarkdownCodeContext.swift` with it: the inline commands and the link
   command **do nothing inside a fenced block or a code span**, and the fixture
   records those cases as empty edits that a port can pass by accident and then
   get wrong in the app. Read `Contract/README.md` § "Inside code, the inline
   commands do nothing" first — especially the part about a block quote *not*
   being code, which is the half that is easy to over-apply.
3. **Render model.** Port `MarkdownRenderModel.swift` against
   `Contract/render-model.json`. Do not skip the `source` ranges — the reading
   view is not usable without them. Then port `sourceRange(replacing:with:)`
   from `MarkdownIncrementalRenderer.swift` against `Contract/edits.jsonl`, and
   have the editor control ask it for every edit it maps back to the source.
   Mapping only the selected characters looks right until somebody removes a
   line break, when a marker the reading view hid turns up as text — see
   `Contract/README.md` § "Reading the edits fixture".
4. **Cloud logic.** Port `CloudWorkspace.swift` and its stores behind an
   interface, with an in-memory double, exactly as the Swift and JS builds do.
   Read `Contract/README.md` § "The Firestore data model" before writing any
   field names.
5. **Only then, the app.** XAML, the editor control, the toolbar, the file
   explorer.

## Notes for the app half

- **UTF-16 is free here.** Every offset in the fixtures counts UTF-16 code
  units, which is exactly how C# indexes `string`. The numbers transfer
  directly, with no conversion layer. This is the single biggest reason .NET is
  a comfortable target for this port — a Go or Rust port would need a boundary
  conversion everywhere.
- **The editing control is the hard part, as it was on every platform.**
  The macOS build uses `NSTextView` with a custom layout manager; the web build
  uses a `contenteditable` with a diff-and-remap controller. On Windows,
  `RichEditBox` is the closest analogue. Whatever you choose, the invariant that
  matters is the one both existing builds hold to: **the Markdown source is the
  model.** A visual edit is mapped back into a source range and applied there.
  The rendered view is never the thing being edited.
- **Re-style incrementally, and keep the reader's place when you cannot.** Every
  build re-renders only the blocks an edit disturbs, so typing costs the same
  however long the document is. The obvious first version re-styles the whole
  pane on every keystroke and loses the scroll position doing it. A theme
  change, a new document or a remote revision still replace a pane wholesale,
  and the six rules that keep the reader's place then were each written from a
  shipped bug. `Contract/README.md` §"Keeping the reader's place while
  re-styling".
- **Themes are already resolved for you.** Do not transcribe them from
  kirupa.com. `Web/public/css/themes.css` is generated from the Swift theme
  definitions and committed, so it is a flat list of hex values for all sixteen
  palettes — including the blended ones, which are genuinely hard to reproduce
  (see `Contract/README.md`).
- **The window has to open wide enough for the comments.** The critique rail is
  open from the moment a document is, so the window's opening size is the
  document column plus the rail — on the macOS build 700 + 356 = 1056 wide by
  820 tall — clamped to the monitor's work area and applied only when no frame
  has been persisted for that window. Derive it from your own two layout
  constants rather than copying 1056, and compute it in the same place as your
  "size to fit" behaviour so the two cannot disagree. `Contract/README.md`
  §"The size a document window opens at" has the full rule and the traps.
- **The rail must survive a narrow window.** It keeps a fixed width, so the
  window's minimum width is the column's minimum *plus* the rail while the rail
  is open (360 + 356 = 716 on the macOS build) and the plain document minimum
  when it is shut; the column is clamped into the width the rail leaves, not
  the window's; and the column's resize handle moves inside the column's edge
  with the rail open, reserving no margin. Miss any one and the rail is squeezed
  or clipped when the window is dragged narrow. `Contract/README.md` §"The
  narrowest a window may be, with the rail in it".
- **A window too narrow for its rail widens, twice and only twice.** When a
  window is first seen on screen, and when the rail opens on one already there,
  grow it to the opening width: never narrower than it is, never past the
  monitor's work area, growing on the trailing edge and sliding left only as far
  as it must. Not on every layout pass, and not animated; closing the rail
  leaves the width alone. This is what gives a restored window, or one narrowed
  while the rail was shut, its column back. `Contract/README.md` §"Widening a
  window that is too narrow for its rail".
- **The icon is generated, and the landing screen shows it.** Add an `.ico`
  output to `macOS/Scripts/make-icons.swift` rather than drawing the kirupa mark
  again: it already writes the Mac `.icns`, the iOS PNG and the web `icon.svg`
  from `macOS/Packaging/Logo.svg`, placing the mark by its round body rather
  than its bounding box. The landing screen is that icon and the word Humanish —
  no version number and no tagline. `Contract/README.md` §"The mark, and where
  it comes from" has the measurements.
- **Double-clicking the title bar fills the screen, and the next double-click
  puts the window back.** Windows already does this: it maximises to the work
  area and restores. So the port's job is not to break it. The Mac had to build
  both halves. SwiftUI's hosting view swallowed the drag (I-238), and the
  Mac's double-click went to Zoom, which sizes the window to its content (W-28,
  I-249). If the port draws its own title bar, keep a real caption region for
  the system to drag, maximise and restore. Make any button placed in it
  pass-through, so that pressing it neither drags the window nor maximises it.
  "Size to fit", if the port has it, stays a separate command.
- **The document's path is one gesture away.** On the Mac, ⌘-clicking or
  right-clicking the title offers **Copy Path** and **Reveal in Finder** above
  the folders (I-240 to I-242). Windows has no title menu like that, so put
  **Copy path** and **Show in File Explorer** where a Windows user looks: the
  File menu, and the context menu of the document's title or tab. Copy the path
  as plain text. Open Explorer with the file *selected*
  (`explorer.exe /select,"<path>"`), not merely its folder. An unsaved document
  says *Not saved yet* instead of offering two commands that cannot work.
- **Shade code blocks from the region being painted, in the layout's own
  coordinates.** If the port draws code-block boxes itself, a repaint hands it a
  region in the view's coordinates, while the text layout measures from its own
  inset origin. Convert the region before looking for blocks, and reach a few
  points past it for the box's padding. A full redraw hides the mistake; a
  scroll does not, because it repaints only the strip it uncovers. On the Mac
  the last two lines of a block went unshaded on scroll until something redrew
  them whole (I-256). Test by scrolling a long code block into view, not by
  drawing the whole pane.
- **Firebase** has a .NET path, but it is not the same shape as the Apple or JS
  SDKs. `FirebaseAdmin` is server-side and must not ship in a desktop app —
  it holds credentials that trust the client completely. For a client app the
  realistic options are the Firestore REST API with a user ID token, or
  `Google.Cloud.Firestore` with care taken over authentication. Expect this to
  be the least pleasant part, and note that the existing builds' cloud paths are
  themselves unverified end to end (below).

## Before you start: the Firebase project is ready now

Both things previously listed here as broken are fixed. The security rules are
published and the Storage bucket exists, so the cloud path is reachable for the
first time. Commands to re-check are in
[Web/README.md § 11b](../Web/README.md#setup-steps-that-cannot-be-done-from-this-repository).

What is still true is that **no build has been exercised end to end against the
real project** — only Google sign-in is enabled, and a token for it cannot be
minted from a script, so every cloud test on every build runs against an
in-memory double. Treat the cloud path as written-and-conformant rather than
proven.

Two things to carry over that no fixture can express, both learned by publishing
the rules against code that was already written and already tested:

- An image upload must send a content type **derived from the file's extension**,
  not taken from the platform's file handle. The Storage rule accepts only
  `image/*`, and an untyped upload is stored as `application/octet-stream` and
  refused.
- Refuse an image that **reaches** the 10 MiB limit, not one that exceeds it. The
  rule is `size < 10 * 1024 * 1024`. The web build checked `>` and so accepted a
  file of exactly 10,485,760 bytes that the server then denied.

A third, learned by building offline support rather than by publishing rules:

- **Cache image bytes yourself.** Firestore's offline persistence covers
  Firestore documents and nothing else; Storage objects are ordinary HTTPS
  downloads. A port that leans on Firestore's cache alone opens an offline
  document with its text intact and every picture broken, which reads as damage
  rather than as being offline. Key the cache by *download URL*, not by the
  image's path — a rename then needs no bookkeeping, and a replaced image misses
  instead of serving the picture it replaced. A miss must fall back to the
  download URL, never to a missing image.

- **A size on an image is HTML, not Markdown.** `![alt](a.png =300x200)` is
  rendered by GitHub as literal text with the image lost entirely, so an image
  that carries a width or a height is written as
  `<img src="…" alt="…" width="300">` and one that does not stays
  `![alt](a.png)`. Setting a size converts one to the other and clearing it
  converts back. Parse liberally (any attribute order, any quoting, entities
  decoded) and write strictly. Two rules cost the Swift and JS ports real time
  and are both covered by fixtures: the Markdown form must percent-encode its
  destination, and an unterminated `<img …` is *not* a tag — treat it as text,
  or `Check <img src="a.png" in the docs` is swallowed to end of line.

- **An image referenced by web address must be downloaded and drawn.** A browser
  does this for you; WinUI will not, and both Apple builds shipped a bug here
  first — every `https://` image drew a placeholder glyph, because only local
  files were ever loaded. Look up from a cache synchronously (styling re-runs on
  every keystroke), download on a miss, and re-style in place when it arrives,
  preserving the selection and without scrolling. Fetch `http`/`https` only — a
  `file:` address would read arbitrary disk and defeat the assets containment —
  record a failure so a broken address costs one request rather than one per
  keystroke, enforce the size ceiling while streaming rather than trusting
  `Content-Length`, and require the bytes to decode as an image so an HTML error
  page returned with HTTP 200 is not mistaken for one.

All of these are specified in
[Contract/README.md](../Contract/README.md#the-assets-convention). It is worth
mirroring the web build's approach of making the test double enforce the rules,
so a write the server would reject cannot pass the suite.

## Direct manipulation of pictures

Selecting a picture, resizing it by a corner, and dragging it somewhere else.
This was built on macOS first, then iOS and the web. It took far longer than it
should have, because five separate faults each looked like the same symptom —
"the resize cursor doesn't work". Everything below is the cost of finding them,
written down so the Windows port does not pay it again.

### What the feature is

| | Behaviour |
| --- | --- |
| Hover / touch a picture | A faint outline, and the four corner handles appear — **without a click**. The handles are the only thing saying the picture can be resized, so requiring a click first hides the affordance behind the knowledge of it. |
| Pointer over the body | A **hand** (`grab`), not an arrow. An arrow only says "not text"; a hand says the thing can be picked up. |
| Pointer over a corner | The matching **diagonal resize** cursor. |
| Drag a corner | Resizes proportionally, previewed live, committed as **one** undoable edit on release. |
| Drag the body | Moves the picture. A **rule across the column** marks where it will land and a **gap opens** to show it fitting there. |
| Release | One undoable edit named *Move Image*. |

### The shared pieces — do not re-derive these

| Where | What |
| --- | --- |
| `MarkdownFormatting.moveImage` | The whole text transform. Covered by `Contract/formatting.jsonl` (451 `moveImage` cases). Port it and make the fixture pass before writing any UI. |
| `MarkdownCodeContext` | Whether a selection is in a fenced block, a code span, or prose — read off the render model, not a scanner of its own, so the commands refuse in exactly the places the reading view draws as code. It is also what the toolbar asks to grey a button out, on every caret move, so read it from the **two blocks at the selection's ends** (`containing(_:spansAround:)`), never the whole document. |
| `EditorImageGeometry` | Handle rects, hit rects, the corner tie-break, `draggedWidth`. Pointer *and* touch variants. |
| `MarkdownImageTag.proportionalSize` | Turning a dragged width into a written width/height pair. |
| `EditorPaneGeometry` | The page, the column inside it, and how far a picture may reach past it: `imageBleed`, `maximumImageWidth`, `imageParagraphIndent`. |

Constants, all in `EditorImageGeometry`:

| Name | Value | Why |
| --- | --- | --- |
| `handleSide` | 9pt | The dot that is *drawn*. |
| `handleSlop` | 12pt | How far outside it a **pointer** still counts, giving a 33pt target. It was 4pt and users could not hit it. |
| `touchTarget` | 44pt | The minimum a **finger** target may be. |
| `overlayInset` | `handleSide/2 + handleSlop` | The overlay clips to its own bounds, so this must cover the *target*, not the dot. |
| `minimumSide` | 24pt | The smallest a picture may be dragged to. |

And in `EditorPaneGeometry`:

| Name | Value | Why |
| --- | --- | --- |
| `maximumImageBleed` | 100pt | How far past the text column a picture may reach, **on each side**. |
| `imageBleed(around:within:)` | — | The bleed actually available: whatever is left over, up to the maximum. Collapses to zero on a narrow window, and everything downstream keeps working with the page and the column being the same thing. |
| `maximumImageWidth(measure:bleed:)` | `measure + 2 × bleed` | The page. A resize stops here. |
| `imageParagraphIndent(imageWidth:measure:bleed:)` | — | How far the picture's own line is indented: `min(bleed, max(0, (page − width) / 2))`. Aligned with the prose while it fits, giving way evenly once it does not, and the two meet exactly at the column's width so there is no jump. |

**The page is wider than the column the text is set in.** Prose wraps at the
column; the margin either side is room a picture — and only a picture — may
spread into. A longer line is a worse line to read, so text never uses it. The
Mac and the web both do this; iOS does not, because a phone has no margins to
give, and that falls out of `imageBleed` returning zero rather than needing a
second code path.

**Both hit rects are capped on small pictures.** Four fixed targets meet in the
middle of anything narrow, leaving no body to take hold of — the picture could
then be resized but never dragged, which is worse than a target that is hard to
hit. A third of each side stays clear at every size. Without the cap a 24pt and
a 32pt picture become all corner.

### Traps, each of which cost real time

These are platform-shaped, so the Windows equivalents will differ — but the
*shape* of each mistake is the same anywhere.

1. **A drop must land on a paragraph edge, never a soft-wrap point.**
   `NSLayoutManager` line fragments are *visual* lines, so a wrapped
   paragraph's fragment ends mid-sentence; taking its edge as an insertion
   point produced `Ome![photo](a.png)ga paragraph.` from a drag aimed at the
   gap above. Use whatever your text stack calls a **paragraph**, not a laid-out
   line. Snap in the view *and* again in `moveImage`, so neither half can
   reintroduce it alone.

2. **The destination shifts when the picture is lifted out.** It is measured
   against the document as it stands, but the image is removed before it is
   re-inserted, so every offset after it moves left by what was taken.
   Uncorrected, a forward drag lands one whole image reference past the mark —
   **and only when dragging forwards**, which is the kind of bug that survives a
   demo. Clamp the final offset too: uncorrected it is an out-of-bounds insert,
   so it crashes rather than misplaces.

3. **Do not offer a drop you will refuse.** The blank lines either side of a
   picture are still where that picture is. Drawing a rule there promises a move
   that releasing then declines to make. Treat the picture's own line plus the
   blank run around it as one settled region.

4. **The gap must span the whole text column.** It is an exclusion /
   text-wrapping region, and it must be expressed in the *text container's*
   coordinates. Converting the x offset as well as the y shifted the band left
   by the container inset and left an uncovered strip exactly that wide down the
   right-hand side, which the layout engine happily wrapped text into — so the
   picture looked inset into the paragraph instead of dropped between two lines.

5. **The gap must not chase its own effect.** It is what moved the text, so
   re-deriving it on every pointer move from a layout it is already distorting
   walks it down the page. Rebuild it only when the target paragraph changes,
   and measure the target with the band removed.

6. **A press must stay a click until it has clearly become a drag.** 4pt on a
   pointer. On touch, use a **long press** instead: a short drag on a touch
   screen is how the document is scrolled, so treating travel alone as a move
   makes a document with pictures in it impossible to read.

7. **Reaching for a handle must not take the handle away.** A handle is centred
   *on* the corner, so half of it lies outside the picture. If "hovering" means
   "over the picture", moving onto a handle ends the hover, hides the handles,
   and the resize cursor never appears. Extend the hover region to the corners'
   own hit rects — not a uniform halo, which lights the picture up when the
   pointer is plainly beside it.

8. **A scrolling text control puts its children in *content* coordinates.**
   On iOS the overlay was sized to the text view's visible `bounds`, so every
   handle below the first screenful fell outside it — and UIKit refuses hit
   tests outside a view's bounds, so those handles could be seen and never
   touched. It reads as "resize doesn't work", but only after scrolling. Size
   any overlay to the *content*, and keep it in step as the document grows.

9. **On Win32/WinUI, check who wins the cursor.** On AppKit the text view
   re-asserted its I-beam on *every* mouse move, while the event that would have
   corrected it only fired when the pointer crossed a registered rect boundary
   — 6 times in 99 moves, measured. Inside a corner target no boundary is
   crossed, so nothing re-asked and the I-beam stayed. The fix was to set the
   shape on every move, after the base class had had its say. Whatever your
   framework's `WM_SETCURSOR` equivalent does, **verify the cursor on screen**,
   not what your code decided it should be.

10. **The built-in text control's own gestures will fight yours.** On iOS the
    text view's long press — the one that opens the selection loupe — cancelled
    the long press used to pick a picture up. The delegate approved the touch,
    the recogniser was attached, and the action simply never fired. The fix was
    to make the control's own recognisers *require ours to fail first*, which is
    safe only because ours refuses any touch that does not land on a picture.
    Expect the same fight wherever a rich text control ships its own press,
    drag or selection handling, and expect the symptom to be silence rather
    than an error.

11. **A committed move invalidates the cached picture rect.** The overlay
    remembers where the picture is so it can draw the frame and place the
    handles, and that rect is refreshed when the picture is tapped or resized —
    not when it moves. Restoring the frame at the end of a move therefore drew
    it around the space the picture had just left, about fifty points away from
    it, over the text. Either recompute the rect from the new layout or drop the
    selection; this port dropped it, because at that instant nothing knows the
    new rect yet. A move that found no destination must still put the frame
    back, since nothing changed.

12. **Scope the "is this touch mine?" filter to the gesture that needs it.**
    Trap 10's fix — refusing touches that miss a picture — is correct for the
    press that moves a picture and wrong for the tap that selects one, because
    the tap is also what *deselects*. Applying it to both left a selected
    picture wearing its frame wherever you tapped next. The filter and its
    scope both need a check; neither is visible to a unit test of the geometry,
    so this port guards them by reading the source.

13. **Find out what your text engine does with a picture that does not fit
    before you design around it.** TextKit does not overflow and does not clip:
    it **compresses the picture into the line it has and carries on making it
    taller**. Measured — asking for 700, 800 and 852 points all drew at 642,
    taller each time, so dragging a picture wide silently distorted it and
    nothing said so. That single fact decides the whole design: a picture can
    only be wider than the column if *its own line* is wider, which is why the
    text is indented and the picture's line gives that indent up, rather than
    the picture being positioned or the container being narrowed. Run the
    experiment on your engine first; if it clips or overflows instead, a
    simpler design may be available.

14. **A resize needs a ceiling, and the ceiling has to be measured.** On the web
    the obvious source was the CSS custom property holding the bleed — but
    `getComputedStyle` hands custom properties back as the tokens they were
    written with, not as resolved lengths, so it read back as the literal text
    `clamp( 0px, (100vw - 700px) / 2, 100px )` and parsed as `NaN`. The ceiling
    silently became the column and a picture could never be dragged into the
    margins at all. Measure the geometry you actually want — there, the
    surface's own width less the plain page padding — rather than reading back
    a number you wrote into a style.

15. **Fit a picture that does not fit by scaling *both* sides.** The ceiling on
    a *drag* is not enough, because a picture can arrive already too big: one
    with no size of its own defaults to 560 points, and a phone's column is
    about 368, so on iOS every unsized picture in every document was drawn
    squashed — measured at 384x107 where its own shape at that width is 384x72.
    Scale it down proportionally when it cannot fit, and change only what is
    *drawn*: the document keeps the size it asked for, so the same file opened
    somewhere wider shows the larger picture again. On the web this is free —
    `max-width` with `height: auto` — which is why it was only ever visible on
    the native builds.

### How to check it, and how not to

The single most useful lesson: **every check that asked "what does the code think
the cursor should be?" passed while the app was visibly wrong.** The geometry was
never the fault. Three separate "fixes" shipped on that evidence.

- Test the **text transform** against `Contract/formatting.jsonl`. Pure, fast,
  and it catches the offset and paragraph bugs above.
- Test the **decision** — which edge a drop chooses — as a pure function over
  rectangles. No UI framework needed. Assert every answer is a line boundary,
  by sweeping the pointer down the whole document rather than sampling a point
  you chose.
- Test the **rendered result**, not a substring. A picture is inserted with a
  blank line either side, so splicing it into "Omega" gives
  `Ome\n\n![photo](a.png)\n\nga` — which passes a check for `Ome![photo]`
  while the word is in two pieces. Assert the **words survived**.
- Drive the **real entry point** and read the cursor the OS ends up holding.
  Asking your own geometry function proves nothing.
- If you photograph the screen: approach along a **realistic path**, not a
  teleport, and beware that spawning a screenshot tool can cost more time than
  the bug you are measuring. A locked screen also refuses region captures while
  still allowing full-screen ones, which reads as a broken app rather than an
  unavailable check.

## Pressing and hovering a critique note

The behaviour is specified in [`Contract/README.md`](../Contract/README.md)
§ "Taking the reader to a criticised passage" and § "Hovering a note tints its
passage". In short:

- A press on a note **reveals its passage**. It never toggles the note off.
- The passage is framed about **a third of the way down** the window.
- A passage that is already comfortably visible **does not move**.
- **Hovering** tints a passage that is already on screen, and never scrolls.
- **Selection outranks hover.** The open note's passage also gets a solid
  rule underneath it.

The arithmetic and the state are already written. Port them; do not re-derive
them.

| Where | What |
| --- | --- |
| `EditorScrollGeometry.offset(toReveal:)`, `isComfortablyVisible(_:)` | Where to scroll, and whether to scroll at all. The recorded numbers are in `EditorScrollGeometryTests.swift`. |
| `CritiqueHighlight` (`Shared/Sources/MarkdownEditorUI/`) | The press/hover state machine, the three washes per severity, and the rule. `CritiqueHighlightTests.swift` asserts their order and hue. |

Two traps cost the Mac build real time:

- **Lay out before you scroll.** A scroll offset is clamped to the height laid
  out so far. After an edit, that is about a screenful. Measure as far as the
  passage, then as far as the target viewport, and no further.
- **Selectable text swallows the press.** If a note's words can be selected,
  the text control takes the press and the card never sees it. Make a pressable
  note's text non-selectable (on a WinUI `TextBlock`, leave
  `IsTextSelectionEnabled` at its default, `False`). Then press the middle of a
  note's words and confirm which element receives it.

When the pointer moves straight from one note to the next, the new note's
*entered* event can arrive before the old note's *exited* event. On *exited*,
clear the hover only if the note being left still holds it.

## Selected text, and the page's face and size

The rules are in [`Contract/README.md`](../Contract/README.md) § "Selected
text", § "Typefaces" and § "Text size". In short:

- Selected text sits on a **pale tint of the accent** and keeps its own
  colours. A selected row, menu item or radio button keeps the full accent.
- In the rendered view a selection is **one rounded bar per line, fitted to
  the words**. Its hard ends stand exactly on the carets, and it fades out past
  a line's end and back in before the next line's start where the selection
  carries on.
- Customize Theme has a **Font** chooser offering the same faces as the
  critique's hand menu, and a **Size** slider from 75% to 150% beneath it. Both
  are part of the draft: previewed, committed by Apply, dropped by Cancel.
- **Never ship QE Dave Mergens or QE Julian Dean.** Their licence forbids it.
  Offer them only where the user has installed them.

The values and the shape are already written. Port them; do not re-derive them.

| Where | What |
| --- | --- |
| `Web/public/css/themes.css` | `--me-text-selection-background` and `--me-inactive-text-selection-background` for all sixteen themes, already solved. |
| `SelectionHighlightSegment` (`Shared/Sources/MarkdownEditorUI/SelectionHighlightGeometry.swift`) | One line's bar: its extent, corner radius, fades and gradient stops. "Selection highlight shape" holds it, and `Web/public/app/core/selection-geometry.js` is a line-for-line port with the measuring half added. |
| `EditorTypeface` (`Shared/Sources/MarkdownEditorUI/EditorTypeface.swift`) | The fifteen faces, their stored ids, groups and optical scales. The bundled files and their licences are in `macOS/Packaging/Fonts`. |
| `EditorColorTheme.clampedTextScale` | The range, the 5% step and the clamping of a stored `editorTextScale`. |

Four traps cost the other builds real time:

- **Stand the control's own selection down; do not paint over it.** A
  translucent tint over a square band leaves the band's square ends showing.
  `RichEditBox` paints its own selection, so hide it and draw the bars yourself:
  under the text where you can, which in XAML means a layer behind an editor
  whose own background is transparent. Where the bars can only go over the
  text, blend them as the web does (`selectionPaint`), or the words are dimmed.
- **The fades reach into the margin, past where the toolkit redraws.**
  Remember where bars were drawn and invalidate all of it when the selection
  changes, or faded ends are left behind. On the Mac this was checked over 68
  selection changes in two themes (I-254).
- **A font family that falls back silently looks like a choice ignored.** Offer
  a face only once the system font collection says it exists. Constructing a
  `FontFamily` will not fail for a missing one.
- **Nothing the preview shows may widen the popover.** On the web, a larger
  size or a wider face widened it, and the slider moved out from under the
  pointer mid-drag. Fix its width, and let the preview wrap and grow downward.

## Validating the port

```powershell
dotnet test Windows/MarkdownEditor.Core.Tests
```

That should run every fixture in `Contract/`. If it does, the shared half of the
Windows build provably matches the Mac build, which is a stronger claim than any
of the other builds could make about each other until now.

Regenerate the fixtures only from a machine with Swift, and only deliberately:

```bash
swift run --package-path Shared markdown-contract Contract
```

A fixture change means behaviour changed. If a Windows session finds a fixture
wrong — which is possible; they record what the Swift does, and the Swift can be
wrong — fix the Swift, regenerate, and say so in the commit. Do not edit the
fixtures by hand.
