<?php
/**
 * What one keystroke costs, in a real browser, on documents of three sizes.
 *
 * Not part of the test suite — the suite counts work rather than timing it,
 * because a clock measures the machine it runs on. This is here so the numbers
 * quoted for a change to the drawing can be reproduced with nothing but PHP
 * and a browser.
 *
 *   /tests/keystroke-cost.php          what the editor does now
 *   /tests/keystroke-cost.php?full=1   the whole model and the whole DOM,
 *                                      rebuilt per keystroke, as it was before
 */

?><!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Humanish — keystroke cost</title>
<link rel="stylesheet" href="../css/themes.css">
<link rel="stylesheet" href="../css/app.css">
<style>
  body { font: 13px/1.6 ui-monospace, SFMono-Regular, Menlo, monospace; padding: 24px; }
  pre { white-space: pre; }
</style>
</head>
<body>
<pre id="out">measuring…</pre>
<div id="surface" contenteditable="true" style="position:absolute;left:-10000px;width:700px"></div>

<script type="module">
import { MarkdownRenderModel } from '../app/core/render-model.js';
import { renderInto } from '../app/ui/renderer.js';
import { readPlainText, textOfBlock } from '../app/dom-text.js';

const out = document.getElementById('out');
const surface = document.getElementById('surface');
const report = [];
const OLD = new URLSearchParams(location.search).has('full');
const EDITS = 12;

/** Headings, prose, inline marks, lists and fenced code, in realistic mixture. */
function corpus(count) {
  const parts = [];
  for (let i = 0; i < count; i += 1) {
    const kind = i % 11;
    if (kind === 0) parts.push(`## Section ${i}`);
    else if (kind === 1) parts.push('');
    else if (kind === 2) parts.push(`Some **bold** and _italic_ text with \`code\` on line ${i}.`);
    else if (kind === 3) parts.push(`- a bullet item number ${i}`);
    else if (kind === 4) parts.push(`1. a numbered item ${i}`);
    else if (kind === 5) parts.push('> a quoted line with a [link](https://example.com/) in it');
    else if (kind === 6) parts.push('```js');
    else if (kind === 7) parts.push(`const value${i} = ${i} * 2;`);
    else if (kind === 8) parts.push('```');
    else parts.push(`Ordinary paragraph text on line ${i}, long enough to be realistic prose.`);
  }
  return parts.join('\n');
}

function timed(body) {
  body(0);
  const started = performance.now();
  for (let step = 1; step <= EDITS; step += 1) body(step);
  return (performance.now() - started) / EDITS;
}

report.push(
  OLD
    ? 'before — the whole model and the whole DOM, once per keystroke'
    : 'after — only what the edit disturbed'
);
report.push('lines       MB   model ms   draw ms   read ms   total ms   blocks drawn');
out.textContent = report.join('\n');

for (const count of [2200, 11000, 55000]) {
  const base = corpus(count);
  // The middle of the document, which is the worst place for an edit to land.
  const cut = Math.floor(base.length / 2);

  // Each source is built fresh from `base`, inside the timed region, because
  // that is what a keystroke does: concatenation produces a rope, and whoever
  // reads the result first pays to flatten it.
  //
  // Do not "tidy" this into deriving each source from the previous one. Slicing
  // a rope flattens it, so a chain of edits arrives already flat and the timer
  // never sees a cost the real editor pays on every keystroke. Measured at
  // 55,000 lines, mid-document: this form pays 0.144 ms of flatten per edit, a
  // chained one 0.006 ms. The difference is the measurement, not noise.
  const sourceAfter = (step) => `${base.slice(0, cut)}${'x'.repeat(step + 1)}${base.slice(cut)}`;

  let model = new MarkdownRenderModel(base);
  let previous = base;
  let drawn = 0;
  renderInto(surface, model);

  const keepUp = (step) => {
    const source = sourceAfter(step);
    if (OLD) {
      model = new MarkdownRenderModel(source);
    } else {
      model.update(source, {
        previousSource: previous,
        range: { location: cut, length: 0 },
        replacement: 'x',
      });
    }
    previous = source;
  };

  const modelMs = timed(keepUp);
  const bothMs = timed((step) => {
    keepUp(step);
    drawn = renderInto(surface, model).built;
  });

  // Reading the surface back is what lets the next edit be diffed. It used to
  // be the whole document as one string; it is now the blocks around the caret.
  const readMs = timed(() => {
    if (OLD) return readPlainText(surface);
    const caret = model.blockCount >> 1;
    const first = Math.max(0, caret - 1);
    const last = Math.min(model.blockCount - 1, caret + 1);
    let text = '';
    for (let index = first; index <= last; index += 1) {
      text += textOfBlock(surface.childNodes[index]);
    }
    return text;
  });

  report.push(
    `${String(count).padStart(6)}  ${(base.length / (1024 * 1024)).toFixed(2).padStart(5)}` +
      `  ${modelMs.toFixed(2).padStart(8)}  ${(bothMs - modelMs).toFixed(2).padStart(7)}` +
      `  ${readMs.toFixed(2).padStart(7)}  ${(bothMs + readMs).toFixed(2).padStart(9)}` +
      `  ${String(drawn).padStart(12)}`
  );
  out.textContent = report.join('\n');
}

document.body.dataset.benchmarkFinished = 'true';
</script>
</body>
</html>
