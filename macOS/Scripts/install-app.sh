#!/bin/bash

# Installs the built app into /Applications and registers it with Launch
# Services, so it appears in Finder's Open With menu and can be set as the
# default handler for .md and .markdown files.
#
# The build output under build/ is deliberately unregistered afterwards.
# Leaving both copies registered makes Finder show "Humanish" twice in
# Open With, and lets the association point at a bundle that `make clean`
# deletes.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Humanish"
PREVIOUS_APP_NAMES=("KONVO" "Markdown Editor")
BUILT_APP="$ROOT/build/$APP_NAME.app"
DESTINATION="${INSTALL_DIR:-/Applications}"
INSTALLED_APP="$DESTINATION/$APP_NAME.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [ ! -d "$BUILT_APP" ]; then
  printf 'No app at %s. Run `make app` first.\n' "$BUILT_APP" >&2
  exit 1
fi

if [ ! -w "$DESTINATION" ]; then
  printf '%s is not writable. Re-run with sudo, or set INSTALL_DIR.\n' "$DESTINATION" >&2
  exit 1
fi

# A running copy cannot be replaced safely. Deleting the bundle out from under
# a live process leaves it unable to load its own resources, and if the quit
# was blocked by an unsaved-changes sheet the person is left answering a dialog
# belonging to an app that no longer exists on disk. So ask, wait, and give up
# rather than force it.
for CANDIDATE_NAME in "$APP_NAME" "${PREVIOUS_APP_NAMES[@]}"; do
  CANDIDATE_APP="$DESTINATION/$CANDIDATE_NAME.app"
  if pgrep -f "$CANDIDATE_APP/Contents/MacOS/" >/dev/null 2>&1; then
    osascript -e "tell application \"$CANDIDATE_NAME\" to quit" >/dev/null 2>&1 || true
    for _ in $(seq 1 20); do
      pgrep -f "$CANDIDATE_APP/Contents/MacOS/" >/dev/null 2>&1 || break
      sleep 0.5
    done
    if pgrep -f "$CANDIDATE_APP/Contents/MacOS/" >/dev/null 2>&1; then
      printf '%s is still running and did not quit.\n' "$CANDIDATE_NAME" >&2
      printf 'It may be waiting on an unsaved document. Quit it, then re-run.\n' >&2
      exit 1
    fi
  fi
done

for OLD_NAME in "${PREVIOUS_APP_NAMES[@]}"; do
  OLD_APP="$DESTINATION/$OLD_NAME.app"
  OLD_BUILT_APP="$ROOT/build/$OLD_NAME.app"
  if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -u "$OLD_APP" >/dev/null 2>&1 || true
    "$LSREGISTER" -u "$OLD_BUILT_APP" >/dev/null 2>&1 || true
  fi
  rm -rf -- "$OLD_APP" "$OLD_BUILT_APP"
done

rm -rf -- "$INSTALLED_APP"
cp -R "$BUILT_APP" "$INSTALLED_APP"

if [ -x "$LSREGISTER" ]; then
  "$LSREGISTER" -u "$BUILT_APP" >/dev/null 2>&1 || true
  "$LSREGISTER" -f "$INSTALLED_APP"
fi

printf 'Installed %s\n' "$INSTALLED_APP"
printf 'Registered as a handler for .md and .markdown.\n'
