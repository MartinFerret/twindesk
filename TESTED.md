# Tested

What was run on real installs, with which versions, and what was only covered by unit tests.

## Versions

| OS | Claude Desktop | twindesk | Date | Status |
|---|---|---|---|---|
| macOS 26.2 (Apple silicon), system Bash 3.2.57 | 3.6556.2 | 0.1.0 | 2026-10-26 | Tested |
| Linux | — | 0.1.0 | — | Experimental – untested |
| Windows | — | 0.1.0 | — | Experimental – untested |

## macOS: real run

Two different Claude accounts: account 1 (paid) in the main instance, account 2 (free) in the profiles. Accounts were told apart by the account ID the app logs at startup next to its data folder (`token cache location: <folder>/config.json`, then `accountId=...`), with instances started one after the other.

| Command | Result | Evidence |
|---|---|---|
| `doctor` | OK | app, version 3.6556.2 (tested), main PID, `claude://` handler, `sqlite3`, writable root, CLI found, `no problems found`, exit 0 |
| `add work` | OK | folder created with mode 700, exit 0 |
| `login work` | OK | listed and closed the main instance and another running profile by PID, started `work`, detected the sign-in in the profile's own cookie store, restarted both closed instances, exit 0. The log shows `work` on account 2 and the main instance on account 1 |
| `login` timeout | OK | `--timeout 20` on an unsigned profile: `error: not signed in after 20s`, exit 5, main instance and other profile restarted |
| `login` Ctrl+C | OK | SIGINT during the wait: `warning: interrupted`, `restarting the main instance`, main instance back |
| `open` (running profile) | OK | focus moved from the terminal to the profile's PID (checked with `NSWorkspace.frontmostApplication`), no new instance |
| `open` (stopped profile) | OK | profile started, PID reported, exit 0 |
| `list`, `list --json` | OK | PIDs and sign-in state match `ps` and the cookie store; JSON parsed by Python `json` |
| `status`, `status --json` | OK | same; JSON parsed |
| `shortcut work` | OK | `~/Applications/Claude (work).app` created; started while the profile was running: no new instance (4 before, 4 after); started by a click: the profile came to the front (seen by the user) |
| `cli work` | OK | separate config folder, fresh Claude Code onboarding, separate sign-in through `localhost`; a new keychain item was created and the default one was not modified (same modification date); default CLI session still signed in |
| `remove` (stopped and running profiles) | OK | `--dry-run` printed the plan and changed nothing; a running profile was stopped by PID first; folders deleted |
| `remove work --all` | OK | profile stopped by PID, shortcut deleted, Desktop and CLI folders deleted, CLI signed out first: keychain items 17 → 16, default item unchanged |
| Restart cycles | OK, 2 of 2 | every instance stopped by PID, no spontaneous relaunch in 30 s, main instance back on account 1, `work` back on account 2 and still signed in |

### Problems found during the real run, and fixed

1. **A sign-in link reaches one running instance, not always the main one.** With the main instance closed but another profile still open, the link went to that other profile, which rejected it (`Google sign-in code does not answer a sign-in this app started; ignoring`). `login` now closes every other instance and restarts them all.
2. **The app allows two instances on the same profile folder.** A shortcut that launched the app directly started a duplicate on a running profile (the extra instance was closed right away; the cookie store passed `pragma integrity_check`). Shortcuts now go through `twindesk open`, and `list`, `open` and `doctor` report duplicates.
3. **The forced kill did not re-check the PID** after the delay and the confirmation. Fixed in both scripts.
4. A crash of the PowerShell `list` on an empty profile and a command-line split bug that prevented finding a running profile, both caught by unit tests.

### Observed, not fixed (documented limitations)

- Chrome extension pairing is disabled by the app in profiles (`local pairing disabled for this launch: userData relocated`).
- `--disk-cache-dir` is ignored by the app; the browser cache is already per profile. Logs and `~/Library/Caches/com.anthropic.claudefordesktop` are shared.
- Claude Desktop restarted by itself twice after being closed (out of 4 closings) in an earlier session; not seen again during the twindesk runs.
- A free account signs in to the desktop app; the app then gets `403 permission_error` when it requests Claude Code access.
- The CLI signs in with the account the browser is signed in to on claude.ai (the `cli` test ended up on account 1 for that reason).
- A shortcut started from a script cannot take the focus (macOS rule); a click does.

### Not tested for real

- The interactive confirmation prompts (the real run used `--yes` from a non-interactive shell). Covered by unit tests: without a terminal and without `--yes`, every confirmation refuses with exit 2.
- The forced kill path (no instance ever ignored TERM within 20 s).
- `install.sh` and `install.ps1` on a real machine beyond the unit-level checks.

## Unit tests

Run on 2026-10-26:

- `bats`: 39 tests, all passing, with the script run by macOS `/bin/bash` 3.2.57.
- `Pester` 5.6.1 on PowerShell 7.4 (Linux container): 30 passing, 1 skipped (Windows-only `.lnk` test).
- `ShellCheck` 0.10.0: no findings. `PSScriptAnalyzer` 1.22.0 (Error and Warning): no findings, with one rule excluded and justified in `PSScriptAnalyzerSettings.psd1`.

CI runs the same suites on macOS, Ubuntu and Windows, including Windows PowerShell 5.1.
