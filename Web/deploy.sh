#!/usr/bin/env bash
#
# Publishes the web build to a shared PHP host over FTPS.
#
# A shared host almost never lets you repoint the document root, so the app is
# split in two: the files that must be reachable by URL go under the document
# root, and everything else — the classes, the starter documents, and the
# documents themselves — goes above it, where the web server will not serve
# them however hard anyone asks.
#
#     ~/<private>/          bootstrap.php, src/, seed/
#     ~/<workspace>/        the documents
#     ~/public_html/<pub>/  index.php, api.php, app/, css/, .htaccess
#
# The generated .htaccess points the public half at the other two with SetEnv,
# so nothing here is baked into the code.
#
# Configuration is entirely environment variables, and the password comes from
# ~/.netrc, so no host name and no credential is ever written into this
# repository:
#
#     MDE_HOST        FTP host name
#     MDE_PUBLIC      remote path for the served files, relative to the FTP root
#     MDE_PRIVATE     remote path for the rest of the app, relative to the FTP root
#     MDE_PRIVATE_ABS the same folder as an absolute path on the server, which is
#                     what PHP needs and what FTP cannot tell us
#     MDE_WORKSPACE   absolute path on the server for the documents
#     MDE_HTPASSWD    optional: absolute path to an .htpasswd file on the server.
#                     Set it and the deployed app asks for a password; unset it
#                     and the app is open to anyone who finds the URL.
#
#     MDE_CRITIQUE_PROVIDER  optional: openAI, anthropic or gemini
#     MDE_CRITIQUE_MODEL     optional: a model name that provider offers
#
# Those last two name things, never secrets. The API key is deliberately not
# settable from here: writing a key into a generated .htaccess would put it in a
# file this script uploads and a mistake could serve. Set it on the server, in
# the environment, once — see WA-17.
#
#     MDE_HOST=ftp.example.com MDE_PUBLIC=public_html/humanish \
#       MDE_PRIVATE=markdown-editor MDE_PRIVATE_ABS=/home/me/markdown-editor \
#       MDE_WORKSPACE=/home/me/kirupaMarkdown \
#       Web/deploy.sh
#
# Pass --dry-run to build the payload and print what would be sent.

set -euo pipefail

dry_run=false
[[ "${1:-}" == "--dry-run" ]] && dry_run=true

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for required in MDE_HOST MDE_PUBLIC MDE_PRIVATE MDE_PRIVATE_ABS MDE_WORKSPACE; do
  if [[ -z "${!required:-}" ]]; then
    echo "error: $required is not set. See the comment at the top of this script." >&2
    exit 1
  fi
done

host="$MDE_HOST"
public="${MDE_PUBLIC%/}"
private="${MDE_PRIVATE%/}"
private_abs="${MDE_PRIVATE_ABS%/}"
workspace="${MDE_WORKSPACE%/}"
htpasswd="${MDE_HTPASSWD:-}"
critique_provider="${MDE_CRITIQUE_PROVIDER:-}"
critique_model="${MDE_CRITIQUE_MODEL:-}"

if ! grep -q "machine $host" ~/.netrc 2>/dev/null; then
  echo "error: no entry for $host in ~/.netrc." >&2
  echo "  machine $host login <user> password <password>" >&2
  exit 1
fi

# Staged rather than uploaded from the working tree, so that what goes to the
# server is only ever the files listed here — never a stray local edit, a test
# fixture, or somebody's scratch document.
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

mkdir -p "$stage/public" "$stage/private"
cp -R "$here/public/." "$stage/public/"
rm -rf "$stage/public/tests"
# `skill/` goes with the private half: it is the KONVO critique pass the server
# sends with every request, and nothing should be able to fetch it by URL.
cp -R "$here/src" "$here/seed" "$here/skill" "$here/bootstrap.php" "$stage/private/"

# Put the assets in a directory named after their contents.
#
# A ?v= query string only versions the URLs index.php writes. The imports
# inside a module are static paths no query string reaches, so a cache that
# keeps a new main.js and a stale welcome.js serves a module graph that fails
# to load at all. Moving the tree instead changes every module URL at once, and
# relative imports inherit the new directory without a build step. The hash is
# of the contents, so an unchanged deploy re-uses the same directory and
# nothing has to be re-downloaded.
#
# `fonts/` and `hands.css` are deliberately *not* in here. A stylesheet moved
# into v/<hash>/css/ resolves its url() from three folders deep instead of one,
# so a font path that is right in the repository is a 404 once deployed. They
# stay put, versioned by a query string, which is enough for a file with no
# imports to break.
#
# The hash is computed from *inside* the staging directory on purpose. `shasum`
# prints the file's path next to its digest, and the staging directory is a
# fresh `mktemp -d` every run, so hashing absolute paths made the version change
# on every deploy no matter what the files said — which is precisely the
# behavior the paragraph above says it avoids. Relative paths keep it honest.
asset_version="$(
  cd "$stage/public" &&
  find app css -type f -print0 |
    LC_ALL=C sort -z | xargs -0 shasum | shasum | cut -c1-12
)"
mkdir -p "$stage/public/v/$asset_version"
mv "$stage/public/app" "$stage/public/css" "$stage/public/v/$asset_version/"
printf '<?php return %s;\n' "'v/$asset_version'" > "$stage/public/asset-base.php"

# The one piece of configuration the server needs, written here so that a
# deployment cannot drift from the paths it was actually installed at.
{
  echo "# Generated by Web/deploy.sh. Edit the deployment, not this file."
  echo "SetEnv MARKDOWN_EDITOR_HOME $private_abs"
  echo "SetEnv MARKDOWN_EDITOR_WORKSPACE $workspace"
  # Which model answers a critique, when it is not the default. Names only:
  # the key is never written here, because this file is uploaded and a
  # misconfigured server could serve it.
  [[ -n "$critique_provider" ]] && echo "SetEnv MDE_CRITIQUE_PROVIDER $critique_provider"
  [[ -n "$critique_model" ]] && echo "SetEnv MDE_CRITIQUE_MODEL $critique_model"
  echo
  echo "DirectoryIndex index.php"
  echo
  echo "# Nothing here is a document root; refuse the obvious probes anyway."
  echo "<FilesMatch \"\\.(md|markdown)\$\">"
  echo "  Require all denied"
  echo "</FilesMatch>"
  echo
  echo "# Assets live under v/<hash>/, so caching them hard is correct: a new"
  echo "# build has different URLs. The page that names them must not be cached"
  echo "# though, or a browser will keep asking for a version that a later"
  echo "# deploy has already deleted."
  echo "<FilesMatch \"\\.php\$\">"
  echo "  <IfModule mod_expires.c>"
  echo "    ExpiresActive Off"
  echo "  </IfModule>"
  echo "  <IfModule mod_headers.c>"
  echo "    Header unset Cache-Control"
  echo "    Header always set Cache-Control \"no-cache, must-revalidate\""
  echo "  </IfModule>"
  echo "</FilesMatch>"
  echo
  echo "# asset-base.php is data for index.php, not a page."
  echo "<Files \"asset-base.php\">"
  echo "  Require all denied"
  echo "</Files>"
  if [[ -n "$htpasswd" ]]; then
    echo
    echo "AuthType Basic"
    echo "AuthName \"Humanish\""
    echo "AuthUserFile $htpasswd"
    echo "Require valid-user"
  fi
} > "$stage/public/.htaccess"

# Belt and braces: the private half sits above the document root already, so
# this only matters if someone later moves it somewhere served.
printf 'Require all denied\n' > "$stage/private/.htaccess"

if $dry_run; then
  echo "would upload to $host"
  echo "  public  -> $public"
  echo "  private -> $private"
  echo
  echo "--- .htaccess ---"
  cat "$stage/public/.htaccess"
  echo "--- files ---"
  (cd "$stage" && find . -type f | sort)
  exit 0
fi

echo "Publishing to $host"
echo "  public    $public"
echo "  private   $private"
echo "  workspace $workspace"
echo

if command -v lftp >/dev/null 2>&1; then
  # mirror --delete keeps a redeploy from leaving last version's files behind.
  lftp -c "
    set ssl:verify-certificate no
    set ftp:ssl-force true
    set ftp:ssl-protect-data true
    set net:max-retries 3
    open $host
    mirror --reverse --delete --verbose --parallel=4 '$stage/public' '$public'
    mirror --reverse --delete --verbose --parallel=4 '$stage/private' '$private'
  "
else
  # curl is one connection per file and cannot remove what a previous deploy
  # left behind, but it is on every machine, which is the point.
  echo "note: lftp not found; uploading with curl (slower, and stale remote"
  echo "      files are not removed)."
  ( cd "$stage" && find . -type f -print0 | while IFS= read -r -d '' file; do
      relative="${file#./}"
      case "$relative" in
        public/*) remote="$public/${relative#public/}" ;;
        private/*) remote="$private/${relative#private/}" ;;
        *) continue ;;
      esac
      printf '  %s\n' "$remote"
      curl -sS -k --netrc --ssl-reqd --ftp-create-dirs --max-time 120 \
        -T "$file" "ftp://$host/$remote"
    done )
fi

echo
echo "Done."
