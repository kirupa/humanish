#!/bin/bash
#
# Checks the pointer shapes over a picture in the real running app.
#
# The pointer is set by AppKit from cursor rects in response to real mouse
# tracking, so it cannot be checked in a unit test. This seeds a throwaway
# document, launches the app on it, moves the real mouse over the picture and
# its corners, and identifies the pointer from the screen.
#
# The app is launched from a bundle whose identifier is deliberately different
# from the installed one (MDE_DEV_BUNDLE=1). Without that, macOS state
# restoration reopens whatever documents the installed copy had open, and this
# script would be clicking around inside somebody's real files.

set -euo pipefail
cd "$(dirname "$0")/.."

# This script takes over the screen: it brings the app to the front and moves
# the real mouse. Run it only on an idle machine. It is opt-in for that reason
# — run it by accident while somebody is working and it clicks into their
# windows and steals focus mid-task.
if [ "${MDE_ALLOW_SCREEN_CONTROL:-}" != "1" ]; then
    cat <<'WHY'
This check drives the real mouse and brings the app to the front, so it needs
the machine to itself. Re-run it with:

    MDE_ALLOW_SCREEN_CONTROL=1 ./Scripts/run-image-cursor-checks.sh

The pointer rects themselves are checked without the screen by
`make check-image-layout`, which is what CI and everyday work should use.
WHY
    exit 0
fi

# A locked screen is not a failing check, it is an unavailable one, and the
# difference matters: `screencapture -R` and `-l` both refuse behind the lock
# screen while full-screen capture keeps working, so the pointer checks come
# back as "could not capture the document window" and read exactly like a bug
# in the app. Say what is actually wrong instead.
if ioreg -n Root -d1 -a 2>/dev/null | grep -A1 CGSSessionScreenIsLocked | grep -q "<true/>"; then
    cat <<'WHY'
The screen is locked, so the pointer cannot be photographed. macOS refuses
region and window captures behind the lock screen while still allowing a
full-screen one, so this check would report a capture failure that looks like
an app bug.

Unlock the screen and run it again.
WHY
    exit 0
fi

fixture="$(mktemp -d)"
app="build/Humanish.app"
pid=""

cleanup() {
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
    fi
    rm -rf "$fixture"
}
trap cleanup EXIT

echo "building the dev app bundle…"
MDE_DEV_BUNDLE=1 ./Scripts/build-app.sh >/dev/null

mkdir -p "$fixture/Cursors.assets"
# A flat, saturated rectangle so the picture can be found on screen by colour.
swift - "$fixture/Cursors.assets/photo.png" <<'SWIFT' >/dev/null
import Cocoa
let size = NSSize(width: 240, height: 150)
let image = NSImage(size: size)
image.lockFocus()
NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.0, alpha: 1.0).setFill()
NSRect(origin: .zero, size: size).fill()
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT

cat > "$fixture/Cursors.md" <<'MD'
# Cursors

Some text before the picture.

![photo](Cursors.assets/photo.png)

Some text after the picture.
MD

before="$(ps -Ao pid=,comm= | grep "$PWD/$app" | awk '{print $1}' || true)"
# `-NSQuitAlwaysKeepsWindows NO` so the app comes up with one window: the
# fixture's. The dev bundle has its own identifier but still gets its own state
# restoration, so every previous run's document was being reopened alongside the
# new one — three windows deep by the third run. The pointer checks then had
# several formatting bars and several title bars to choose between at slightly
# different offsets, and picked a row of controls made of two different windows.
open -a "$PWD/$app" "$fixture/Cursors.md" --args -NSQuitAlwaysKeepsWindows NO

for _ in $(seq 1 40); do
    sleep 0.5
    pid="$(ps -Ao pid=,comm= | grep "$PWD/$app" | awk '{print $1}' | grep -vxF "${before:-none}" | head -1 || true)"
    [ -n "$pid" ] && break
done

if [ -z "$pid" ]; then
    echo "could not launch the dev app"
    exit 1
fi

sleep 3
status=0
swift Scripts/check-image-cursors.swift "$pid" || status=$?

# The picture must come back the size it went in: a stray drag during the
# checks would resize it, and that has happened.
if grep -q '^!\[photo\](Cursors.assets/photo.png)$' "$fixture/Cursors.md"; then
    echo "  ok   the checks did not resize the picture"
else
    echo "  FAIL the checks resized the picture — the pointer results are unreliable"
    sed -n '5p' "$fixture/Cursors.md"
    status=1
fi

exit $status
