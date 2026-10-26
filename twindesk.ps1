# twindesk - run several Claude Desktop accounts side by side (Windows).
# Each profile is the official app launched with its own --user-data-dir.
# Not affiliated with Anthropic. MIT licensed.
#
# Compatible with Windows PowerShell 5.1 and PowerShell 7. Same commands,
# options, output and exit codes as the Bash version.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:Version = '0.1.0'
# Claude Desktop versions this release was tested against ("os|version|date").
$script:TestedVersions = @('macos|3.6556.2|2026-10-26')

$script:EXIT_OK = 0
$script:EXIT_ERROR = 1
$script:EXIT_USAGE = 2
$script:EXIT_NO_APP = 3
$script:EXIT_NO_PROFILE = 4
$script:EXIT_TIMEOUT = 5
$script:EXIT_INTERRUPTED = 130

$script:DryRun = $false
$script:AssumeYes = $false
$script:Json = $false

$script:ExitCode = 0

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

function Test-Color([bool]$ToStdErr) {
    if ($env:NO_COLOR) { return $false }
    if ($ToStdErr) { return -not [Console]::IsErrorRedirected }
    return -not [Console]::IsOutputRedirected
}

function Format-Paint([string]$Code, [string]$Text, [bool]$ToStdErr) {
    if (Test-Color $ToStdErr) { return "$([char]27)[$($Code)m$Text$([char]27)[0m" }
    return $Text
}

function Write-Say([string]$Text) { [Console]::Out.WriteLine($Text) }
function Write-Ok([string]$Text) { [Console]::Out.WriteLine("$(Format-Paint '32' 'ok' $false) $Text") }
function Write-Info([string]$Text) { [Console]::Out.WriteLine("$(Format-Paint '36' '->' $false) $Text") }
function Write-Warn([string]$Text) { [Console]::Error.WriteLine("$(Format-Paint '33' 'warning:' $true) $Text") }
function Write-Err([string]$Text) { [Console]::Error.WriteLine("$(Format-Paint '31' 'error:' $true) $Text") }
function Write-Dry([string]$Text) { [Console]::Out.WriteLine("$(Format-Paint '35' '[dry-run]' $false) $Text") }

# Abort with an exit code: an ordinary exception carrying the code in Data
# (classes in catch clauses are unreliable on Windows PowerShell 5.1).
function Exit-Twindesk([int]$Code, [string]$Message) {
    $e = New-Object System.Exception $Message
    $e.Data['TwindeskExitCode'] = $Code
    throw $e
}

function ConvertTo-JsonString([string]$s) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    foreach ($c in $s.ToCharArray()) {
        switch ([int]$c) {
            34 { [void]$sb.Append('\"') }
            92 { [void]$sb.Append('\\') }
            10 { [void]$sb.Append('\n') }
            13 { [void]$sb.Append('\r') }
            9 { [void]$sb.Append('\t') }
            default {
                if ([int]$c -lt 32) { [void]$sb.Append(('\u{0:x4}' -f [int]$c)) } else { [void]$sb.Append($c) }
            }
        }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function ConvertTo-JsonBool([string]$v) {
    if ($v -eq 'yes') { return 'true' }
    if ($v -eq 'no') { return 'false' }
    return 'null'
}

function ConvertTo-JsonNum($v) { if ($null -ne $v -and "$v" -ne '') { return "$v" } return 'null' }

# ---------------------------------------------------------------------------
# Confirmation
# ---------------------------------------------------------------------------

function Confirm-Action([string]$Question) {
    if ($script:AssumeYes) { return $true }
    if ($script:DryRun) { Write-Dry "would ask: $Question"; return $true }
    if ([Console]::IsInputRedirected) {
        Exit-Twindesk $script:EXIT_USAGE 'confirmation needed but stdin is not a terminal: re-run with --yes'
    }
    [Console]::Error.Write("$Question [y/N] ")
    $answer = [Console]::In.ReadLine()
    return ($answer -match '^(y|yes)$')
}

# ---------------------------------------------------------------------------
# Platform, paths, names
# ---------------------------------------------------------------------------

function Get-OsName {
    if ($env:TWINDESK_OS) { return $env:TWINDESK_OS }
    if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) { return 'windows' }
    return 'unsupported'
}

$script:OS = Get-OsName

function Get-OsStatus { if ($script:OS -eq 'macos') { return 'tested' } return 'experimental' }

function Get-LocalAppData {
    if ($env:LOCALAPPDATA) { return $env:LOCALAPPDATA }
    return (Join-Path $HOME 'AppData/Local')
}

$script:Root = if ($env:TWINDESK_HOME) { $env:TWINDESK_HOME } else { Join-Path (Get-LocalAppData) 'twindesk' }
$script:ProfilesDir = Join-Path $script:Root 'profiles'
$script:CliDir = Join-Path $script:Root 'cli'

# Main Claude Desktop data folders. twindesk never reads, writes or deletes them:
# they are only used by the guards below to refuse paths that touch them.
function Get-MainDataDir {
    $dirs = @()
    if ($env:APPDATA) { $dirs += (Join-Path $env:APPDATA 'Claude') }
    $dirs += (Join-Path (Get-LocalAppData) 'Packages/Claude_pzs8sxrjxfjjc')
    return $dirs
}

# Resolve a path (following links) without requiring it to exist.
function Resolve-FullPath([string]$Path) {
    $p = [System.IO.Path]::GetFullPath($Path)
    $rest = @()
    while (-not (Test-Path -LiteralPath $p) -and $p -ne [System.IO.Path]::GetPathRoot($p)) {
        $rest = @([System.IO.Path]::GetFileName($p)) + $rest
        $p = [System.IO.Path]::GetDirectoryName($p)
    }
    # Follow link targets component by component.
    $cur = [System.IO.Path]::GetPathRoot($p)
    foreach ($seg in ($p.Substring($cur.Length) -split '[\\/]' | Where-Object { $_ -ne '' })) {
        $cur = Join-Path $cur $seg
        $item = Get-Item -LiteralPath $cur -Force -ErrorAction SilentlyContinue
        if ($item -and $item.PSObject.Properties['LinkType'] -and $item.LinkType) {
            $target = @($item.Target)[0]
            if ($target) {
                if (-not [System.IO.Path]::IsPathRooted($target)) { $target = Join-Path (Split-Path $cur -Parent) $target }
                $cur = Resolve-FullPath $target
            }
        }
    }
    foreach ($r in $rest) { $cur = Join-Path $cur $r }
    return $cur.TrimEnd('\', '/')
}

function Test-Within([string]$Child, [string]$Parent) {
    $sep = [System.IO.Path]::DirectorySeparatorChar
    $c = $Child.TrimEnd('\', '/') + $sep
    $p = $Parent.TrimEnd('\', '/') + $sep
    $cmp = if ($script:OS -eq 'windows') { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    return $c.StartsWith($p, $cmp)
}

function Test-Root {
    if (-not [System.IO.Path]::IsPathRooted($script:Root)) {
        Exit-Twindesk $script:EXIT_USAGE "data root must be an absolute path: $($script:Root)"
    }
    if ([System.IO.Path]::GetFileName($script:Root.TrimEnd('\', '/')) -ne 'twindesk') {
        Exit-Twindesk $script:EXIT_USAGE "data root must be a folder named 'twindesk': $($script:Root)"
    }
    $real = Resolve-FullPath $script:Root
    foreach ($d in Get-MainDataDir) {
        $rd = Resolve-FullPath $d
        if (Test-Within $real $rd) { Exit-Twindesk $script:EXIT_USAGE "data root is inside the main Claude data folder, refusing: $($script:Root)" }
        if (Test-Within $rd $real) { Exit-Twindesk $script:EXIT_USAGE "data root contains the main Claude data folder, refusing: $($script:Root)" }
    }
}

function Test-NameOk([string]$Name) { return [regex]::IsMatch($Name, '^[a-z0-9][a-z0-9-]{0,31}\z', [System.Text.RegularExpressions.RegexOptions]::CultureInvariant) }

function Assert-Name([string]$Name) {
    if (-not $Name) { Exit-Twindesk $script:EXIT_USAGE 'missing profile name' }
    if (-not (Test-NameOk $Name)) {
        Exit-Twindesk $script:EXIT_USAGE "invalid profile name '$Name': use 1-32 chars, lowercase letters, digits and '-', not starting with '-'"
    }
    if ($Name -eq 'default' -or $Name -eq 'main') { Exit-Twindesk $script:EXIT_USAGE "'$Name' is reserved" }
}

function Get-ProfileDir([string]$Name) { return (Join-Path $script:ProfilesDir $Name) }
function Get-CliProfileDir([string]$Name) { return (Join-Path $script:CliDir $Name) }

function Assert-Profile([string]$Name) {
    Assert-Name $Name
    if (-not (Test-Path -LiteralPath (Get-ProfileDir $Name) -PathType Container)) {
        Exit-Twindesk $script:EXIT_NO_PROFILE "profile '$Name' not found (create it with: twindesk add $Name)"
    }
}

# Delete <root>/<kind>/<name> only: resolved, checked, never a link, never outside the root.
function Remove-SafeDir([string]$Path, [string]$Kind, [string]$Name) {
    Assert-Name $Name
    Test-Root
    $expected = Join-Path (Join-Path (Resolve-FullPath $script:Root) $Kind) $Name
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSObject.Properties['LinkType'] -and $item.LinkType) { Exit-Twindesk $script:EXIT_ERROR "refusing to delete a link: $Path" }
    $real = Resolve-FullPath $Path
    $same = if ($script:OS -eq 'windows') { $real -ieq $expected } else { $real -ceq $expected }
    if (-not $same) { Exit-Twindesk $script:EXIT_ERROR "refusing to delete '$Path': resolves to '$real', expected '$expected'" }
    if ($script:DryRun) { Write-Dry "would delete $real"; return }
    Remove-Item -LiteralPath $real -Recurse -Force
}

# ---------------------------------------------------------------------------
# App detection
# ---------------------------------------------------------------------------

$script:App = ''      # what we launch
$script:AppExeDir = '' # folder the running claude.exe lives under
$script:IsSquirrelStub = $false

function Find-App {
    if ($env:TWINDESK_APP) {
        $script:App = $env:TWINDESK_APP
    }
    else {
        # Per-user (Squirrel) install. The stub forwards to app-<version>\claude.exe.
        $c = Join-Path (Get-LocalAppData) 'AnthropicClaude/claude.exe'
        if (Test-Path -LiteralPath $c -PathType Leaf) { $script:App = $c }
    }
    if (-not $script:App -or -not (Test-Path -LiteralPath $script:App -PathType Leaf)) { return $false }
    $script:AppExeDir = Split-Path $script:App -Parent
    $script:IsSquirrelStub = Test-Path -LiteralPath (Join-Path $script:AppExeDir 'Update.exe')
    return $true
}

function Assert-App { if (-not (Find-App)) { Exit-Twindesk $script:EXIT_NO_APP 'Claude Desktop not found (set TWINDESK_APP to its path)' } }

function Get-AppVersion {
    try { return (Get-Item -LiteralPath $script:App).VersionInfo.ProductVersion } catch { return '' }
}

function Get-TestedVersion {
    foreach ($l in $script:TestedVersions) {
        $f = $l -split '\|'
        if ($f[0] -eq $script:OS) { return $f[1] }
    }
    return ''
}

function Compare-Version([string]$A, [string]$B) {
    $x = @($A -split '\.'); $y = @($B -split '\.')
    $n = [Math]::Max($x.Count, $y.Count)
    for ($i = 0; $i -lt $n; $i++) {
        $xi = 0; $yi = 0
        if ($i -lt $x.Count -and $x[$i] -match '^(\d+)') { $xi = [long]$Matches[1] }
        if ($i -lt $y.Count -and $y[$i] -match '^(\d+)') { $yi = [long]$Matches[1] }
        if ($xi -lt $yi) { return -1 }
        if ($xi -gt $yi) { return 1 }
    }
    return 0
}

# ---------------------------------------------------------------------------
# Processes: always by PID, identified by executable path and command line
# ---------------------------------------------------------------------------

# Split a Windows command line the way CommandLineToArgvW does.
function Split-CommandLine([string]$Line) {
    $argsOut = New-Object System.Collections.Generic.List[string]
    $cur = New-Object System.Text.StringBuilder
    $inQuotes = $false; $has = $false; $i = 0
    while ($i -lt $Line.Length) {
        $c = $Line[$i]
        if ($c -eq '\') {
            $n = 0
            while ($i -lt $Line.Length -and $Line[$i] -eq '\') { $n++; $i++ }
            if ($i -lt $Line.Length -and $Line[$i] -eq '"') {
                [void]$cur.Append('\' * [Math]::Floor($n / 2))
                if ($n % 2 -eq 1) { [void]$cur.Append('"'); $i++ }
            }
            else { [void]$cur.Append('\' * $n) }
            $has = $true
            continue
        }
        if ($c -eq '"') { $inQuotes = -not $inQuotes; $has = $true; $i++; continue }
        if (($c -eq ' ' -or $c -eq "`t") -and -not $inQuotes) {
            if ($has) { $argsOut.Add($cur.ToString()); [void]$cur.Clear(); $has = $false }
            $i++; continue
        }
        [void]$cur.Append($c); $has = $true; $i++
    }
    if ($has) { $argsOut.Add($cur.ToString()) }
    return , $argsOut.ToArray()
}

# Process snapshot: objects with Pid, Exe, CommandLine.
function Get-ProcessSnapshot {
    if ($env:TWINDESK_PS_FIXTURE) {
        foreach ($l in Get-Content -LiteralPath $env:TWINDESK_PS_FIXTURE) {
            if (-not $l.Trim()) { continue }
            $f = $l -split "`t", 3
            [pscustomobject]@{ Pid = [int]$f[0]; Exe = $f[1]; CommandLine = $f[2] }
        }
        return
    }
    foreach ($p in Get-CimInstance Win32_Process -Filter "Name = 'claude.exe'" -ErrorAction SilentlyContinue) {
        [pscustomobject]@{ Pid = [int]$p.ProcessId; Exe = [string]$p.ExecutablePath; CommandLine = [string]$p.CommandLine }
    }
}

# main | profile | '' (helpers with --type=, or other programs)
function Get-InstanceKind($Proc) {
    if (-not $Proc.Exe -or -not (Test-Within $Proc.Exe $script:AppExeDir)) { return '' }
    if ([System.IO.Path]::GetFileName($Proc.Exe) -ine 'claude.exe') { return '' }
    # The Squirrel stub only forwards to app-<version>\claude.exe and exits.
    if ($script:IsSquirrelStub -and $Proc.Exe -ieq $script:App) { return '' }
    $argv = Split-CommandLine $Proc.CommandLine
    $rest = @($argv | Select-Object -Skip 1)
    foreach ($a in $rest) { if ($a.StartsWith('--type=')) { return '' } }
    foreach ($a in $rest) { if ($a.StartsWith('--user-data-dir=')) { return 'profile' } }
    return 'main'
}

function Get-MainPid {
    foreach ($p in Get-ProcessSnapshot) { if ((Get-InstanceKind $p) -eq 'main') { $p.Pid } }
}

# PIDs of every instance running a given profile folder. More than one means a
# duplicate: the app does not stop a second instance on the same folder, and two
# instances writing one profile can corrupt it.
function Get-ProfilePidAll([string]$Name) {
    $want = Get-ProfileDir $Name
    foreach ($p in Get-ProcessSnapshot) {
        if ((Get-InstanceKind $p) -ne 'profile') { continue }
        $argv = Split-CommandLine $p.CommandLine
        foreach ($a in @($argv | Select-Object -Skip 1)) {
            if ($a.StartsWith('--user-data-dir=')) {
                $v = $a.Substring(16).TrimEnd('\', '/')
                if ($v -ieq $want) { $p.Pid }
            }
        }
    }
}

function Get-ProfilePid([string]$Name) { return (@(Get-ProfilePidAll $Name) | Select-Object -First 1) }

function Test-PidExpected([int]$ProcessId, [string]$Expect) {
    if ($Expect -eq 'main') { return (@(Get-MainPid) -contains $ProcessId) }
    if ($Expect.StartsWith('profile:')) { return ((Get-ProfilePid $Expect.Substring(8)) -eq $ProcessId) }
    return $false
}

function Test-PidAlive([int]$ProcessId) { return [bool](Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) }

# Close exactly one PID gracefully (WM_CLOSE), wait, verify. Force only as a
# last resort, after the delay and an explicit confirmation.
function Stop-InstancePid([int]$ProcessId, [string]$Label, [string]$Expect) {
    $limit = if ($env:TWINDESK_STOP_TIMEOUT) { [int]$env:TWINDESK_STOP_TIMEOUT } else { 20 }
    # Re-check what the PID is right before each action (PIDs can be reused).
    if (-not (Test-PidExpected $ProcessId $Expect)) { Exit-Twindesk $script:EXIT_ERROR "PID $ProcessId is no longer $Label, not touching it" }
    if ($script:DryRun) { Write-Dry "would close $Label (PID $ProcessId)"; return }
    $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($proc) { [void]$proc.CloseMainWindow() }
    $waited = 0
    while ((Test-PidAlive $ProcessId) -and $waited -lt $limit) { Start-Sleep -Seconds 1; $waited++ }
    if (Test-PidAlive $ProcessId) {
        Write-Warn "$Label (PID $ProcessId) still running after $($limit)s"
        if (Confirm-Action "Force quit $Label (PID $ProcessId)? Unsaved work in it will be lost.") {
            if (-not (Test-PidExpected $ProcessId $Expect)) { Exit-Twindesk $script:EXIT_ERROR "PID $ProcessId is no longer $Label, not touching it" }
            Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
        }
    }
    if (Test-PidAlive $ProcessId) { Exit-Twindesk $script:EXIT_ERROR "$Label (PID $ProcessId) did not stop" }
    Write-Ok "$Label stopped (PID $ProcessId)"
}

function Wait-ForPid([scriptblock]$Probe, [int]$Limit) {
    for ($i = 0; $i -lt $Limit; $i++) {
        $p = & $Probe
        if ($p) { return @($p)[0] }
        Start-Sleep -Seconds 1
    }
    return $null
}

function Start-Main {
    if ($script:DryRun) { Write-Dry 'would start the main instance'; return }
    Start-Process -FilePath $script:App | Out-Null
}

function Start-Profile([string]$Name) {
    $arg = '--user-data-dir=' + (Get-ProfileDir $Name)
    if ($script:DryRun) { Write-Dry "would start profile '$Name' with $arg"; return }
    Start-Process -FilePath $script:App -ArgumentList ('"' + $arg + '"') | Out-Null
}

# Bring a window to the front by PID (Win32), never by name.
function Set-ForegroundPid([int]$ProcessId) {
    if ($script:DryRun) { Write-Dry "would bring PID $ProcessId to the front"; return $true }
    try {
        if (-not ('Twindesk.Win32' -as [type])) {
            Add-Type -Namespace Twindesk -Name Win32 -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@
        }
        $h = (Get-Process -Id $ProcessId).MainWindowHandle
        if ($h -ne [IntPtr]::Zero) {
            [void][Twindesk.Win32]::ShowWindow($h, 9)
            if ([Twindesk.Win32]::SetForegroundWindow($h)) { return $true }
        }
    }
    catch { Write-Verbose $_.Exception.Message }
    Write-Warn "could not bring PID $ProcessId to the front"
    return $false
}

# ---------------------------------------------------------------------------
# Profile state
# ---------------------------------------------------------------------------

# Signed in = the profile's own cookie store has a non-expired claude.ai
# "sessionKey" row. Only the row count is read, never the value.
function Get-SignedIn([string]$Name) {
    $dir = Get-ProfileDir $Name
    $db = $null
    foreach ($c in @((Join-Path $dir 'Cookies'), (Join-Path $dir 'Network/Cookies'))) {
        if (Test-Path -LiteralPath $c -PathType Leaf) { $db = $c; break }
    }
    if (-not $db) { return 'no' }
    $sqlite = Get-Command sqlite3 -ErrorAction SilentlyContinue
    if (-not $sqlite) { return 'unknown' }
    $uri = $db.Replace('%', '%25').Replace('?', '%3f').Replace('#', '%23').Replace('\', '/')
    $now = ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 11644473600) * 1000000
    $q = "select count(*) from cookies where host_key in ('claude.ai','.claude.ai') and name='sessionKey' and (expires_utc=0 or expires_utc>$now);"
    try { $count = & $sqlite.Source -readonly "file:$($uri)?immutable=1" $q 2>$null } catch { return 'unknown' }
    if ("$count" -notmatch '^\d+$') { return 'unknown' }
    if ([int]$count -eq 0) { return 'no' }
    return 'yes'
}

function Get-DirSizeKb([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    $files = @(Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue)
    if ($files.Count -eq 0) { return 0 }
    $sum = ($files | Measure-Object -Property Length -Sum).Sum
    return [long][Math]::Ceiling($sum / 1024)
}

function Format-Kb([long]$Kb) {
    $ci = [System.Globalization.CultureInfo]::InvariantCulture
    if ($Kb -ge 1048576) { return ($Kb / 1048576).ToString('0.0', $ci) + ' GB' }
    if ($Kb -ge 1024) { return ($Kb / 1024).ToString('0', $ci) + ' MB' }
    return "$Kb KB"
}

# Names of Desktop profiles (profiles/<name>) and CLI-only profiles (cli/<name>).
function Get-ProfileName {
    $names = @()
    foreach ($base in @($script:ProfilesDir, $script:CliDir)) {
        if (-not (Test-Path -LiteralPath $base)) { continue }
        foreach ($d in Get-ChildItem -LiteralPath $base -Directory -Force) {
            if ($d.PSObject.Properties['LinkType'] -and $d.LinkType) { continue }
            if (Test-NameOk $d.Name) { $names += $d.Name }
        }
    }
    $names | Sort-Object -Unique
}

function Test-HasDesktop([string]$Name) {
    $d = Get-ProfileDir $Name
    if (-not (Test-Path -LiteralPath $d -PathType Container)) { return $false }
    $i = Get-Item -LiteralPath $d -Force
    return -not ($i.PSObject.Properties['LinkType'] -and $i.LinkType)
}

# Works without the app (profiles are then shown as stopped), so profiles can
# still be listed and removed after Claude Desktop is uninstalled.
function Get-ProfileRow([string]$Name) {
    $row = [pscustomobject]@{ Desktop = 'no'; Pid = $null; SignedIn = 'unknown'; Kb = 0; Cli = 'no' }
    if (Test-HasDesktop $Name) {
        $row.Desktop = 'yes'
        if ($script:App) { $row.Pid = Get-ProfilePid $Name }
        $row.SignedIn = Get-SignedIn $Name
        $row.Kb = Get-DirSizeKb (Get-ProfileDir $Name)
    }
    if (Test-Path -LiteralPath (Get-CliProfileDir $Name)) { $row.Cli = 'yes' }
    return $row
}

# ---------------------------------------------------------------------------
# Shortcuts (Start menu .lnk with a marker in its description)
# ---------------------------------------------------------------------------

function Get-ShortcutPath([string]$Name) {
    $base = if ($env:APPDATA) { $env:APPDATA } else { Join-Path $HOME 'AppData/Roaming' }
    return (Join-Path $base "Microsoft/Windows/Start Menu/Programs/Claude ($Name).lnk")
}

function Get-ShortcutMarker([string]$Name) { return "twindesk-profile:$Name" }

function Test-ShortcutOwned([string]$Path, [string]$Name) {
    try {
        $sh = New-Object -ComObject WScript.Shell
        return ($sh.CreateShortcut($Path).Description -eq (Get-ShortcutMarker $Name))
    }
    catch { return $false }
}

function New-ProfileShortcut([string]$Name) {
    $path = Get-ShortcutPath $Name
    if ((Test-Path -LiteralPath $path) -and -not (Test-ShortcutOwned $path $Name)) {
        Exit-Twindesk $script:EXIT_ERROR "'$path' exists and was not created by twindesk"
    }
    if ($script:DryRun) { Write-Dry "would create shortcut $path"; return }
    New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
    # The shortcut runs `twindesk open`, which focuses a running profile by PID
    # instead of starting a second instance on the same folder.
    $sh = New-Object -ComObject WScript.Shell
    $lnk = $sh.CreateShortcut($path)
    $lnk.TargetPath = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
    $lnk.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $PSCommandPath + '" open ' + $Name
    $lnk.IconLocation = $script:App
    $lnk.Description = Get-ShortcutMarker $Name
    $lnk.Save()
    Write-Ok "shortcut created: $path"
}

function Remove-ProfileShortcut([string]$Name) {
    $path = Get-ShortcutPath $Name
    if (-not (Test-Path -LiteralPath $path)) { return }
    if (-not (Test-ShortcutOwned $path $Name)) { Write-Warn "not deleting '$path': not created by twindesk"; return }
    if ($script:DryRun) { Write-Dry "would delete shortcut $path"; return }
    Remove-Item -LiteralPath $path -Force
    Write-Ok "shortcut removed: $path"
}

# claude:// handler (read-only)
function Get-UrlHandler {
    foreach ($k in @('HKCU:\Software\Classes\claude\shell\open\command', 'Registry::HKEY_CLASSES_ROOT\claude\shell\open\command')) {
        try {
            $v = (Get-ItemProperty -LiteralPath $k -ErrorAction Stop).'(default)'
            if ($v) { return [string]$v }
        }
        catch { Write-Verbose "no handler at $k" }
    }
    return ''
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

function Invoke-Add([string]$Name) {
    Assert-Name $Name
    Test-Root
    $dir = Get-ProfileDir $Name
    if (Test-Path -LiteralPath $dir) { Exit-Twindesk $script:EXIT_ERROR "profile '$Name' already exists" }
    if ($script:DryRun) { Write-Dry "would create $dir"; return }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Write-Ok "profile '$Name' created: $dir"
    Write-Say "Next: twindesk login $Name"
}

function Get-ListJson {
    $items = @()
    foreach ($n in Get-ProfileName) {
        $r = Get-ProfileRow $n
        $running = if ($r.Pid) { 'true' } else { 'false' }
        $si = if ($r.Desktop -eq 'yes') { ConvertTo-JsonBool $r.SignedIn } else { 'null' }
        $items += ('{{"name":{0},"desktop_profile":{1},"running":{2},"pid":{3},"signed_in":{4},"size_kb":{5},"cli_profile":{6},"path":{7}}}' -f
            (ConvertTo-JsonString $n), (ConvertTo-JsonBool $r.Desktop), $running, (ConvertTo-JsonNum $r.Pid), $si,
            $r.Kb, (ConvertTo-JsonBool $r.Cli), (ConvertTo-JsonString (Get-ProfileDir $n)))
    }
    return '[' + ($items -join ',') + ']'
}

function Invoke-List {
    if (-not $script:App -and -not (Find-App)) { Write-Warn 'Claude Desktop not found: running state unknown' }
    if ($script:Json) { Write-Say (Get-ListJson); return }
    $names = @(Get-ProfileName)
    if ($names.Count -eq 0) { Write-Say 'No profiles yet. Create one with: twindesk add <name>'; return }
    Write-Say ('{0,-20} {1,-18} {2,-10} {3,-9} {4}' -f 'PROFILE', 'STATE', 'SIGNED IN', 'SIZE', 'CLI')
    foreach ($n in $names) {
        $r = Get-ProfileRow $n
        if ($r.Desktop -eq 'yes') {
            $state = if ($r.Pid) { "running ($($r.Pid))" } else { 'stopped' }
            Write-Say ('{0,-20} {1,-18} {2,-10} {3,-9} {4}' -f $n, $state, $r.SignedIn, (Format-Kb $r.Kb), $r.Cli)
        }
        else { Write-Say ('{0,-20} {1,-18} {2,-10} {3,-9} {4}' -f $n, '(CLI only)', '-', '-', $r.Cli) }
    }
}

function Invoke-Open([string]$Name) {
    Assert-App
    Assert-Profile $Name
    $all = @(Get-ProfilePidAll $Name)
    if ($all.Count -gt 1) { Write-Warn "profile '$Name' runs in several instances ($($all -join ' ')): this can corrupt it. Quit the extra windows." }
    $p = Get-ProfilePid $Name
    if ($p) {
        Write-Info "profile '$Name' is running (PID $p), bringing it to the front"
        [void](Set-ForegroundPid $p)
        return
    }
    Start-Profile $Name
    if ($script:DryRun) { return }
    $p = Wait-ForPid { Get-ProfilePid $Name } 30
    if (-not $p) { Exit-Twindesk $script:EXIT_TIMEOUT "profile '$Name' did not start within 30s" }
    Write-Ok "profile '$Name' started (PID $p)"
    if ((Get-SignedIn $Name) -eq 'no') { Write-Say "Not signed in yet: run 'twindesk login $Name'." }
}

# Every running instance: objects with Pid, Kind (main|profile|foreign) and Name.
function Get-AppInstance {
    $prefix = $script:ProfilesDir.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    foreach ($p in Get-ProcessSnapshot) {
        $kind = Get-InstanceKind $p
        if ($kind -eq 'main') { [pscustomobject]@{ Pid = $p.Pid; Kind = 'main'; Name = '' }; continue }
        if ($kind -ne 'profile') { continue }
        $argv = Split-CommandLine $p.CommandLine
        $n = ''
        foreach ($a in @($argv | Select-Object -Skip 1)) {
            if ($a.StartsWith('--user-data-dir=')) {
                $v = $a.Substring(16).Replace('/', [System.IO.Path]::DirectorySeparatorChar).TrimEnd('\', '/')
                $pfx = $prefix.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
                if ($v.StartsWith($pfx, [System.StringComparison]::OrdinalIgnoreCase)) { $n = $v.Substring($pfx.Length) }
            }
        }
        if ($n -and (Test-NameOk $n) -and (Get-ProfilePid $n) -eq $p.Pid) { [pscustomobject]@{ Pid = $p.Pid; Kind = 'profile'; Name = $n } }
        else { [pscustomobject]@{ Pid = $p.Pid; Kind = 'foreign'; Name = '' } }
    }
}

function Get-OtherInstance([string]$Name) {
    Get-AppInstance | Where-Object { -not ($_.Kind -eq 'profile' -and $_.Name -eq $Name) }
}

function Format-Instance($i) {
    if ($i.Kind -eq 'main') { return "main instance (PID $($i.Pid))" }
    return "profile '$($i.Name)' (PID $($i.Pid))"
}

$script:LoginRestoreMain = $false
$script:LoginRestoreProfiles = @()

# Restart what the sign-in closed: the main instance and the other profiles.
function Invoke-LoginCleanup {
    if ($script:LoginRestoreMain -and -not @(Get-MainPid).Count) {
        Write-Info 'restarting the main instance'
        try { Start-Main } catch { Write-Warn $_.Exception.Message }
    }
    foreach ($n in $script:LoginRestoreProfiles) {
        if (-not (Get-ProfilePid $n)) {
            Write-Info "restarting profile '$n'"
            try { Start-Profile $n } catch { Write-Warn $_.Exception.Message }
        }
    }
    $script:LoginRestoreMain = $false
    $script:LoginRestoreProfiles = @()
}

# Close every instance except profile <name>, by PID. Remembers what to restart.
function Close-OtherInstance([string]$Name) {
    foreach ($i in @(Get-OtherInstance $Name)) {
        if ($i.Kind -eq 'main') { $script:LoginRestoreMain = $true; Stop-InstancePid $i.Pid 'main instance' 'main' }
        elseif ($i.Kind -eq 'profile') {
            if ($script:LoginRestoreProfiles -notcontains $i.Name) { $script:LoginRestoreProfiles += $i.Name }
            Stop-InstancePid $i.Pid "profile '$($i.Name)'" "profile:$($i.Name)"
        }
    }
}

function Invoke-Login([string]$Name, [int]$Timeout) {
    Assert-App
    Assert-Profile $Name
    if ((Get-SignedIn $Name) -eq 'yes') { Write-Ok "profile '$Name' is already signed in"; return }
    $others = @(Get-OtherInstance $Name)
    $foreign = @($others | Where-Object { $_.Kind -eq 'foreign' })
    if ($foreign.Count) {
        Exit-Twindesk $script:EXIT_ERROR "a Claude instance not managed by twindesk is running with its own --user-data-dir (PID $($foreign[0].Pid)). Close it yourself, then retry."
    }
    Write-Say 'A sign-in link (claude://) reaches only one running Claude instance, usually not'
    Write-Say "the one signing in, so every other instance is closed while profile '$Name' signs in."
    $list = ($others | ForEach-Object { Format-Instance $_ }) -join ', '
    if ($list) {
        Write-Say "To close: $list."
        Write-Warn 'closing an instance interrupts any Claude Code or Cowork session running in it.'
        if (-not (Confirm-Action 'Close them now? They are restarted at the end.')) { Exit-Twindesk $script:EXIT_ERROR 'cancelled' }
    }
    if ($script:DryRun) {
        if ($list) { Write-Dry "would close: $list" }
        Write-Dry "would start profile '$Name', wait up to $($Timeout)s for sign-in, then restart what was closed"
        return
    }
    $completed = $false
    $restoreMain = $false; $restoreProfiles = @()
    try {
        Close-OtherInstance $Name
        $p = Get-ProfilePid $Name
        if (-not $p) {
            Start-Profile $Name
            $p = Wait-ForPid { Get-ProfilePid $Name } 30
            if (-not $p) { Exit-Twindesk $script:EXIT_TIMEOUT "profile '$Name' did not start within 30s" }
        }
        else { [void](Set-ForegroundPid $p) }
        Write-Ok "profile '$Name' is running (PID $p)"
        Write-Say ''
        Write-Say "In the window of profile '$($Name)':"
        Write-Say '  1. Sign in (email link or Google).'
        Write-Say '  2. When the browser asks to open Claude, accept.'
        Write-Say "Waiting up to $($Timeout)s. Press Ctrl+C to cancel (closed instances are restarted)."
        $elapsed = 0
        while ($true) {
            if ((Get-SignedIn $Name) -eq 'yes') { break }
            $again = @(Get-OtherInstance $Name)
            if ($again.Count) {
                if (@($again | Where-Object { $_.Kind -eq 'foreign' }).Count) {
                    Exit-Twindesk $script:EXIT_ERROR 'a Claude instance not managed by twindesk started during sign-in. Close it yourself, then retry.'
                }
                Write-Warn "another Claude instance started during sign-in ($(($again | ForEach-Object { $_.Pid }) -join ' ')), closing it again."
                Close-OtherInstance $Name
                Write-Warn "if you already clicked the link, it went to the wrong instance: click 'Open Claude' in the browser again now."
            }
            if (-not (Get-ProfilePid $Name)) { Exit-Twindesk $script:EXIT_ERROR "profile '$Name' was closed before signing in" }
            if ($elapsed -ge $Timeout) { Exit-Twindesk $script:EXIT_TIMEOUT "not signed in after $($Timeout)s" }
            Start-Sleep -Seconds 2; $elapsed += 2
        }
        $completed = $true
        Write-Ok "profile '$Name' is signed in"
    }
    finally {
        # Runs on success, error and Ctrl+C alike.
        $restoreMain = $script:LoginRestoreMain
        $restoreProfiles = @($script:LoginRestoreProfiles)
        Invoke-LoginCleanup
        if ($completed) {
            if ($restoreMain) {
                $m = Wait-ForPid { Get-MainPid } 30
                if ($m) { Write-Ok "main instance running again (PID $m)" } else { Write-Warn 'main instance did not come back within 30s' }
            }
            else { Write-Say 'main instance left stopped (it was not running before)' }
            foreach ($n in $restoreProfiles) {
                $q = Wait-ForPid { Get-ProfilePid $n } 30
                if ($q) { Write-Ok "profile '$n' running again (PID $q)" } else { Write-Warn "profile '$n' did not come back within 30s" }
            }
            $p = Get-ProfilePid $Name
            if ($p) { Write-Ok "profile '$Name' running (PID $p), signed in: $(Get-SignedIn $Name)" }
        }
    }
}

function Invoke-Status([string]$Name) {
    Assert-App
    if ($Name) { Assert-Profile $Name }
    $mains = @(Get-MainPid)
    $handler = Get-UrlHandler
    $ver = Get-AppVersion
    $tested = Get-TestedVersion
    if ($script:Json) {
        $head = '{{"version":{0},"os":{1},"os_status":{2},"app":{3},"app_version":{4},"tested_version":{5},"main_pids":[{6}],"claude_url_handler":{7},"root":{8},"profiles":' -f
        (ConvertTo-JsonString $script:Version), (ConvertTo-JsonString $script:OS), (ConvertTo-JsonString (Get-OsStatus)),
        (ConvertTo-JsonString $script:App), (ConvertTo-JsonString "$ver"), (ConvertTo-JsonString $tested), ($mains -join ','),
        (ConvertTo-JsonString $handler), (ConvertTo-JsonString $script:Root)
        if ($Name) {
            $p = Get-ProfilePid $Name
            Write-Say ($head + ('[{{"name":{0},"pid":{1},"signed_in":{2}}}]}}' -f (ConvertTo-JsonString $Name), (ConvertTo-JsonNum $p), (ConvertTo-JsonBool (Get-SignedIn $Name))))
        }
        else { Write-Say ($head + (Get-ListJson) + '}') }
        return
    }
    Write-Say "twindesk $($script:Version) on $($script:OS) ($(Get-OsStatus))"
    Write-Say "app:              $($script:App)$(if ($ver) { " (version $ver)" })"
    Write-Say "main instance:    $(if ($mains.Count) { $mains -join ' ' } else { 'not running' })"
    Write-Say "claude:// opens:  $(if ($handler) { $handler } else { 'unknown' })"
    Write-Say "data root:        $($script:Root)"
    if ($Name) {
        $p = Get-ProfilePid $Name
        Write-Say "profile $($Name):    $(if ($p) { "running (PID $p)" } else { 'stopped' }), signed in: $(Get-SignedIn $Name)"
    }
    else { Write-Say ''; Invoke-List }
}

function Find-Cli {
    if ($env:TWINDESK_CLAUDE_CLI) { return $env:TWINDESK_CLAUDE_CLI }
    $c = Get-Command claude -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    return $null
}

function Invoke-Cli([string]$Name, [string[]]$Rest) {
    Assert-Name $Name
    Test-Root
    $cli = Find-Cli
    if (-not $cli) { Exit-Twindesk $script:EXIT_NO_APP "Claude Code CLI ('claude') not found in PATH" }
    $dir = Get-CliProfileDir $Name
    if ($script:DryRun) { Write-Dry "would run: CLAUDE_CONFIG_DIR=$dir $cli $($Rest -join ' ')"; return }
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Write-Info "CLI profile '$Name' created: $dir"
    }
    $old = $env:CLAUDE_CONFIG_DIR
    $env:CLAUDE_CONFIG_DIR = $dir
    try { & $cli @Rest; $script:ExitCode = $LASTEXITCODE }
    finally { $env:CLAUDE_CONFIG_DIR = $old }
}

function Invoke-Alias([string]$Name) {
    Assert-Name $Name
    $d = (Get-CliProfileDir $Name).Replace("'", "''")
    Write-Say '# Add to your PowerShell profile (twindesk never edits it):'
    Write-Say "function claude-$Name { `$o = `$env:CLAUDE_CONFIG_DIR; `$env:CLAUDE_CONFIG_DIR = '$d'; try { claude @args } finally { `$env:CLAUDE_CONFIG_DIR = `$o } }"
    Write-Say "function claude-desktop-$Name { twindesk open $Name }"
}

function Invoke-Remove([string]$Name, [bool]$All) {
    Assert-Name $Name
    Test-Root
    $dir = Get-ProfileDir $Name; $clidir = Get-CliProfileDir $Name
    if (-not (Test-Path -LiteralPath $dir) -and -not (Test-Path -LiteralPath $clidir)) { Exit-Twindesk $script:EXIT_NO_PROFILE "profile '$Name' not found" }
    if ($All) { $script:AssumeYes = $true }
    if (Test-Path -LiteralPath $dir) {
        if (-not (Confirm-Action "Delete Desktop profile '$Name' ($dir) and its shortcut? Its sign-in and local sessions are lost.")) { Exit-Twindesk $script:EXIT_ERROR 'cancelled' }
        if (Find-App) {
            $p = Get-ProfilePid $Name
            if ($p) { Stop-InstancePid $p "profile '$Name'" "profile:$Name" }
            if ($script:OS -eq 'windows') { Remove-ProfileShortcut $Name }
        }
        Remove-SafeDir $dir 'profiles' $Name
        if (-not $script:DryRun) { Write-Ok "Desktop profile '$Name' deleted" }
    }
    if (Test-Path -LiteralPath $clidir) {
        if (Confirm-Action "Also delete CLI profile '$Name' ($clidir)?") {
            # Sign out first so the CLI removes its own stored credential; twindesk never touches the credential store itself.
            $cli = Find-Cli
            if ($cli) {
                if ($script:DryRun) { Write-Dry "would run: CLAUDE_CONFIG_DIR=$clidir $cli auth logout" }
                else {
                    $old = $env:CLAUDE_CONFIG_DIR; $env:CLAUDE_CONFIG_DIR = $clidir
                    try { & $cli auth logout *> $null } catch { Write-Warn 'CLI sign-out failed; its stored credential may remain' }
                    finally { $env:CLAUDE_CONFIG_DIR = $old }
                }
            }
            else { Write-Warn 'Claude Code CLI not found: its stored credential for this profile may remain' }
            Remove-SafeDir $clidir 'cli' $Name
            if (-not $script:DryRun) { Write-Ok "CLI profile '$Name' deleted" }
        }
        else { Write-Say "CLI profile kept: $clidir" }
    }
}

function Invoke-Doctor {
    $problems = 0
    Write-Say "twindesk $($script:Version)"
    if ($script:OS -eq 'windows') { Write-Warn "OS: Windows $([System.Environment]::OSVersion.Version) - experimental, untested" }
    else { Write-Warn "OS: $($script:OS) - use the Bash version of twindesk here" }
    if (Find-App) {
        Write-Ok "app: $($script:App)"
        $ver = Get-AppVersion; $tested = Get-TestedVersion
        if (-not $ver) { Write-Warn 'app version: unknown' }
        elseif (-not $tested) { Write-Warn "app version $($ver): untested on this OS" }
        else {
            switch (Compare-Version $ver $tested) {
                0 { Write-Ok "app version $ver (tested)" }
                1 { Write-Warn "app version $($ver): untested version (newer than tested $tested). If something breaks, report it." }
                default { Write-Warn "app version $($ver): older than tested $tested. Fix: update Claude Desktop." }
            }
        }
        if ($tested) { Write-Ok "--user-data-dir: verified on $($script:OS) with $tested" } else { Write-Warn "--user-data-dir: experimental - untested on $($script:OS)" }
        $mains = @(Get-MainPid)
        if ($mains.Count) { Write-Ok "main instance running: PID $($mains -join ' ')" } else { Write-Say '   main instance: not running' }
        foreach ($n in Get-ProfileName) {
            if (-not (Test-HasDesktop $n)) { continue }
            $all = @(Get-ProfilePidAll $n)
            if ($all.Count -gt 1) {
                Write-Err "profile $n runs in several instances ($($all -join ' ')). Fix: quit the extra ones; two instances on one profile can corrupt it."
                $problems++
            }
            $p = Get-ProfilePid $n
            Write-Say "   profile $($n): $(if ($p) { "running (PID $p)" } else { 'stopped' }), signed in: $(Get-SignedIn $n)"
        }
    }
    else {
        Write-Err 'app: Claude Desktop not found. Fix: install it (per-user installer), or set TWINDESK_APP to claude.exe. The Microsoft Store (MSIX) version is not supported.'
        $problems++
    }
    $h = Get-UrlHandler
    if ($h) { Write-Ok "claude:// handler: $h (a sign-in link reaches only one running instance: use 'twindesk login')" } else { Write-Warn 'claude:// handler: unknown' }
    if (Get-Command sqlite3 -ErrorAction SilentlyContinue) { Write-Ok 'sqlite3 found (sign-in detection)' }
    else { Write-Warn "sqlite3 not found: sign-in state shows 'unknown'. Fix: install sqlite3 and add it to PATH." }
    try {
        New-Item -ItemType Directory -Force -Path $script:Root | Out-Null
        $probe = Join-Path $script:Root '.write-test'
        Set-Content -LiteralPath $probe -Value '' ; Remove-Item -LiteralPath $probe -Force
        Write-Ok "data root writable: $($script:Root)"
    }
    catch { Write-Err "data root not writable: $($script:Root). Fix: check permissions or set TWINDESK_HOME."; $problems++ }
    $cli = Find-Cli
    if ($cli) { Write-Ok "Claude Code CLI: $cli" } else { Write-Say "   Claude Code CLI: not found ('twindesk cli' unavailable)" }
    if ($problems -gt 0) { Write-Err "$problems problem(s) found"; $script:ExitCode = $script:EXIT_ERROR; return }
    Write-Ok 'no problems found'
}

function Show-Usage {
    @"
twindesk $($script:Version) - run several Claude Desktop accounts side by side

Usage: twindesk <command> [options]

Commands:
  add <profile>              create a profile
  list [--json]              list profiles: running, PID, signed in, size
  open <profile>             start a profile, or bring it to the front
  login <profile>            guided sign-in (closes other instances meanwhile)
                             [--timeout <seconds>] (default 300)
  status [profile] [--json]  diagnostic
  shortcut <profile>         create a launcher for the profile
  cli <profile> [args...]    run Claude Code CLI with the profile's own config
  alias <profile>            print shell aliases to copy (nothing is written)
  remove <profile> [--all]   stop and delete a profile and its shortcut
  doctor                     check the setup
  help                       show this help

Options:
  --dry-run   show what would change, change nothing
  --yes, -y   answer yes to confirmations
  --version   print version

Profile names: 1-32 chars, a-z 0-9 and '-'; 'default' and 'main' are reserved.
Exit codes: 0 ok, 1 error, 2 usage, 3 app not found, 4 profile not found,
            5 timeout, 130 interrupted.
Not affiliated with Anthropic.
"@
}

function Invoke-Main([string[]]$Argv) {
    if (-not $Argv -or $Argv.Count -eq 0) { Write-Say (Show-Usage); $script:ExitCode = $script:EXIT_USAGE; return }
    $cmd = $Argv[0]
    $rest = @($Argv | Select-Object -Skip 1)
    switch -CaseSensitive ($cmd) {
        { $_ -in '-h', '--help', 'help' } { Write-Say (Show-Usage); return }
        { $_ -in '--version', '-V', 'version' } { Write-Say "twindesk $($script:Version)"; return }
    }
    if ($cmd -ceq 'cli') {
        # Everything after the profile name goes to Claude Code untouched.
        $i = 0
        while ($i -lt $rest.Count -and $rest[$i] -ceq '--dry-run') { $script:DryRun = $true; $i++ }
        if ($i -ge $rest.Count) { Exit-Twindesk $script:EXIT_USAGE 'usage: twindesk cli <profile> [args...]' }
        Invoke-Cli $rest[$i] @($rest | Select-Object -Skip ($i + 1))
        return
    }
    $pos = @(); $timeout = '300'; $all = $false
    for ($i = 0; $i -lt $rest.Count; $i++) {
        $a = $rest[$i]
        if ($a -ceq '--dry-run') { $script:DryRun = $true }
        elseif ($a -ceq '--yes' -or $a -ceq '-y') { $script:AssumeYes = $true }
        elseif ($a -ceq '--json') { $script:Json = $true }
        elseif ($a -ceq '--all') { $all = $true }
        elseif ($a -ceq '--timeout') {
            if ($i + 1 -ge $rest.Count) { Exit-Twindesk $script:EXIT_USAGE '--timeout needs a value' }
            $i++; $timeout = $rest[$i]
        }
        elseif ($a.StartsWith('--timeout=')) { $timeout = $a.Substring(10) }
        elseif ($a -ceq '--') { $pos += @($rest | Select-Object -Skip ($i + 1)); break }
        elseif ($a.StartsWith('-')) { Exit-Twindesk $script:EXIT_USAGE "unknown option: $a" }
        else { $pos += $a }
    }
    if ($timeout -notmatch '^\d+$') { Exit-Twindesk $script:EXIT_USAGE '--timeout must be a number of seconds' }
    if ($pos.Count -gt 1) { Exit-Twindesk $script:EXIT_USAGE 'too many arguments' }
    $name = if ($pos.Count) { $pos[0] } else { '' }
    if ($cmd -in 'add', 'open', 'login', 'shortcut', 'alias', 'remove' -and -not $name) { Exit-Twindesk $script:EXIT_USAGE "usage: twindesk $cmd <profile>" }
    if ($cmd -in 'list', 'doctor' -and $name) { Exit-Twindesk $script:EXIT_USAGE "twindesk $cmd takes no profile" }
    switch -CaseSensitive ($cmd) {
        'add' { Invoke-Add $name }
        'list' { Invoke-List }
        'open' { Invoke-Open $name }
        'login' { Invoke-Login $name ([int]$timeout) }
        'status' { Invoke-Status $name }
        'shortcut' { Assert-App; Assert-Profile $name; New-ProfileShortcut $name }
        'alias' { Invoke-Alias $name }
        'remove' { Invoke-Remove $name $all }
        'doctor' { Invoke-Doctor }
        default { Write-Err "unknown command: $cmd"; [Console]::Error.WriteLine((Show-Usage)); $script:ExitCode = $script:EXIT_USAGE }
    }
}

if ($env:TWINDESK_SOURCE_ONLY -ne '1') {
    try { Invoke-Main $args }
    catch [System.Management.Automation.PipelineStoppedException] { $script:ExitCode = $script:EXIT_INTERRUPTED }
    catch {
        if ($_.Exception.Data.Contains('TwindeskExitCode')) {
            Write-Err $_.Exception.Message
            $script:ExitCode = [int]$_.Exception.Data['TwindeskExitCode']
        }
        else { Write-Err $_.Exception.Message; $script:ExitCode = $script:EXIT_ERROR }
    }
    exit $script:ExitCode
}
