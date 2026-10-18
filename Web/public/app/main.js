// Application wiring.
//
// Everything user-visible is assembled here: the editing surface, the command
// table shared by the toolbar and menus, image import, the explorer divider,
// and the critique rail.
//
// There is one view. The Markdown and Side-by-Side panes are gone, following
// the Mac (macOS PRD I-142): a rendered view that is genuinely editable makes
// a second pane showing the same document a second place to look rather than a
// second thing to see, and the raw source is still one keystroke away in any
// text editor.

import { api, ApiError } from './api.js';
import {
  restoreStorage, storageMode, isCloud, currentAccount, useCloud, signOutAndUseLocal,
  cloudIsAvailable,
} from './storage.js';
import { MarkdownDocumentModel } from './document.js';
import { startLiveUpdates } from './live.js';
import { makeRange, maxRange } from './core/range.js';
import { MarkdownRenderModel } from './core/render-model.js';
import {
  InlineStyle,
  ListStyle,
  applyHeading,
  insertHorizontalRule,
  insertLink,
  insertImage,
  setImageSize,
  moveImage,
  toggleInline,
  toggleList,
  toggleQuote,
  wrapCodeBlock,
  isInlineStyleAvailable,
  isLinkAvailable,
} from './core/formatting.js';
import { codeContextInModel } from './core/code-context.js';
import { renderInto } from './ui/renderer.js';
import { EditorSurface } from './ui/editor-surface.js';
import { positionForOffset } from './dom-text.js';
import { Explorer } from './ui/explorer.js';
import { buildToolbar } from './ui/toolbar.js';
import { buildMenus } from './ui/menus.js';
import { WelcomeScreen, recentDocuments, savedDocuments } from './ui/welcome.js';
import { buildMobileUI } from './ui/mobile.js';
import { ImageSelection } from './ui/image-selection.js';
import { SelectionHighlight } from './ui/selection-highlight.js';
import {
  chooseImageSource,
  confirmAction,
  confirmDiscard,
  showError,
  showPrompt,
} from './ui/dialogs.js';
import { theme, openThemePopover } from './ui/theme.js';
import { CritiqueRail } from './ui/critique.js';
import {
  clearCritiqueHighlights,
  paintCritiqueHighlights,
} from './ui/critique-highlights.js';

const SIDEBAR_KEY = 'markdown-editor.sidebarVisible';
const SIDEBAR_WIDTH_KEY = 'markdown-editor.sidebarWidth';
const LAYOUT_KEY = 'markdown-editor.layout';

/** Below this the desktop toolbar cannot lay out without wrapping (WB-3). */
const MOBILE_MAX_WIDTH = 820;

const element = (id) => document.getElementById(id);

theme.apply();

const model = new MarkdownDocumentModel();

/**
 * The one render model, kept up to date rather than rebuilt.
 *
 * It holds a reference to the source it describes — the same string the
 * document holds, not a copy — so asking it for the model of a source it is
 * already on costs a comparison, and asking it for the model of a source one
 * character away costs one line.
 */
const renderModel = new MarkdownRenderModel();

function modelFor(source) {
  return renderModel.update(source, model.lastChange);
}
/**
 * WT-13: the explorer starts closed. A first visit opens on the document alone;
 * the nav is one click away and, once opened, is remembered. Only an explicit
 * `'true'` counts, so the calm state is what an unconfigured browser gets.
 */
let sidebarVisible = localStorage.getItem(SIDEBAR_KEY) === 'true';

/**
 * WB-2: the layout is a remembered choice. A first visit guesses from the
 * screen — coarse pointer or a window too narrow for the toolbar — but once
 * the user picks, the guess never overrides them again.
 */
const storedLayout = localStorage.getItem(LAYOUT_KEY);
let mobileLayout =
  storedLayout === null
    ? window.matchMedia(`(max-width: ${MOBILE_MAX_WIDTH}px), (pointer: coarse)`).matches
    : storedLayout === 'mobile';

/** The drawer is transient, unlike the desktop sidebar preference. */
let drawerOpen = false;
let config = { workspaceName: 'Workspace', imageExtensions: [] };

/**
 * The rendered pane's projection. Every mapping goes through the render model,
 * which is rebuilt whenever the source changes — the model is the only thing
 * that knows where a rendered character came from.
 */
const richProjection = {
  render: (source) => renderInto(element('richSurface'), modelFor(source), resolveImageURL),
  textFor: (source) => modelFor(source).text,
  toSource: (source, range) => modelFor(source).sourceRange(range),
  // Typing, cut and paste: removing a line break takes the markers hidden
  // beside it, or they surface as text (I-330).
  toSourceEdit: (source, range, replacement) =>
    modelFor(source).sourceRangeReplacing(range, replacement),
  toSurface: (source, range) => modelFor(source).renderedRange(range),
  // Block-level access, so an edit can be read from the blocks it touched
  // instead of from the whole surface.
  layoutFor: (source) => modelFor(source),
};

const richSurface = new EditorSurface(element('richSurface'), richProjection, model);

// T-24: the selection is drawn by the editor, rounded and fading across lines.
const selectionHighlight = new SelectionHighlight(element('richSurface'));

const explorer = new Explorer({
  tree: element('explorerTree'),
  pathButton: element('explorerPath'),
  pathLabel: element('explorerPathLabel'),
  refreshButton: element('explorerRefresh'),
  revealButton: element('explorerReveal'),
  newDocumentButton: element('explorerNewDocument'),
  newFolderButton: element('explorerNewFolder'),
});

const welcome = new WelcomeScreen(element('welcome'), {
  newDocument: () => commands.newDocument(),
  open: () => commands.open(),
  openPath: (path) => openDocument(path),
  storageChanged: () => adoptStorage(),
});

/**
 * Re-reads everything that depends on which storage is active (WR-4).
 *
 * Switching storage does not just change where a save goes; it changes what
 * documents exist. The open document is closed rather than carried across,
 * because keeping it would leave the editor showing a file from one place
 * while saving to another.
 */
async function adoptStorage() {
  model.reset();
  try {
    config = await api.config();
    welcome.workspaceName = config.workspaceName;
    explorer.rootName = config.workspaceName;
    await explorer.setRoot('');
  } catch (error) {
    showError(error);
  }
  updateStorageIndicator();
  restartLiveUpdates();
  updateStatus();
}

/**
 * WC-7: subscriptions belong to the backend that created them.
 *
 * Restarted rather than kept, on every storage change, because a listener
 * opened against one account's documents means nothing after a switch to
 * another account — or to the server's disk, which pushes nothing at all.
 * Tearing down first also guarantees the old listeners are released even when
 * the new backend opens none.
 */
let stopLiveUpdates = null;
/** The revision another device wrote that this browser has not applied. */
let pendingExternalRevision = null;

function showExternalNotice(kind, message) {
  const notice = element('externalNotice');
  const text = element('externalNoticeText');
  if (!notice || !text) return;
  notice.dataset.kind = kind;
  text.textContent = message;
  notice.hidden = false;
  element('externalNoticeKeep').hidden = kind !== 'conflict';
  element('externalNoticeReload').hidden = kind !== 'conflict';
}

function hideExternalNotice() {
  pendingExternalRevision = null;
  const notice = element('externalNotice');
  if (notice) notice.hidden = true;
}

/**
 * WC-10. Another device's revision arrived while there are unsaved edits here.
 *
 * Held rather than dropped, and said so persistently rather than in a status
 * flash: this browser is the only place that copy exists, and the whole point
 * of the notice is to make it reachable. Autosave still writes this browser's
 * version, so nothing here is at risk while the question goes unanswered.
 */
function noteExternalConflict(revision) {
  pendingExternalRevision = revision;
  showExternalNotice(
    'conflict',
    'Changed by something else. Your unsaved edits are kept.'
  );
}

function showNewestVersion() {
  const revision = pendingExternalRevision;
  hideExternalNotice();
  if (!revision) return;
  model.applyRemote(revision);
  richSurface.renderedSource = null;
  refreshSurfaces({ force: true });
  updateStatus();
  flashStatus('Showing the newest version');
}

function restartLiveUpdates() {
  stopLiveUpdates?.();
  hideExternalNotice();
  stopLiveUpdates = startLiveUpdates({
    model,
    explorer,
    notify: flashStatus,
    onConflict: noteExternalConflict,
    onDocumentChanged: () => {
      hideExternalNotice();
      richSurface.renderedSource = null;
      refreshSurfaces({ force: true });
      updateStatus();
    },
  });
}

/**
 * Says which storage is in use, so it is never a guess (WR-5).
 *
 * Hidden while there is only one. The indicator exists to answer "where is
 * this going", and a badge that has said the same thing on every document
 * anybody has ever opened stops being read long before it becomes wrong.
 */
function updateStorageIndicator() {
  const indicator = document.getElementById('storageIndicator');
  if (!indicator) return;
  if (!cloudIsAvailable()) {
    indicator.hidden = true;
    indicator.textContent = '';
    return;
  }
  indicator.hidden = false;
  const account = currentAccount();
  indicator.textContent = isCloud()
    ? `Cloud · ${account?.email || account?.name || 'signed in'}`
    : 'This device';
  indicator.dataset.storage = storageMode();
  indicator.title = isCloud()
    ? 'Documents are stored in your Google account and sync across devices.'
    : 'Documents are stored in the workspace folder on the server hosting this page.';
}

/**
 * The surface a command acts on.
 *
 * There is only one. Kept as a function rather than inlined because every
 * command reads it, and a single view is a layout decision rather than a
 * promise -- naming the seam costs nothing and is what made removing the
 * second pane a small change.
 */
function activeSurface() {
  return richSurface;
}

function currentSelection() {
  return activeSurface().currentSourceSelection() ?? model.selection;
}

/** Applies a `{text, selection}` result from the shared formatting layer. */
function applyResult(result) {
  const surface = activeSurface();
  model.edit(result.text, result.selection);
  surface.focus();
  surface.applySelection(model.source, model.selection);
}

function resolveImageURL(destination) {
  if (/^[a-z][a-z0-9+.-]*:/i.test(destination)) return destination;
  if (!model.path) return null;
  const folder = model.path.includes('/')
    ? model.path.slice(0, model.path.lastIndexOf('/'))
    : '';
  const relative = destination.split('/').map(decodeSegment).join('/');
  const joined = folder ? `${folder}/${relative}` : relative;
  return api.imageURL(joined);
}

function decodeSegment(segment) {
  try {
    return decodeURIComponent(segment);
  } catch {
    return segment;
  }
}

const commands = {
  /**
   * Switching storage closes the open document, so it goes through the same
   * unsaved-changes guard every other document-closing command does (WR-7).
   */
  async connectCloud() {
    if (isCloud()) {
      welcome.show({ dismissable: true });
      return;
    }
    if (!(await guardUnsaved())) return;
    try {
      await useCloud();
      await adoptStorage();
    } catch (error) {
      showError(error);
    }
  },

  async useLocalStorage() {
    if (!isCloud()) return;
    if (!(await guardUnsaved())) return;
    try {
      await signOutAndUseLocal();
      await adoptStorage();
    } catch (error) {
      showError(error);
    }
  },

  inline(name) {
    applyResult(
      toggleInline(InlineStyle[name], model.source, currentSelection(), modelFor(model.source))
    );
  },
  heading(level) {
    applyResult(applyHeading(level, model.source, currentSelection()));
  },
  list(name) {
    applyResult(toggleList(ListStyle[name], model.source, currentSelection()));
  },
  quote() {
    applyResult(toggleQuote(model.source, currentSelection()));
  },
  codeBlock() {
    applyResult(wrapCodeBlock(model.source, currentSelection()));
  },
  horizontalRule() {
    applyResult(insertHorizontalRule(model.source, currentSelection()));
  },
  async link() {
    const destination = await showPrompt({
      title: 'Insert Link',
      message: 'Enter the URL this link should point to.',
      value: 'https://',
      confirmLabel: 'Insert',
    });
    if (destination === null) return;
    applyResult(
      insertLink(destination, model.source, currentSelection(), modelFor(model.source))
    );
  },
  image: () => addImage(),
  undo: () => model.undo(),
  redo: () => model.redo(),
  selectAll() {
    const surface = activeSurface();
    surface.focus();
    model.setSelection(makeRange(0, model.source.length));
    surface.applySelection(model.source, model.selection);
  },
  newDocument: () => newDocument(),
  open: () => {
    if (mobileLayout) drawerOpen = true;
    else sidebarVisible = true;
    applySidebarVisibility();
    element('explorerTree').focus();
  },
  save: () => saveDocument(),
  saveAs: () => saveDocument({ forcePrompt: true }),
  close: () => closeDocument(),
  newFolder: () => explorer.newFolder(),
  newDocumentFile: () => explorer.newDocument(),
  showWelcome: () => welcome.show({ dismissable: true }),
  toggleSidebar() {
    if (mobileLayout) {
      drawerOpen = !drawerOpen;
    } else {
      sidebarVisible = !sidebarVisible;
    }
    applySidebarVisibility();
  },
  /**
   * WA-1: read the draft and write notes on it.
   *
   * Opening the rail and running are the same command deliberately. A rail
   * that opens empty and waits for a second press is two steps for one
   * intention, and the empty state already explains itself for anyone who
   * opens it another way.
   */
  critique() {
    critique.run();
  },
  toggleCritique() {
    critique.toggle();
  },  setMobileLayout: (enabled) => setMobileLayout(enabled),
  toggleMobileLayout: () => setMobileLayout(!mobileLayout),
  setSavedForLater(wanted) {
    if (!model.path) return;
    savedDocuments.set(model.path, wanted);
    // The filled bookmark is the confirmation; mobile has no status bar.
    mobileUI.refresh();
  },
  customizeTheme(anchor) {
    openThemePopover(anchor ?? element('toolbar').querySelector('.me-tool-group:last-child button'), () => {
      // Re-rendering picks up theme-dependent inline styles in one pass.
      refreshSurfaces({ force: true });
    });
  },
};

// ── AI assisted critique (WA-*) ──────────────────────────────────────────────

/**
 * The rail of comments, and the shading it points at.
 *
 * The document is read from the model rather than handed in, so the rail is
 * always looking at the same text the surfaces are — including after a reload
 * from the server, which is a change the author did not make and which still
 * has to move the marks.
 *
 * Constructed here, above the toolbar and the menu bar, because both of them
 * *describe* it: the View menu reads `critique.isVisible` while it is being
 * built, not when it is opened, so a rail declared further down is a rail that
 * does not exist yet and the whole module fails to evaluate.
 */
const critique = new CritiqueRail({
  root: element('critiqueRail'),
  text: () => model.source,
  documentPath: () => model.path ?? null,
  onHighlightsChanged: () => repaintCritique(),
  onReveal: (range) => revealSourceRange(range),
});

const toolbar = buildToolbar(element('toolbar'), commands);
buildMenus(element('menubar'), commands, {
  canUndo: () => model.canUndo,
  canRedo: () => model.canRedo,
  sidebarVisible: () => sidebarVisible,
  critiqueVisible: () => critique.isVisible,
  mobileLayout: () => mobileLayout,
  isCloud: () => isCloud(),
  cloudAvailable: () => cloudIsAvailable(),
});

const mobileUI = buildMobileUI({
  root: element('app'),
  topBar: element('mobileBar'),
  formatBar: element('formatBar'),
  commands,
  state: {
    canUndo: () => model.canUndo,
    documentName: () => model.displayName,
    documentPath: () => model.path,
    isDirty: () => model.isDirty,
    isSavedForLater: () => (model.path ? savedDocuments.includes(model.path) : false),
  },
});

// Tapping outside the drawer closes it, which is the only dismissal gesture a
// phone offers once the sidebar covers the document.
element('drawerScrim').addEventListener('click', () => {
  drawerOpen = false;
  applySidebarVisibility();
});

/**
 * F-11: the toolbar mirrors what is active where the caret sits. The render
 * model already knows which spans cover a source offset, so this is a lookup
 * rather than a second parser.
 */
function refreshActiveStyles() {
  const selection = model.selection;
  const rendered = modelFor(model.source);
  const inline = new Set();
  let list = null;
  let quote = false;
  let heading = 0;

  for (const span of rendered.spansAtSourceOffset(selection.location)) {
    const start = span.sourceRange.location;
    const end = start + span.sourceRange.length;
    if (selection.location < start || selection.location > end) continue;
    const kind = span.style.kind;
    if (kind === 'heading') heading = span.style.level;
    else if (kind === 'quote') quote = true;
    else if (kind === 'bulletedList') list = 'bulleted';
    else if (kind === 'numberedList') list = 'numbered';
    else if (kind === 'taskList') list = 'task';
    else if (
      kind === 'bold' ||
      kind === 'italic' ||
      kind === 'underline' ||
      kind === 'strikethrough' ||
      kind === 'inlineCode'
    ) {
      inline.add(kind);
    }
  }
  toolbar.setActiveStyles({ inline, list, quote, heading });
  mobileUI.setActiveStyles({ inline, list, quote, heading });

  // What can work here, from the same model: inside a fence or a code span
  // Markdown is literal, so the inline commands refuse and their buttons say
  // so rather than clicking through to nothing.
  const context = codeContextInModel(selection, rendered);
  const available = new Set(
    Object.values(InlineStyle).filter((style) => isInlineStyleAvailable(style, context))
  );
  const availability = { inline: available, link: isLinkAvailable(context) };
  toolbar.setAvailability(availability);
  mobileUI.setAvailability(availability);
}

function refreshSurfaces(options = {}) {
  richSurface.sync(model.source, model.selection, options);
  // A sync replaces every element in the rendered pane, so a selected image
  // has to be found again or the size panel would close on its own first
  // keystroke.
  // The controller maps a drop position to a source offset through the model,
  // so it needs the model the pane was just built from.
  imageSelection.setModel(modelFor(model.source));
  imageSelection.restore();
  // A re-render can move every word, including under a selection that did
  // not itself change.
  selectionHighlight.refresh();
}

// ── Selecting an image to resize (WI-17) ─────────────────────────────────────

const imageSelection = new ImageSelection(
  element('richSurface').parentElement,
  (range, size) => {
    applyResult(setImageSize(model.source, range, size));
  },
  (range, destination) => {
    applyResult(moveImage(model.source, range, destination));
  }
);

element('richSurface').addEventListener('mousedown', (event) => {
  const wrapper = event.target.closest?.('.me-image');
  if (wrapper) {
    // The wrapper is not editable, so a click would otherwise land the caret
    // beside it and leave nothing selected to act on.
    event.preventDefault();
    imageSelection.select(wrapper);
  } else {
    imageSelection.clear();
  }
});

// A press on the picture's body may become a move. Tracked from pointerdown so
// the same gesture works with a mouse, a trackpad and a finger; it stays a
// click until it has travelled far enough to be meant.
element('richSurface').addEventListener('pointerdown', (event) => {
  const wrapper = event.target.closest?.('.me-image');
  if (!wrapper) return;
  imageSelection.beginMove(event, wrapper);
});

// Any edit elsewhere means the panel is describing an image the caret has
// left, so it stops applying.
for (const surface of [richSurface]) {
  surface.element.addEventListener('keydown', () => imageSelection.clear());
}

// The handles are drawn in the pane's scrolled coordinate space, so they ride
// along with the content — but a resize of the window reflows the text under
// them and they have to be measured again.
element('richSurface').parentElement.addEventListener(
  'scroll',
  () => imageSelection.reposition(),
  { passive: true }
);
window.addEventListener('resize', () => imageSelection.reposition());

model.addEventListener('change', () => {
  refreshSurfaces();
  refreshActiveStyles();
  updateStatus();
  // The marks move onto the new text before anything is redrawn, so a
  // highlight never spends a frame pointing at where its sentence used to be.
  critique.noteCurrentText(model.source);
  repaintCritique();
});
model.addEventListener('selection', refreshActiveStyles);

function repaintCritique() {
  paintCritiqueHighlights({
    highlights: critique.highlights,
    selectedID: critique.selectedID,
    surfaces: [
      {
        root: element('richSurface'),
        map: (range) => richProjection.toSurface(model.source, range),
        layout: modelFor(model.source),
      },
    ],
  });
}

/** Brings a finding's passage into view without stealing the caret. */
function revealSourceRange(range) {
  const surface = activeSurface();
  const mapped = surface.projection.toSurface(model.source, range);
  const node = surface.element;
  const position = positionForOffset(node, mapped.location);
  if (!position) return;
  const probe = document.createRange();
  probe.setStart(position.node, position.offset);
  probe.collapse(true);
  const rect = probe.getBoundingClientRect();
  const bounds = node.parentElement.getBoundingClientRect();
  if (rect.top < bounds.top || rect.bottom > bounds.bottom) {
    node.parentElement.scrollTop += rect.top - bounds.top - bounds.height / 3;
  }
}

function noteSelectionMoved(surface) {
  refreshActiveStyles();
  // A click in the *text* opens the card for the passage under it, which is
  // the other half of the two-way link: without it the rail can point into the
  // document but the document cannot point back.
  const caret = surface.currentSourceSelection();
  if (caret) critique.selectAtOffset(caret.location);
}

richSurface.onSelectionChange = () => noteSelectionMoved(richSurface);
model.addEventListener('open', () => {
  // A held revision belongs to the document it came from, and this is a
  // different one now.
  hideExternalNotice();
  richSurface.renderedSource = null;
  refreshSurfaces({ force: true });
  // So is a critique. Keeping one across an open would leave notes about a
  // document nobody is looking at, anchored to offsets in a different text.
  critique.documentChanged();
});
model.addEventListener('autosaved', () => flashStatus('Autosaved'));
model.addEventListener('saved', () => flashStatus('Saved'));
model.addEventListener('error', (event) => showError(event.detail));

element('externalNoticeReload')?.addEventListener('click', showNewestVersion);
element('externalNoticeKeep')?.addEventListener('click', () => {
  // Autosave already writes this browser's version, so keeping it means
  // nothing more than putting the question away.
  hideExternalNotice();
});

function updateStatus() {
  const folder = model.path?.includes('/')
    ? model.path.slice(0, model.path.lastIndexOf('/'))
    : '';
  const name = model.displayName + (model.isDirty ? ' — Edited' : '');
  element('statusDocument').textContent = folder ? `${name} · ${folder}` : name;
  mobileUI.refresh();
}

let statusTimer = null;
function flashStatus(message) {
  const label = element('statusSaved');
  label.textContent = message;
  if (statusTimer) window.clearTimeout(statusTimer);
  statusTimer = window.setTimeout(() => {
    label.textContent = '';
  }, 2000);
  updateStatus();
}

function applySidebarVisibility() {
  // In mobile the sidebar is a transient drawer, so its state must not be
  // written over the desktop preference.
  if (!mobileLayout) localStorage.setItem(SIDEBAR_KEY, sidebarVisible ? 'true' : 'false');
  const visible = mobileLayout ? drawerOpen : sidebarVisible;
  element('sidebar').hidden = !visible;
  element('sidebarDivider').hidden = mobileLayout || !sidebarVisible;
  element('drawerScrim').hidden = !(mobileLayout && drawerOpen);
  element('app').dataset.drawer = mobileLayout && drawerOpen ? 'open' : 'closed';
  // WT-13: the desktop explorer floats over the document rather than displacing
  // it, so the document never moves when the nav opens. Styling keys off this.
  element('app').dataset.nav = visible ? 'open' : 'closed';
  toolbar.setSidebarVisible(visible);
}

function closeDrawer() {
  if (!drawerOpen) return;
  drawerOpen = false;
  applySidebarVisibility();
}

/** WB-1: swaps the whole chrome, keeping the command table and document. */
function setMobileLayout(enabled) {
  mobileLayout = enabled;
  localStorage.setItem(LAYOUT_KEY, enabled ? 'mobile' : 'desktop');
  element('app').dataset.layout = enabled ? 'mobile' : 'desktop';
  mobileUI.setEnabled(enabled);

  if (enabled) drawerOpen = false;

  applySidebarVisibility();
  mobileUI.refresh();
  refreshSurfaces({ force: true });
}

/**
 * Gates any action that would abandon unsaved edits (PRD D-6). Only an explicit
 * "Don't Save" or a save that actually succeeded may proceed; cancelling — or
 * dismissing the prompt with Escape, which resolves null — must not.
 */
async function guardUnsaved() {
  if (!model.isDirty) return true;
  const choice = await confirmDiscard(model.displayName);
  if (choice === 'discard') return true;
  if (choice !== 'save') return false;
  try {
    await saveDocument();
  } catch {
    return false;
  }
  // A cancelled Save As leaves the document dirty and untitled, so the caller
  // must not continue either.
  return !model.isDirty;
}

async function newDocument() {
  if (!(await guardUnsaved())) return;
  model.reset();
  welcome.hide();
  refreshSurfaces({ force: true });
  richSurface.focus();
  updateStatus();
}

async function openDocument(path) {
  if (!(await guardUnsaved())) return;
  try {
    await model.open(path);
    recentDocuments.note(model.path);
    welcome.hide();
    closeDrawer();
    explorer.select(model.path);
    updateStatus();
    activeSurface().focus();
  } catch (error) {
    if (error instanceof ApiError) recentDocuments.forget(path);
    showError(error);
  }
}

async function saveDocument({ forcePrompt = false } = {}) {
  let target = model.path;
  if (forcePrompt || !target) {
    const suggestion = target ?? model.suggestedFileName;
    const entered = await showPrompt({
      title: forcePrompt ? 'Save As' : 'Save',
      message: 'Enter a workspace-relative path, ending in .md or .markdown.',
      value: suggestion,
      confirmLabel: 'Save',
    });
    if (entered === null) return;
    target = entered.trim();
    if (target === '') return;
  }
  try {
    await model.save({ path: target });
    recentDocuments.note(model.path);
    await explorer.reload();
    explorer.select(model.path);
    updateStatus();
  } catch (error) {
    showError(error);
    throw error;
  }
}

async function closeDocument() {
  if (!(await guardUnsaved())) return;
  model.reset();
  welcome.show();
  updateStatus();
}

// ---------------------------------------------------------------- images

const imageInput = document.createElement('input');
imageInput.type = 'file';
imageInput.accept = 'image/*';
imageInput.multiple = true;
imageInput.style.display = 'none';
document.body.append(imageInput);
imageInput.addEventListener('change', () => {
  const files = Array.from(imageInput.files ?? []);
  imageInput.value = '';
  if (files.length > 0) importImages(files);
});

function pickImage() {
  imageInput.click();
}

/**
 * WI-15: an image comes either from a file, which is copied in beside the
 * document, or from a URL, which is referenced where it already lives.
 */
async function addImage() {
  const source = await chooseImageSource();
  if (source === 'file') pickImage();
  else if (source === 'url') await insertImageURL();
}

/** WI-16: reference an image that is already on the web. */
async function insertImageURL() {
  const destination = await showPrompt({
    title: 'Image address',
    message: 'The image stays where it is; this document just points at it.',
    value: 'https://',
    confirmLabel: 'Insert',
  });
  if (destination === null || destination.trim() === 'https://') return;
  const altText = await showPrompt({
    title: 'Description',
    message: 'Shown if the image cannot load, and read aloud by screen readers.',
    confirmLabel: 'Insert',
  });
  applyResult(insertImage(destination.trim(), altText ?? '', model.source, currentSelection()));
}

/**
 * I-1 … I-18: the file is copied into `<stem>.assets/` beside the document and
 * a relative Markdown reference is inserted at the caret. The document must
 * already have a location, because the assets folder is defined relative to it.
 */
async function importImages(files) {
  if (model.isUntitled) {
    // Assets live beside the document, so there is nowhere to put them yet.
    // Offer the step that unblocks the import rather than just refusing.
    const save = await confirmAction({
      title: 'Save the document before adding an image.',
      message:
        'Images are copied into a folder beside the Markdown file, so the document needs a location first.',
      confirmLabel: 'Save…',
    });
    if (!save) return;
    try {
      await saveDocument();
    } catch {
      return;
    }
    if (model.isUntitled) return;
  }
  for (const file of files) {
    try {
      const result = await api.uploadImage(model.path, file);
      const selection = currentSelection();
      const snippet = result.markdownReference;
      const newSource =
        model.source.slice(0, selection.location) +
        snippet +
        model.source.slice(maxRange(selection));
      model.edit(newSource, makeRange(selection.location + snippet.length, 0));
    } catch (error) {
      showError(error);
      return;
    }
  }
  activeSurface().focus();
}

richSurface.onPasteFiles = importImages;

for (const surface of [element('richSurface')]) {
  surface.addEventListener('dragover', (event) => {
    if (!event.dataTransfer?.types.includes('Files')) return;
    event.preventDefault();
    surface.classList.add('is-drop-target');
  });
  surface.addEventListener('dragleave', () => surface.classList.remove('is-drop-target'));
  surface.addEventListener('drop', (event) => {
    const files = Array.from(event.dataTransfer?.files ?? []).filter((file) =>
      file.type.startsWith('image/')
    );
    if (files.length === 0) return;
    event.preventDefault();
    surface.classList.remove('is-drop-target');
    placeCaretAt(surface, event.clientX, event.clientY);
    importImages(files);
  });
}

/**
 * Puts the caret where the image was dropped, so it lands where the author
 * pointed rather than wherever the caret happened to be (PRD WI-9).
 */
function placeCaretAt(surfaceElement, x, y) {
  surfaceElement.focus();
  const range = caretRangeAt(surfaceElement, x, y) ?? endOfBlockAt(surfaceElement, y);
  if (range === null) return;
  range.collapse(true);
  const selection = getSelection();
  selection.removeAllRanges();
  selection.addRange(range);
}

function caretRangeAt(surfaceElement, x, y) {
  if (typeof document.caretPositionFromPoint === 'function') {
    const position = document.caretPositionFromPoint(x, y);
    if (position && surfaceElement.contains(position.offsetNode)) {
      const range = document.createRange();
      range.setStart(position.offsetNode, position.offset);
      return range;
    }
    return null;
  }
  if (typeof document.caretRangeFromPoint === 'function') {
    const found = document.caretRangeFromPoint(x, y);
    if (found && surfaceElement.contains(found.startContainer)) return found;
  }
  return null;
}

/**
 * Dropping in the empty space beside a line is a normal gesture, and the
 * browser reports no caret position there. Fall back to the end of whichever
 * line the pointer is level with.
 */
function endOfBlockAt(surfaceElement, y) {
  for (const block of surfaceElement.children) {
    const box = block.getBoundingClientRect();
    if (y < box.top || y > box.bottom) continue;
    const range = document.createRange();
    range.selectNodeContents(block);
    range.collapse(false);
    return range;
  }
  return null;
}

// --------------------------------------------------------------- dividers

function installDivider(divider, onDrag) {
  let active = false;
  divider.addEventListener('pointerdown', (event) => {
    active = true;
    divider.setPointerCapture(event.pointerId);
    divider.classList.add('is-dragging');
  });
  divider.addEventListener('pointermove', (event) => {
    if (active) onDrag(event.clientX);
  });
  const stop = (event) => {
    if (!active) return;
    active = false;
    divider.releasePointerCapture(event.pointerId);
    divider.classList.remove('is-dragging');
  };
  divider.addEventListener('pointerup', stop);
  divider.addEventListener('pointercancel', stop);
}

installDivider(element('sidebarDivider'), (clientX) => {
  const width = Math.min(480, Math.max(160, clientX));
  document.documentElement.style.setProperty('--me-sidebar-width', `${width}px`);
  localStorage.setItem(SIDEBAR_WIDTH_KEY, String(width));
});

// ---------------------------------------------------------------- startup

window.addEventListener('beforeunload', (event) => {
  if (!model.isDirty) return;
  event.preventDefault();
  event.returnValue = '';
});

document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'hidden') model.flushAutosave().catch(() => {});
});

explorer.onOpenFile = (item) => {
  if (!item.isMarkdown) {
    showError(
      new ApiError(
        `“${item.name}” is not a Markdown document.`,
        'Humanish opens files with a .md or .markdown extension.'
      )
    );
    return;
  }
  openDocument(item.path);
};

explorer.onRevealRequested = () => {
  if (model.path) explorer.reveal(model.path);
};

// WF-9: a document that is open when it is renamed, moved, or deleted keeps
// working. The file on disk moved, so the editor follows it rather than
// carrying on with a path that no longer resolves.
explorer.onEntryCreated = (entry) => {
  if (entry.isMarkdown) openDocument(entry.path);
};

explorer.onEntryMoved = (fromPath, entry) => {
  recentDocuments.forget(fromPath);
  if (entry.isMarkdown) recentDocuments.note(entry.path);
  // WB-10: a rename must not silently empty the saved list.
  savedDocuments.relocate(fromPath, entry.path);
  if (model.path !== fromPath) return;

  model.relocate(entry.path, entry.name);
  explorer.select(entry.path);
  updateStatus();
};

explorer.onEntryDeleted = (entry) => {
  recentDocuments.forget(entry.path);
  // Covers the entry itself and, for a folder, everything that was under it.
  savedDocuments.forgetUnder(entry.path);
  const wasInside =
    model.path !== null &&
    (model.path === entry.path || model.path.startsWith(`${entry.path}/`));
  if (!wasInside) return;

  model.detach();
  updateStatus();
};

async function start() {
  const storedWidth = localStorage.getItem(SIDEBAR_WIDTH_KEY);
  if (storedWidth) {
    document.documentElement.style.setProperty('--me-sidebar-width', `${storedWidth}px`);
  }
  setMobileLayout(mobileLayout);
  element('app').hidden = false;

  // Storage first: `config` and the tree both depend on which backend answers.
  // A remembered cloud session that has expired falls back to local rather
  // than blocking the launch, and says why (WR-3).
  const storage = await restoreStorage();
  updateStorageIndicator();

  try {
    config = await api.config();
    welcome.workspaceName = config.workspaceName;
    explorer.rootName = config.workspaceName;
    await explorer.setRoot('');
  } catch (error) {
    showError(error);
  }

  // Asked for once at launch rather than when somebody presses the button:
  // what the server is set up with decides what the rail may offer, and
  // finding that out after the press means a button that looked available and
  // was not. Deliberately not awaited -- a slow answer must not hold up the
  // editor, and the rail redraws when it arrives.
  critique.loadConfig();

  if (storage.reason === 'signed-out') {    showError(new ApiError(
      'You were signed out of your cloud workspace.',
      'Reconnect your Google account from the welcome screen to reach those documents.'
    ));
  } else if (storage.reason) {
    showError(new ApiError(
      'Your cloud workspace could not be reached, so local files are being used.',
      storage.reason
    ));
  }

  model.reset();

  // After the tree exists, so the first sync watches the folders on screen.
  restartLiveUpdates();

  // W-1: honor an explicit ?path= first, then the launch preference.
  //
  // A visitor who has never chosen where documents are saved is shown the
  // welcome screen even if the launch preference is off, because the fallback
  // they would otherwise land in silently is a workspace anyone reaching this
  // page can edit. Turning the preference off says "don't show me this again",
  // which is not the same as "decide for me".
  //
  // With one place documents can go there is nothing to choose, so
  // `restoreStorage` reports the choice as made and the preference is obeyed
  // as written. The warning is still on the welcome screen for anyone who
  // opens it.
  const requested = new URLSearchParams(window.location.search).get('path');
  if (requested) {
    await openDocument(requested);
  } else if (recentDocuments.showAtLaunch || !storage.chosen) {
    welcome.show();
  } else {
    richSurface.focus();
  }
  updateStatus();
}

start();
