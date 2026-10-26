#!/usr/bin/env bash
# Install or uninstall twindesk for the current user (macOS, Linux). No sudo.
#
#   ./install.sh                         install to ~/.local/bin (or $TWINDESK_BIN_DIR)
#   ./install.sh --uninstall             remove the command, ask about profiles
#   ./install.sh --uninstall --keep-profiles | --purge
#
# Run it from a clone of the repository; there is no curl | bash installer.

set -euo pipefail

BIN_DIR="${TWINDESK_BIN_DIR:-$HOME/.local/bin}"
SRC_DIR="$(cd -P "$(dirname "$0")" && pwd -P)"
TARGET="$BIN_DIR/twindesk"
MARKER="# twindesk - run several Claude Desktop accounts side by side."

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

is_ours() { [ -f "$1" ] && sed -n '2p' "$1" | grep -qxF "$MARKER"; }

install_cmd() {
  [ "$(id -u)" != 0 ] || die "do not run as root: twindesk installs per user"
  [ -f "$SRC_DIR/twindesk" ] || die "run this from the twindesk repository"
  if [ -e "$TARGET" ] && ! is_ours "$TARGET"; then die "$TARGET exists and is not twindesk"; fi
  mkdir -p "$BIN_DIR"
  cp "$SRC_DIR/twindesk" "$TARGET.tmp"
  chmod 755 "$TARGET.tmp"
  mv -f "$TARGET.tmp" "$TARGET"
  printf 'ok installed %s\n' "$TARGET"
  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *)
      printf '\n%s is not in your PATH. Add this line to your shell config (not done for you):\n' "$BIN_DIR"
      # shellcheck disable=SC2016 # printed literally for the user to copy
      printf '  export PATH="%s:$PATH"\n' "$BIN_DIR"
      ;;
  esac
  printf '\nNext: twindesk doctor\n'
}

uninstall_cmd() { # keep|purge|ask
  local mode="$1" name names
  if [ ! -e "$TARGET" ]; then printf 'twindesk is not installed in %s\n' "$BIN_DIR"; fi
  if [ -e "$TARGET" ] && ! is_ours "$TARGET"; then die "$TARGET is not twindesk, not touching it"; fi
  if [ "$mode" = ask ] && [ -e "$TARGET" ]; then
    names="$(NO_COLOR=1 "$TARGET" list --json 2>/dev/null | grep -o '"name":"[a-z0-9-]*"' | cut -d'"' -f4 || true)"
    if [ -n "$names" ]; then
      [ -t 0 ] || die "profiles exist: re-run with --keep-profiles or --purge"
      printf 'Profiles found: %s\nDelete them too (sign-ins and local sessions are lost)? [y/N] ' "$(printf '%s' "$names" | tr '\n' ' ')"
      read -r answer || answer=""
      case "$answer" in y|Y|yes) mode=purge ;; *) mode=keep ;; esac
    else
      mode=keep
    fi
  fi
  if [ "$mode" = purge ] && [ -e "$TARGET" ]; then
    names="$(NO_COLOR=1 "$TARGET" list --json 2>/dev/null | grep -o '"name":"[a-z0-9-]*"' | cut -d'"' -f4 || true)"
    # `list` includes CLI-only profiles; `remove --all` deletes both parts with its own guards.
    for name in $names; do "$TARGET" remove "$name" --yes --all; done
  fi
  if [ -e "$TARGET" ]; then rm -f -- "$TARGET"; printf 'ok removed %s\n' "$TARGET"; fi
  [ "$mode" = keep ] && printf 'Profiles kept. Reinstall twindesk to use them again.\n'
  return 0
}

case "${1:-}" in
  "") install_cmd ;;
  --uninstall)
    case "${2:-}" in
      "") uninstall_cmd ask ;;
      --keep-profiles) uninstall_cmd keep ;;
      --purge) uninstall_cmd purge ;;
      *) die "unknown option: $2" ;;
    esac ;;
  -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) die "unknown option: $1" ;;
esac
