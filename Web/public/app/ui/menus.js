// Menu bar (PRD M-*, section 14 shortcuts).
//
// A faithful macOS-style menu bar, including the keyboard shortcuts, so muscle
// memory carries over from the native app. Every item calls into the same
// command table the toolbar uses, and the definitions below are the one place
// a shortcut is written down.

const IS_MAC = /Mac|iPhone|iPad/.test(navigator.platform ?? navigator.userAgent);

/** Renders a shortcut the way the platform writes it. */
function shortcutLabel(shortcut) {
  if (!shortcut) return '';
  const parts = [];
  if (shortcut.control) parts.push(IS_MAC ? '⌃' : 'Ctrl+');
  if (shortcut.shift) parts.push(IS_MAC ? '⇧' : 'Shift+');
  if (shortcut.command) parts.push(IS_MAC ? '⌘' : 'Ctrl+');
  parts.push(shortcut.key.toUpperCase());
  return parts.join('');
}

function matches(event, shortcut) {
  if (!shortcut) return false;
  const primary = IS_MAC ? event.metaKey : event.ctrlKey;
  const secondary = IS_MAC ? event.ctrlKey : event.altKey;
  if (Boolean(shortcut.command) !== primary) return false;
  if (Boolean(shortcut.control) !== secondary) return false;
  if (Boolean(shortcut.shift) !== event.shiftKey) return false;
  if (event.key.toLowerCase() === shortcut.key.toLowerCase()) return true;
  // ⇧⌘7 arrives as "&" on a US layout, so fall back to the physical key.
  return /^[0-9]$/.test(shortcut.key) && event.code === `Digit${shortcut.key}`;
}

export function buildMenus(root, commands, state) {
  const menus = [];
  let openList = null;

  const title = document.createElement('span');
  title.className = 'me-menubar__title';
  title.textContent = 'Humanish';

  function closeAll() {
    for (const menu of menus) {
      menu.list.hidden = true;
      menu.button.setAttribute('aria-expanded', 'false');
    }
    openList = null;
  }

  for (const definition of menuDefinitions(commands, state)) {
    const holder = document.createElement('div');
    holder.className = 'me-menu';

    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'me-menu__button';
    button.textContent = definition.title;
    button.setAttribute('aria-haspopup', 'true');
    button.setAttribute('aria-expanded', 'false');

    const list = document.createElement('ul');
    list.className = 'me-menu__list';
    list.setAttribute('role', 'menu');
    list.hidden = true;

    const entry = { button, list, holder, title: definition.title };
    menus.push(entry);

    const show = () => {
      closeAll();
      // Items are rebuilt on open so checkmarks and disabled states are current.
      const items = itemsFor(entry.title, commands, state);
      list.replaceChildren(...items.map((item) => renderItem(item, closeAll)));
      list.hidden = false;
      button.setAttribute('aria-expanded', 'true');
      openList = list;
    };

    button.addEventListener('click', (event) => {
      event.stopPropagation();
      if (openList === list) closeAll();
      else show();
    });
    // Once one menu is open, hovering the others switches between them, the
    // way a real menu bar behaves.
    button.addEventListener('mouseenter', () => {
      if (openList && openList !== list) show();
    });

    holder.append(button, list);
  }

  document.addEventListener('click', closeAll);
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') closeAll();
  });

  root.replaceChildren(title, ...menus.map((menu) => menu.holder));

  document.addEventListener('keydown', (event) => {
    for (const menu of menuDefinitions(commands, state)) {
      for (const item of menu.items) {
        if (item.separator || !item.shortcut) continue;
        if (matches(event, item.shortcut)) {
          event.preventDefault();
          closeAll();
          item.action();
          return;
        }
      }
    }
  });

  return { close: closeAll };
}

function itemsFor(title, commands, state) {
  return menuDefinitions(commands, state).find((menu) => menu.title === title)?.items ?? [];
}

function renderItem(item, closeAll) {
  const row = document.createElement('li');
  if (item.separator) {
    row.className = 'me-menu__separator';
    row.setAttribute('role', 'separator');
    return row;
  }

  const button = document.createElement('button');
  button.type = 'button';
  button.className = 'me-menu__item';
  button.setAttribute('role', 'menuitem');
  button.disabled = Boolean(item.disabled);

  const check = document.createElement('span');
  check.className = 'me-menu__check';
  check.textContent = item.checked ? '✓' : '';

  const label = document.createElement('span');
  label.textContent = item.title;

  const key = document.createElement('span');
  key.className = 'me-menu__shortcut';
  key.textContent = shortcutLabel(item.shortcut);

  button.append(check, label, key);
  button.addEventListener('click', () => {
    closeAll();
    item.action();
  });
  row.append(button);
  return row;
}

function menuDefinitions(commands, state) {
  const separator = { separator: true };
  return [
    {
      title: 'File',
      items: [
        { title: 'New', shortcut: { command: true, key: 'n' }, action: commands.newDocument },
        { title: 'Open…', shortcut: { command: true, key: 'o' }, action: commands.open },
        { title: 'Open Recent…', action: commands.showWelcome },
        separator,
        {
          title: 'New Document in Folder…',
          shortcut: { command: true, control: true, key: 'n' },
          action: commands.newDocumentFile,
        },
        {
          title: 'New Folder…',
          shortcut: { command: true, shift: true, key: 'n' },
          action: commands.newFolder,
        },
        separator,
        { title: 'Save', shortcut: { command: true, key: 's' }, action: commands.save },
        {
          title: 'Save As…',
          shortcut: { command: true, shift: true, key: 's' },
          action: commands.saveAs,
        },
        separator,
        { title: 'Close', shortcut: { command: true, key: 'w' }, action: commands.close },
        // Storage lives in File because it decides where Save goes (WR-6), and
        // is absent entirely while there is only one place documents can go.
        // A menu item that names the one option available is a menu item that
        // tells you nothing.
        ...(state.cloudAvailable()
          ? [
            separator,
            {
              title: state.isCloud() ? 'Cloud Storage (Connected)' : 'Connect Google Account…',
              action: commands.connectCloud,
            },
            {
              title: 'Use Files On This Device',
              disabled: !state.isCloud(),
              action: commands.useLocalStorage,
            },
          ]
          : []),
      ],
    },
    {
      title: 'Edit',
      items: [
        {
          title: 'Undo',
          shortcut: { command: true, key: 'z' },
          disabled: !state.canUndo(),
          action: commands.undo,
        },
        {
          title: 'Redo',
          shortcut: { command: true, shift: true, key: 'z' },
          disabled: !state.canRedo(),
          action: commands.redo,
        },
        separator,
        { title: 'Select All', shortcut: { command: true, key: 'a' }, action: commands.selectAll },
      ],
    },
    {
      title: 'Insert',
      items: [
        {
          title: 'Add Image…',
          shortcut: { command: true, shift: true, key: 'i' },
          action: commands.image,
        },
        { title: 'Link…', shortcut: { command: true, key: 'k' }, action: commands.link },
        {
          title: 'Horizontal Rule',
          shortcut: { command: true, control: true, key: 'h' },
          action: commands.horizontalRule,
        },
      ],
    },
    {
      title: 'Format',
      items: [
        {
          title: 'Bold',
          shortcut: { command: true, key: 'b' },
          action: () => commands.inline('bold'),
        },
        {
          title: 'Italic',
          shortcut: { command: true, key: 'i' },
          action: () => commands.inline('italic'),
        },
        {
          title: 'Underline',
          shortcut: { command: true, key: 'u' },
          action: () => commands.inline('underline'),
        },
        {
          title: 'Strikethrough',
          shortcut: { command: true, control: true, key: 'k' },
          action: () => commands.inline('strikethrough'),
        },
        separator,
        {
          title: 'Inline Code',
          shortcut: { command: true, key: 'e' },
          action: () => commands.inline('inlineCode'),
        },
        {
          title: 'Code Block',
          shortcut: { command: true, shift: true, key: 'e' },
          action: commands.codeBlock,
        },
        separator,
        { title: 'Body', shortcut: { command: true, key: '0' }, action: () => commands.heading(0) },
        ...[1, 2, 3, 4, 5, 6].map((level) => ({
          title: `Heading ${level}`,
          shortcut: { command: true, key: String(level) },
          action: () => commands.heading(level),
        })),
        separator,
        {
          title: 'Bulleted List',
          shortcut: { command: true, shift: true, key: '7' },
          action: () => commands.list('bulleted'),
        },
        {
          title: 'Numbered List',
          shortcut: { command: true, shift: true, key: '8' },
          action: () => commands.list('numbered'),
        },
        {
          title: 'Task List',
          shortcut: { command: true, shift: true, key: '9' },
          action: () => commands.list('task'),
        },
        {
          title: 'Block Quote',
          shortcut: { command: true, control: true, key: 'q' },
          action: commands.quote,
        },
      ],
    },
    {
      title: 'View',
      items: [
        {
          title: 'Show File Explorer',
          shortcut: { command: true, control: true, key: 's' },
          checked: state.sidebarVisible(),
          action: commands.toggleSidebar,
        },
        separator,
        {
          // ⌃⌘C, matching the macOS build's Critique ▸ AI Assisted Critique.
          // There is no Critique menu here: the macOS one is there for the
          // keys that work through the notes, which this build does not have,
          // and without them it would be a menu that exists to hold a shortcut.
          title: 'AI Assisted Critique',
          shortcut: { command: true, control: true, key: 'c' },
          action: commands.critique,
        },
        {
          // ⇧⌘C, not ⌃⌘C: that one runs the critique, and not ⌃⌘K either,
          // which is already Strikethrough.
          title: 'Show Critique',
          shortcut: { command: true, shift: true, key: 'c' },
          checked: state.critiqueVisible(),
          action: commands.toggleCritique,
        },
        separator,
        {
          title: 'Mobile Layout',
          shortcut: { command: true, control: true, key: 'm' },
          checked: state.mobileLayout(),
          action: commands.toggleMobileLayout,
        },
        separator,
        { title: 'Customize Theme…', action: () => commands.customizeTheme() },
      ],
    },
  ];
}
