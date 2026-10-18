# The cross-platform contract

This directory is the answer to a question that had no good answer before it
existed: **if you are writing Humanish for a fourth platform, what exactly do
you have to match?**

The three READMEs are product requirements documents, and they are thorough, but
each describes one build. They tell you what the Mac app does, or what the web
app does. None of them tells you what *Humanish* does, independently of the
platform it happens to be running on — and none of them is checkable. A new
build could satisfy every sentence in all three and still write documents the
others cannot open.

So this is not more prose. It is the compiled Swift, dumped as data:

| File | What it pins down | Cases |
| --- | --- | --- |
| `formatting.jsonl` | Every formatting command, at every interesting selection, in every corpus document | 9,471 |
| `render-model.json` | What the reading view shows, and where each part of it came from in the source | 14 documents, every span |
| `edits.jsonl` | Which Markdown an edit made in the reading view replaces, wherever it removes a line break | 273 |
| `paths.json` | Workspace-path arithmetic: naming, descendancy, subtree rewriting, collision numbering | 123 |

Regenerate them after changing `MarkdownEditorCore` or `CloudPath`:

```bash
swift run --package-path Shared markdown-contract Contract
```

A test in `MarkdownEditorContractTests` regenerates and compares, so a fixture
that no longer describes the code fails the suite rather than quietly
misleading whoever ports next.

## Why these files exist at all

The web build's README claims it was verified against the compiled Swift by
differential testing: 14,148 formatting cases and 41 documents through the
render model, zero mismatches. That was true. But the harness that ran it was
never committed, so the claim outlived any means of checking it, and nobody
starting a fourth build could repeat it.

These files are that harness's output, committed. A port is correct when it
reproduces them, and you can tell whether it does by running them.

## Offsets are UTF-16 code units

Every `[location, length]` pair in every fixture counts UTF-16 code units, which
is what Swift's `NSString`, JavaScript strings, C# `string`, and Java `String`
all index by. In those languages the numbers can be used directly.

Go, Rust, and Python index differently — bytes, or scalars — and a port in one of
those has to convert at the boundary. That is precisely why the corpus contains
`😀`, a regional-indicator flag, and a four-person family emoji: a port that
treats one visible character as one unit will pass most of the corpus and fail
those, which is the failure you want, early and loudly.

## Reading the formatting fixture

One JSON object per line. The first line is the header, which carries the
corpus; every line after it is a case.

```
{"version":1,"about":"…","offsets":"UTF-16 code units","caseCount":9471,"documents":[{"id":"mixed","text":"# Trip notes\n…"}]}
{"argument":"bold","command":"toggleInline","document":"mixed","replace":[0,0],"selection":[2,4],"selectionAfter":[4,4],"with":"**"}
```

Each case says: take the named document, put the selection at `selection`, run
the command, and you must get the document back with `with` written over the
`replace` range, and the selection at `selectionAfter`.

The edit is stored rather than the whole resulting text because most commands
change a handful of characters in a document that is otherwise identical —
storing the result made the file forty times larger and no clearer.

A runner is about fifteen lines:

```csharp
foreach (var line in File.ReadLines("Contract/formatting.jsonl").Skip(1))
{
    var c = JsonSerializer.Deserialize<Case>(line);
    var source = documents[c.Document];
    var expected = source.Remove(c.Replace[0], c.Replace[1]).Insert(c.Replace[0], c.With);

    var actual = Formatting.Apply(c.Command, c.Argument, source, c.Selection[0], c.Selection[1]);

    Assert.Equal(expected, actual.Text);
    Assert.Equal(c.SelectionAfter[0], actual.SelectionStart);
    Assert.Equal(c.SelectionAfter[1], actual.SelectionLength);
}
```

### The twenty commands

| `command` | `argument` |
| --- | --- |
| `toggleInline` | `bold`, `italic`, `underline`, `strikethrough`, `inlineCode` |
| `applyHeading` | `0`–`6`, where `0` removes the heading |
| `toggleList` | `bulleted`, `numbered`, `task` |
| `toggleQuote` | — |
| `wrapCodeBlock` | — |
| `insertNewline` | — |
| `insertLink` | the destination, `https://example.com` in the fixture |
| `insertHorizontalRule` | — |

`insertNewline` is in the list because pressing Return is a formatting command
in this editor: inside a list it continues the list, and on an empty list item it
ends it. A port that treats Return as plain text insertion passes everything
else and gets lists wrong.

### Inside code, the inline commands do nothing

Markdown is inert inside code. `**bold**` typed into a fenced block or between
a code span's backticks is not emphasis — it is four asterisks and a word, and
every conforming renderer, this one included, shows it that way. So
`toggleInline` and `insertLink` **must return the document and the selection
unchanged** when the selection is code. There is no third option: the command
cannot do what it was asked, and the only thing it can otherwise produce is
literal punctuation in the writer's code. A port that skips this reproduces the
bug this rule was written for — the caret in a fence, bold pressed, and
`**bold text**` saved into the file.

Code, for this purpose, is:

| | Where it starts | Where it ends |
| --- | --- | --- |
| **A fenced code block** | the first character of its opening fence line | the end of its closing fence line, or the end of the file if it is never closed |
| **An inline code span** | *after* its opening backtick run | the end of its closing backtick run |

The asymmetry at the start is deliberate and load-bearing. A caret at the first
character of a fence line is inside the block, because anything written there
displaces the fence. A caret at the first backtick of a code span is in front of
it, and what is written there lands in the prose, correctly.

Two selections are **not** code and must still format:

- one that **contains a whole code span**, with prose either side —
  `**Call \`reload()\` now**` is valid Markdown and useful;
- anything in a **block quote**. A quote is prose. Bold in a quote is ordinary
  Markdown, the renderer hides its markers there as it does anywhere else, and a
  port that refuses in a quote has over-applied this rule.

A selection that overlaps a code region **without containing it** is refused,
because it would put one marker inside the code and its partner outside.

Inline code itself stays available inside a code span, because that is how a
span is taken off again — and there it *removes* the span rather than adding
one, including from a bare caret between the backticks.

**Four-space indented code is not code here.** This editor's render model does
not implement indented code blocks: an indented line is an ordinary paragraph,
and emphasis typed on one is drawn as emphasis. Refusing there would stop a
command that visibly works. A port that *does* implement indented code should
make the two agree — the rule is that the commands refuse in exactly the places
the reading view draws as code, and nowhere else.

Derive the answer from the render model rather than from a scanner of its own;
that is what keeps the two from disagreeing. `MarkdownCodeContext.swift` and
`Web/public/app/core/code-context.js` are the two existing implementations, and
the refusals are in `formatting.jsonl` like any other case — an unchanged
document is recorded as an empty edit.

**Read two blocks, not the document.** The toolbar asks this on every caret
move, so every build answers it from the blocks the selection's two ends fall
in, and the answer is exactly the one a walk of the whole document gives. The
code a caret is in contains the caret. The code a selection is in overlaps it
without lying inside it, and a region that does that must hold the selection's
first character or its last. A fence is one block and a code span never leaves
its line, so the blocks those two characters fall in hold every candidate. Ask
fences before code spans, across both blocks, in document order; a fence found
at the start is already the answer. `MarkdownCodeContext.containing(_:spansAround:)`
and `codeContextInModel` are the shape to copy, and both suites check the
two-block reading against a walk of every span — every caret, and every
selection between code edges and line boundaries, in the corpus and in a set of
fence-heavy documents.

## Reading the render fixture

`render-model.json` holds, for each corpus document, the text the reading view
displays and every style span in it. Each span carries two ranges:

- `rendered` — where it is in the displayed text
- `source` — where it came from in the original Markdown

The second is the half that is easy to skip and impossible to do without. It is
what lets a click in the rendered pane put the caret in the right place in the
source, and what keeps a selection where it was when switching views. A port
that renders correctly but maps ranges wrongly looks finished and is not.

`includesMarkup` says whether the span covers the syntax characters as well as
the content. `isAtomic` marks a span that behaves as one unit for selection —
an image, or a horizontal rule.

## Reading the edits fixture

`edits.jsonl` answers the question the render fixture leaves open: when
somebody edits the reading view, which Markdown does the edit replace? Mapping
the selected characters back through `source` is the answer almost everywhere,
and wrong at a line break. The markers a line begins with — a heading's `## `,
a quote's `> ` — are not on screen, so the characters either side of a rendered
line break say nothing about them. Delete only the `\n` between a quote and an
empty heading, which draws as a blank line, and the heading's hidden `## `
lands at the end of the quote as text. That is the bug this fixture was written
for, and its document, `empty-heading-under-quote`, follows the formatting
corpus's fourteen in the header with four more written to find the rule's
edges.

The first line is a header carrying the documents, each with the text it
renders to, so a port can check its rendering before its edits. Every line
after it is one edit: replace `rendered` in the document's rendered text with
`with`, and the Markdown that edit replaces is `source`. Every edit removes a
line break the reading view shows, in one of three ways:

| `kind` | The edit |
| --- | --- |
| `join` | ⌫ at the start of a line, or ⌦ at the end of the one above |
| `joinTyping` | Typing a character over the line break |
| `deleteLine` | Deleting the whole line the break ends |

The rule they pin is `sourceRange(replacing:with:)` in
`MarkdownIncrementalRenderer.swift`:

- An edit that does not end at the start of a rendered line maps exactly as its
  characters do. That is every keystroke that is not removing a line break, and
  it is decided by looking at one character.
- **Joining** a line onto the one above also removes the heading or quote
  marker the lower line began with, so its text carries on in the upper line's
  style. Only that marker, and only if the line hid it whole: `## ` in a fence,
  `##` with no space after it, and a `**` opening bold on the joined line are
  all left alone.
- **Deleting whole lines**, from the start of one to the start of another, also
  removes what the first of them hid at its start, so the line that moves up
  keeps its own style rather than inheriting a heading from a line that is
  gone.
- A replacement that **ends in a line break** — Return, above all — is never
  adjusted, because it leaves a line boundary where the old one was.
- A **CRLF** is one line break. An edit that stops between its `\r` and its
  `\n` is not at the start of a line, and deleting only the `\n` joins nothing.

The documents are `ContractCorpus.editingDocuments`, kept apart from the
formatting corpus so that adding them changed none of its 9,471 cases.
`sourceRangeReplacing` in `Web/public/app/core/render-model.js` is the second
implementation, and `Web/public/tests/contract-edits.test.js` replays every
case against it.

A port should ask this one rule from every path that turns an edit in the
reading view into an edit of the source — typing, delete in both directions,
the end of an input method's composition, cut, and paste. A path that maps its
selection any other way brings the bug back for that way of editing alone,
which is why both builds also check it from the editor's side:
`make check-line-joins` presses the keys in a real Mac editor, and the web
build's DOM suite *Line breaks removed through the surface* makes the same
edits to its surface and reads them back both ways it can.

## What is not in these files

Some of the contract is not a pure function and cannot be dumped as cases. Those
parts are listed here with the file that defines them, so nothing has to be
reverse-engineered from behaviour.

### A withdrawn command has to look withdrawn

The fixture can say that `toggleInline` returns the document unchanged inside
code. It cannot say what the toolbar does about it, and a control that silently
does nothing when clicked is worse than the bug it is refusing to cause: the
writer presses it twice, then concludes the editor is broken.

So every build **greys the control out** while the selection is in code, rather
than hiding it. Hiding teaches nothing, and a toolbar that changes shape as the
caret moves is its own problem. The same goes for the menu item behind the
keyboard shortcut, on platforms that have one.

Ask the shared availability predicate rather than re-deriving the rule in the
interface — `MarkdownFormatting.isAvailable(_:context:)` and
`isLinkAvailable(context:)`, or their JavaScript twins in `formatting.js` — so
the button and the command can never disagree about what will happen.

Ask it from a render model the pane **already has**, not from a fresh parse. The
answer is needed on every caret move, and parsing an 80 KB document takes about
37 ms against 0.8 ms to scan the spans of one already parsed. Both native builds
and the web build pass the model they are holding.

### The Firestore data model

Documents live at `users/{uid}/nodes/{documentId}`, one flat collection per
account — a subcollection rather than a `uid` field so the security rules are a
path match and cannot be got wrong for a single document.

`documentId` is the workspace path percent-encoded exactly as JavaScript's
`encodeURIComponent` encodes it: everything escaped except
`A–Z a–z 0–9 - _ . ! ~ * ' ( )`. **This is the one that decides whether two
builds can see each other's documents at all.** `paths.json` has cases for it,
including non-ASCII and emoji paths.

Every node document has these fields, and the security rules validate them:

| Field | Type | On | Notes |
| --- | --- | --- | --- |
| `type` | string | all | `folder`, `file`, or `asset` |
| `path` | string | all | Workspace-relative, no leading slash |
| `parent` | string | all | Containing folder; `""` at the root |
| `name` | string | all | Last path component |
| `modified` | number | all | **Milliseconds** since the epoch, as JavaScript's `Date.now()` writes. Read it as a double: Firestore hands back either |
| `text` | string | files | The Markdown itself |
| `hasByteOrderMark` | bool | files | Preserved so a round-trip through the editor does not change the file's bytes |
| `size` | number | files, assets | UTF-8 **bytes**, not characters |
| `storagePath` | string | assets | Object path in Cloud Storage |
| `url` | string | assets | Download URL |
| `contentType` | string | assets | MIME type |

Defined in `Shared/Sources/MarkdownEditorCloud/CloudNode.swift` and
`Web/public/app/cloud/`. A document is refused above 900,000 bytes, below
Firestore's 1 MiB per-document cap.

**Count those 900,000 in UTF-8 bytes, not characters, and enforce it in the
client.** Every port has to, because neither of the two server-side limits
substitutes for it:

- The rule in `firestore.rules` reads `text.size() < 900000`, and the rules
  language has no byte-length function — `size()` on a string counts
  *characters*. Measured against the real engine: 500,000 accented characters
  (1,000,000 UTF-8 bytes) are accepted by the rules.
- Firestore's own limit is a hard 1,048,487 bytes per property, and a write past
  it fails with `400 INVALID_ARGUMENT` — **not** the `403 PERMISSION_DENIED` a
  client can read as "you are signed out". 600,000 accented characters land
  exactly there: inside the character limit, outside the byte cap.

So a client counting characters has a band of documents that pass its own check,
pass the rules, and then fail with an error meaning something else entirely.
Counting UTF-8 bytes at 900,000 is strictly stricter than both and closes it.
Verified by `Web/firebase/run-rules-checks.sh`.

### Where image bytes live

Not in Firestore. A Firestore document is capped at 1 MiB and base64 inflates a
file by about a third, which would cap an inserted image near 700 KB and spend
the same budget the text needs.

Images go to a Cloud Storage bucket at:

```
users/{uid}/{workspace path of the asset}#{milliseconds since epoch}
```

The timestamp keeps a re-uploaded image from being served from a CDN copy of the
previous one at the same object path. The limit is 10 MiB, enforced in the app
and again in `Web/firebase/storage.rules`, where a client cannot talk its way
around it.

**Refuse an image that reaches the limit, not one that exceeds it.** The rule is
`request.resource.size < 10 * 1024 * 1024`, so a file of exactly 10,485,760 bytes
is denied by the server. A port that checks `> limit` accepts that file and then
fails on upload with a bare permission error, which is the one outcome the
client-side check exists to prevent. The web build had this wrong until the
rules were published and it became reachable.

**Every port must cache image bytes on the device.** Firestore's offline
persistence covers Firestore documents and nothing else; Storage objects are
ordinary HTTPS downloads. A port that relies on Firestore's cache alone opens an
offline document with its text intact and every picture broken, which reads to
the person holding the device as damage rather than as being offline. The web
build keeps the bytes in IndexedDB; a native port has a filesystem and should
use it. Three rules make the cache correct on any platform:

* **Key by download URL, not by the image's path in the workspace.** A rename
  moves images, and the download URL moves with them, so a rename needs no cache
  bookkeeping. The URL also carries a token that changes when the bytes behind it
  are replaced, so a replaced image misses instead of serving the old picture:
  the cache can go empty but it cannot go stale.
* **A miss must fall back to the download URL,** never to a missing image. The
  cache is only ever allowed to improve on the uncached behaviour.
* **Adopt what is already on the device before returning the document; do not
  wait on what is not.** A miss only matters with no network, and with no network
  the download fails anyway — so blocking every open on fetching images spends
  something real to buy something hypothetical. Bytes that were just *uploaded*
  are cached from the copy in hand rather than downloaded back.

**Every port must send a real `image/*` content type, derived from the file
extension rather than taken from the platform's file handle.** The Storage rule
accepts only `contentType.matches('image/.*')`, and an upload with no declared
type is stored as `application/octet-stream` and refused. Platforms hand over
untyped files routinely — a drag from some applications, a paste, bytes read
straight off disk — so the type has to be derived. By the time it is needed the
extension has already been checked against the accepted list, so deriving it is
safe. A type the platform *does* declare is kept only when it is itself an
`image/*`. The map is the one below; a port that skips this sees images that
silently fail to add, reported as a bare permission error.

| Extension | Type | | Extension | Type |
| --- | --- | --- | --- | --- |
| `png` | `image/png` | | `bmp` | `image/bmp` |
| `jpg`, `jpeg` | `image/jpeg` | | `webp` | `image/webp` |
| `gif` | `image/gif` | | `svg` | `image/svg+xml` |
| `heic` | `image/heic` | | `tiff`, `tif` | `image/tiff` |
| `heif` | `image/heif` | | | |

A second thing no fixture can express: **if a port caches image URLs by path so
the renderer can resolve them synchronously, the cache must be re-keyed whenever
a path changes.** A document's assets folder is a *sibling*, not a descendant, so
a subtree walk over the renamed path does not reach it and has to be handled
separately.

**The Markdown text never contains a Storage URL.** It keeps the relative
reference every build writes, and the URL is resolved at render time from the
`asset` node. That is what keeps a document portable between builds.

### The assets convention

A document's images live in a sibling folder named after the document's stem
plus `.assets`, so `Trip.md` has `Trip.assets/`. The reference written into the
document is relative and percent-encoded per RFC 3986 — unreserved characters
are `A–Z a–z 0–9 - . _ ~`, everything else escaped:

```markdown
![my shot](Trip.assets/my%20shot.png)
```

A name already taken gets `-2`, `-3`, and so on before the extension, and an
existing file is never overwritten. `paths.json` has the cases. Renaming a
document moves its assets folder with it and rewrites the references inside it;
deleting a document deliberately leaves the assets behind, because the originals
may exist nowhere else.

### How an image carries a size

Markdown has no syntax for image dimensions. Every port must therefore agree on
what to write instead, or a document sized on one platform shows raw HTML on
another.

The rule is: **an image with no size stays Markdown; an image with a size is an
HTML `<img>` tag.** Setting a size converts one to the other, and clearing it
converts back.

```markdown
![my shot](Trip.assets/my%20shot.png)
<img src="Trip.assets/my%20shot.png" alt="my shot" width="300" height="200">
```

This was settled by rendering the candidates through GitHub's own
`POST /markdown`, not by preference:

| Written as | What GitHub does with it |
| --- | --- |
| `<img src="a.png" alt="s" width="300" height="200">` | **Honoured** — both dimensions survive |
| `![s](a.png =300x200)` | Rendered as literal text; **the image is lost** |
| `![s\|300x200](a.png)` | Renders, but the size is ignored and the alt text becomes `s\|300x200` |

Only the first keeps both the picture and the size, so it is the one the
documents use. It is also consistent with the existing use of `<u>` for
underline: reach for HTML exactly where Markdown has no syntax, and nowhere
else.

A port must read a tag more liberally than it writes one, because a person may
have typed it. Attributes come in any order, quoted with `"` or `'` or not at
all, in any case, with or without a self-closing `/`, and a quoted value may
contain `>`. HTML entities are decoded. These are **not** images and stay as
literal text: `<imgx …>` and `<image …>` (a shared prefix is not a match), a tag
with no `src` or an empty one, and — importantly — **a tag with no closing `>`**,
which otherwise swallows the rest of the line. A dimension that is not a
positive whole number, such as `50%`, is reported as absent rather than
rewritten, so hand-written HTML the editor cannot represent in a number field is
still displayed and not silently damaged.

Two rules govern the conversion:

1. **Going back to Markdown percent-encodes the destination.** An HTML attribute
   holds `my file.png` happily; the same text in Markdown is not an image at all.
   The encoding is idempotent, so an already-encoded path is unharmed.
2. **A size is only ever set on a range that is exactly one image reference.**
   If it is not, the text is left untouched. A stale range from a document that
   has since been edited must never corrupt it.

Resizing preserves the aspect ratio, derived from the image's own pixel
dimensions rather than from anything in the document. The dimension the person
edited is kept exactly and the other is derived; the derived one is rounded, but
never to zero, or a very wide, very short image would vanish. When the image has
not loaded there is no shape to preserve, so nothing is derived.

An image may also be referenced by URL instead of being copied into the assets
folder. Nothing is uploaded in that case and the document points at the original
address.

### Drawing an image held at a web address

A browser draws `<img src="https://…">` itself; a native build has to fetch the
bytes. That difference is invisible in every fixture here, so it is written down
instead — the macOS and iOS builds both once drew a placeholder glyph for every
address, and a port that reads only the fixtures would reproduce that.

The rules a native port must follow, all shared between macOS and iOS in
`RemoteImageStore` and worth copying rather than reinventing:

| Rule | Why |
| --- | --- |
| Look up synchronously; download asynchronously | Styling re-runs on every keystroke, so a lookup must be instant. On a miss, draw the placeholder, start one download, and re-style when it lands. |
| `http` and `https` only | A `file:` address would let a document read any file on disk, defeating the containment that keeps an import inside the document's own folder. `data:` is already bytes. |
| Record a failure as a failure | Otherwise a broken address costs one request per keystroke. One attempt per address per launch. |
| Cap the transfer, while streaming | 25 MB. `Content-Length` may be absent, so the ceiling has to be enforced against bytes actually received, and a missing length is not itself grounds to refuse. |
| Require the bytes to decode as an image | A server answering an error page with HTTP 200 is a failure, not a picture. |
| Unescape the destination before parsing the URL | A Markdown `\)` inside an address parses as a different URL if it is read literally. |

Re-styling on arrival must preserve the selection and must not scroll. A cached
image also supplies the natural size, so an address can be resized
proportionally like a local file; before it loads there is no shape to preserve,
which is the same "not loaded" case the sizing rules above already describe.

### Drawing an image kept beside the document

A browser gets this free: `<img src="notes.assets/photo.png">` is decoded once
by the engine and redrawn from its own cache. A native build that rebuilds the
document's attachments on every keystroke does not, and re-reads and re-decodes
every picture on the page per character. Measured on macOS with forty
photo-sized references: 65.7 ms per keystroke against 1.1 ms for the same text
without images — about 15 fps, felt as lag rather than seen as a glitch.

Shared between macOS and iOS in `LocalImageStore`. A port needs four rules:

| Rule | Why |
| --- | --- |
| Decode once and keep it | The whole point. Styling an illustrated document should cost about what styling its prose costs. |
| Key on modification date **and size**, not the path | A picture edited in another app must not go on drawing its old self. Size is in the key because a timestamp is coarse enough that a generated or scripted image can be rewritten inside the same second. A `stat` costs a microsecond against a decode's millisecond, so checking every lookup is worth it. |
| Cost entries by pixel area, and evict | An image is far larger decoded than compressed — a 34 MB photo is roughly 48 MB of pixels — so a count-based limit budgets nothing. This cache evicts, unlike the remote one, because a long illustrated document could otherwise hold more memory than the rest of the app. Eviction only costs a re-read. |
| Give the memory back under pressure | A text editor should hand a hundred megabytes of decoded pictures back to the OS long before the machine swaps. `NSCache` does this by itself; a port hand-rolling a dictionary has to do it deliberately. |

Two traps worth inheriting, both of which produced tests that passed against a
broken cache. Reading a file's modification date and setting it back does **not**
round-trip — the filesystem keeps nanoseconds a `Date` does not reproduce — so a
test that tries to hold the timestamp still while changing the content proves
nothing about the size half of the key; pin both writes to an explicit whole
second instead. And asserting that a cost function returns the right number says
nothing about whether that number ever reaches the cache: size a cache for one
image and add two.

### Reading the paths fixture

`paths.json` is a flat list of calls. Each case names a `function`, its
`input` arguments, and either an `output` or an `error`:

```json
{ "function": "documentId", "input": ["a/b/c.md"], "output": "a%2Fb%2Fc.md" }
{ "function": "documentId", "input": [""], "error": "rootIsNotADocument" }
```

A case with `error` must fail. The string is the Swift error case name; a port
should map it to whatever its own failure looks like, but it must not succeed.
The functions covered are `normalize`, `name`, `parent`, `stem`,
`fileExtension`, `isMarkdown`, `assetsFolderName`, `documentId`, `join`,
`isDescendant`, `nextAvailableName`, and `rewrite` (which re-points a path and
everything under it when a folder moves).

### Sort order

Explorer order is folders first, then natural case-insensitive order, so
`Folder 2` comes before `Folder 10`. Each build spells this with its platform's
own collation — `localizedStandardCompare` in Swift, `Intl.Collator` with
`numeric: true` in JavaScript, `strnatcasecmp` in PHP. On .NET the equivalent is
`StrCmpLogicalW`, or a comparer that splits digit runs and compares them
numerically.

### Themes

Sixteen palettes — eight colours × light and dark — transcribed once from
kirupa.com into `Shared/Sources/MarkdownEditorUI/EditorColorTheme.swift`.

**Do not transcribe them again.** `Web/public/css/themes.css` is *generated* from
that Swift file and is committed, so it is a plain list of resolved hex values
for all sixteen, including the derived ones. Read the colours from there.

One thing that will bite a port: several colours are blends, and `NSColor`'s
blend does not interpolate in sRGB. It converts to Apple's Generic RGB —
different primaries, gamma 1.8 — mixes, and converts back, so black halfway to
white is `0.573`, not `0.5`. A naive sRGB blend is off by up to 46/255. Since
`themes.css` holds the resolved values, a port that reads them avoids the
problem; a port that reimplements the blending must reproduce this.

### Selected text

Selected text is drawn on a **tint**, not on the accent. The tint is the theme's
accent laid thinly over the page, and the words keep their own colours, so body
text, headings, links and code read the same selected as not. Rows, menus,
radio buttons and anything else that is *selected* rather than *highlighted*
keep the full accent and its black-or-white label (`--me-selection-background`,
`--me-selection-text`). Those are different colours in every theme, so keep
them apart.

- **Read the tint from `themes.css`.** `--me-text-selection-background` is the
  accent at an opacity solved per theme. `--me-inactive-text-selection-background`
  is the quieter tint for a selection the editor is not acting on, because its
  window is behind another or the focus is elsewhere. Both are `rgba()`,
  generated from `EditorColorTheme.textSelectionBackgroundColor` and
  `inactiveTextSelectionBackgroundColor`.
- **The opacity is solved, not chosen.** It is the strongest opacity, at most
  40%, at which the tint laid over the page stands no more than 1.4:1 from it
  and code on a code block keeps 4.5:1. That leaves body text at 7.6:1 or
  better, and it comes out between 14% (Black Light) and 40%. The inactive tint
  is the page's own text colour, solved by the same rule at 1.3:1 and at most
  25%. A port that re-solves must composite before it measures, because a
  contrast ratio does not look at alpha.
- **Keep it translucent.** It is laid over whatever is under it, so the
  selected part of a code block or a critique mark still shows. A tint mixed in
  advance is one colour everywhere. In Blue Dark that colour is all but the
  web's low-severity critique shading, so a selection inside a marked passage
  would disappear.

In the rendered view, the selection is **one rounded bar per line, fitted to
the words**, not a band across the full width of every line it crosses. The
shape is one pure function, `SelectionHighlightSegment.line(...)` in
`Shared/Sources/MarkdownEditorUI/SelectionHighlightGeometry.swift`.
`Web/public/app/core/selection-geometry.js` ports it line for line and is
tested against the same cases. Port it rather than drawing the shape by eye:

- **A bar's hard ends stand exactly on the carets** either side of the
  selection, with no padding, so a bar never reaches into a letter that is not
  selected. A narrow run, a lone "i", is hugged rather than widened. A run less
  than half a point wide is drawn `max(4, 0.3 × height)` wide so it shows: an
  empty line inside a selection, or a selected line break.
- **Where the selection carries on to the next line**, the bar runs past the
  last word by the fade length, `clamp(0.75 × height, 10, 24)`, and fades out.
  The next line's bar fades in from the same distance before its first word.
  Only the selection's real start and end are hard. The fade eases: smoothstep,
  sampled at quarters as 0, 0.156, 0.5, 0.844 and 1. A straight ramp shows a
  crease where it meets the flat part of the bar.
- **Corners are rounded by `min(0.22 × height, 6)`**, and never by more than
  half the bar's width.
- **A bar is its line's height less the spacing beneath it**, so a
  paragraph's lines stay separate bars instead of merging into a slab. The web
  cannot see line spacing, so it uses the line height less 2px, centred on the
  glyphs.
- **The space a line wraps at is not a chosen word.** It belongs to the line,
  but the bar fades out from the last word rather than from after the space.

Where a port draws the bars matters as much as their shape:

- **Draw them under the text and over the backgrounds.** macOS draws them after
  the code-block boxes and the critique marks, and before the glyphs. It stands
  its toolkit's own selection band down rather than painting over it, because a
  translucent tint over a square band leaves the square ends showing (I-252).
- **If the bars can only go over the text**, as on the web, a translucent wash
  dims the words. The web blends instead: `multiply` on a light page and
  `screen` on a dark one, in colours solved so the page comes out exactly the
  tint (`selectionPaint`). The letters keep their own colours, and a code block
  or a critique mark is shaded by the same amount.
- **The fades reach into the margin, where a toolkit's own redraw usually does
  not.** Remember everywhere a bar was drawn since the selection last changed,
  and invalidate all of it when the selection changes again. Otherwise faded
  ends are left behind (I-254).
- **The Markdown source view keeps the platform's standard selection.**

Reference: the suites "Selection highlight shape"
(`SelectionHighlightGeometryTests`) and "Editor color themes", which hold the
contrast in all sixteen themes, plus `Web/public/tests/selection-geometry.test.js`.
`make -C macOS check-selection-shape` reads a real rendered selection's pixels
back. The macOS README has the rules as T-22 and T-24 and the traps as I-252 to
I-255. The web's rows are WT-18 and WT-20.

### Typefaces

The document's face and the critique's hand are **two choices from one list**.
Customize Theme ▸ Font and the critique's hand menu offer exactly the same
faces, in the same groups, with each name set in its own face. The list is
`EditorTypeface` in `Shared/Sources/MarkdownEditorUI/EditorTypeface.swift`, and
the web's copy is `Web/public/app/ui/typefaces.js`. A port should keep one list
too, because two copies drift the first time either one gains a face.

The ids are **stored**, under `editorTypeface` for the page and
`critiqueHandFont` for the notes, so they never change:

| Id | Name | Group | Optical scale |
| --- | --- | --- | --- |
| `sans` | System Sans | first, and the default for both | 1.00 |
| `architectsDaughter` | Architects Daughter | Bundled | 1.19 |
| `caveat` | Caveat | Bundled | 1.28 |
| `indieFlower` | Indie Flower | Bundled | 1.12 |
| `patrickHand` | Patrick Hand | Bundled | 1.09 |
| `shadowsIntoLight` | Shadows Into Light | Bundled | 0.84 |
| `gloriaHallelujah` | Gloria Hallelujah | Bundled | 0.90 |
| `kalam` | Kalam | Bundled | 0.97 |
| `permanentMarker` | Permanent Marker | Bundled | 0.84 |
| `bradleyHand` | Bradley Hand | From your computer | 1.03 |
| `markerFelt` | Marker Felt | From your computer | 0.88 |
| `noteworthy` | Noteworthy | From your computer | 0.94 |
| `chalkboard` | Chalkboard | From your computer | 1.01 |
| `qeDaveMergens` | QE Dave Mergens | From your computer | 1.36 |
| `qeJulianDean` | QE Julian Dean | From your computer | 1.57 |

- **Bundled faces ship with the app**, each beside its licence. Seven are under
  the SIL Open Font License and Permanent Marker is under the Apache License
  2.0. The files are in `macOS/Packaging/Fonts` and `Web/public/fonts`.
- **Faces from your computer are offered only where they draw.** The Mac's menu
  calls this group *From your Mac*. The four Apple faces will usually be
  missing on Windows, and that is fine: an unavailable face is simply not
  listed.
- **QE Dave Mergens and QE Julian Dean are never shipped.** Their licence is
  for personal use and forbids embedding them in software or passing them on.
  They must not go in the app, its installer, the repository or the website. A
  user who installs them gets them offered like any other face on the machine.
- **Measure whether a face draws; do not ask.** On the web,
  `document.fonts.check()` says yes to a family that does not exist. A picker
  that offers a face and then silently draws another looks like the app
  ignoring the choice. A XAML `FontFamily` falls back silently too, so look the
  family up in the system font collection instead (DirectWrite's
  `FindFamilyName`).
- **The optical scale** is what a requested size is multiplied by so that every
  face reads at the same size. It is measured from x-height, the system face's
  over this one's, because the faces disagree about capitals far more than
  about lowercase. The numbers were measured against the Mac's system face, and
  the web uses them unchanged on every platform. A Windows port can do the same,
  or re-measure against its own system face by the same rule. Either way, store
  the id, never the scale.
- **Body text and headings take the face; code stays monospaced.** Headings
  keep their sizes. With System Sans the page is drawn exactly as it was before
  there was a choice.
- **Draw emphasis where a face has none.** Every hand ships in one weight and
  upright. Asked for the bold of one, a toolkit hands back the same face, so
  Bold appears to do nothing. Where a face lacks a bold or an italic, synthesise
  one: the Mac strokes for bold and slants for italic, the web takes the
  browser's synthesis, and DirectWrite has font simulations for both. Where a
  face has a real one, use it. Caveat is a variable font with a real bold.
  Never synthesise for the system face.
- **A stored face that no longer resolves reads as System Sans**, which is what
  the page would draw anyway.

Reference: the "Editor typeface" suite (`EditorTypefaceTests`) and
`Web/public/tests/typefaces.test.js`. The macOS README has the rules as T-16 to
T-21, and the web's rows are WT-16 and WT-17.

### Text size

Beneath the Font chooser is a **Size** slider: **75% to 150%, in steps of 5%**,
with the percentage beside it. It is the face's correction, because two hands
at the same size can look a size apart. It is chosen in Customize Theme with
the colours, and Cancel puts back the size the popover opened with. (The Mac
applies each choice as it is made, so the page is the preview; the web still
previews a draft and commits it on Apply.) It is kept app-wide as
`editorTextScale`, a number (1.25 for 125%).

- **It scales everything the rendered text is set with**: the type, the space
  between lines and paragraphs, and the indents of lists, quotes and code. So
  150% is the same page drawn larger, not larger words in the old spacing.
- **It does not scale** the column the text is set in, the pictures in it, or
  the Markdown source view.
- **At 100% the page is drawn with exactly the values it had** before the
  slider existed.
- **A stored value is clamped into range and rounded to a whole percent**, and
  anything that is not a number reads as 100%. Rounding is what makes a
  slider's 1.0000000000000002 the 100% it says it is.
- **Make Text Bigger and Make Text Smaller step through stops**: 0.75, 0.8,
  then every tenth to 1.5 (`EditorColorTheme.textScaleStops`). A size between
  stops moves to the next stop in that direction, so a size set on the
  slider's 5% steps comes back to a round number on the first press, and at
  either end the command does nothing.
- **The popover must not change width as the size changes.** The web's first
  version sized the popover to its preview, so a larger size or a wider face
  widened it, and the slider with it, which moved the thumb out from under the
  pointer mid-drag. The popover is now a fixed width. The preview wraps, and the
  popover grows downward only, below the slider.

Reference: `EditorColorTheme.textScale`, `clampedTextScale` and
`steppedTextScale`, tested in the "Editor text size" suite (`EditorTextScaleTests`), and
`Web/public/app/core/text-scale.js` with `Web/public/tests/text-scale.test.js`.
The macOS README has the rule as T-23, and the web's row is WT-19.

### Keyboard shortcuts

These are product, not platform courtesy, and a build should have them:

| Shortcut | Command |
| --- | --- |
| `Ctrl/⌘ B` | Bold |
| `Ctrl/⌘ I` | Italic |
| `Ctrl/⌘ U` | Underline |
| `Ctrl/⌘ K` | Insert link |
| `Ctrl/⌘ Alt/⌥ I` | Insert image |
| `Ctrl/⌘ Alt/⌥ M` | Cycle editor view |
| `Ctrl/⌘ Alt/⌥ O` | Open folder |
| `Ctrl/⌘ 1` – `6` | Heading 1 – 6 |
| `Ctrl/⌘ Alt/⌥ 0` | Paragraph (no heading) |
| `Ctrl/⌘ '` | Quote |
| `Ctrl/⌘ +` / `−` / `0` | Make text bigger / smaller / actual size, where the platform does not already take them for zoom |

Plus the platform's own document shortcuts — New, Open, Save, Save As, Close —
using whatever that platform's convention is.

The heading, quote and text-size keys arrived on the Mac first (§14.1 of the
macOS README); the web and Windows builds do not have them yet.

### Keeping the reader's place while re-styling

Replacing the whole text of a pane loses the reader's scroll position, and
every build has lost it that way at least once. Until rendering became
incremental this was the price of every keystroke everywhere: macOS, iOS and
the web build all re-styled by throwing the pane's contents away and building
them again, per character. None of them does that for typing any more. Each
re-renders only the blocks an edit disturbs — one on the Swift builds, and in
the browser the dirty blocks plus one either side, since a neighbour can
change where a block ends — and the count stays the same however long the
document is. But all three still replace a pane wholesale for the things that
genuinely change every character on screen: a palette or theme change, a
change of column width, opening a different document, or a revision arriving
from elsewhere.

So this section is not history. It governs those paths in every build today,
and it governs the *first* version of any new one, which will re-style the
whole pane on every keystroke because that is the obvious thing to write. These
rules were written from bugs rather than from a design, which is why they are
worth reading before a port rediscovers them.

The failure looks like the document jumping far down the page and snapping back
on a keystroke. Six rules prevent it, and each corresponds to a defect that
actually shipped:

1. **Restore an absolute offset, not a fraction of the travel.** A fraction is
   relative to the document's height, and typing changes the height, so
   restoring a fraction moves the text on almost every keystroke. Fractions are
   only meaningful for syncing *two different* documents, which is a different
   job.
2. **Never publish a position from a pane that has not finished laying out.**
   Partial layout describes the part measured so far, not the document. A pane
   20pt down a 29629pt file reported itself 17% of the way through because only
   114pt existed yet; applying that to the real height threw the other pane
   5198pt down. Report "don't know" rather than a number — which means the
   value must be nullable, since zero is indistinguishable from a reader parked
   at the top.
3. **Lay a pane out fully before applying a position to it.** The receiving
   side needs the same care as the sending side. A pane that has just been
   created has measured only the screenful it shows, and a document 136,017pt
   tall reports the 600pt of its viewport, so a reader 80% through lands at the
   very top.
4. **Reveal the caret last, and only if it is off screen.** Revealing before
   restoring the offset means the restore undoes the reveal. Revealing when the
   caret is already visible moves the page during ordinary typing. A caret
   straddling the edge of the viewport counts as off screen — testing for
   intersection rather than containment leaves it permanently half-hidden.

5. **Publish a selection change only when the writer caused it.** Replacing a
   pane's whole text storage makes the toolkit move the selection part-way
   through, before the intended one is put back. AppKit announces that
   intermediate value through the same delegate callback it uses for a real
   caret move, and it is not near the caret: 19,681 characters away in the case
   that was measured. Publishing it made the other pane reveal a caret the
   writer had not moved, so a split editor lurched down the document and back
   on every character typed — which is what this cost when a keystroke still
   replaced the storage. Typing no longer does, but opening a document and
   changing the palette still do, so suppress selection notifications while
   re-styling and publish the settled selection afterwards. UIKit does the same
   thing on `attributedText` assignment — the iOS build guards it — so a port
   should assume its toolkit does too until it has checked.

6. **Catch a pane up when it joins the split, not on every update.** Aligning
   one pane to the other applies a normalized *fraction*, and the two panes
   render the same text at different heights, so the operation is **not
   idempotent** — repeating it drags the idle pane further out of step each
   time. Declarative UI layers make this easy to get wrong: SwiftUI calls
   `updateNSView` for both panes on every keystroke, and the alignment sat in
   the function that call lands in, so 20 keystrokes produced 40 unwanted
   moves. Separate "register this pane" from "this pane is joining the split",
   and owe the catch-up again only when the layout genuinely changes — the view
   mode switches, or a pane leaves and comes back.

   Telling "joining" from "updating again" means holding pane identity, which
   carries its own trap: panes are held weakly because they are deallocated
   without a teardown call, and a freed address gets reused, so a new pane can
   inherit a dead one's identity and be mistaken for one that has already
   caught up. Prune identities to the live panes wherever the weak list is
   compacted. This was measured, not imagined — removing the pruning makes a
   replacement pane land on the dead pane's address and never align.

The arithmetic is shared and testable:
`Shared/Sources/MarkdownEditorUI/EditorScrollGeometry.swift`, with the recorded
numbers in `EditorScrollGeometryTests.swift`. The parts that are not pure —
which are the parts that broke — are asserted against real views by
`macOS/Scripts/check-scroll.swift`, and the coordination between panes by
`macOS/Scripts/check-session.swift`.

A trap that made a first version of those checks worthless: `NSTextView` never
shrinks its frame once grown, so re-styling an already-measured pane cannot
lose the offset and proves nothing. Whatever the platform equivalent is, the
state to test from is a pane that has *not* been measured yet. On UIKit the
shape of the problem is different again — assigning `attributedText` resets
`contentOffset` outright — so a port should establish what its own toolkit does
rather than assume this one transfers.

### The critique's score

A score is the one part of a critique that gets read without the notes, so it
must not be possible to raise it without changing the draft. The macOS README
records the rule as I-274 to I-276. Every build that scores a critique has to
match it, because two builds with the same critique and different numbers have
both stopped meaning anything.

- **What counts.** Every note counts against the draft, at 12 for high, 5 for
  medium and 2 for low, unless it is marked **Done**. A **dismissed** note still
  counts: dismissing is a decision to leave the passage as it is, not a fix.
  Each problem the summary lists counts 2, the weight of a low note, so that
  answering every note cannot reach 100 while the summary still names three
  things wrong.
- **How it is scored.** The score is `round(100 · e^(−penalty / 60))`, between
  1 and 100, and exactly 100 when nothing counts. It decays rather than
  subtracting, so every fix is worth something and no draft reaches zero.
- **Ready means the critic said so.** 100 reads **Ready** only when a critique
  of the draft exactly as it stands found nothing. A 100 reached by marking
  notes Done, or over a draft edited since, reads **Looks ready**, with
  **Critique again** beside it. Below that the bands are **Nearly there** from
  85, **Solid, with work to do** from 60, **Needs a pass** from 35, and **Needs a
  rewrite** under 35.
- **A fresh critique reopens a Done note it raises again**, and keeps a
  dismissal. Done means *fixed*, and the same objection about the draft as it
  stands says it was not. Carried over, the Done would hold the score at a
  hundred that no re-run could confirm.
- **The line under the score says why**, when the notes do not: how many notes
  are answered, that dismissed notes still count, and, once no note is open,
  that the problems in the summary still count. When the number explains
  itself, there is no line.
- **The critic is not asked to fill a quota.** The prompt asks for *up to*
  three problems, and for none when nothing holds the draft back, because each
  one now costs the score. With none listed, the overall read stands on its own
  and is not filed under what does not work.
- **The verdict changes on the edit that makes the draft stale**, not on the
  next redraw for some other reason. The web build first did this only when an
  edit moved a mark, and a clean critique has no marks.
- **A quick pass has no score.** It reads only for slips and serious problems,
  and a number out of it would look like a verdict on structure and voice it
  never read. It shows how many notes are left to fix instead.

The rule is `CritiqueScore` in
`Shared/Sources/MarkdownEditorCore/CritiqueScore.swift`, with
`CritiqueScoreTests.swift` as the specification. The web build ports it in
`Web/public/app/core/critique-score.js` and `critique-model.js`, tested in
`Web/public/tests/critique.test.js`. The web port was brought back into line in
the same change after it had kept the old rule, under which dismissing every
note printed 100 · Ready. The web build has no quick pass yet.

### Taking the reader to a criticised passage

Every build shades the passage each critique note is about, and every build
lets you press the note. What the press then does is the part worth writing
down, because the obvious spellings of it are all wrong in ways that read to
the person holding the mouse as the feature being broken.

**A press on a note is a reveal, never a toggle.** Pressing a note that is
already open must take the reader back to its passage. The toggle is the
tempting version — it is one line, and it gives you a way to turn the mark off
— and it is exactly wrong: somebody pressing a note a second time is doing so
*because the first press did not appear to do anything*, and what they get is
the mark going out. The macOS build shipped the toggle and it was reported as
"I have to click several times".

**Frame the passage; do not merely expose it.** Every toolkit has a
"scroll this into view" call, and every one of them does the *smallest* scroll
that makes the rectangle visible. A passage below the fold therefore lands hard
against the bottom edge of the window, half under the scrollbar, with nothing
after it to read — which is not what somebody who pressed a comment asked for.
Put it about a third of the way down instead, and let the clamp handle the rest:
a passage near the top of the document stays where it is, one near the end stops
at the document's last screenful, and a document shorter than the window does
not move. A passage taller than the window is the only case that is not a
clamp — start it at its first line, because a reader sent to a long quotation
wants to begin at its beginning.

**Do not move a passage the reader is already looking at.** Clicking a shaded
passage in the *text* raises its note, and that runs through the same reveal.
Moving the page under the pointer that just landed on it is the rudest thing
the feature can do. "Visible" is the wrong test, though — a passage sitting in
the last few points of the window is visible and is precisely what the reveal
exists to fix. Require a margin of air above and below before doing nothing is
the better answer.

**Measure before you scroll.** This is the one that only bites on long
documents, and it is the same trap as the previous section: a scroll offset is
clamped to the height the document has been *laid out to*, not to its real
height. Since re-styling throws layout away and every build rebuilds no more
than a screenful afterwards — measuring a long document per keystroke is felt
as typing lag — a pane the reader has just typed into has measured about a
window's worth. Asking it to scroll 280,000 points down lands at 400. Lay out
as far as the passage before asking where it is, and as far as the *target
viewport* before scrolling there. Only that far: laying out the whole document
on every press costs about fifty times as much and buys nothing.

The arithmetic is shared and testable —
`EditorScrollGeometry.offset(toReveal:)` and `isComfortablyVisible(_:)`, with
the recorded numbers in `EditorScrollGeometryTests.swift`. The parts that are
not pure are asserted against real views by
`macOS/Scripts/check-critique-reveal.swift`.

A trap that has nothing to do with scrolling and cost more than all of the
above: **selectable text swallows the press.** On macOS, SwiftUI's
`.textSelection(.enabled)` installs an AppKit view over the words, and that view
takes the click before any gesture on the card is reached — `hitTest` in the
middle of a note returns it rather than the hosting view. Since the words are
most of a note's area, the card answered a press on its margin and ignored one
on itself. Whatever the platform's equivalent is (a `<span>` with
`user-select`, a read-only text control), a port must check which element
actually receives the press on the note's text, and not assume that a handler
on the container sees it.

### Hovering a note tints its passage

A rail of notes beside a column of prose has a pointing problem: the note names
a passage, and on a long document the passage it names is often not the one
beside it. Pressing to find out is a poor way to ask a question, because
pressing also moves the page.

So the pointer answers it. **When the pointer rests on a note, the passage that
note is about changes colour where it is already on screen.** Three rules make
it work rather than annoy:

- **It never scrolls.** A hover is a question, not an instruction. If the
  passage is off screen, nothing happens — a page that moves when the pointer
  passes over a list is unusable.
- **Selection outranks hover.** A reader whose pointer is resting on the note
  they have already opened is looking at one thing, not two, and dropping the
  passage back to the weaker wash while the pointer sits over its card reads as
  the selection being lost.
- **The hover wash sits between the other two** — the resting mark's own
  colour, at an alpha halfway to the selected one. Keeping the hue means the
  hover reads as *more of the mark already there* rather than as a different
  kind of mark. Landing halfway is what keeps the three legible as an order: a
  hover a shade off resting cannot be seen, and one a shade off selected makes
  the press that follows look like it did nothing.

**A wash cannot carry the press on its own, so the open note's passage is also
ruled.** This is the part that reads as a nicety and is not. The three alphas
are an order, and an order is only readable when you can see two of them at
once — but a press replaces one wash with another in a place the reader is
usually not looking, and **when the passage was already on screen there is no
scroll to tell them anything happened either.** A difference of a few
hundredths of an alpha, under text, is a difference somebody reasonably reports
as the press having done nothing. So the open passage gets a solid rule under
it, in the severity's own tint — the colour its note is bordered in, so the
note and the passage read as one object.

Two things a port will be tempted to do instead, both worse. Making the
selected wash much louder puts the noise on top of the words the author is
trying to read; a rule is loud without being in the way, because it is not on
top of anything. And giving the hover a rule too collapses the distinction the
previous rule just bought: the reader asks a question by pointing and answers
it by pressing, and the two answers have to look different.

Hover state is **not** document state. It is not saved, it does not enter the
undo stack, and it does not mark the document as changed — it is where the
pointer is, which stops being true the moment it moves.

One implementation trap, and it is the same on every toolkit that reports hover
as two separate events: moving the pointer from one note straight to the next
delivers the *arrival* on the new note before the *departure* from the old one
often enough to matter. Clearing unconditionally on departure turns the new
highlight straight back off, which on screen is a flicker rather than a move.
Clear only when the note being left is still the one holding the pointer.

**While a note is open, every other passage steps back** to a fainter wash of
its own colour, so on a page with a mark in every paragraph the open passage is
the one that stands out. The order is selection, then hover, then receded, then
rest: hovering another note still tints its passage, because "which passage is
this?" has to be answerable with a note open as much as without. A port will be
tempted to hide the other marks instead, and it is worse. A mark is how a reader
finds a note from the draft, and a page shading only the open passage has lost
the map of the others and the places to click with it. The receded wash has to
stay visible: the faintest, a low note on white, measures ΔE 5.0 from the page
and 3.3 from the resting wash it replaces, and the tests hold every severity in
both modes to at least 4.6 and 3.

**Two notes' marks never run together.** A mark is padded beyond its words —
in the macOS build 3pt either side and 1pt above and below — and that padding
made two neighbouring sentences overlap by 2pt, on a line and between lines, so
their washes drew as one and nobody could tell which note owned which words.
Where two passages' words are apart and their marks would touch, both give way
to the midpoint and leave 2pt of page between them. A passage inside another,
or two that share words, has no gap to leave and is drawn as it is. It is the
padding that gives way, never the words.

**A passage is filled once**, as one shape, not once per line. Its own lines
overlap by the same padding, and a semi-transparent wash filled a line at a time
comes out at twice the alpha where they meet — a stripe between every pair of
lines that reads as the seam between two notes. The open note's rule follows the
line as measured, not the mark as cut, so it sits the same distance under the
words on every line.

The state machine, the four washes, the rule and the separation are shared and
testable: `Shared/Sources/MarkdownEditorUI/CritiqueHighlight.swift`, with
`CritiqueHighlightTests.swift` asserting the ordering, the hue, that twelve
distinct washes come out of three severities in four states, that the rule
belongs to the open state alone, and that `CritiqueHighlightLayout.separated`
leaves the gap between neighbours and only there.

### A note names where it is

The critic writes a location with every note, and it is not fit to show: the
same paragraph was "Opening, paragraph 2" on one read and "Opening, paragraph
1" on the next, because whether a title counts as a paragraph is a judgement
the model makes afresh each time, and the label was fixed at the moment of the
read, so a paragraph added above a note left it naming the one before. **The
place under a note is worked out from where the note is anchored**, from the
draft as it is now:

- The section is the nearest heading above the passage, its markup taken out
  and cut at a word past 32 characters, with an ellipsis. Before the first
  heading it is **Opening**; a draft with no headings says only **Paragraph
  2**.
- A level-one heading on the draft's first line is the **Title**, not a
  section, and does not count as a paragraph.
- Paragraphs are always numbered. A list, quote or code block is numbered only
  when its section has more than one.
- Blocks are counted the way the editor draws the draft, not the way CommonMark
  parses it, so the label agrees with the page.
- A passage in front matter keeps the critic's label; there is nothing to count.

The rules are `CritiqueOutline` and `CritiquePlace` in
`Shared/Sources/MarkdownEditorCore/CritiquePlace.swift`, with
`CritiquePlaceTests.swift` as the specification, including which edits can move
a place and so are worth recounting for. The web build does not do this yet.

### Noticing that the file changed underneath the editor

Any build that saves on a timer needs this, and the naive version is worse than
not having it. The decision is a pure function of three strings and belongs in
the portable core:

```
detect(editorText, lastKnownDiskText, diskText):
    if diskText == lastKnownDiskText:  none        # our own write
    if diskText == editorText:         none        # our own write, unannounced
    if editorText == lastKnownDiskText: reloadable # nothing here is at stake
    otherwise:                          conflict   # both hold work
```

`lastKnownDiskText` is whatever this app last read out of the file or wrote
into it. Comparing the file against **that** rather than against the text on
screen is the whole trick, and each branch rules out one specific way of
crying wolf:

1. Autosave writes *A*, somebody types on to *AB*, and only then does the write
   event arrive. At read time the file genuinely differs from the screen with
   nobody else involved. Branch 1 catches it; comparing against the screen
   would report every autosave as somebody else's change.
2. A save that goes through the platform's own document machinery never gets to
   announce itself. The only evidence those bytes are ours is that they match
   the screen — that is branch 2, and without it every manual save raises a
   false alarm.

Two things about the watcher, both learned the hard way:

- **Atomic replacement.** Nearly everything — other editors, `git`, `mv` —
  writes a temporary file and renames it over the target. That unlinks the
  inode a file descriptor is holding, so a watcher registered on the descriptor
  reports the first external save and is **deaf forever after**. That is worse
  than having no watcher, because it looks like it works. Watch for
  rename/delete as well as write, and re-arm on the *path*, tolerating the
  window where nothing is there yet. Test it with two consecutive replacements:
  the bug only shows on the second.
- **Suspend saving while a conflict is unanswered.** Otherwise the notice is
  pointless — the timer overwrites the other app's version seconds after
  pointing it out. If the platform's document system cannot be held off (iOS
  cannot), keep the incoming text in memory so it stays reachable, and say so.

Reference: `Shared/Sources/MarkdownEditorCore/ExternalDocumentChange.swift` and
`Shared/Sources/MarkdownEditorUI/FileChangeMonitor.swift`, with the wiring
asserted end to end by `macOS/Scripts/check-session.swift`. The web build
reaches the same outcome from a different direction — it has no file to watch,
so it re-reads the document whenever the tab comes back to the front.

### Closing a document stops its editor

An editor that saves on a timer, watches its file and runs a critique has three
things that outlive the document unless something stops them, and on macOS
27.2 nothing does it for you. A SwiftUI `DocumentGroup` keeps a closed
document's window alive, and the view in it is never told it has gone:
`onDisappear` does not run. The closed editor goes on working, and the ways
that shows are worse than the memory it holds:

- A file another app rewrites after its window has closed is still noticed,
  taken in and autosaved, to a document that no longer exists. That surfaces
  as a "couldn't autosave" alert over whatever the writer is doing next.
- Typing and closing inside the autosave's delay does the same, over a file
  that had in fact saved: the platform's document saved it as the window
  closed, and the timer fired afterwards.

So when a document's window closes:

1. **Drop** the pending autosave rather than flushing it. `NSDocument` has
   saved before its window closes; a second save after the close is the false
   alarm above. A port whose platform does not save on close must flush here
   instead, so check which yours is.
2. Stop watching the file.
3. Stop a critique that is still running.
4. Remove whatever was installed app-wide on the window's behalf. On macOS
   that is two local mouse monitors for the title bar.
5. Take the editor out of the window **while the window is still on screen**.

Hang this on the window's own close notification (`NSWindow.willCloseNotification`),
not on the UI framework's disappearance callback and not on the request to
close. A close the writer cancels from the save sheet must change nothing, and
the notification is not posted for one. Step 5's timing is measured, not
taste: taken down once the window had left the screen, the editor's layers
stayed behind, about 15 MB of footprint on every close of the 21,500-word
document. Taken down inside the close, then laid out and flushed there, eight
closes in a row add 0.4 MB of heap in all.

Test it against a document whose saves are counted, not the real one: on macOS
an autosave aimed at a closed document presents a modal error, which hangs an
unattended run instead of failing it. Type, let one autosave land as the
positive control, type again, close at once, and check the count stays put.
Then close a watched document, rewrite its file from outside, and check again.

Reference: `windowIsClosing(_:)` in `macOS/Sources/MarkdownEditor/WindowChrome.swift`
and `documentWindowClosed()` in `macOS/Sources/MarkdownEditor/MarkdownEditorView.swift`,
asserted by the "Closing a document window" checks in
`macOS/Scripts/check-window.swift`. The macOS README records the requirement
as D-42. The web build
has no window to close. A tab holds one document at a time, its watchers
follow the open document when it becomes a different one
(`Web/public/app/live.js`), and a hidden tab flushes its autosave rather than
dropping it, because nothing else will save it.

### The size a document window opens at

A window that opens too small for what it is already showing is a window whose
first use is being resized. Every build that shows the critique rail — the
column of editorial comments docked against the document's trailing edge; see
`macOS/README.md` §10a for the feature itself — will hit this, because the rail
is **open from the moment a document is**. It is not a panel you summon, it is
part of the document's furniture, and it says what it needs (an API key, a first
run) rather than waiting to be discovered. A window sized to the writing alone
therefore opens with the notes squeezing the column they dock to.

The opening size is derived, not picked:

```
width  = document column width + comments rail width
height = a screenful of prose
```

On the existing desktop build that is `700 + 356 = 1056` wide by `820` tall.
Those two numbers are the layout's own constants — the rail keeps a fixed width
rather than taking whatever room is spare, and the column has a default reading
measure — so a port should read its own pair rather than copy `1056`, or the
window and the layout will drift apart the first time either is tuned.

Four rules go with it, and each was paid for:

- **Use the same expression the "zoom to fit" affordance uses.** On macOS that
  is the green button; on Windows it is the maximise/restore behaviour a window
  chooses for itself. If opening and zooming are computed separately they
  disagree, and zooming a freshly opened window visibly resizes it for no reason
  the reader can see. One function, two callers.
- **Do not count a floating sidebar.** The file explorer floats *over* the
  document rather than taking part in the row, precisely so that opening it does
  not move the text. Widening the window to make room for it undoes that from
  the other side. Count only what is actually in the row.
- **Clamp to the screen, and let the minimum win.** Cap the derived size to the
  display's working area — `NSScreen.visibleFrame`, `MonitorInfo.rcWork`,
  `window.screen.availWidth/Height` — less an allowance for the window's own
  chrome, which on the macOS build measured 52pt of title bar and toolbar. Then
  take the maximum with the window's own minimum size: on a display too small
  for that minimum, a window that overflows beats one squeezed below the size
  its content refuses to go under. This ordering is the same one the explorer
  width uses.
- **It is a default, not a rule.** It applies when nothing has been saved for
  the window — a genuine first run. A restored window, or one the reader sized
  by hand, keeps what it had, with one exception: a window too narrow for the
  rail it is showing is widened once when it is first seen (see "Widening a
  window that is too narrow for its rail", below). Do not re-apply the default
  size on every launch, and never shrink a restored window to it. On SwiftUI
  that is `Scene.defaultSize`; the equivalents are WinUI's `AppWindow.Resize`
  guarded by "no persisted frame", and on the web a size written only when the
  stored layout is absent.

One thing measured on the macOS build that will save a port an hour: SwiftUI's
`defaultSize` is documented as the window's *content* size, but the number handed
to it came back as the window's **frame** — 1056 × 820 outside, 1056 × 768 of
content, the 52 being the title bar and toolbar. That is why the chrome
allowance is subtracted from the screen's working area rather than added to the
requested size: it is then correct under either reading. Settle this on your own
platform the same way it was settled here — launch with the saved window state
deleted and read the frame back — rather than from the layout code, which cannot
tell you which of the two a framework meant.

Reference: `Shared/Sources/MarkdownEditorUI/EditorPaneGeometry.swift`
(`idealContentWidth`, `defaultWindowContentSize` — both pure, both tested in
`EditorPaneGeometryTests`), wired up in
`macOS/Sources/MarkdownEditor/MarkdownEditorApp.swift` with the constants in
`Layout` at the foot of `MarkdownEditorView.swift`. The macOS README records the
reasoning as I-243 and I-267 to I-268.

### The narrowest a window may be, with the rail in it

The rail keeps a fixed width beside the document, so it does not shrink with the
window — a window dragged narrower clips it. Three rules keep it whole, and the
first alone is not enough:

- **The minimum width follows the rail.** While the rail is open the narrowest
  the window may be is the column's own minimum plus the rail — `360 + 356 =
  716` on the macOS build — and it falls back to the document's minimum (620)
  when the rail is shut. Under a flat 620 the column took 608 points and the
  rail got 12: it was dragged off the edge rather than closed, which reads as a
  panel that vanishes when a window is resized. The opening size's clamp
  (above) uses this same rail-open minimum, because that is what a new window
  opens showing.
- **Clamp the column against the room the rail leaves**, not against the
  window. With the floor raised to 716 a 700-point column still "fitted the
  window" and squeezed the rail to 16 points, because the column's clamp had
  never been told the rail was there. Subtract the rail from the width first,
  then clamp the column into what is left.
- **Reserve nothing for a resize handle that is no longer in a margin.** The
  column's width gripper normally hangs just outside the column, in the margin;
  with the rail open there is no margin, so it is drawn inside the column's edge
  instead — anywhere else it sits under the rail, which is drawn over it, and the
  document cannot be resized at all. Keep reserving the margin's width for it
  and a column that fits exactly loses those points: that is how a 1056-point
  window came to hold a 688-point column instead of 700.

Reference: `EditorPaneGeometry.minimumContentWidth(columnMinimum:documentMinimum:railWidth:railIsOpen:)`
and `gripperOffset(gripperWidth:bleed:railIsOpen:)`, both tested in
`EditorPaneGeometryTests`; the column clamp is `clampedWidth` in
`macOS/Sources/MarkdownEditor/MarkdownEditorView.swift`. The macOS README
records the reasoning as I-244 to I-246, and I-199 for where the gripper goes.

### Widening a window that is too narrow for its rail

The opening size covers a window with nothing saved, and the minimum keeps the
rail whole at any width by squeezing the column. Between the two is a window
that holds the rail only by taking the room from the writing: one restored at a
narrower width, which comes back with the rail open whatever it was showing
when it was sized, or one narrowed while the rail was shut and then shown the
rail again. Such a window is widened to the opening size's ideal width, at two
moments and no others:

- **When it is first seen**, once it is really on screen. Measured any earlier,
  the frame is the one the framework is about to replace and the widening is
  undone a moment later; the macOS build waits one turn of the run loop after
  the view lands in its window.
- **When the rail opens** on a window that is already on screen.

Not on every layout pass. The column's width changes on every drag of its
gripper, and a window that grew back to the ideal each time could never be made
smaller. Between those two moments the width belongs to the reader.

Three rules decide the new frame, and the order matters:

- **Never narrower.** A window wider than it needs is one somebody made that
  wide, including one wider than the screen.
- **Never wider than the screen's working area.** A display that cannot hold
  the pair gets the widest window it can show, rather than one running off the
  desk where the overflow cannot be reached.
- **Never moved unless it must be.** Grow on the trailing edge, where the rail
  is, so the writing stays where the reader left it. Slide the window left only
  when growing in place would push it off the right edge, and only by as much as
  that takes. A window that already fits is not touched at all, not even set to
  the frame it already has.

Closing the rail does **not** narrow the window again: taking the rail's width
back would move the writing to pay for a panel that was just dismissed, and
with the rail gone the page takes its bleed margins back, so the room is not
wasted. Zoom still offers the writing alone. Nor is the widening animated: the
rail appears in a single frame, so a window that took a moment to catch up would
spend that moment showing exactly the clipped rail this exists to prevent.

Reference: `EditorPaneGeometry.widenedFrame(_:toWidth:within:)`, tested in
`EditorPaneGeometryTests`, and called from `sizeToContentIfNeeded` in
`macOS/Sources/MarkdownEditor/WindowChrome.swift`; `make -C macOS check-window`
asserts it against a real window. The macOS README records the reasoning as
I-269 to I-272.

### The mark, and where it comes from

There is one application icon and every build shows it: the kirupa mark on a
white plate. It is **generated**, not drawn by hand per platform —
`macOS/Scripts/make-icons.swift` reads `macOS/Packaging/Logo.svg` and writes the
Mac `.icns`, the iOS PNG and the web `icon.svg` in one pass, from one set of
measurements. A port should add its output to that script rather than start a
second copy of the artwork, which is the mistake this arrangement was built to
undo: the web build carried a hand-written blue plate for months after the Mac
icon had stopped being blue, and the landing screen carried a *third* mark that
matched neither.

Four things a port has to get right, each measured rather than assumed:

- **Place the mark by its round body, not by its bounding box.** Size *and*
  centre on it, as though any accent were not there. On this mark the leaves
  stick out of the body at one corner and nothing balances them, so the full
  ink box's centre sits at (0.489, 0.484) of the artwork against the body's
  (0.540, 0.520) — about a twentieth of the icon, and plainly visible as a
  lean. The body is found as ink that is dark *and* near-neutral; brightness
  alone catches the `#008000` leaves, which are darker than the `#333333` ring.
  Measured, that outline bounds the whole body: the ring and the orange inside
  it are concentric to within a one-pixel antialiased fringe, so there is no
  third measurement to reconcile.
- **Do not "optically" correct for a broken outline.** This mark's ring is open
  — the leaves cross it, leaving a 40° gap — so its dark pixels weigh to the
  lower right, and it is tempting to shift the mark until that weight is
  centred. Two versions of that idea were built and both looked worse than what
  they fixed: the full correction crowds the accent into the plate's corner and
  opens an empty quarter opposite, and the gentler one still lifts the mark off
  centre. The gap is where the accent sits, not an error. Centre the body and
  let the accent overhang.
- **Size to the platform's own plate.** 0.66 of the plate where the platform
  gives the icon an inset plate of its own (macOS), 0.51 of the square where it
  rounds the corners off the artwork instead (iOS). The same fraction in both
  places puts the mark against the visible edge on one of them.
- **Show the same file on the landing screen.** macOS reads
  `NSImage.applicationIconName`; the web points an `<img>` at the same
  `icon.svg` it links as a favicon. Neither redraws the mark, so the Dock or
  tab, the file manager and the landing screen cannot disagree.

The artwork stays vector. The generator renders ten sizes from 16 to 1024
pixels, and a vector redrawn at each of them is sharp where one bitmap resampled
ten times is not.

### How long a draft is

Somebody writing to a slot — 600 words for a column, five minutes for a talk —
checks two numbers more than any others, and a build that cannot say them sends
the draft off to something that can. Every build shows them wherever it keeps a
document's subtitle; macOS puts them under the name in the title bar:

- `1,234 words · 6 min read` for the whole draft, and `1 word · 1 min read`
  for one word;
- `56 of 1,234 words` while a selection holds a word, and the whole draft's
  line again when it holds none — a caret, or a selection of only spaces and
  Markdown marks;
- `0 words` for a draft with none, rather than a reading time of nothing.

**The words are the critique's words.** They are `MarkdownProse.wordCount`, the
count that decides whether a draft is long enough to critique (thirty words), so
the title bar can never show 40 for a draft the critique turns away as too
short. It skips what a reader never reads as prose — fenced code, front matter,
link and image destinations, reference definitions, HTML tags and comments,
list and heading markers — and counts a run of non-space characters with a
letter or digit in it, so a dash between spaces is not a word and
`state-of-the-art` is one. Han, Hiragana and Katakana count a character a word,
which is how counts are conventionally given for them. A selection is counted
on its own text, never as a share of the whole: a share would have to know
where the code blocks fall, which is the one thing the count exists to know.

**The reading time is at 238 words a minute, rounded up.** That is Brysbaert's
2019 review of 190 studies of silent reading. The 200 most counters use is a
round number rather than a measurement, and adds a minute to every five.
Rounding up makes a 250-word post a two-minute read, and a single sentence a
minute rather than none.

Counting is one pass over the draft: 1.4ms on the 21,500-word document the
macOS typing measurements use. That is nothing once, and too much to add to
every keystroke on exactly the drafts where typing is slowest, so the count
waits for a quarter of a second without an edit. A document that opens shows
its count on its first frame.

The rules are `DocumentLength` and `MarkdownProse` in
`Shared/Sources/MarkdownEditorCore/`, with `DocumentLengthTests.swift` and
`MarkdownProseTests.swift` as the specification. The web build does not do this
yet.

### A draft is named by its title

A draft that has never been saved still has a name: the window shows it and
Save proposes it. Every build should make that name the draft's own title, as
its writer typed it. Left alone, macOS 26 and later name an untitled draft a
few seconds after its first autosave, and invent the name rather than read it:
on macOS 27.2 two drafts that both opened `# Field notes on speed` were offered
as "Field Notes on Speed" and "Draft Speed and Latency Notes". A writer who has
typed their title should not have to type it again in a save sheet, letter case
and all.

- **The title is the line the critique calls the Title** (see "A note names
  where it is"): a Heading 1 on the draft's first written line, front matter
  and blank lines aside, with its Markdown taken out. A draft that opens any
  other way has no title — including `# ` with no words after it, which is how
  every new document begins — and keeps whatever the platform calls it.
- **It is made safe to save, and otherwise left alone.** `: ` becomes ` - `, and
  any other colon or slash becomes `-`, because Finder will not take a colon and
  stores a slash as one: `# Speed: a field guide` is saved as "Speed - a field
  guide". Runs of spaces become one. Leading dots go, because a leading dot
  hides the file, and trailing dots, spaces, dashes and commas go. Past 80
  characters it stops at the last whole word that fits, or cuts at 80 when that
  would leave fewer than 40. Last, it is cut to 240 UTF-8 bytes: a name holds
  255 with its extension, and an emoji is four.
- **It follows the title** as the title is edited. When the title goes, the
  draft gets back the placeholder it opened under, "Untitled" or "Untitled 2",
  by that name: asking macOS for a fresh one named it "Untitled -1".
- **It never takes a name it did not give.** A duplicate arrives named
  "… copy" so that saving it cannot overwrite its original, and renaming it
  after its title would propose exactly the original's name. A name the writer
  types into the title bar is theirs to keep. Once saved, a document is named by
  its file, like any other.

`DocumentTitle` in `Shared/Sources/MarkdownEditorCore/DocumentTitle.swift`
holds what the title is and the name it makes, with `DocumentTitleTests.swift`
as the specification. Following the title is the platform's own document
machinery: on macOS it is `DraftNamer` in
`macOS/Sources/MarkdownEditor/TitleBarModel.swift`, asserted against real
windows by `make -C macOS check-window`. The web build does not do this yet:
an unsaved draft there is "Untitled", and Save proposes `Untitled.md`.

### A block quote has one bar

A quote drawn as an indent and nothing else reads, on a page of paragraphs, as
a layout slip rather than somebody else's words. Every build draws **a bar down
the left of a block quote**, in the quote's left inset: 3 points wide, rounded,
in the text colour at 28% so that it follows the theme.

**It is one bar for a run of quoted lines**, from the first line's text to the
last line's, through wrapped lines and the space between quoted paragraphs. A
line that is not quoted ends the run, so a paragraph between two quotes gives
each its own bar. This is the part a port gets wrong. A renderer that makes
each `>` line a block of its own and borders each block draws a dash beside
every line instead, because the gap between two blocks belongs to neither. The
web build did exactly that until the gap between two quoted lines was moved
from margin into padding. Measured in headless Chrome, three 18px dashes with
7px between them became one 68px bar: the same 68px the lines spanned before,
so the lines of a quote sit no closer together than the paragraphs around it.

**It is the same however little of it is redrawn.** A native text view redraws
only the rectangle that changed — a caret blink, a line of scrolling — and a bar
worked out from the text inside that rectangle comes out as a short piece of
itself. Find the run from the text, then clip it to the rectangle.

The styling is `RichMarkdownStyler`, which marks quoted text with
`.markdownQuoteBar`, and `EditorColorTheme.quoteBarColor`, with
`RichMarkdownStylerTests.swift` and `EditorColorThemeTests.swift` as the
specification. The macOS drawing is in
`macOS/Sources/MarkdownEditor/RichMarkdownTextView.swift`, and
`make -C macOS check-code-block-scroll` draws two quotes whole and then a strip
at a time, in both palettes, and checks that each comes out as one bar either
way. The web build's rule is `.me-block.me-quote + .me-block.me-quote` in
`Web/public/css/app.css`, kept there by `Web/public/tests/stylesheet.test.js`.

### Every control is named by what it does

A screen reader reads a control by its name, and a control left to its symbol
is named after the picture: on macOS, VoiceOver read Quote as "Lyrics",
Horizontal Rule as "Remove", Add Image as "Photo With A Plus Badge" and the
heading menu as "Change Text Size". Every build holds to four rules, each of
which a port meets in its own accessibility API — `accessibilityLabel` in
SwiftUI, `aria-label` on the web:

- **Name a control by what it does**, never by its icon. A formatting button is
  named by its tooltip's title, and the heading menu is **Paragraph Style**,
  which is what the web build already called it.
- **Hide a picture that only decorates.** The sparkles beside CRITIQUE and the
  folder in an empty explorer were each a stop of their own, read as "Sparkle"
  and "Move".
- **Say what a control holds as well as what it is.** The theme popover's size
  slider is **Text size**, valued "100%". If the platform makes the A at each
  end a button — SwiftUI does, and each steps the size by 5% — it is named
  **Smaller text** or **Larger text**; hidden, it was still a stop, and read as
  nothing. Where they are only decoration, as on the web, they are hidden.
- **Write capitals into the string, not the style.** A severity chip drawn
  "1 HIGH" must be read "1 high". SwiftUI's `.textCase(.uppercase)` reaches past
  the text into the button's name and hint, so VoiceOver was handed "1 HIGH"
  and "SHOWS ONLY THESE NOTES".

A name is checked by asking the platform what it would say, never by reading
the source. On macOS that is `make -C macOS check-voiceover`: 29 checks of the
names, values and presses the real views give VoiceOver, 15 of which fail
against the views as they were before these rules. The macOS README's §13.4
lists what each control is called.

### What is deliberately per-platform

Not everything is a requirement. These differ between the existing builds on
purpose, and a new build should decide for itself:

- Scroll and selection synchronisation between split panes (macOS has it, iOS
  does not)
- The file explorer (macOS and web have one, iOS does not)
- Where the formatting toolbar sits, and whether it is a toolbar at all
- Drag-and-drop and paste of images
- The welcome window and recent documents
- The title bar: what a double-click does, and where the document's path
  commands live, follow each platform's own convention. `Windows/README.md`
  says what that means on Windows.

## Properties, not just fixtures

The fixtures say what this implementation produces. They cannot say what *any*
implementation must never do, and a port will hit the second problem first —
usually by measuring characters instead of UTF-16 code units, or by trusting a
selection that arrived from the platform's text control.

These properties are checked in Swift by
`MarkdownFormattingInvariantTests`, `MarkdownRenderModelInvariantTests`,
`RichMarkdownStylerTests` and `MarkdownTextCodecInvariantTests`, over the same
corpus that generates the fixtures. They need no fixture file, so a port can
assert them from day one, before any output matches.

**Formatting.** For every command, over every selection of every corpus
document:

- The returned selection lies inside the returned text.
- It never begins or ends in the middle of a surrogate pair.
- No command returns empty text unless the document was already empty.
- A selection outside the document is clamped, never trapped or crashed on.
- Applying a heading level twice is the same as applying it once.
- Every command works on the empty document.
- Toggling an inline style twice restores the text, where the selection and its
  immediate neighbours contain no marker characters. Outside that, Markdown is
  genuinely ambiguous — see `macOS/README.md` §16.3.

**Render model.** For every corpus document, and for every prefix and every
suffix of one:

- Every span's rendered range lies inside the rendered text, and its source
  range inside the source, with neither splitting a surrogate pair.
- Rendering the same text twice gives the same model.
- `sourceRange(for:)` and `renderedRange(for:)` return ranges inside their
  target string for *any* input, including negative locations and lengths.
- The empty document renders to an empty model with no spans.

Prefixes and suffixes matter more than they look. A finished document has
balanced markup; a document being typed does not, and unterminated fences,
half-written links and lone `*` characters only exist in that state. Every
crash this renderer has had was in one.

**Styling.** The attributed string handed to the text control must be exactly
as long as the model text it came from. The span table is what maps an edit in
the rendered view back into the source, so one character of drift means every
later edit is written to the wrong offset in the file. No attribute run may
extend past the end of the string.

**Reading and writing.** Bytes in, identical bytes out — for every corpus
document, with and without a byte order mark. Line endings are preserved, never
normalised. Malformed UTF-8 is refused rather than repaired: replacing bad
bytes with U+FFFD and then saving overwrites the original with the damage.

## Reading order for a new build

1. This file.
2. `README.md` at the repository root — what the project is, and where storage
   is going.
3. `Contract/paths.json` and `Shared/Sources/MarkdownEditorCloud/CloudPath.swift`
   — small, and everything else rests on it.
4. `Contract/formatting.jsonl` with
   `Shared/Sources/MarkdownEditorCore/MarkdownFormatting.swift` beside it.
5. `Contract/render-model.json` with
   `Shared/Sources/MarkdownEditorCore/MarkdownRenderModel.swift`.
6. `Contract/edits.jsonl` with
   `Shared/Sources/MarkdownEditorCore/MarkdownIncrementalRenderer.swift`,
   once the render fixture passes — it is the step from showing a document to
   editing one.
7. `Web/README.md` §11 for the cloud model, and `Web/firebase/` for the rules —
   the web build is the one with a working cloud path, so it is the reference.
8. The README of whichever existing build is closest in shape to the one being
   written.

Port the pure logic first, get the fixtures passing, and only then build the
interface. That is the order the web build was written in, and it is why it
could be verified at all.

## Standing caveats

**Nothing about the Firebase project is outstanding any more.** The rules are
published and the Storage bucket exists: an unauthenticated read, an
unauthenticated write, and both Storage operations all answer `403`, where the
Firestore calls previously answered `200`.

What remains true is that **no build has been exercised end to end against the
real project**, because only Google sign-in is enabled and a token for it cannot
be minted headlessly. Every cloud test on every build runs against an in-memory
double. A port should treat the cloud path as written-and-conformant rather than
proven, and the first real sign-in is the moment to watch for.

**The rules themselves are now an exception to that**, and a port should use the
same escape hatch. `Web/firebase/run-rules-checks.sh` puts 29 checks through
Firebase's own rules engine in the emulators, including both deny-by-default
catch-alls and all three limits from either side of their edge, with thirteen
mutants killed. The Auth emulator issues ID tokens to anybody, so the
Google-only constraint above does not apply there — it never applied to the
emulators, which is worth stating plainly because this document previously
described the rules as unverifiable on the strength of it. They are language-
neutral HTTP checks against a `demo-` project, so a Windows port can run the
same script against the same two files and needs no .NET equivalent.

**So is the data path.** `Web/firebase/run-cloud-checks.sh` runs the web
build's real store against an emulated Firestore. Three results a port should
take as given rather than rediscover:

- The range query in `subtreeOf` **does** over-match. `path >= 'Notes'` and
  `path < 'Notes\uf8ff'` returns `Notes 2/Out.md` and `Notes.md` as well.
  Confirmed by issuing the bare range and looking. Filter on a separator
  afterwards or renaming a folder will drag its similarly named siblings along.
- A batch is **atomic**: one write that breaks the rules refuses the whole
  batch, including the valid writes beside it. The create-before-delete
  ordering depends on that, and it holds.
- A local write reaches its own listener **not at all**, provided the snapshot
  carrying `hasPendingWrites` is skipped. There is no second, confirmed
  snapshot to wait for — a listener without `includeMetadataChanges` is not
  woken merely because a write was acknowledged, since the data did not
  change. A port that skips the pending snapshot and then expects a confirmed
  one will hang waiting for it.

One caveat for whoever runs these: the emulator does **not** enforce
Firestore's 500-write batch limit — it accepted 613 in one batch — so a
functional test cannot catch a chunk size that production would refuse. Assert
the constant directly.

Every point above has since been reproduced by a **second, independent SDK** —
the Swift one, in `Shared/Firebase/run-emulator-checks.sh`. That matters for a
port: these were previously observations about how the JavaScript client
behaves, and two clients agreeing makes them observations about Firestore. The
one place the two builds deliberately differ is the name in the source, not the
name on the wire — Swift's `CloudNode.kind` is stored as `type`, because `type`
is what the rules validate and what the web build writes. A port should expect
to make the same split.

A practical note for a native check: the listener case cannot be tested with
one client. A client is not delivered its own write at all, so the write has to
come from a genuinely separate client instance, not merely a separate store
object sharing one connection.

Re-checked on 6 August 2026, with the commands to repeat the checks, in
[Web/README.md § 11b](../Web/README.md#setup-steps-that-cannot-be-done-from-this-repository).
The console work itself is done.
