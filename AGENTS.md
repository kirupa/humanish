# Working on this repository

Notes for anyone — person or agent — changing this code. The product itself is
specified in [`README.md`](README.md) and the per-build PRDs it links to; this
file is only the things that are easy to get wrong and cheap to state.

## Running the macOS app

```bash
cd macOS && make run           # builds build/Humanish.app and opens it
cd macOS && make test          # the shared package's unit tests
cd macOS && make check-window  # a real document window, measured
```

`make run` is how a change to the window, the document column or the critique
rail gets looked at. `make check-window` is how it gets asserted: it opens the
real editor in a real window and reads the frame back, so "the rail fits" is a
check rather than something somebody has to remember to eyeball.

## Humanish opens wide enough for the rail

**A document window must contain the document column *and* the critique rail.
A window that opens with the rail clipped at its trailing edge is a bug report,
not a finished change.**

The rail is presented on every newly opened document — `CritiqueModel` starts
undismissed — so this is the ordinary case, not an edge one. It is a fixed
width, `Layout.railWidth` in `macOS/Sources/MarkdownEditor/MarkdownEditorView.swift`,
currently 356 points. The window must hold that *plus* the column beside it.

Four functions answer the width questions, all in
`Shared/Sources/MarkdownEditorUI/EditorPaneGeometry.swift`, all pure and all
covered by `Shared/Tests/MarkdownEditorUITests/EditorPaneGeometryTests.swift`:

- `idealContentWidth(columnWidth:railWidth:railIsOpen:)` — how wide the window
  needs to be. Zoom goes to it, and so does every widening below.
- `defaultWindowContentSize(ideal:minimum:available:)` — the size a new window
  opens at (`Layout.defaultWindowContentSize`): the ideal, capped to the screen,
  never under the minimum.
- `minimumContentWidth(columnMinimum:documentMinimum:railWidth:railIsOpen:)` —
  how narrow it may be dragged before the rail would be clipped again. Below
  the ideal width the column gives way, never the rail: the view clamps the
  column against the room the rail leaves.
- `widenedFrame(_:toWidth:within:)` — how `WindowChrome` grows a window that is
  too narrow for the rail it is showing, when it is first seen and when the
  rail opens: never narrower, never past the screen, moved only if it must be.

Do not re-derive any of them by hand in a view. They are in one place so that
"does the rail fit" is a test rather than a thing somebody has to remember,
and so a screen too small for both degrades in one known way instead of three
invented ones.

### Why the rule is written down

The code makes it true when a window opens, and `make check-window` keeps it
true. What neither covers is a screenshot taken on a machine set up
differently. So when you verify by eye: look at the rail's body text and its
**Run critique** button, not just its header. The header was visible in the
screenshot that reported this bug; everything under it was outside the window.

`screencapture -l` and `-R` both fail behind a lock screen while a full-screen
capture still succeeds, so a locked machine looks like a broken check rather
than a failing one. `MDE_WINDOW_PNG=/tmp/window.png make check-window` draws
the window's own content instead, and works either way.

See §10a (I-243 to I-246 and I-267 to I-272) and §16.9 of
[`macOS/README.md`](macOS/README.md) for the full requirements and what each
decision was weighed against, and "The size a document window opens at" in
[`Contract/README.md`](Contract/README.md) for what every port has to match.

## House style for comments

Comments here explain *why*, usually by naming what was measured and what the
earlier wrong version did. A comment that restates the code is noise; a
comment recording the reason a non-obvious choice was made is the point. Match
the surrounding register rather than introducing a new one.
