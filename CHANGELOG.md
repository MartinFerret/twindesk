# Changelog

## 0.1.0 – 2026-10-26

First release.

- Commands: `add`, `list`, `open`, `login`, `status`, `shortcut`, `cli`, `alias`, `remove`, `doctor`, `help`, `--version`.
- Bash script for macOS and Linux (Bash 3.2 compatible), PowerShell script for Windows with the same commands, options, output and exit codes.
- `login` closes every other Claude instance by PID while a profile signs in, and restarts them afterwards, on timeout and on Ctrl+C.
- Shortcuts go through `twindesk open`, so a running profile is focused instead of started twice; duplicate instances on one profile are reported.
- `--dry-run` on every command that changes something; deletion limited to the twindesk data folder, resolved and checked.
- Per-user installers with uninstall, no admin rights.
- Tested on macOS 26.2 with Claude Desktop 3.6556.2. Linux and Windows: experimental, untested.
