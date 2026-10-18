<?php

declare(strict_types=1);

// A shared host rarely lets you repoint the document root, so the public files
// end up in a URL subdirectory while the rest of the app stays above it, out
// of reach of the web. MARKDOWN_EDITOR_HOME names that private folder; unset,
// the layout is the one in this repository.
$home = getenv('MARKDOWN_EDITOR_HOME') ?: ($_SERVER['MARKDOWN_EDITOR_HOME'] ?? '');
require (is_string($home) && $home !== '' ? rtrim($home, '/\\') : __DIR__ . '/..')
    . '/bootstrap.php';

use MarkdownEditor\Workspace;
use MarkdownEditor\WorkspaceError;

// Resolving the workspace here means a misconfigured install says so on a
// styled page instead of failing later inside a fetch the user cannot see.
$workspaceName = '';
$startupError = null;
try {
    $workspaceName = Workspace::prepare()->name();
} catch (WorkspaceError $error) {
    $startupError = $error;
}

// Cache busting.
//
// A query string only versions the URLs written on this page. The imports
// *inside* a module are plain static paths that no query string reaches, so a
// cache holding a new main.js against a stale welcome.js loads a module graph
// that fails outright — which is exactly what a 31-day CDN policy did to the
// first deploy of this file. A deploy therefore puts the whole asset tree in a
// directory named after its contents and writes asset-base.php beside this
// file; every module URL then changes together, and relative imports inherit
// the versioned directory for free. Locally there is no such file and assets
// are served straight out of app/ and css/.
$assetBase = '';
if (is_file(__DIR__ . '/asset-base.php')) {
    $assetBase = trim((string) require __DIR__ . '/asset-base.php', '/');
}
$asset = static fn (string $path): string => $assetBase === '' ? $path : "$assetBase/$path";

?><!DOCTYPE html>
<html lang="en" data-theme-color="blue" data-appearance="light">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>Humanish</title>
<link rel="icon" href="icon.svg" type="image/svg+xml">
<link rel="stylesheet" href="<?= htmlspecialchars($asset('css/themes.css'), ENT_QUOTES) ?>">
<link rel="stylesheet" href="<?= htmlspecialchars($asset('css/app.css'), ENT_QUOTES) ?>">
<!-- The critique's typefaces. Outside the versioned asset tree on purpose: a
     stylesheet inside it resolves url() from wherever the deploy put it, which
     is a different depth from the repository layout, so the font paths would be
     right in one and a 404 in the other. See hands.css. -->
<link rel="stylesheet" href="hands.css?v=<?= htmlspecialchars($assetBase === '' ? '0' : $assetBase, ENT_QUOTES) ?>">
</head>
<body>
<?php if ($startupError !== null): ?>
<div class="me-startup-error">
  <h1>Humanish cannot start</h1>
  <p><?= htmlspecialchars($startupError->getMessage(), ENT_QUOTES) ?></p>
  <p class="me-startup-error__recovery">
    <?= htmlspecialchars($startupError->recoverySuggestion(), ENT_QUOTES) ?>
  </p>
</div>
<?php else: ?>
<div class="me-app" id="app" hidden>

  <div class="me-menubar" role="menubar" id="menubar">
    <span class="me-menubar__title">Humanish</span>
  </div>

  <div class="me-toolbar" id="toolbar"></div>

  <!-- Mobile layout (WB-*): replaces the menu bar and toolbar above. The
       formatting bar is the header's second row — see WB-26. -->
  <div class="me-mobile" id="mobileBar" hidden></div>
  <div class="me-format" id="formatBar" role="toolbar" aria-label="Formatting" hidden></div>

  <div class="me-body">
    <aside class="me-sidebar" id="sidebar" aria-label="File explorer">
      <div class="me-sidebar__header">
        <button type="button" class="me-sidebar__path" id="explorerPath"
                aria-haspopup="menu" aria-expanded="false">
          <span id="explorerPathLabel"><?= htmlspecialchars($workspaceName, ENT_QUOTES) ?></span>
          <svg viewBox="0 0 10 6" aria-hidden="true" class="me-chevron">
            <path d="M1 1l4 4 4-4" fill="none" stroke="currentColor" stroke-width="1.5"/>
          </svg>
        </button>
        <button type="button" class="me-icon-button" id="explorerNewDocument"
                title="New document" aria-label="New document">
          <svg viewBox="0 0 16 16" aria-hidden="true"><use href="#icon-new-document"/></svg>
        </button>
        <button type="button" class="me-icon-button" id="explorerNewFolder"
                title="New folder" aria-label="New folder">
          <svg viewBox="0 0 16 16" aria-hidden="true"><use href="#icon-new-folder"/></svg>
        </button>
        <button type="button" class="me-icon-button" id="explorerReveal"
                title="Show the current document's folder" aria-label="Show the current document's folder">
          <svg viewBox="0 0 16 16" aria-hidden="true"><use href="#icon-target"/></svg>
        </button>
        <button type="button" class="me-icon-button" id="explorerRefresh"
                title="Refresh" aria-label="Refresh">
          <svg viewBox="0 0 16 16" aria-hidden="true"><use href="#icon-refresh"/></svg>
        </button>
      </div>
      <div class="me-sidebar__tree" id="explorerTree" role="tree" tabindex="0"></div>
    </aside>

    <div class="me-divider me-divider--sidebar" id="sidebarDivider" role="separator"
         aria-orientation="vertical" aria-label="Sidebar width" tabindex="0"></div>

    <main class="me-editor" id="editor">
      <div class="me-notice" id="externalNotice" hidden role="status">
        <span class="me-notice__text" id="externalNoticeText"></span>
        <span class="me-notice__actions">
          <button type="button" class="me-notice__button" id="externalNoticeKeep"
                  title="Keep what is on screen; the next save writes it over the other version">Keep Mine</button>
          <button type="button" class="me-notice__button me-notice__button--primary"
                  id="externalNoticeReload"
                  title="Discard the unsaved edits here and show the newest version">Show Newest</button>
        </span>
      </div>
      <!-- One view. The Markdown and Side-by-Side panes are gone, following the
           Mac: a rendered view that is genuinely editable makes a second pane
           showing the same document a second place to look rather than a second
           thing to see. -->
      <div class="me-editor__panes" id="editorPanes">
        <div class="me-pane me-pane--rich" id="richPane">
          <div class="me-surface" id="richSurface" role="textbox"
               aria-multiline="true" aria-label="Document" spellcheck="true"></div>
        </div>
      </div>
    </main>

    <!-- WA-*: the critique rail. Docked against the document rather than
         floating beside it, because the notes are *about* the text they sit
         next to. `hidden` from the start: an empty rail on a first visit is a
         column of nothing taking a third of the window. -->
    <aside class="me-critique" id="critiqueRail" aria-label="Critique" hidden></aside>
  </div>

  <div class="me-statusbar" id="statusbar">
    <span id="statusDocument">No document</span>
    <span class="me-statusbar__spacer"></span>
    <!-- Hidden from the start: with one place documents can go there is
         nothing for this to say, and it is only unhidden when the cloud
         is switched back on. An element the code only ever *unsets*
         hidden on has to be written hidden (WY-23). -->
    <span class="me-statusbar__storage" id="storageIndicator" hidden></span>
    <span id="statusSaved"></span>
  </div>

  <div class="me-drawer-scrim" id="drawerScrim" hidden></div>
</div>

<div class="me-welcome-backdrop" id="welcome" hidden></div>
<div class="me-popover-layer" id="popoverLayer"></div>
<!-- `hidden` from the start: this layer carries the dimming behind a dialog, and
     dialogs.js only ever *unsets* it. Without it the whole app is dimmed 28%
     until some dialog happens to open and close. -->
<div class="me-alert-layer" id="alertLayer" hidden></div>

<svg style="display:none" aria-hidden="true">
  <symbol id="icon-target" viewBox="0 0 16 16">
    <circle cx="8" cy="8" r="5.2" fill="none" stroke="currentColor" stroke-width="1.4"/>
    <circle cx="8" cy="8" r="1.6" fill="currentColor"/>
  </symbol>
  <symbol id="icon-refresh" viewBox="0 0 16 16">
    <path d="M13 8a5 5 0 1 1-1.6-3.7" fill="none" stroke="currentColor"
          stroke-width="1.4" stroke-linecap="round"/>
    <path d="M13 2.2V5h-2.8" fill="none" stroke="currentColor"
          stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/>
  </symbol>
  <symbol id="icon-new-document" viewBox="0 0 16 16">
    <path d="M3.6 1.9h5L12 5.2v4.1" fill="none" stroke="currentColor" stroke-width="1.3"
          stroke-linecap="round" stroke-linejoin="round"/>
    <path d="M3.6 1.9v12.2h4.2" fill="none" stroke="currentColor" stroke-width="1.3"
          stroke-linecap="round" stroke-linejoin="round"/>
    <path d="M8.4 2v3.4h3.4" fill="none" stroke="currentColor" stroke-width="1.3"
          stroke-linejoin="round"/>
    <path d="M11.6 10.4v4.2M9.5 12.5h4.2" fill="none" stroke="currentColor"
          stroke-width="1.4" stroke-linecap="round"/>
  </symbol>
  <symbol id="icon-new-folder" viewBox="0 0 16 16">
    <path d="M1.8 12.4V4a1.2 1.2 0 0 1 1.2-1.2h2.6l1.3 1.5h4.3" fill="none"
          stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"/>
    <path d="M1.8 12.4a1 1 0 0 0 1 1h5.1" fill="none" stroke="currentColor"
          stroke-width="1.3" stroke-linecap="round"/>
    <path d="M14.2 5.5v2.3" fill="none" stroke="currentColor" stroke-width="1.3"
          stroke-linecap="round"/>
    <path d="M11.9 11.4v4.2M9.8 13.5H14" fill="none" stroke="currentColor"
          stroke-width="1.4" stroke-linecap="round"/>
  </symbol>
</svg>

<script type="module" src="<?= htmlspecialchars($asset('app/main.js'), ENT_QUOTES) ?>"></script>
<?php endif; ?>
</body>
</html>
