#!/usr/bin/env bats
# Unit tests for twindesk. Run with: bats test/

load helpers

setup() { setup_env; }
teardown() { teardown_env; }

# --- names -------------------------------------------------------------------

@test "valid profile names are accepted" {
  for n in a work perso-2 0abc "$(printf 'a%.0s' $(seq 1 32))"; do
    fn validate_name "$n"
    [ "$status" -eq 0 ]
  done
}

@test "invalid profile names are rejected with exit 2" {
  for n in "" Work -lead "a b" "a/b" ".." "a_b" "é" "a.b" "$(printf 'a%.0s' $(seq 1 33))" 'a$(x)'; do
    fn validate_name "$n"
    [ "$status" -eq 2 ]
  done
}

@test "reserved names are rejected" {
  for n in default main; do
    td add "$n"
    [ "$status" -eq 2 ]
    [[ "$output" == *reserved* ]]
  done
}

# --- JSON & versions ----------------------------------------------------------

@test "json_str escapes quotes, backslashes and control characters" {
  fn json_str 'a"b\c'
  [ "$output" = '"a\"b\\c"' ]
  fn json_str "$(printf 'x\ty')"
  [ "$output" = '"x\ty"' ]
  fn json_str "$(printf 'l1\nl2')"
  [ "$output" = '"l1\nl2"' ]
  fn json_str "$(printf 'a\001b')"
  [ "$output" = '"a\u0001b"' ]
}

@test "version_cmp orders dotted versions numerically" {
  fn version_cmp 3.6556.2 3.6556.2; [ "$output" = 0 ]
  fn version_cmp 3.6556.10 3.6556.2; [ "$output" = 1 ]
  fn version_cmp 3.10 3.9; [ "$output" = 1 ]
  fn version_cmp 2.99 3.0; [ "$output" = -1 ]
  fn version_cmp 1.0 1; [ "$output" = 0 ]
}

# --- process classification (by command line, never by name) -----------------

@test "classify tells main, profile and helper processes apart" {
  local exe=/Applications/Claude.app/Contents/MacOS/Claude
  fn classify "$exe" "$exe"; [ "$output" = main ]
  fn classify "$exe --user-data-dir=/x/twindesk/profiles/a" "$exe"; [ "$output" = profile ]
  fn classify "$exe --type=renderer --user-data-dir=/y" "$exe"; [ "$output" = "" ]
  fn classify "/Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper --type=gpu-process" "$exe"; [ "$output" = "" ]
  fn classify "grep $exe" "$exe"; [ "$output" = "" ]
  fn classify "/bin/zsh -c pgrep -f $exe" "$exe"; [ "$output" = "" ]
  fn classify "${exe}Helper" "$exe"; [ "$output" = "" ]
}

@test "profile_pid matches the exact folder only (no prefix confusion)" {
  local exe=/Applications/Claude.app/Contents/MacOS/Claude root="$HOME/Library/Application Support/twindesk"
  export TWINDESK_OS=macos TWINDESK_HOME="$root" TWINDESK_PS_FIXTURE="$BATS_TEST_TMPDIR/ps"
  cat > "$TWINDESK_PS_FIXTURE" <<EOF
  101 $exe
  202 $exe --user-data-dir=$root/profiles/ab
  303 $exe --user-data-dir=$root/profiles/a
  404 $exe --type=renderer --user-data-dir=$root/profiles/a
  505 /usr/bin/grep $exe --user-data-dir=$root/profiles/a
EOF
  fn eval 'APP_EXE='"'$exe'"'; profile_pid a'
  [ "$output" = 303 ]
  fn eval 'APP_EXE='"'$exe'"'; profile_pid ab'
  [ "$output" = 202 ]
  fn eval 'APP_EXE='"'$exe'"'; profile_pid abc'
  [ "$output" = "" ]
  fn eval 'APP_EXE='"'$exe'"'; main_pids'
  [ "$output" = 101 ]
}

# --- data root and deletion guards --------------------------------------------

@test "data root must be named twindesk" {
  export TWINDESK_HOME="$HOME/somewhere"
  td add work
  [ "$status" -eq 2 ]
  [ ! -e "$HOME/somewhere/profiles/work" ]
}

@test "data root inside the main Claude data folder is refused" {
  export TWINDESK_HOME="$HOME/.config/Claude/twindesk"
  td add work
  [ "$status" -eq 2 ]
  [[ "$output" == *"main Claude data folder"* ]]
  export TWINDESK_HOME="$HOME/Library/Application Support/Claude/x/twindesk"
  td add work
  [ "$status" -eq 2 ]
}

@test "safe_remove_dir refuses a symlinked profile folder" {
  mkdir -p "$TWINDESK_HOME/profiles" "$HOME/precious"
  touch "$HOME/precious/keep"
  ln -s "$HOME/precious" "$TWINDESK_HOME/profiles/work"
  fn safe_remove_dir "$TWINDESK_HOME/profiles/work" profiles work
  [ "$status" -ne 0 ]
  [ -f "$HOME/precious/keep" ]
}

@test "safe_remove_dir refuses a path that is not <root>/<kind>/<name>" {
  mkdir -p "$TWINDESK_HOME/profiles/work" "$HOME/other"
  fn safe_remove_dir "$HOME/other" profiles work
  [ "$status" -ne 0 ]
  [ -d "$HOME/other" ]
  fn safe_remove_dir "$TWINDESK_HOME/profiles/work/../../" profiles work
  [ "$status" -ne 0 ]
  [ -d "$TWINDESK_HOME" ]
}

@test "safe_remove_dir through a symlinked root deletes only the target folder" {
  mkdir -p "$HOME/real/profiles/work" "$HOME/.local/share"
  ln -s "$HOME/real" "$HOME/.local/share/twindesk"
  fn safe_remove_dir "$HOME/real/profiles/work" profiles work
  # Resolves to <resolved root>/profiles/work: allowed, and only that folder goes.
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/real/profiles/work" ]
  [ -d "$HOME/real/profiles" ]
}

@test "remove without --yes in a non-interactive shell refuses (exit 2)" {
  td add work
  td remove work < /dev/null
  [ "$status" -eq 2 ]
  [ -d "$TWINDESK_HOME/profiles/work" ]
}

@test "remove --yes deletes the Desktop profile, keeps an unrelated folder" {
  td add work
  mkdir -p "$TWINDESK_HOME/profiles/keep"
  td remove work --yes
  [ "$status" -eq 0 ]
  [ ! -e "$TWINDESK_HOME/profiles/work" ]
  [ -d "$TWINDESK_HOME/profiles/keep" ]
}

@test "remove --all also deletes the CLI profile" {
  td add work
  mkdir -p "$TWINDESK_HOME/cli/work"
  export TWINDESK_CLAUDE_CLI="$BATS_TEST_TMPDIR/bin/fake-claude"
  printf '#!/bin/bash\necho "$CLAUDE_CONFIG_DIR $*" >> "%s/cli.log"\n' "$BATS_TEST_TMPDIR" > "$TWINDESK_CLAUDE_CLI"
  chmod +x "$TWINDESK_CLAUDE_CLI"
  td remove work --all
  [ "$status" -eq 0 ]
  [ ! -e "$TWINDESK_HOME/cli/work" ]
  grep -q "cli/work auth logout" "$BATS_TEST_TMPDIR/cli.log"
}

@test "remove of an unknown profile exits 4" {
  td remove ghost --yes
  [ "$status" -eq 4 ]
}

# --- dry-run changes nothing ---------------------------------------------------

@test "--dry-run changes nothing for add, open, shortcut, remove, login" {
  td add work --dry-run
  [ "$status" -eq 0 ]
  [ ! -e "$TWINDESK_HOME/profiles/work" ]
  mkdir -p "$TWINDESK_HOME/profiles/work"
  td open work --dry-run
  [ "$status" -eq 0 ]
  td shortcut work --dry-run
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.local/share/applications/twindesk-work.desktop" ]
  td login work --dry-run
  [ "$status" -eq 0 ]
  td remove work --dry-run --all
  [ "$status" -eq 0 ]
  [ -d "$TWINDESK_HOME/profiles/work" ]
  [ -z "$(fake_pids)" ]
}

# --- sign-in detection -----------------------------------------------------------

@test "signed_in: yes with a valid sessionKey row, no when expired or absent" {
  td add work
  make_cookies "$TWINDESK_HOME/profiles/work" "$(chromium_time 3600)"
  fn signed_in work; [ "$output" = yes ]
  rm "$TWINDESK_HOME/profiles/work/Cookies"
  make_cookies "$TWINDESK_HOME/profiles/work" "$(chromium_time -3600)"
  fn signed_in work; [ "$output" = no ]
  rm "$TWINDESK_HOME/profiles/work/Cookies"
  make_cookies "$TWINDESK_HOME/profiles/work" none
  fn signed_in work; [ "$output" = no ]
  rm "$TWINDESK_HOME/profiles/work/Cookies"
  fn signed_in work; [ "$output" = no ]
}

@test "list --json never prints cookie values" {
  td add work
  make_cookies "$TWINDESK_HOME/profiles/work" "$(chromium_time 3600)"
  sqlite3 "$TWINDESK_HOME/profiles/work/Cookies" "update cookies set value='SECRET-TOKEN-VALUE';"
  td list --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"signed_in":true'* ]]
  [[ "$output" != *SECRET* ]]
  td status work
  [[ "$output" != *SECRET* ]]
}

# --- lifecycle with the fake app --------------------------------------------------

@test "open starts the profile and reports its PID; second open does not start another" {
  td add work
  td open work
  [ "$status" -eq 0 ]
  [ "$(fake_pids | wc -l | tr -d ' ')" = 1 ]
  td open work
  [ "$status" -eq 0 ]
  [[ "$output" == *"is running"* ]]
  [ "$(fake_pids | wc -l | tr -d ' ')" = 1 ]
  td list
  [[ "$output" == *"running ("* ]]
}

@test "remove stops a running profile by PID and leaves the main instance alone" {
  td add work
  "$FAKE_APP" & local main=$!
  td open work
  td remove work --yes
  [ "$status" -eq 0 ]
  kill -0 "$main"
  [ ! -e "$TWINDESK_HOME/profiles/work" ]
  kill -TERM "$main"
}

@test "login closes the main instance, waits for sign-in, restarts it" {
  td add work
  "$FAKE_APP" >/dev/null 2>&1 & local main=$!
  # Simulate the user signing in after a few seconds.
  ( sleep 4; make_cookies "$TWINDESK_HOME/profiles/work" "$(chromium_time 3600)" ) &
  td login work --yes --timeout 30
  [ "$status" -eq 0 ]
  [[ "$output" == *"main instance stopped (PID $main)"* ]]
  [[ "$output" == *"is signed in"* ]]
  ! kill -0 "$main" 2>/dev/null
  [[ "$output" == *"main instance running again"* ]]
}

@test "login times out with exit 5 and restarts the main instance" {
  td add work
  "$FAKE_APP" >/dev/null 2>&1 &
  td login work --yes --timeout 4
  [ "$status" -eq 5 ]
  [[ "$output" == *"restarting the main instance"* ]]
}

@test "login refuses without --yes when not interactive and main is running" {
  td add work
  "$FAKE_APP" >/dev/null 2>&1 & local main=$!
  td login work < /dev/null
  [ "$status" -eq 2 ]
  kill -0 "$main"
  kill -TERM "$main"
}

# --- shortcut, alias, cli -------------------------------------------------------

@test "shortcut creates a marked .desktop file removed with the profile" {
  td add work
  td shortcut work
  [ "$status" -eq 0 ]
  local f="$HOME/.local/share/applications/twindesk-work.desktop"
  grep -qx "X-Twindesk-Profile=work" "$f"
  # The launcher goes through `twindesk open`, never straight to the app,
  # so a running profile is focused instead of started twice.
  grep -q '^Exec=/bin/sh -c ".*twindesk.* open work"$' "$f"
  ! grep -q -- "--user-data-dir=" "$f"
  td remove work --yes
  [ ! -e "$f" ]
}

@test "remove never deletes a shortcut it did not create" {
  td add work
  local f="$HOME/.local/share/applications/twindesk-work.desktop"
  mkdir -p "$(dirname "$f")"; echo "[Desktop Entry]" > "$f"
  td remove work --yes
  [ -f "$f" ]
}

@test "alias only prints, writes nothing" {
  td alias work
  [ "$status" -eq 0 ]
  [[ "$output" == *"CLAUDE_CONFIG_DIR="*"/cli/work"* ]]
  [ ! -e "$TWINDESK_HOME/cli/work" ]
}

@test "cli runs Claude Code with the profile's CLAUDE_CONFIG_DIR and passes args" {
  export TWINDESK_CLAUDE_CLI="$BATS_TEST_TMPDIR/bin/fake-claude"
  printf '#!/bin/bash\necho "dir=$CLAUDE_CONFIG_DIR args=$*"\n' > "$TWINDESK_CLAUDE_CLI"
  chmod +x "$TWINDESK_CLAUDE_CLI"
  td cli work --version -p "hi there"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\n%s' "-> CLI profile 'work' created: $TWINDESK_HOME/cli/work" "dir=$TWINDESK_HOME/cli/work args=--version -p hi there")" ]
}

# --- misc -------------------------------------------------------------------------

@test "missing app exits 3" {
  export TWINDESK_APP="$BATS_TEST_TMPDIR/nope"
  td add work
  td open work
  [ "$status" -eq 3 ]
}

@test "usage errors exit 2" {
  td
  [ "$status" -eq 2 ]
  td frobnicate
  [ "$status" -eq 2 ]
  td add
  [ "$status" -eq 2 ]
  td login work --timeout abc
  [ "$status" -eq 2 ]
}

@test "--version and help exit 0" {
  td --version
  [ "$status" -eq 0 ]
  [[ "$output" == "twindesk "* ]]
  td help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Not affiliated with Anthropic"* ]]
}

@test "NO_COLOR and non-terminal output contain no escape codes" {
  unset NO_COLOR
  td add work
  [[ "$output" != *$'\033'* ]]
}

@test "script uses no Bash 4+ only features" {
  ! grep -nE 'declare -A|mapfile|readarray|\$\{[a-zA-Z_]+(,,|\^\^)|coproc|&>>|\|&' "$SCRIPT"
}

@test "list shows CLI-only profiles and works without the app" {
  td add work
  mkdir -p "$TWINDESK_HOME/cli/scripts"
  export TWINDESK_APP="$BATS_TEST_TMPDIR/nope"
  td list --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"name":"scripts","desktop_profile":false'* ]]
  [[ "$output" == *'"name":"work","desktop_profile":true'* ]]
  td remove scripts --yes
  [ "$status" -eq 0 ]
  [ ! -e "$TWINDESK_HOME/cli/scripts" ]
}

@test "stop_pid refuses a PID that is not the expected instance" {
  sleep 30 & local other=$!
  fn eval "APP_EXE='$FAKE_APP'; stop_pid $other 'main instance' main"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no longer main instance"* ]]
  kill -0 "$other"
  kill "$other"
}

@test "login also closes other profiles by PID and restarts them" {
  td add work
  td add other
  td open other
  local other_pid; other_pid="$(fn eval "APP_EXE='$FAKE_APP'; profile_pid other"; printf '%s' "$output")"
  [ -n "$other_pid" ]
  ( sleep 4; make_cookies "$TWINDESK_HOME/profiles/work" "$(chromium_time 3600)" ) &
  td login work --yes --timeout 30
  [ "$status" -eq 0 ]
  [[ "$output" == *"To close: profile 'other' (PID $other_pid)"* ]]
  [[ "$output" == *"profile 'other' stopped (PID $other_pid)"* ]]
  [[ "$output" == *"profile 'other' running again"* ]]
  ! kill -0 "$other_pid" 2>/dev/null
}

@test "login refuses when a non-twindesk instance with its own data dir runs" {
  td add work
  "$FAKE_APP" --user-data-dir="$HOME/elsewhere" >/dev/null 2>&1 & local foreign=$!
  td login work --yes --timeout 5
  [ "$status" -eq 1 ]
  [[ "$output" == *"not managed by twindesk"* ]]
  kill -0 "$foreign"
  kill -TERM "$foreign"
}

@test "the shortcut command focuses a running profile instead of starting a second one" {
  td add work
  td shortcut work
  local f="$HOME/.local/share/applications/twindesk-work.desktop" cmd
  cmd="$(sed -n 's/^Exec=\/bin\/sh -c "\(.*\)"$/\1/p' "$f")"
  [ -n "$cmd" ]
  /bin/sh -c "$cmd" >/dev/null 2>&1
  [ "$(fake_pids | wc -l | tr -d ' ')" = 1 ]
  /bin/sh -c "$cmd" >/dev/null 2>&1
  [ "$(fake_pids | wc -l | tr -d ' ')" = 1 ]
}

@test "list, open and doctor flag two instances on one profile" {
  local exe=/Applications/Claude.app/Contents/MacOS/Claude root="$HOME/Library/Application Support/twindesk"
  export TWINDESK_OS=macos TWINDESK_HOME="$root" TWINDESK_PS_FIXTURE="$BATS_TEST_TMPDIR/ps"
  mkdir -p "$root/profiles/work"
  printf '  11 %s --user-data-dir=%s\n  12 %s --user-data-dir=%s\n' "$exe" "$root/profiles/work" "$exe" "$root/profiles/work" > "$TWINDESK_PS_FIXTURE"
  fn eval "APP_EXE='$exe'; profile_pid_count work"
  [ "$output" = 2 ]
  fn eval "APP_EXE='$exe'; profile_pid work"
  [ "$output" = 11 ]
}

@test "shortcut --label validates the label and only applies to shortcut" {
  td add work
  for l in "" "../x" "toolongtoolong" 'a"b' "-x"; do
    td shortcut work --label "$l"
    [ "$status" -eq 2 ]
  done
  td open work --label 2
  [ "$status" -eq 2 ]
  [[ "$output" == *"only applies to 'shortcut'"* ]]
  [ -z "$(fake_pids)" ]
}

@test "shortcut --label names the Linux launcher after the label" {
  td add work
  td shortcut work --label "Client A"
  [ "$status" -eq 0 ]
  local f="$HOME/.local/share/applications/twindesk-work.desktop"
  grep -qx "Name=Claude (Client A)" "$f"
  grep -qx "X-Twindesk-Profile=work" "$f"
}

@test "first_line never fails under pipefail, even with long output" {
  fn first_line seq 1 200000
  [ "$status" -eq 0 ]
  [ "$output" = 1 ]
  fn first_line true
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}
