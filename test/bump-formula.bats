#!/usr/bin/env bats
# Tests for scripts/bump-formula.sh with a local fake release archive.

SCRIPT="$BATS_TEST_DIRNAME/../scripts/bump-formula.sh"

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  TAP="$BATS_TEST_TMPDIR/tap"
  mkdir -p "$TAP/Formula" "$BATS_TEST_TMPDIR/rel/twindesk-9.9.9"
  cat > "$TAP/Formula/twindesk.rb" <<'EOF'
class Twindesk < Formula
  url "https://github.com/MartinFerret/twindesk/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
end
EOF
  printf '#!/usr/bin/env bash\nTWINDESK_VERSION="9.9.9"\n' > "$BATS_TEST_TMPDIR/rel/twindesk-9.9.9/twindesk"
  tar -czf "$BATS_TEST_TMPDIR/rel/v9.9.9.tar.gz" -C "$BATS_TEST_TMPDIR/rel" twindesk-9.9.9
  export TWINDESK_RELEASE_BASE="file://$BATS_TEST_TMPDIR/rel"
  SHA="$(shasum -a 256 "$BATS_TEST_TMPDIR/rel/v9.9.9.tar.gz" | cut -c1-64)"
}

@test "updates url and sha256, prints git commands, never commits" {
  run /bin/bash "$SCRIPT" 9.9.9 --tap "$TAP"
  [ "$status" -eq 0 ]
  grep -qx "  sha256 \"$SHA\"" "$TAP/Formula/twindesk.rb"
  grep -qx "  url \"file://$BATS_TEST_TMPDIR/rel/v9.9.9.tar.gz\"" "$TAP/Formula/twindesk.rb"
  [[ "$output" == *"git commit -am \"twindesk 9.9.9\""* ]]
  [[ "$output" == *"$SHA"* ]]
}

@test "--dry-run shows the diff and changes nothing" {
  cp "$TAP/Formula/twindesk.rb" "$BATS_TEST_TMPDIR/before.rb"
  run /bin/bash "$SCRIPT" v9.9.9 --tap "$TAP" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run]"* ]]
  [[ "$output" == *"+  sha256 \"$SHA\""* ]]
  cmp "$TAP/Formula/twindesk.rb" "$BATS_TEST_TMPDIR/before.rb"
}

@test "refuses an archive whose script has another version" {
  # A v9.9.8 archive that still contains the 9.9.9 script.
  cp "$BATS_TEST_TMPDIR/rel/v9.9.9.tar.gz" "$BATS_TEST_TMPDIR/rel/v9.9.8.tar.gz"
  run /bin/bash "$SCRIPT" 9.9.8 --tap "$TAP"
  [[ "$output" == *"does not say version 9.9.8"* ]]
  [ "$status" -ne 0 ]
  grep -q "0000000000" "$TAP/Formula/twindesk.rb"
}

@test "refuses bad versions and a missing formula" {
  run /bin/bash "$SCRIPT" "1.2;rm" --tap "$TAP"
  [ "$status" -ne 0 ]
  run /bin/bash "$SCRIPT" 9.9.9 --tap "$BATS_TEST_TMPDIR/nope"
  [ "$status" -ne 0 ]
  run /bin/bash "$SCRIPT"
  [ "$status" -eq 2 ]
}
