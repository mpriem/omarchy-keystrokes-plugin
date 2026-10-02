#!/usr/bin/env bash
# Optional installer for local checkouts, including uncommitted edits.
set -euo pipefail

fail() { echo "install.sh: $*" >&2; exit 1; }
replace=false
for arg in "$@"; do
  case "$arg" in
    --replace) replace=true ;;
    --help|-h)
      echo "Usage: ./install.sh [--replace]"
      echo "Install and enable this local checkout. Existing installations require confirmation."
      echo "--replace consents to replacing plugin files and deleting extra files in that directory."
      exit 0 ;;
    *) fail "unknown argument: $arg" ;;
  esac
done

id=markpriem.keystrokes
src=$(cd "$(dirname "$0")" && pwd -P)
# Match Omarchy's plugin manager and the Lua helper's installation path.
dst=$HOME/.config/omarchy/plugins/$id
[[ ! -L $dst ]] || fail "refusing to replace a symlink: $dst"
[[ ! -e $dst || -d $dst ]] || fail "destination is not a directory: $dst"
[[ ! $src -ef $dst ]] || fail "run this installer from a separate checkout"

for command in rsync omarchy-plugin-validate omarchy omarchy-shell; do
  command -v "$command" >/dev/null || fail "required command not found: $command"
done

# Only distribute plugin files: never copy .env, logs, or other checkout data.
# Validate the exact payload before touching an existing installation.
stage=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-keystrokes-install.XXXXXX")
trap 'rm -rf -- "$stage"' EXIT
(
  cd "$src"
  [[ ! -L hypr ]] || fail "hypr must not be a symlink"
  cp -a --parents -- manifest.json qmldir CaptureStatus.qml Config.js KeyLabels.js StrokeHistory.js StrokeModel.qml SettingsFile.qml CaptureProtocol.js Capture.qml OverlayWindow.qml Keystrokes.qml Panel.qml \
    hypr/keystrokes.lua runtime.sh README.md LICENSE "$stage/"
)
omarchy-plugin-validate "$stage"

if [[ -d $dst && $replace == false ]]; then
  [[ -t 0 && -t 1 ]] || fail "installation exists; use --replace to consent to replacing its files: $dst"
  echo "Replace plugin files and delete extra local files in $dst?"
  echo "Git metadata is retained. Plugin settings and Hyprland configuration are untouched."
  read -r -p "Continue? [y/N] " answer || fail "cancelled"
  case "$answer" in
    y|Y|yes|YES) ;;
    *) fail "cancelled" ;;
  esac
fi

mkdir -p -- "$dst"
rsync -a --delete --exclude .git -- "$stage/" "$dst/"
# Discover new installs before trying to enable them.
omarchy-shell shell rescanPlugins >/dev/null
plugins=$(omarchy plugin list)
if ! awk -v id="$id" '$1 == id && $2 == "enabled" { found = 1 } END { exit !found }' <<<"$plugins"; then
  omarchy plugin enable "$id"
fi
echo "$id: installed to $dst"
