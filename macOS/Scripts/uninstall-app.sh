#!/bin/bash

# Removes the installed app and drops its Launch Services registration, so
# .md files fall back to whichever other handler macOS picks.

set -euo pipefail

APP_NAME="Humanish"
DESTINATION="${INSTALL_DIR:-/Applications}"
INSTALLED_APP="$DESTINATION/$APP_NAME.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [ ! -d "$INSTALLED_APP" ]; then
  printf 'Nothing installed at %s.\n' "$INSTALLED_APP"
  exit 0
fi

# Deleting a bundle out from under a live process leaves it unable to load its
# own resources, and a quit can legitimately take a while — or stop entirely on
# an unsaved-changes sheet. Removing the app at that moment destroys the very
# thing the person is being asked about. So ask, wait, and refuse rather than
# force it.
if pgrep -f "$INSTALLED_APP/Contents/MacOS/" >/dev/null 2>&1; then
  osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
  for _ in $(seq 1 20); do
    pgrep -f "$INSTALLED_APP/Contents/MacOS/" >/dev/null 2>&1 || break
    sleep 0.5
  done
  if pgrep -f "$INSTALLED_APP/Contents/MacOS/" >/dev/null 2>&1; then
    printf '%s is still running and did not quit.\n' "$APP_NAME" >&2
    printf 'It may be waiting on an unsaved document. Quit it, then re-run.\n' >&2
    exit 1
  fi
fi

if [ -x "$LSREGISTER" ]; then
  "$LSREGISTER" -u "$INSTALLED_APP" >/dev/null 2>&1 || true
fi

rm -rf -- "$INSTALLED_APP"
printf 'Removed %s\n' "$INSTALLED_APP"
