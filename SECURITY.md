# Security

twindesk is a small shell script. This page lists everything it touches and everything it never touches, and how each rule is enforced in the code.

## What twindesk touches

| What | Where | When |
|---|---|---|
| Its own data folder | macOS `~/Library/Application Support/twindesk`, Linux `${XDG_DATA_HOME:-~/.local/share}/twindesk`, Windows `%LOCALAPPDATA%\twindesk` | `add`, `cli`, `remove` |
| Claude Desktop processes | started with `--user-data-dir=<profile folder>`; closed by PID | `open`, `login`, `remove` |
| A launcher per profile | macOS `~/Applications/Claude (<profile>).app` (built with `osacompile`, re-signed ad hoc after twindesk adds its marker and optional badge icon), Linux `~/.local/share/applications/twindesk-<profile>.desktop`, Windows Start menu `Claude (<profile or label>).lnk` | `shortcut`, deleted by `remove` |
| Claude's icon, read-only | `Claude.app/Contents/Resources/<icon>.icns` | `shortcut --label` |
| The profile's cookie store, read-only | `<profile folder>/Cookies` | `list`, `status`, `login`, `doctor` |
| The installed command | `~/.local/bin/twindesk`, or `%LOCALAPPDATA%\twindesk\bin` | `install.sh`, `install.ps1` |

## What twindesk never touches

- **The main Claude data folder** (`~/Library/Application Support/Claude`, `~/.config/Claude`, `%APPDATA%\Claude`). twindesk never reads, writes, moves or deletes it. Its path appears in the code only in a guard that refuses a data root inside it, or containing it.
- **The Claude Desktop app**, its files and its code signature.
- **The keychain or credential store**, directly. One indirect case: `remove` asks Claude Code to sign a CLI profile out (`claude auth logout`) before deleting it, so that Claude Code deletes that profile's own credential instead of leaving it orphaned.
- **The `claude://` handler.** `doctor` and `status` only read which app handles it.
- **Your shell config and `PATH`.** `alias` and the installers print lines for you to copy.
- **The network.** twindesk makes no requests and sends no telemetry.
- **Admin rights.** No sudo, no elevation. The installers refuse to run as root.

## Secrets

twindesk never reads, prints, logs or copies a token, cookie value or session key. To know whether a profile is signed in, it counts the rows of the profile's own cookie store that are named `sessionKey`, belong to `claude.ai` and have not expired:

```sql
select count(*) from cookies where host_key in ('claude.ai','.claude.ai') and name='sessionKey' and (expires_utc=0 or expires_utc>NOW);
```

The database is opened read-only (`-readonly`, `immutable=1`). Only the count is used. A unit test puts a fake secret in the value column and checks that it never appears in any output.

## Deletion guards

Every deletion goes through one function (`safe_remove_dir` / `Remove-SafeDir`):

- only `<root>/profiles/<name>` or `<root>/cli/<name>` can be deleted;
- the name must match `^[a-z0-9][a-z0-9-]{0,31}$` (`default` and `main` are reserved);
- the path is resolved (links followed) and must equal exactly the expected folder under the resolved root;
- a link is never deleted or followed for deletion;
- the root itself must be an absolute path to a folder named `twindesk`, and must not be inside, or contain, the main Claude data folder;
- confirmation is required unless `--yes` is given, and refused when there is no terminal to ask;
- `--dry-run` shows the deletion and does nothing.

Launchers live outside the root, because that is where the OS looks for them. twindesk writes a marker into each launcher it creates (the profile name) and only ever deletes a launcher whose marker matches.

## Processes: by PID, never by name

With several instances of the same app, closing or focusing "Claude" by name is ambiguous. twindesk never does it.

- An instance is identified by its command line: the app's executable with no `--user-data-dir` is the main instance; with `--user-data-dir=<profile folder>`, exactly, it is that profile. Helper processes (`--type=...`) are ignored.
- Closing sends TERM (macOS, Linux) or a window close message (Windows) to that PID, waits, and checks that it is gone. A forced kill happens only after the delay and an explicit confirmation.
- The PID is checked again right before each signal, so a reused PID is never hit.
- Focusing uses the PID (`NSRunningApplication` or System Events on macOS, `xdotool`/`wmctrl` on Linux, `SetForegroundWindow` on Windows).
- An instance started with a `--user-data-dir` that is not a twindesk profile is never closed: `login` stops and asks you to close it yourself.

## Reporting a problem

Open an issue, or for anything sensitive contact the maintainer privately through GitHub before publishing details.
