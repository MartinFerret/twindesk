# Install or uninstall twindesk for the current user (Windows). No admin rights.
#
#   .\install.ps1                              install to %LOCALAPPDATA%\twindesk\bin
#   .\install.ps1 -Uninstall                   remove the command, ask about profiles
#   .\install.ps1 -Uninstall -KeepProfiles | -Purge
#
# Run it from a clone of the repository; there is no download-and-run installer.

[CmdletBinding()]
param(
    [switch]$Uninstall,
    [switch]$KeepProfiles,
    [switch]$Purge
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$base = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $HOME 'AppData/Local' }
$binDir = if ($env:TWINDESK_BIN_DIR) { $env:TWINDESK_BIN_DIR } else { Join-Path $base 'twindesk/bin' }
$ps1 = Join-Path $binDir 'twindesk.ps1'
$cmd = Join-Path $binDir 'twindesk.cmd'
$marker = '# twindesk - run several Claude Desktop accounts side by side (Windows).'

function Test-TwindeskFile([string]$Path) {
    return (Test-Path -LiteralPath $Path) -and ((Get-Content -LiteralPath $Path -TotalCount 1) -eq $marker)
}

function Install-Twindesk {
    $src = Join-Path $PSScriptRoot 'twindesk.ps1'
    if (-not (Test-Path -LiteralPath $src)) { throw 'run this from the twindesk repository' }
    if ((Test-Path -LiteralPath $ps1) -and -not (Test-TwindeskFile $ps1)) { throw "$ps1 exists and is not twindesk" }
    New-Item -ItemType Directory -Force -Path $binDir | Out-Null
    Copy-Item -LiteralPath $src -Destination $ps1 -Force
    # Bypass applies to this one process only; the system execution policy is not changed.
    Set-Content -LiteralPath $cmd -Encoding ASCII -Value "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0twindesk.ps1`" %*`r`nexit /b %ERRORLEVEL%"
    Write-Output "ok installed $ps1"
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not (($userPath -split ';') -contains $binDir)) {
        Write-Output ''
        Write-Output "$binDir is not in your PATH. To add it (not done for you), run:"
        Write-Output "  [Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path','User') + ';$binDir', 'User')"
    }
    Write-Output ''
    Write-Output 'Next: twindesk doctor'
}

function Uninstall-Twindesk([bool]$KeepAll, [bool]$PurgeAll) {
    if ((Test-Path -LiteralPath $ps1) -and -not (Test-TwindeskFile $ps1)) { throw "$ps1 is not twindesk, not touching it" }
    $mode = if ($PurgeAll) { 'purge' } elseif ($KeepAll) { 'keep' } else { 'ask' }
    $names = @()
    if (Test-Path -LiteralPath $ps1) {
        $json = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ps1 list --json 2>$null
        $names = @([regex]::Matches("$json", '"name":"([a-z0-9-]+)"') | ForEach-Object { $_.Groups[1].Value })
    }
    if ($mode -eq 'ask') {
        $mode = 'keep'
        if ($names.Count -gt 0) {
            $a = Read-Host "Profiles found: $($names -join ' '). Delete them too (sign-ins and local sessions are lost)? [y/N]"
            if ($a -match '^(y|yes)$') { $mode = 'purge' }
        }
    }
    if ($mode -eq 'purge') {
        # 'remove --all' deletes Desktop and CLI parts with its own guards.
        foreach ($n in $names) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ps1 remove $n --yes --all }
    }
    foreach ($f in @($ps1, $cmd)) {
        if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force; Write-Output "ok removed $f" }
    }
    if ((Test-Path -LiteralPath $binDir) -and -not (Get-ChildItem -LiteralPath $binDir -Force)) { Remove-Item -LiteralPath $binDir -Force }
    if ($mode -eq 'keep') { Write-Output 'Profiles kept. Reinstall twindesk to use them again.' }
}

if ($Uninstall) { Uninstall-Twindesk -KeepAll $KeepProfiles.IsPresent -PurgeAll $Purge.IsPresent } else { Install-Twindesk }
