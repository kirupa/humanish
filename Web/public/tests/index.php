<?php

declare(strict_types=1);

/**
 * The browser test page.
 *
 * This is the path that needs nothing but PHP: open /tests/ and the same suites
 * the node runner executes run in the browser, plus the DOM tests that only
 * make sense there.
 */

?><!DOCTYPE html>
<html lang="en" data-theme-color="blue" data-appearance="light">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Humanish — Tests</title>
<link rel="stylesheet" href="../css/themes.css">
<style>
  body {
    margin: 0;
    padding: 28px;
    font: 13px/1.55 -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
    background: var(--me-page-background);
    color: var(--me-primary-text);
  }
  h1 { font-size: 19px; margin: 0 0 4px; }
  .subtitle { color: var(--me-secondary-text); margin: 0 0 20px; }
  .summary {
    font-weight: 700;
    padding: 10px 14px;
    border-radius: 8px;
    margin-bottom: 18px;
    background: var(--me-sidebar-background);
    border: 1px solid var(--me-separator);
  }
  .summary.pass { color: #1f7a3d; }
  .summary.fail { color: #b3261e; }
  .suite { font-weight: 700; margin: 16px 0 5px; }
  .case { padding-left: 18px; }
  .case.pass::before { content: "\2714 "; color: #1f7a3d; }
  .case.fail::before { content: "\2718 "; color: #b3261e; }
  .message {
    padding-left: 32px;
    color: #b3261e;
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    white-space: pre-wrap;
  }
  .note { margin-top: 26px; color: var(--me-secondary-text); }
  code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
</style>
</head>
<body>
<h1>Humanish — Tests</h1>
<p class="subtitle">
  The ported core, running against the same expectations as the macOS build.
</p>
<div class="summary" id="summary">Running…</div>
<div id="results"></div>
<p class="note">
  Server-side tests run separately: <code>php Web/tests/php/run.php</code>.
</p>

<script type="module">
import { runAll } from './harness.js';
import { discoverTestModules } from './suites.js';

const results = document.getElementById('results');
const summaryElement = document.getElementById('summary');

try {
  for (const specifier of discoverTestModules({ includeDOM: true })) {
    await import(specifier);
  }

  const summary = await runAll((event) => {
    if (event.kind === 'suite') {
      const heading = document.createElement('div');
      heading.className = 'suite';
      heading.textContent = `${event.name} (${event.count})`;
      results.append(heading);
      return;
    }
    const row = document.createElement('div');
    row.className = `case ${event.kind}`;
    row.textContent = event.name;
    results.append(row);
    if (event.kind === 'fail') {
      const message = document.createElement('div');
      message.className = 'message';
      message.textContent = event.message;
      results.append(message);
    }
  });

  summaryElement.className = `summary ${summary.failed === 0 ? 'pass' : 'fail'}`;
  summaryElement.textContent =
    summary.failed === 0
      ? `${summary.passed} tests in ${summary.suites} suites passed`
      : `${summary.failed} of ${summary.total} tests failed`;
  document.body.dataset.testsFinished = String(summary.failed === 0);
} catch (error) {
  summaryElement.className = 'summary fail';
  summaryElement.textContent = `The suite could not start: ${error.message}`;
  document.body.dataset.testsFinished = 'false';
}
</script>
</body>
</html>
