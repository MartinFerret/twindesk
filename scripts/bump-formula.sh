#!/usr/bin/env bash
# Update the Homebrew formula in a local clone of the tap to a new release.
#
#   scripts/bump-formula.sh <version> [--tap <path>] [--dry-run]
#
# Downloads the release archive of v<version>, computes its sha256, rewrites
# url and sha256 in <tap>/Formula/twindesk.rb, and prints the git and brew
# commands to run next. It never commits or pushes.

set -euo pipefail

REPO="MartinFerret/twindesk"
BASE="${TWINDESK_RELEASE_BASE:-https://github.com/$REPO/archive/refs/tags}"
TAP="$HOME/homebrew-twindesk"
DRY_RUN=0
VERSION=""

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
usage() { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --tap) [ $# -ge 2 ] || die "--tap needs a path"; TAP="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) [ -z "$VERSION" ] || die "too many arguments"; VERSION="$1" ;;
  esac
  shift
done

[ -n "$VERSION" ] || { usage >&2; exit 2; }
VERSION="${VERSION#v}"
case "$VERSION" in
  *[!0-9.]*|.*|*.|*..*) die "version must look like 1.2.3: $VERSION" ;;
esac
FORMULA="$TAP/Formula/twindesk.rb"
[ -f "$FORMULA" ] || die "formula not found: $FORMULA (use --tap)"

URL="$BASE/v$VERSION.tar.gz"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/bump-formula.XXXXXX")"
trap 'rm -rf -- "$TMP"' EXIT

printf '$ curl -fsSL %s | shasum -a 256\n' "$URL"
curl -fsSL "$URL" -o "$TMP/archive.tar.gz" || die "cannot download $URL (is v$VERSION released?)"
SHA="$(shasum -a 256 "$TMP/archive.tar.gz" | cut -c1-64)"
printf '%s\n' "$SHA"

# Sanity check: the archive must contain the script at the expected version.
tar -xzf "$TMP/archive.tar.gz" -C "$TMP"
SCRIPT=""
for f in "$TMP"/*/twindesk; do [ -f "$f" ] && SCRIPT="$f" && break; done
[ -n "$SCRIPT" ] || die "the archive has no twindesk script at its root"
grep -q "^TWINDESK_VERSION=\"$VERSION\"$" "$SCRIPT" || die "the archive's twindesk does not say version $VERSION"

sed -e "s|^  url \".*\"$|  url \"$URL\"|" -e "s|^  sha256 \".*\"$|  sha256 \"$SHA\"|" "$FORMULA" > "$TMP/twindesk.rb"
grep -q "^  url \"$URL\"$" "$TMP/twindesk.rb" || die "could not update url in $FORMULA"
grep -q "^  sha256 \"$SHA\"$" "$TMP/twindesk.rb" || die "could not update sha256 in $FORMULA"

if cmp -s "$FORMULA" "$TMP/twindesk.rb"; then
  printf 'Formula already at %s.\n' "$VERSION"
  exit 0
fi
diff -u "$FORMULA" "$TMP/twindesk.rb" | sed '1,2d' || true

if [ "$DRY_RUN" = 1 ]; then
  printf '\n[dry-run] %s not changed.\n' "$FORMULA"
  exit 0
fi
cp "$TMP/twindesk.rb" "$FORMULA"
cat <<EOF

Updated $FORMULA. Next:

  cd "$TAP"
  brew audit --new --strict --online MartinFerret/twindesk/twindesk
  git commit -am "twindesk $VERSION"
  git push
  brew update && brew upgrade twindesk && twindesk --version
EOF
