# Shared setup for twindesk bats tests. Everything runs inside a temporary
# HOME with a fake Claude Desktop app: no real app, profile or keychain is used.

SCRIPT="$BATS_TEST_DIRNAME/../twindesk"
TD_BASH="${TD_BASH:-/bin/bash}"

setup_env() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export TWINDESK_OS=linux
  export TWINDESK_HOME="$HOME/.local/share/twindesk"
  export NO_COLOR=1
  export TWINDESK_STOP_TIMEOUT=5
  unset XDG_DATA_HOME XDG_CONFIG_HOME TWINDESK_PS_FIXTURE
  FAKE_APP="$BATS_TEST_TMPDIR/bin/claude-desktop"
  mkdir -p "$(dirname "$FAKE_APP")"
  cat > "$FAKE_APP" <<'EOF'
#!/bin/bash
# Fake Claude Desktop: stays alive until it receives TERM.
trap 'exit 0' TERM
while :; do sleep 1 & wait $!; done
EOF
  chmod +x "$FAKE_APP"
  export TWINDESK_APP="$FAKE_APP"
}

teardown_env() {
  # Stop any fake instance this test started, by PID.
  local pid
  for pid in $(pgrep -f "^/bin/bash $FAKE_APP" 2>/dev/null || true); do
    kill -TERM "$pid" 2>/dev/null || true
  done
}

# Run the CLI.
td() { run "$TD_BASH" "$SCRIPT" "$@"; }

# Call an internal function with the script sourced.
# shellcheck disable=SC2016 # $0 and $@ expand in the inner shell on purpose
fn() { run "$TD_BASH" -c 'TWINDESK_SOURCE_ONLY=1; . "$0"; "$@"' "$SCRIPT" "$@"; }

# Create a Chromium-like cookie store with or without a sessionKey row.
make_cookies() { # dir expires_utc(or "none")
  command -v sqlite3 >/dev/null 2>&1 || skip "sqlite3 not installed"
  mkdir -p "$1"
  sqlite3 "$1/Cookies" "create table cookies(host_key text, name text, value text, encrypted_value blob, expires_utc integer);"
  if [ "$2" != none ]; then
    sqlite3 "$1/Cookies" "insert into cookies values('.claude.ai','sessionKey','',x'00',$2);"
  fi
  sqlite3 "$1/Cookies" "insert into cookies values('.claude.ai','__ssid','',x'00',0);"
}

chromium_time() { # seconds from now
  echo $(( ($(date +%s) + 11644473600 + $1) * 1000000 ))
}

wait_until() { # seconds command...
  local n="$1"; shift
  while [ "$n" -gt 0 ]; do
    if "$@"; then return 0; fi
    sleep 1; n=$((n - 1))
  done
  return 1
}

fake_pids() { pgrep -f "^/bin/bash $FAKE_APP" 2>/dev/null || true; }
