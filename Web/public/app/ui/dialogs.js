// Alerts and prompts.
//
// The macOS build routes every failure through NSError presentation, which is
// modal and always shows a recovery suggestion. These are the web equivalents:
// nothing is written to the console and discarded (PRD G-6).

const layer = () => document.getElementById('alertLayer');

/**
 * Builds a dialog on the alert layer and resolves with whatever it closes with.
 *
 * Exported so a feature with a panel of its own -- the critique's provider,
 * model and key -- can use the same layer, the same Escape handling and the
 * same focus rules as every other dialog here, rather than growing a second
 * kind of modal that behaves almost the same.
 */
export function presentDialog(build) {
  return present(build);
}

/** A heading, a paragraph and a button, so a caller can build its own dialog. */
export const dialogParts = { heading, paragraph, button };

function present(build) {
  return new Promise((resolve) => {
    const host = layer();
    const alert = document.createElement('div');
    alert.className = 'me-alert';
    alert.setAttribute('role', 'dialog');
    alert.setAttribute('aria-modal', 'true');

    let settled = false;
    const close = (value) => {
      if (settled) return;
      settled = true;
      host.hidden = true;
      host.replaceChildren();
      document.removeEventListener('keydown', onKeyDown, true);
      resolve(value);
    };

    function onKeyDown(event) {
      if (event.key === 'Escape') {
        event.preventDefault();
        event.stopPropagation();
        close(null);
      }
    }

    build(alert, close);
    host.replaceChildren(alert);
    host.hidden = false;
    document.addEventListener('keydown', onKeyDown, true);

    const focusTarget = alert.querySelector('input') ?? alert.querySelector('.me-button--default');
    focusTarget?.focus();
    if (focusTarget instanceof HTMLInputElement) focusTarget.select();
  });
}

function heading(text) {
  const node = document.createElement('p');
  node.className = 'me-alert__title';
  node.textContent = text;
  return node;
}

function paragraph(text, className) {
  const node = document.createElement('p');
  node.className = className;
  node.textContent = text;
  return node;
}

function button(label, className, onClick) {
  const node = document.createElement('button');
  node.type = 'button';
  node.className = `me-button ${className}`;
  node.textContent = label;
  node.addEventListener('click', onClick);
  return node;
}

/** Reports a failure, showing its recovery suggestion when there is one. */
export function showError(error) {
  const message = error?.message ?? String(error);
  const recovery = error?.recovery ?? '';

  return present((alert, close) => {
    const buttons = document.createElement('div');
    buttons.className = 'me-alert__buttons';
    buttons.append(button('OK', 'me-button--default', () => close(null)));

    alert.append(heading('Humanish'), paragraph(message, 'me-alert__message'));
    if (recovery) alert.append(paragraph(recovery, 'me-alert__recovery'));
    alert.append(buttons);
  });
}

/**
 * States something that is not a failure.
 *
 * `showError` puts "Humanish" at the top and treats its second string
 * as a recovery suggestion, which is exactly wrong for a panel reporting what
 * is configured -- it would read as though the configuration were the problem.
 */
export function showMessage({ title, lines = [] }) {
  return present((alert, close) => {
    const buttons = document.createElement('div');
    buttons.className = 'me-alert__buttons';
    buttons.append(button('OK', 'me-button--default', () => close(null)));

    alert.append(heading(title));
    for (const [index, line] of lines.entries()) {
      if (line === '') continue;
      alert.append(paragraph(line, index === 0 ? 'me-alert__message' : 'me-alert__recovery'));
    }
    alert.append(buttons);
  });
}

/** @returns {Promise<string|null>} the entered text, or null when cancelled. */
export function showPrompt({ title, message = '', value = '', confirmLabel = 'OK' }) {
  return present((alert, close) => {
    const field = document.createElement('input');
    field.type = 'text';
    field.className = 'me-alert__field';
    field.value = value;

    const submit = () => close(field.value.trim() === '' ? null : field.value);
    field.addEventListener('keydown', (event) => {
      if (event.key === 'Enter') {
        event.preventDefault();
        submit();
      }
    });

    const buttons = document.createElement('div');
    buttons.className = 'me-alert__buttons';
    buttons.append(
      button('Cancel', '', () => close(null)),
      button(confirmLabel, 'me-button--default', submit)
    );

    alert.append(heading(title));
    if (message) alert.append(paragraph(message, 'me-alert__message'));
    alert.append(field, buttons);
  });
}

/**
 * Where an image should come from (PRD WI-15).
 *
 * A file has to be copied into the assets folder beside the document, and a
 * URL must not be — so the choice has to be made before either route starts,
 * and the file picker can no longer just open on its own.
 *
 * @returns {Promise<'file'|'url'|null>} null when cancelled.
 */
export function chooseImageSource() {
  return present((alert, close) => {
    const buttons = document.createElement('div');
    buttons.className = 'me-alert__buttons';
    buttons.append(
      button('Cancel', '', () => close(null)),
      button('Image Address…', '', () => close('url')),
      button('Choose File…', 'me-button--default', () => close('file'))
    );

    alert.append(
      heading('Add an image'),
      paragraph(
        'Choose a file to copy in beside this document, or link to an image already on the web.',
        'me-alert__message'
      ),
      buttons
    );
  });
}

/**
 * The unsaved-changes prompt (PRD D-6).
 *
 * @returns {Promise<'save'|'discard'|null>} null when cancelled.
 */
export function confirmDiscard(documentName) {
  return present((alert, close) => {
    const buttons = document.createElement('div');
    buttons.className = 'me-alert__buttons';
    buttons.append(
      button("Don't Save", '', () => close('discard')),
      button('Cancel', '', () => close(null)),
      button('Save', 'me-button--default', () => close('save'))
    );

    alert.append(
      heading(`Do you want to save the changes you made to ${documentName}?`),
      paragraph('Your changes will be lost if you don’t save them.', 'me-alert__recovery'),
      buttons
    );
  });
}

/**
 * A two-choice question. Used where an action cannot proceed yet but the
 * editor can offer the step that would unblock it.
 *
 * @returns {Promise<boolean>} true when confirmed.
 */
export function confirmAction({ title, message = '', confirmLabel = 'OK' }) {
  return present((alert, close) => {
    const buttons = document.createElement('div');
    buttons.className = 'me-alert__buttons';
    buttons.append(
      button('Cancel', '', () => close(false)),
      button(confirmLabel, 'me-button--default', () => close(true))
    );

    alert.append(heading(title));
    if (message) alert.append(paragraph(message, 'me-alert__recovery'));
    alert.append(buttons);
  }).then((value) => value === true);
}
