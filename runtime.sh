#!/usr/bin/env bash
# Create/remove private, memory-backed transport files. Called only at lifecycle
# boundaries; key events never appear in command arguments or shell output.
set -euo pipefail
fail() { echo "keystrokes: $*" >&2; exit 1; }
runtime=${XDG_RUNTIME_DIR:-}
[[ $runtime == /* && $runtime != / && $runtime != */ ]] || fail 'XDG_RUNTIME_DIR must be an absolute runtime directory'
[[ -d $runtime && ! -L $runtime && -O $runtime ]] || fail 'runtime directory must be owned by this user and not a symlink'
[[ $(stat -c %a -- "$runtime") == 700 ]] || fail 'runtime directory must have mode 0700'
[[ $(stat -f -c %T -- "$runtime") == tmpfs ]] || fail 'runtime directory must be on tmpfs'

case ${1:-} in
  create)
    umask 077
    directory=$(mktemp -d -- "$runtime/omarchy-keystrokes.XXXXXXXXXXXX")
    trap 'rm -f -- "$directory/events" "$directory/spare" "$directory/ack" "$directory/owner"; rmdir -- "$directory"' ERR
    : > "$directory/events"
    : > "$directory/spare"
    : > "$directory/ack"
    printf '%s\n' "${directory##*.}" > "$directory/owner"
    # A consumer can disappear after mkdir but before reading our stdout.
    # Reap only this unclaimed session after the startup/lease deadlines.
    # Redirect all descriptors so the lifecycle process can finish promptly.
    ( sleep 3
      if [[ -d $directory && ! -L $directory ]]; then
        ack=$(head -c 128 -- "$directory/ack" 2>/dev/null || true)
        if [[ ! $ack =~ ^${directory##*.}\ [1-9][0-9]*$ ]]; then
          bash "$0" remove "$directory" >/dev/null 2>&1 || true
        fi
      fi
    ) </dev/null >/dev/null 2>&1 &
    printf '%s\n' "$directory"
    ;;
  remove|cleanup)
    directory=${2:-}
    [[ $directory == "$runtime/omarchy-keystrokes."* ]] || fail 'invalid session directory'
    suffix=${directory#"$runtime/omarchy-keystrokes."}
    [[ $suffix =~ ^[[:alnum:]]{12}$ ]] || fail 'invalid session directory'
    [[ ! -L $directory ]] || fail 'refusing a session symlink'
    [[ -e $directory ]] || exit 0
    [[ -d $directory && -O $directory && $(stat -c %a -- "$directory") == 700 ]] || fail 'invalid session owner or permissions'
    if [[ ${1:-} == cleanup ]]; then
      # One ordered destruction operation. Failed compositor contact falls back
      # after the producer lease has expired; never restart capture here.
      if ! timeout -k 0.2 2 hyprctl repl "if Keystrokes then if Keystrokes.protocol == 5 then return Keystrokes.stop('$suffix') else Keystrokes.set(false) end end" >/dev/null 2>&1; then
        sleep 1.1
      fi
    fi
    failed=0
    # Scrub the existing inodes before unlinking, including fallback cleanup.
    for name in events spare retired; do
      file=$directory/$name
      if [[ -e $file && ! -L $file && -f $file && -O $file ]]; then
        printf '%2048s' '' | dd of="$file" conv=notrunc oflag=nofollow status=none || failed=1
      fi
    done
    # No recursive deletion: remove only this protocol's known files.
    rm -f -- "$directory/events" "$directory/spare" "$directory/retired" "$directory/ack" "$directory/owner" || failed=1
    rmdir -- "$directory" || failed=1
    exit "$failed"
    ;;
  *) fail 'usage: runtime.sh create | remove <session-directory> | cleanup <session-directory>' ;;
esac
