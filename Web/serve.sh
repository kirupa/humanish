#!/usr/bin/env bash
#
# Local preview.
#
# The app has no build step, so this is the whole development loop: PHP's
# built-in server pointed at the document root. Everything served here is a
# plain file that a real Apache or nginx host serves the same way.
#
#     Web/serve.sh              # http://127.0.0.1:8000, ~/kirupaMarkdown
#     Web/serve.sh 9000         # a different port
#     MARKDOWN_EDITOR_WORKSPACE=~/Notes Web/serve.sh
#
set -euo pipefail

port="${1:-8000}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v php >/dev/null 2>&1; then
  echo "error: php is not installed or not on PATH." >&2
  exit 1
fi

# PHP owns the decision so the browser and the command line can never disagree
# about which folder is open, and so the first run creates it.
workspace="$(
  MARKDOWN_EDITOR_WORKSPACE="${MARKDOWN_EDITOR_WORKSPACE:-}" \
    php -r 'require "'"$root"'/bootstrap.php"; echo MarkdownEditor\Workspace::prepare()->root();'
)"

echo "Humanish"
echo "  editor     http://127.0.0.1:$port/"
echo "  tests      http://127.0.0.1:$port/tests/"
echo "  workspace  $workspace"
echo

MARKDOWN_EDITOR_WORKSPACE="$workspace" \
  exec php -S "127.0.0.1:$port" -t "$root/public"
