# twindesk

Run several Claude Desktop accounts side by side. One window per account, no logging out and back in to switch.

![twindesk demo](docs/demo.gif)

Not affiliated with Anthropic. Claude is a trademark of Anthropic, PBC.

## Why

Claude Desktop signs in to one account at a time. If you have a personal account and a work or client account, every switch means signing out, signing back in and waiting for the email link.

twindesk works around this by launching the official app with a separate data folder per profile (`--user-data-dir`). Each profile keeps its own sign-in, app settings and local Claude Code / Cowork sessions. Your chats stay where they always were: with your account, on Anthropic's side.

It also gives you a separate Claude Code CLI sign-in per profile, which needs no workaround at all.

## Install

macOS, with Homebrew:

```sh
brew install MartinFerret/twindesk/twindesk
```

macOS and Linux, from a clone:

```sh
git clone https://github.com/MartinFerret/twindesk.git
cd twindesk
./install.sh
```

Windows (experimental, see [Support](#support)):

```powershell
git clone https://github.com/MartinFerret/twindesk.git
cd twindesk
.\install.ps1
```

No sudo, no admin rights, no `curl | bash`. The installer copies one script to `~/.local/bin` (or `%LOCALAPPDATA%\twindesk\bin`) and tells you how to add it to your `PATH`; it does not edit your shell config.

Requirements: Claude Desktop installed, and `sqlite3` to detect sign-in:

- macOS: preinstalled.
- Debian/Ubuntu: `sudo apt install sqlite3` (the one step that needs sudo, and it is apt's, not twindesk's).
- Windows: `winget install SQLite.SQLite`, then make sure `sqlite3.exe` is in your `PATH` (not verified on a real machine).

Without it everything works, but `list` shows the sign-in state as `unknown` and `login` cannot tell when you are signed in.

## Quick start

```sh
twindesk doctor          # check your setup
twindesk add work        # create a profile
twindesk login work      # sign in to your second account (guided)
twindesk open work       # open it next to your main Claude
```

Your main Claude keeps your first account. The `work` window has the second.

## Commands

| Command | What it does |
|---|---|
| `twindesk add <profile>` | Create a profile |
| `twindesk list [--json]` | Profiles, running state and PID, signed-in state, disk usage |
| `twindesk open <profile>` | Start a profile, or bring it to the front if it is running |
| `twindesk login <profile> [--timeout <s>]` | Guided sign-in (see below), 300 s by default |
| `twindesk status [profile] [--json]` | Diagnostics |
| `twindesk shortcut <profile> [--label <text>]` | Launcher for the profile: an app in `~/Applications` (macOS), a `.desktop` file (Linux), a Start menu shortcut (Windows). `--label` puts a badge on the launcher's icon on macOS (for example `--label 2` or `--label Work`) and names the shortcut after it on Linux and Windows |
| `twindesk cli <profile> [args...]` | Run Claude Code CLI with the profile's own sign-in and settings |
| `twindesk alias <profile>` | Print shell aliases to copy; nothing is written |
| `twindesk remove <profile> [--yes] [--all]` | Stop and delete a profile and its shortcut; asks separately about the CLI profile (`--all`: delete everything without asking) |
| `twindesk doctor` | Check OS, app, version, `claude://` handler, running instances, permissions |

Every command that changes something accepts `--dry-run`. Confirmations can be answered in advance with `--yes`; without a terminal and without `--yes`, twindesk refuses instead of guessing.

Profile names: 1 to 32 characters, lowercase letters, digits and `-`. `default` and `main` are reserved.

Exit codes: `0` ok, `1` error, `2` usage, `3` app not found, `4` profile not found, `5` timeout, `130` interrupted.

## How sign-in works

Claude Desktop signs in through a `claude://` link that your browser hands back to the app. When several instances run, macOS delivers that link to just one of them, usually not the one that is signing in, and that instance rejects it. So `twindesk login` does this for you:

1. Lists every other running Claude instance (your main one and other profiles), asks for confirmation, and closes them, one by one by PID.
2. Opens the profile and tells you what to do.
3. Waits until the profile's own cookie store shows a session (it checks that a session cookie exists, never its value). If Claude restarts by itself meanwhile, twindesk closes it again and tells you.
4. Restarts everything it closed, also when you press Ctrl+C or the timeout runs out.

You do this once per profile, then again when the session expires (about a month). Closing an instance interrupts any Claude Code or Cowork session running in it; twindesk warns you first.

Claude Code CLI profiles sign in on their own the first time you run `twindesk cli <profile>`, through `localhost`, with no dance. The CLI signs in with whatever account your browser is currently signed in to on claude.ai: to pick another account, open the sign-in link in a private window.

## Known limitations

Read this before relying on twindesk.

- **Unofficial.** twindesk relies on a command-line flag the app accepts today. Any Claude Desktop update can change that. `twindesk doctor` warns when your app is newer than the last tested version.
- **Sign-in needs every other instance closed.** See above. Anything else that goes through a `claude://` link (signing in again, probably connector authorizations: not verified) has the same constraint.
- **Never start a profile twice.** The app does not prevent two instances on the same profile folder, and two instances writing one profile can corrupt it. `twindesk open` and the shortcuts bring a running profile to the front instead; `list`, `open` and `doctor` warn if a profile runs twice. Do not launch the app with `--user-data-dir` yourself.
- **Chrome extension is off in profiles.** Claude Desktop turns off its Chrome extension pairing when it sees a relocated data folder (its log says `local pairing disabled for this launch: userData relocated`). Only your main instance keeps it.
- **Shared between instances:** the app binary and its updates (an update started from one instance affects the others), the logs (`~/Library/Logs/Claude`), a small system cache (`~/Library/Caches/com.anthropic.claudefordesktop`) and the keychain item "Claude Safe Storage". The browser cache itself is per profile; `--disk-cache-dir` was tested and is ignored by the app.
- **Claude Desktop sometimes restarts by itself** after being closed (seen 2 times out of 4 in testing, cause unknown). `twindesk login` handles it.
- **Same Dock icon once running.** `shortcut --label` badges the launcher's icon, but a running profile still shows the normal Claude icon in the Dock: changing that would mean modifying the app, which twindesk never does. Starting a shortcut from a script cannot steal focus (a macOS rule); clicking it does.
- **Free accounts** can sign in to the desktop app, but the app gets a `403 permission_error` when it requests Claude Code access, so Claude Code inside Desktop is probably unavailable on a free plan (not verified).
- **Sign-in state needs `sqlite3`.** Without it, `list` shows `unknown`.

## Support

| Platform | Status | Tested with |
|---|---|---|
| macOS 26.2 (Apple silicon) | Tested | Claude Desktop 3.6556.2, 2026-10-26 |
| Linux (Ubuntu/Debian, official `claude-desktop` package) | Experimental – untested | — |
| Windows (per-user installer) | Experimental – untested | — |

"Experimental – untested" means the code exists and its unit tests pass, but nobody has run it against a real install yet. On Windows, the Microsoft Store (MSIX) version is not supported. Reports welcome.

Tested with Claude Desktop 3.6556.2 on macOS 26.2, 2026-10-26. Details in [TESTED.md](TESTED.md).

## What twindesk touches

- Its own data folder: `~/Library/Application Support/twindesk` (macOS), `${XDG_DATA_HOME:-~/.local/share}/twindesk` (Linux), `%LOCALAPPDATA%\twindesk` (Windows). Profiles live in `profiles/<name>`, CLI profiles in `cli/<name>`.
- Running Claude Desktop instances: it starts them with `--user-data-dir`, and closes them by PID when you ask it to (`login`, `remove`).
- Optionally a launcher for a profile, created by `shortcut` and deleted with the profile.

It never modifies Claude Desktop, its signature, the `claude://` handler or your main Claude data folder, never uses sudo, makes no network requests and sends no telemetry. It never reads, prints or logs a token, cookie value or session key. The one indirect exception: `remove` signs a CLI profile out through Claude Code itself (`claude auth logout`), which deletes that profile's own credential from your keychain. Details in [SECURITY.md](SECURITY.md).

## Uninstall

```sh
./install.sh --uninstall                  # asks whether to keep your profiles
./install.sh --uninstall --keep-profiles  # or --purge to delete them
```

With Homebrew: `brew uninstall twindesk` (profiles are kept; run `twindesk remove <profile> --all` first to delete them).

On Windows: `.\install.ps1 -Uninstall` (with `-KeepProfiles` or `-Purge`). Purging goes through `twindesk remove --all` for each profile.

## Contributing

Testing on Linux and Windows is where help matters most. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT, see [LICENSE](LICENSE).
