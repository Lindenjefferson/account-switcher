. (Join-Path $PSScriptRoot '_fake-accounts.ps1')
$realProfile = $env:USERPROFILE
$realConfig = $env:CLAUDE_CONFIG_DIR
$root = Join-Path ([IO.Path]::GetTempPath()) ("mc-sl-" + [guid]::NewGuid())
. New-FakeEnvironment $root @{ main = 'a'; accounts = @{ a = @{ email = 'a@x'; dir = '~/.claude' }; b = @{ email = 'b@x' } } }
$accts = (Get-Accounts).Accounts
$b = $accts | Where-Object Name -eq 'b'
$settings = Join-Path $root '.claude\settings.json'
$esc = [char]27
$dot = [char]0xB7
function Expected([string]$account, $five, $week) { $u = ('Session: {0}% {1} Week: {2}%' -f $five, $dot, $week); if ($account) { "$account $dot $u" } else { $u } }
function Remove-Ansi([string]$t) { $t -replace "$esc\[[0-9;]*m", '' }
function New-Input($five, $week) {
    [pscustomobject]@{ rate_limits = [pscustomobject]@{
        five_hour = [pscustomobject]@{ used_percentage = $five }; seven_day = [pscustomobject]@{ used_percentage = $week } } }
}

Describe 'Format-StatusLine' {
    It 'colors' {
        $t = Format-StatusLine (New-Input 50 85) $b 80
        $t | Should Match ([regex]::Escape("$esc[33m85%"))
        $t | Should Not Match ([regex]::Escape("$esc[") + '3[13]m50')
        (Format-StatusLine (New-Input 96 10) $b 80) | Should Match ([regex]::Escape("$esc[31m96%"))
        (Format-StatusLine (New-Input 50 10) $b 80) | Should Not Match ([regex]::Escape("$esc["))
    }

    It 'text' {
        Remove-Ansi (Format-StatusLine (New-Input 12 27) $b 80) | Should Be (Expected 'b' 12 27)
        Remove-Ansi (Format-StatusLine (New-Input 12.6 27) $b 80) | Should Be (Expected 'b' 13 27)
    }

    It 'without rate_limits' {
        Format-StatusLine ([pscustomobject]@{ model = 'x' }) $b 80 | Should Be 'b'
    }

    It 'time until reset (resets_at in Unix seconds)' {
        $now = Get-Date
        $sec = { param($d) [DateTimeOffset]::new($d).ToUnixTimeSeconds() }
        $in = [pscustomobject]@{ rate_limits = [pscustomobject]@{
            five_hour = [pscustomobject]@{ used_percentage = 85; resets_at = (& $sec $now.AddMinutes(125)) }
            seven_day = [pscustomobject]@{ used_percentage = 10; resets_at = (& $sec $now.AddHours(76)) } } }
        $t = Format-StatusLine $in $b 80 $now
        $t | Should Match ([regex]::Escape("$esc[33m85%$esc[0m (resets in 2h0"))
        Remove-Ansi $t | Should Match ([regex]::Escape("Week: 10% (resets in 3d 3h)") + '|' + [regex]::Escape("Week: 10% (resets in 3d 4h)"))
    }

    It 'without account' {
        Remove-Ansi (Format-StatusLine (New-Input 12 27) $null 80) | Should Be (Expected $null 12 27)
    }
}

Describe 'Get-CurrentAccount' {
    It 'current account' {
        $env:CLAUDE_CONFIG_DIR = $b.Dir
        (Get-CurrentAccount).Name | Should Be 'b'
        Remove-Item Env:CLAUDE_CONFIG_DIR
        (Get-CurrentAccount).Name | Should Be 'a'
    }
}

Describe 'statusline.ps1' {
    It 'script end to end' {
        $script = Join-Path $ScriptsDir 'statusline.ps1'
        $env:USERPROFILE = $root
        $env:CLAUDE_CONFIG_DIR = $b.Dir
        $before = [Console]::OutputEncoding
        [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false
        $out = '{"rate_limits":{"five_hour":{"used_percentage":85},"seven_day":{"used_percentage":10}}}' |
            powershell -NoProfile -ExecutionPolicy Bypass -File $script
        [Console]::OutputEncoding = $before
        Remove-Item Env:CLAUDE_CONFIG_DIR
        Remove-Ansi ($out -join '') | Should Be (Expected 'b' 85 10)
    }

    It 'invalid input does not break it' {
        $script = Join-Path $ScriptsDir 'statusline.ps1'
        $out = 'not json' | powershell -NoProfile -ExecutionPolicy Bypass -File $script 2>&1
        ($out -join '').Trim() | Should Be ''
    }
}

Describe 'Register-StatusLine / Unregister-StatusLine' {
    It 'register: inserts and is idempotent' {
        [IO.File]::WriteAllText($settings, '{"theme":"dark"}')
        $null = Register-StatusLine
        $s = Get-Content $settings -Raw | ConvertFrom-Json
        $s.statusLine.command | Should Match 'statusline\.ps1'
        $s.theme | Should Be 'dark'
        $before = Get-Content $settings -Raw
        Register-StatusLine | Should Be $null
        Get-Content $settings -Raw | Should Be $before
    }

    It 'register: respects another status line' {
        $other = '{"theme":"dark","statusLine":{"type":"command","command":"other.sh"}}'
        [IO.File]::WriteAllText($settings, $other)
        Register-StatusLine | Should Match 'another'
        Get-Content $settings -Raw | Should Be $other
    }

    It 'register and unregister: invalid JSON is not rewritten' {
        $broken = '{"theme":"dark",}'
        [IO.File]::WriteAllText($settings, $broken)
        Register-StatusLine | Should Match 'invalid'
        Get-Content $settings -Raw | Should Be $broken
        $broken2 = '{"statusLine":{"type":"command","command":"x/statusline.ps1"},}'
        [IO.File]::WriteAllText($settings, $broken2)
        Unregister-StatusLine | Should Match 'invalid'
        Get-Content $settings -Raw | Should Be $broken2
    }

    It 'unregister: removes only ours' {
        [IO.File]::WriteAllText($settings, '{"theme":"dark"}')
        $null = Register-StatusLine
        Unregister-StatusLine
        $s = Get-Content $settings -Raw | ConvertFrom-Json
        $s.statusLine | Should Be $null
        $s.theme | Should Be 'dark'
        # ours as the last key (comma before, not after)
        [IO.File]::WriteAllText($settings, '{"theme":"dark","statusLine":{"type":"command","command":"powershell -File C:/x/statusline.ps1"}}')
        Unregister-StatusLine
        (Get-Content $settings -Raw | ConvertFrom-Json).theme | Should Be 'dark'
        $other = '{"statusLine":{"type":"command","command":"other.sh"}}'
        [IO.File]::WriteAllText($settings, $other)
        Unregister-StatusLine
        Get-Content $settings -Raw | Should Be $other
    }
}

$env:USERPROFILE = $realProfile
if ($null -ne $realConfig) { $env:CLAUDE_CONFIG_DIR = $realConfig }
Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
