# Pester 5 tests for twindesk.ps1. Run with: Invoke-Pester test/
# Everything runs in a temporary folder with fixtures: no real app, profile
# or credential store is used.

BeforeAll {
    $script:Ps1 = Join-Path $PSScriptRoot '../twindesk.ps1'
    $script:Pwsh = (Get-Process -Id $PID).Path

    function Invoke-Td {
        param([string[]]$Arguments, [string]$StdIn = '')
        # Piped stdin: the script sees a non-interactive session, as in CI.
        $out = $StdIn | & $script:Pwsh -NoProfile -NonInteractive -File $script:Ps1 @Arguments 2>&1
        [pscustomobject]@{ Code = $LASTEXITCODE; Out = (($out | ForEach-Object { "$_" }) -join "`n") }
    }

    # Dot-source this block inside a test to load the script's functions there,
    # after the test's environment is set.
    $script:LoadTd = {
        $env:TWINDESK_SOURCE_ONLY = '1'
        . $script:Ps1
        $env:TWINDESK_SOURCE_ONLY = $null
    }
}

Describe 'twindesk' {
    BeforeEach {
        $script:Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("td-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:Tmp | Out-Null
        $env:TWINDESK_HOME = Join-Path $script:Tmp 'local/twindesk'
        $env:LOCALAPPDATA = Join-Path $script:Tmp 'local'
        $env:APPDATA = Join-Path $script:Tmp 'roaming'
        $env:NO_COLOR = '1'
        $env:TWINDESK_OS = 'windows'
        $env:TWINDESK_PS_FIXTURE = $null
        $env:TWINDESK_CLAUDE_CLI = $null
        $script:FakeApp = Join-Path $script:Tmp 'local/AnthropicClaude/claude.exe'
        New-Item -ItemType Directory -Force -Path (Split-Path $script:FakeApp) | Out-Null
        Set-Content -LiteralPath $script:FakeApp -Value 'fake'
        $env:TWINDESK_APP = $script:FakeApp
        # No real process list: an empty fixture unless a test writes one.
        $env:TWINDESK_PS_FIXTURE = Join-Path $script:Tmp 'ps.txt'
        Set-Content -LiteralPath $env:TWINDESK_PS_FIXTURE -Value ''
    }

    AfterEach {
        Remove-Item -LiteralPath $script:Tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    Describe 'profile names' {
        It 'accepts valid names' {
            . $script:LoadTd
            foreach ($n in @('a', 'work', 'perso-2', '0abc', ('a' * 32))) { Test-NameOk $n | Should -BeTrue }
        }
        It 'rejects invalid names with exit 2' {
            foreach ($n in @('Work', '-lead', 'a b', 'a/b', '..', 'a_b', [string][char]0xE9, 'a.b', ('a' * 33), "a`n")) {
                (Invoke-Td @('add', $n)).Code | Should -Be 2
            }
        }
        It 'rejects reserved names' {
            foreach ($n in @('default', 'main')) {
                $r = Invoke-Td @('add', $n)
                $r.Code | Should -Be 2
                $r.Out | Should -Match 'reserved'
            }
        }
    }

    Describe 'JSON and versions' {
        It 'escapes quotes, backslashes and control characters' {
            . $script:LoadTd
            ConvertTo-JsonString 'a"b\c' | Should -Be '"a\"b\\c"'
            ConvertTo-JsonString "x`ty" | Should -Be '"x\ty"'
            ConvertTo-JsonString "l1`nl2" | Should -Be '"l1\nl2"'
            ConvertTo-JsonString "a$([char]1)b" | Should -Be '"a\u0001b"'
        }
        It 'compares dotted versions numerically' {
            . $script:LoadTd
            Compare-Version '3.6556.2' '3.6556.2' | Should -Be 0
            Compare-Version '3.6556.10' '3.6556.2' | Should -Be 1
            Compare-Version '2.99' '3.0' | Should -Be -1
            Compare-Version '1.0' '1' | Should -Be 0
        }
    }

    Describe 'process classification (by command line, never by name)' {
        BeforeEach {
            $base = Join-Path $script:Tmp 'local/AnthropicClaude'
            $exe = Join-Path $base 'app-1.2.3/claude.exe'
            $prof = Join-Path $env:TWINDESK_HOME 'profiles'
            # Squirrel layout: Update.exe next to the stub.
            Set-Content -LiteralPath (Join-Path $base 'Update.exe') -Value 'fake'
            $lines = @(
                "101`t$exe`t`"$exe`"",
                "202`t$exe`t`"$exe`" `"--user-data-dir=$prof/ab`"",
                "303`t$exe`t`"$exe`" `"--user-data-dir=$prof/a`"",
                "404`t$exe`t`"$exe`" --type=renderer `"--user-data-dir=$prof/a`"",
                "505`t$($script:FakeApp)`t`"$($script:FakeApp)`" `"--user-data-dir=$prof/a`"",
                "606`tC:/other/claude.exe`t`"C:/other/claude.exe`""
            )
            Set-Content -LiteralPath $env:TWINDESK_PS_FIXTURE -Value $lines
        }
        It 'finds the exact profile folder only, no prefix confusion' {
            . $script:LoadTd
            [void](Find-App)
            Get-ProfilePid 'a' | Should -Be 303
            Get-ProfilePid 'ab' | Should -Be 202
            Get-ProfilePid 'abc' | Should -BeNullOrEmpty
        }
        It 'finds the main instance and ignores helpers, the stub and other apps' {
            . $script:LoadTd
            [void](Find-App)
            @(Get-MainPid) | Should -Be @(101)
        }
        It 'splits Windows command lines like CommandLineToArgvW' {
            . $script:LoadTd
            $a = Split-CommandLine '"C:\Program Files\x.exe" "--user-data-dir=C:\a b\c" -x "q\"uote" back\\slash'
            $a.Count | Should -Be 5
            $a[1] | Should -Be '--user-data-dir=C:\a b\c'
            $a[3] | Should -Be 'q"uote'
            $a[4] | Should -Be 'back\\slash'
        }
    }

    Describe 'data root and deletion guards' {
        It 'requires the root to be named twindesk' {
            $env:TWINDESK_HOME = Join-Path $script:Tmp 'elsewhere'
            (Invoke-Td @('add', 'work')).Code | Should -Be 2
            Test-Path (Join-Path $script:Tmp 'elsewhere/profiles/work') | Should -BeFalse
        }
        It 'refuses a root inside the main Claude data folder' {
            $env:TWINDESK_HOME = Join-Path $env:APPDATA 'Claude/twindesk'
            $r = Invoke-Td @('add', 'work')
            $r.Code | Should -Be 2
            $r.Out | Should -Match 'main Claude data folder'
        }
        It 'refuses to delete a path outside <root>/<kind>/<name>' {
            . $script:LoadTd
            $other = Join-Path $script:Tmp 'other'
            New-Item -ItemType Directory -Path $other | Out-Null
            { Remove-SafeDir $other 'profiles' 'work' } | Should -Throw
            Test-Path $other | Should -BeTrue
        }
        It 'refuses to delete a linked profile folder' {
            . $script:LoadTd
            $precious = Join-Path $script:Tmp 'precious'
            New-Item -ItemType Directory -Path $precious | Out-Null
            Set-Content -LiteralPath (Join-Path $precious 'keep') -Value 'x'
            New-Item -ItemType Directory -Force -Path (Join-Path $env:TWINDESK_HOME 'profiles') | Out-Null
            $link = Join-Path $env:TWINDESK_HOME 'profiles/work'
            try { New-Item -ItemType SymbolicLink -Path $link -Target $precious -ErrorAction Stop | Out-Null }
            catch { Set-ItResult -Skipped -Because 'creating symbolic links is not allowed here'; return }
            { Remove-SafeDir $link 'profiles' 'work' } | Should -Throw
            Test-Path (Join-Path $precious 'keep') | Should -BeTrue
        }
        It 'remove without --yes in a non-interactive shell refuses (exit 2)' {
            (Invoke-Td @('add', 'work')).Code | Should -Be 0
            (Invoke-Td @('remove', 'work') -StdIn '').Code | Should -Be 2
            Test-Path (Join-Path $env:TWINDESK_HOME 'profiles/work') | Should -BeTrue
        }
        It 'remove --yes deletes only the profile' {
            Invoke-Td @('add', 'work') | Out-Null
            New-Item -ItemType Directory -Force -Path (Join-Path $env:TWINDESK_HOME 'profiles/keep') | Out-Null
            (Invoke-Td @('remove', 'work', '--yes')).Code | Should -Be 0
            Test-Path (Join-Path $env:TWINDESK_HOME 'profiles/work') | Should -BeFalse
            Test-Path (Join-Path $env:TWINDESK_HOME 'profiles/keep') | Should -BeTrue
        }
        It 'remove of an unknown profile exits 4' {
            (Invoke-Td @('remove', 'ghost', '--yes')).Code | Should -Be 4
        }
    }

    Describe 'dry-run' {
        It 'changes nothing for add, open, login and remove' {
            (Invoke-Td @('add', 'work', '--dry-run')).Code | Should -Be 0
            Test-Path (Join-Path $env:TWINDESK_HOME 'profiles/work') | Should -BeFalse
            New-Item -ItemType Directory -Force -Path (Join-Path $env:TWINDESK_HOME 'profiles/work') | Out-Null
            (Invoke-Td @('open', 'work', '--dry-run')).Code | Should -Be 0
            (Invoke-Td @('login', 'work', '--dry-run')).Code | Should -Be 0
            (Invoke-Td @('remove', 'work', '--dry-run', '--all')).Code | Should -Be 0
            Test-Path (Join-Path $env:TWINDESK_HOME 'profiles/work') | Should -BeTrue
        }
    }

    Describe 'sign-in detection' {
        BeforeAll { $script:HasSqlite = [bool](Get-Command sqlite3 -ErrorAction SilentlyContinue) }
        It 'reads only the presence of a valid sessionKey row' {
            if (-not $script:HasSqlite) { Set-ItResult -Skipped -Because 'sqlite3 not installed'; return }
            Invoke-Td @('add', 'work') | Out-Null
            $db = Join-Path $env:TWINDESK_HOME 'profiles/work/Cookies'
            $future = ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 11644473600 + 3600) * 1000000
            & sqlite3 $db "create table cookies(host_key text, name text, value text, expires_utc integer); insert into cookies values('.claude.ai','sessionKey','SECRET-TOKEN-VALUE',$future);"
            $r = Invoke-Td @('list', '--json')
            $r.Code | Should -Be 0
            $r.Out | Should -Match '"signed_in":true'
            $r.Out | Should -Not -Match 'SECRET'
            & sqlite3 $db "update cookies set expires_utc=1;"
            (Invoke-Td @('list', '--json')).Out | Should -Match '"signed_in":false'
        }
        It 'reports no cookie store as not signed in' {
            Invoke-Td @('add', 'work') | Out-Null
            (Invoke-Td @('list', '--json')).Out | Should -Match '"signed_in":false'
        }
    }

    Describe 'alias and cli' {
        It 'alias only prints, writes nothing' {
            $r = Invoke-Td @('alias', 'work')
            $r.Code | Should -Be 0
            $r.Out | Should -Match 'CLAUDE_CONFIG_DIR'
            Test-Path (Join-Path $env:TWINDESK_HOME 'cli/work') | Should -BeFalse
        }
        It 'cli passes CLAUDE_CONFIG_DIR and arguments, and its exit code' {
            $fake = Join-Path $script:Tmp 'fake-claude.ps1'
            Set-Content -LiteralPath $fake -Value 'Write-Output "dir=$env:CLAUDE_CONFIG_DIR args=$($args -join ''|'')"; exit 7'
            $env:TWINDESK_CLAUDE_CLI = $fake
            $r = Invoke-Td @('cli', 'work', '--version', '-p', 'hi there')
            $r.Code | Should -Be 7
            $r.Out | Should -Match ([regex]::Escape("dir=$(Join-Path $env:TWINDESK_HOME 'cli/work') args=--version|-p|hi there"))
        }
        It 'remove --all signs the CLI profile out, then deletes it' {
            Invoke-Td @('add', 'work') | Out-Null
            New-Item -ItemType Directory -Force -Path (Join-Path $env:TWINDESK_HOME 'cli/work') | Out-Null
            $log = Join-Path $script:Tmp 'cli.log'
            $fake = Join-Path $script:Tmp 'fake-claude.ps1'
            Set-Content -LiteralPath $fake -Value "Add-Content -LiteralPath '$log' -Value (`"`$env:CLAUDE_CONFIG_DIR `" + (`$args -join ' '))"
            $env:TWINDESK_CLAUDE_CLI = $fake
            (Invoke-Td @('remove', 'work', '--all')).Code | Should -Be 0
            Test-Path (Join-Path $env:TWINDESK_HOME 'cli/work') | Should -BeFalse
            Get-Content -LiteralPath $log | Should -Match 'auth logout'
        }
    }

    Describe 'list' {
        It 'shows CLI-only profiles and works without the app' {
            Invoke-Td @('add', 'work') | Out-Null
            New-Item -ItemType Directory -Force -Path (Join-Path $env:TWINDESK_HOME 'cli/scripts') | Out-Null
            $env:TWINDESK_APP = Join-Path $script:Tmp 'nope.exe'
            $r = Invoke-Td @('list', '--json')
            $r.Code | Should -Be 0
            $r.Out | Should -Match '"name":"scripts","desktop_profile":false'
            $r.Out | Should -Match '"name":"work","desktop_profile":true'
        }
    }

    Describe 'usage and misc' {
        It 'missing app exits 3' {
            $env:TWINDESK_APP = Join-Path $script:Tmp 'nope.exe'
            Invoke-Td @('add', 'work') | Out-Null
            (Invoke-Td @('open', 'work')).Code | Should -Be 3
        }
        It 'usage errors exit 2' {
            (Invoke-Td @()).Code | Should -Be 2
            (Invoke-Td @('frobnicate')).Code | Should -Be 2
            (Invoke-Td @('add')).Code | Should -Be 2
            (Invoke-Td @('login', 'work', '--timeout', 'abc')).Code | Should -Be 2
        }
        It '--version and help exit 0' {
            $r = Invoke-Td @('--version')
            $r.Code | Should -Be 0
            $r.Out | Should -Match '^twindesk '
            (Invoke-Td @('help')).Out | Should -Match 'Not affiliated with Anthropic'
        }
        It 'prints no escape codes with NO_COLOR' {
            (Invoke-Td @('add', 'work')).Out | Should -Not -Match ([char]27)
        }
        It 'has the same commands and exit codes as the Bash version' {
            $bash = Get-Content -Raw (Join-Path $PSScriptRoot '../twindesk')
            $ps = Get-Content -Raw $script:Ps1
            $start = $bash.IndexOf('Usage: twindesk'); $end = $bash.IndexOf('Not affiliated with Anthropic.', $start)
            $usageBash = $bash.Substring($start, $end - $start)
            $s2 = $ps.IndexOf('Usage: twindesk'); $e2 = $ps.IndexOf('Not affiliated with Anthropic.', $s2)
            $ps.Substring($s2, $e2 - $s2).Replace("`r", '') | Should -Be $usageBash.Replace("`r", '')
        }
    }

    Describe 'Windows only' -Skip:($PSVersionTable.PSVersion.Major -ge 6 -and -not $IsWindows) {
        It 'shortcut creates a marked .lnk removed with the profile' {
            Invoke-Td @('add', 'work') | Out-Null
            (Invoke-Td @('shortcut', 'work')).Code | Should -Be 0
            $lnk = Join-Path $env:APPDATA 'Microsoft/Windows/Start Menu/Programs/Claude (work).lnk'
            Test-Path $lnk | Should -BeTrue
            (Invoke-Td @('remove', 'work', '--yes')).Code | Should -Be 0
            Test-Path $lnk | Should -BeFalse
        }
    }
}
