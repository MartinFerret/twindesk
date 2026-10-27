# Contributing

Thanks for helping. The most useful contribution right now is a **real test on Linux or Windows**.

## Reporting a test run

Run, with your own profile names:

```sh
twindesk doctor
twindesk add test
twindesk login test
twindesk list
twindesk open test
twindesk remove test
```

Then open an issue with the OS and version, the Claude Desktop version (`twindesk doctor` prints it), the output of each command, and what you saw on screen. Remove anything personal first. Never paste cookie values, tokens or files from a profile folder.

Things we do not know yet on Linux and Windows:

- what the main process command line looks like (`ps -A -ww -o pid=,args= | grep -i claude` on Linux, `Get-CimInstance Win32_Process -Filter "Name='claude.exe'" | Select ProcessId,ExecutablePath,CommandLine` on Windows);
- whether the app accepts `--user-data-dir` there;
- which instance receives the `claude://` sign-in link;
- on Windows, whether the per-user `claude.exe` forwards its arguments to the app.

## Code

- `twindesk` must stay compatible with Bash 3.2 (the macOS system bash): no `declare -A`, no `mapfile`, no `${var,,}`. Check with `/bin/bash`, not a Homebrew bash.
- `twindesk.ps1` must run on Windows PowerShell 5.1 and PowerShell 7, and keep the same commands, options, messages and exit codes as the Bash version.
- Never target an instance by app name or bundle id: always by PID, identified by its command line.
- One commit per change, with a clear message.

Before a pull request:

```sh
shellcheck -x twindesk install.sh scripts/bump-formula.sh test/helpers.bash
TD_BASH=/bin/bash bats test/
```

```powershell
Invoke-ScriptAnalyzer -Path twindesk.ps1 -Settings ./PSScriptAnalyzerSettings.psd1
Invoke-Pester test/
```

CI runs the same checks on macOS, Ubuntu and Windows.
