# Humanish

A clean space to write documents that AI helps review, built for the Mac, for
iPhone and iPad, and for the browser (<https://www.kirupa.com/humanish/>).

All three keep Markdown as the canonical document underneath, and edit it the
*same* way. Rendering is an editable projection of the source, not a
replacement for it — so text you didn't touch comes back byte for byte, and a
folder written by one build opens in the others with every image still
resolving.

| | [macOS](macOS/) | [iOS](iOS/) | [Web](Web/) |
| --- | --- | --- | --- |
| Built with | SwiftUI + AppKit | SwiftUI + UIKit | ES modules + PHP |
| Dependencies | none | none | none |
| Files live | anywhere on disk | Files and iCloud Drive | in a workspace folder, `~/kirupaMarkdown` by default |
| Get started | `cd macOS && make install` | open `iOS/MarkdownEditor.xcodeproj` | `Web/serve.sh` |
| Publish it | — | — | `Web/deploy.sh` to any PHP host |
| On a phone | — | native, iPhone and iPad | a thumb-first layout, `⌃⌘M` or automatic |
| AI critique | yes, key in the Keychain | — | yes, bring your own key |
| Requirements | macOS 13+, Swift toolchain | iOS 17+, Xcode | PHP 8.1+ |

## What it does

- **Three editing modes** — rendered, side by side, or raw Markdown — with the
  rendered view fully editable and the two panes synchronized
- **A complete formatting toolbar and menu bar**: headings, bold, italic,
  underline, strikethrough, inline and fenced code, bulleted, numbered, and task
  lists, block quotes, links, and horizontal rules — all toggling, all with the
  standard shortcuts, and all greyed out while the caret is inside code, where
  Markdown is literal and a marker would only land in your source
- **Images** dragged, pasted, or chosen, copied into `<document>.assets/` beside
  the file and referenced relatively, with collisions resolved rather than
  overwritten — or referenced by web address and left where they are, which
  every build downloads and draws for real
- **Image sizing** by selecting an image and setting a width or height, the
  other following to keep the aspect ratio
- **A file explorer** with lazy expansion, reveal, and an ancestor path dropdown
- **File management**, in the web build: create, rename, duplicate, drag to move,
  and delete files and folders from the sidebar — with a document's images
  following it through a rename, and its references rewritten to match
- **Sixteen themes** — eight kirupa.com colors on a light/dark axis
- **Autosave**, undo that moves in meaningful units, and a welcome screen with
  recent documents

Each build's README is a full product requirements document:
[macOS](macOS/README.md) · [iOS](iOS/README.md) · [Web](Web/README.md).

The iOS build is newer than the other two and does not have all of it yet — no
file explorer, no split-pane sync, no cloud storage. Its README records the
gaps explicitly, along with what has and has not been verified by actually
running it on a simulator.

## Using it across devices

There is nothing to migrate. A document is a `.md` file, its images sit in a
`<stem>.assets/` folder beside it, and image references are relative — so a
folder is self-contained and can live anywhere.

- **macOS** — save into iCloud Drive, Dropbox, OneDrive, or Google Drive and
  keep working. The app isn't sandboxed, so any folder you can reach works, and
  it's built on the standard document system, so writes coordinate with the sync
  client rather than racing it.
- **iOS** — the system document browser reaches iCloud Drive and every other
  Files provider, and documents are edited in place rather than copied in.
- **Web** — point `MARKDOWN_EDITOR_WORKSPACE` at the same synced folder, or
  symlink `~/kirupaMarkdown` to it.
- **Or skip syncing entirely** — host the web build once and every device
  reaches the same files through a browser. `Web/deploy.sh` publishes to a
  shared PHP host, including the layout that keeps your documents above the
  document root. The editor has no accounts of its own, so put it behind the
  web server's own authentication before pointing it at anything private.

The one caveat: editing the same document on two devices at once produces a
conflict copy, because neither build merges. Details in
[Web/README.md § 5](Web/README.md#5-the-workspace).

## Where storage is going: cloud-first

The intended end state is one storage model everywhere — **Firestore is the
document store, and every device keeps an offline copy of what it has opened**.
Local files stop being an alternative destination and become the cache.

This is a direction, not a description. Where it actually stands today:

| Build | Talks to Firestore | Offline copy |
| --- | --- | --- |
| Web | Built and **switched off** behind one flag, because the console steps it needs are outstanding and a door that does not open is worse than no door. See [Web/README.md §11b](Web/README.md#11b-cloud-storage-and-accounts) | Yes, once it is switched back on |
| macOS | Not from the interface yet. The cloud core and the Firebase adapter are built and compile into the app's package | Yes, once wired up — the on-disk cache is switched on in `FirebaseConfiguration` |
| iOS | Same as macOS | Same as macOS |

So **no build can reach a cloud document from its interface today.** The web
build could, and it is switched off until the console work is done; the native
builds never could. What the native side has now is the layer
underneath: `Shared/Sources/MarkdownEditorCloud/` holds every cloud decision
with no Firebase in it at all — 49 tests, run by `run-tests.sh` in a third of a
second with no network — and `Shared/Firebase/` holds the adapter that puts
Firestore and Cloud Storage behind them. Both build for macOS and iOS. Neither
is reachable from a menu yet, and the adapter additionally needs an Apple app
registered in the Firebase console before it can sign anyone in — see step 4.

Getting the rest of the way needs, in order:

1. ~~**Enable Cloud Storage and publish the security rules.**~~ **Done on
   6 August 2026.** The bucket exists and the rules are published: an
   unauthenticated read, an unauthenticated write, and both Storage operations
   now answer `403`, where the Firestore calls previously answered `200` and an
   empty result. The commands to repeat every check are in
   [Web/README.md § 11b](Web/README.md#setup-steps-that-cannot-be-done-from-this-repository).
2. **Verify the cloud path against the real backend.** Every cloud decision is
   tested against an in-memory Firestore; not one byte has been written to the
   real one. Making Firestore the default while that is true would be reckless.
   This needs a real interactive Google sign-in — the only provider enabled — so
   it cannot be done by a script, and with no JDK on the build machine the
   Firebase emulator is not an alternative. What has been done instead is to
   make the in-memory Firestore *enforce the published rules on every write*, so
   a write the real server would reject can no longer pass the suite.
3. **Make cloud the default in the web build**, with local demoted to a fallback
   for anyone not signed in.
4. **Add Firestore to the native builds.** Half done, and the half that is done
   is the half with the decisions in it. This carried a reversal of this
   project's no-third-party-dependencies rule, made deliberately: the Firebase
   Apple SDK is now a dependency. The alternative — Firestore's REST API over
   `URLSession`, keeping the rule intact — cannot subscribe to changes, so live
   updates would become polling, and the offline cache would have to be written
   by hand. Both are the reasons the SDK exists, so writing them again by hand
   to avoid it would have been the wrong trade.

   The dependency is quarantined. `Shared/Package.swift` still has none, so
   `run-tests.sh` neither downloads nor builds Firebase; the SDK is declared in
   a second package, `Shared/Firebase/`, which nothing depends on yet and which
   only the apps ever will. It builds for macOS and iOS, and
   `swift test --package-path Shared/Firebase` covers its configuration.

   **Before any of it can run, the project needs an Apple app registered.** A
   Firebase app ID belongs to a registered app, and the one in
   `FirebaseConfiguration` is the *web* app's ID with `web` changed to `ios` —
   well-formed, right project, not a real app, because the web app's hash cannot
   also belong to an Apple one. It is named `placeholderAppID` and checked
   before sign-in opens a browser, so the failure says which console step is
   missing rather than surfacing as an OAuth error. Fixing it is one action:
   Firebase console ▸ Project settings ▸ Your apps ▸ add an Apple app with
   bundle ID `com.kirupa.markdown-editor`, then paste its app ID in. One
   registration covers both apps, as they share the bundle ID.

   After that, what is left is the interface: sign-in, a cloud document list,
   and open/save wired to `CloudWorkspace`.

### How images fit

Images are the one part of the data that does **not** live in Firestore. They go
to a **Cloud Storage bucket**, with Firestore holding only a pointer:

```
Firestore   users/{uid}/nodes/{id}     type: 'asset', storagePath, url, contentType
Storage     users/{uid}/<path>#<ts>    the actual bytes, 10 MB cap
```

Firestore's 1 MiB document limit is what decides this. Base64 inflates bytes by
about a third, so storing an image inline would cap it near 700 KB while eating
the same budget the document text needs — too small for an ordinary screenshot.

The Markdown itself never contains a Storage URL. It keeps the relative
`<stem>.assets/name.png` reference that all four builds already write, and the
URL is resolved when the document renders. That is what keeps a document
portable between them.

The catch worth knowing: **Firestore's offline persistence does not extend to
Storage.** Documents opened on a device are available offline; their images are
not, unless the browser happens to have them in its HTTP cache. Closing that
gap needs an explicit image cache, and it cannot be built yet because the bucket
does not exist. Both points are recorded in
[Web/README.md § 11b](Web/README.md#working-offline).

## Repository layout

```
Shared/   The Swift core and styling, compiled by both native apps
macOS/    The Mac app: SwiftUI + AppKit, bundle scripts, icons, PRD
iOS/      The iPhone and iPad app: SwiftUI + UIKit, Xcode project, PRD
Web/      The browser app: PHP backend, ES modules, PRD
Contract/ What every build must agree on, as runnable fixtures
Windows/  The brief for a WinUI 3 build. Not written yet
```

Starting the Windows build? Read [`Windows/README.md`](Windows/README.md)
first. The short version: WinUI 3 cannot be compiled on macOS, so run that
session on Windows, and port the platform-independent half — which is most of
it — against [`Contract/`](Contract/README.md).

## How the three stay in step

Two different mechanisms, because only two of the three can share Swift.

**macOS and iOS share source.** The Markdown parser, the range mapping, the
formatting commands, the image importer, the type scale, and all sixteen
palettes are the same files, in `Shared/`, compiled once per platform. They
cannot drift, because there is nothing to drift from.

That sharing turned up something worth knowing: `NSColor.blended` does not
interpolate in sRGB — it converts to Apple's Generic RGB (different primaries,
gamma 1.8), mixes, and converts back, so black halfway to white is 0.573 rather
than 0.5. UIKit has no equivalent, and a naive sRGB blend was off by up to
46/255. The portable implementation reproduces AppKit to within 1/255 on every
colour the app displays, which is asserted by test. It matters beyond iOS,
because `themes.css` is generated by compiling that same Swift.

**The web build is a port, and the port is verified rather than trusted:**

- `render-model.js` and `formatting.js` are line-by-line ports of their Swift
  counterparts, relying on the fact that Swift `NSString` offsets and JavaScript
  string indices are both UTF-16 code units
- They were differential-tested against the compiled Swift — 14,148 formatting
  cases and 41 documents through the render model, comparing output text, every
  style span, and every range mapping, with zero mismatches
- `Web/public/css/themes.css` is *generated* by compiling the app's real
  `EditorColorTheme.swift`, so derived colors cannot drift

**And now anything else can be checked the same way.** That differential test
was real, but the harness that ran it was never committed, so the number above
outlived any means of repeating it — and a fourth build could not have used it
at all. `Contract/` fixes that. It is the compiled Swift's behaviour exported as
language-neutral fixtures: 9,471 formatting cases, every render-model span with
its source mapping, and 123 path cases, including the emoji and CRLF documents
that catch the mistakes a port actually makes.

```bash
swift run --package-path Shared markdown-contract Contract
```

A test regenerates and compares them, so a fixture that no longer describes the
code fails the suite instead of quietly misleading whoever ports next.
[`Contract/README.md`](Contract/README.md) explains the formats and, just as
importantly, writes down the parts that *cannot* be a fixture: the Firestore
field names, the Cloud Storage object paths, the sort collation, and which
features are deliberately left to each platform.

## Tests

```bash
macOS/Scripts/run-tests.sh      # 847 tests — the shared Swift core, both apps
php Web/tests/php/run.php       # 95 tests — the PHP backend
open http://127.0.0.1:8000/tests/   # 505 tests — the browser client
node Web/tests/run.mjs          # 496 tests — the same, minus the DOM tests,
                                #   plus 5 that check the code still agrees
                                #   with the published Firebase rules, and the
                                #   render model measured against Contract/,
                                #   which is not served to the browser

swift test --package-path Shared/Firebase   # 5 tests — the Firebase adapter
```

The last one is deliberately separate. `Shared/Package.swift` declares no
dependencies at all, so `run-tests.sh` neither downloads nor builds the Firebase
SDK and the fast loop stays fast; the SDK is declared in a second package that
only the apps will depend on.

The browser page is the one that needs nothing but PHP, and it is where the DOM
tests run. It is not a superset, though: the rules-conformance tests read the
`.rules` files off disk, so they run only under node. Both are worth running
before a change to the cloud backend.
