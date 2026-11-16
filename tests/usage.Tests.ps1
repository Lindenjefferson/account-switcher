. (Join-Path $PSScriptRoot '_fake-accounts.ps1')
$realProfile = $env:USERPROFILE
$root = Join-Path ([IO.Path]::GetTempPath()) ("mc-usage-" + [guid]::NewGuid())
. New-FakeEnvironment $root @{
    main = 'master'
    accounts = @{
        master  = @{ email = 'm@x'; dir = '~/.claude' }
        valid   = @{ email = 'v@x' }
        expired = @{ email = 'e@x' }
        nothing = @{ email = 's@x' }
        resetup = @{ email = 'r@x' }
    }
}

$now = Get-Date
function ConvertTo-Ms([datetime]$d) { [DateTimeOffset]::new($d).ToUnixTimeMilliseconds() }
function New-Util([int]$five, [int]$week, [datetime]$resetFive) {
    @{ five_hour = @{ utilization = $five; resets_at = ([DateTimeOffset]::new($resetFive)).ToString('o') }
       seven_day = @{ utilization = $week; resets_at = ([DateTimeOffset]::new($now.AddDays(3))).ToString('o') } }
}
function Set-FakeAccount([string]$name, $expires, $util) {
    $p = Join-Path $root ".claude-accounts\$name"
    New-Item -ItemType Directory -Force $p | Out-Null
    if ($expires) {
        $cred = @{ claudeAiOauth = @{ accessToken = 'fake-token'; expiresAt = (ConvertTo-Ms $expires) } }
        [IO.File]::WriteAllText((Join-Path $p '.credentials.json'), ($cred | ConvertTo-Json -Depth 5))
    }
    if ($util) {
        $state = @{ cachedUsageUtilization = @{ fetchedAtMs = (ConvertTo-Ms $now.AddMinutes(-30)); utilization = $util } }
        [IO.File]::WriteAllText((Join-Path $p '.claude.json'), ($state | ConvertTo-Json -Depth 10))
    }
}
Set-FakeAccount 'valid' $now.AddHours(1) (New-Util 2 27 $now.AddHours(2))
Set-FakeAccount 'expired' $now.AddHours(-1) (New-Util 2 27 $now.AddHours(2))
Set-FakeAccount 'resetup' $null (New-Util 90 30 $now.AddMinutes(-10))
$accts = (Get-Accounts).Accounts
function A([string]$n) { $accts | Where-Object Name -eq $n }

Describe 'Get-AccountUsage' {
    It 'uses the API when the token is valid' {
        Mock Invoke-UsageApi { [pscustomobject]@{ five_hour = @{ utilization = 12; resets_at = $null }; seven_day = @{ utilization = 40; resets_at = $null } } }
        $u = Get-AccountUsage (A 'valid') -now $now
        $u.Source | Should Be 'live'
        $u.Five | Should Be 12
        $u.Week | Should Be 40
    }

    It 'falls back to the saved value when the token is expired' {
        Mock Invoke-UsageApi { throw 'should not be called' }
        $u = Get-AccountUsage (A 'expired') -now $now
        $u.Source | Should Be 'saved'
        $u.Five | Should Be 2
        $u.Week | Should Be 27
        Assert-MockCalled Invoke-UsageApi -Times 0 -Scope It
    }

    It 'falls back to the saved value when the API fails' {
        Mock Invoke-UsageApi { throw '401' }
        (Get-AccountUsage (A 'valid') -now $now).Source | Should Be 'saved'
    }

    It 'account with no folder or login' {
        $u = Get-AccountUsage (A 'nothing') -now $now
        $u.Source | Should Be $null
        Format-Usage $u | Should Be '-'
    }

    It 'a window that reset becomes zero' {
        $u = Get-AccountUsage (A 'resetup') -now $now
        $u.Five | Should Be 0
        $u.ResetFive | Should Be $null
        $u.Week | Should Be 30
    }

    It 'master account reads ~/.claude.json' {
        Get-StateFile (A 'master') | Should Be (Join-Path $root '.claude.json')
        Get-StateFile (A 'valid') | Should Be (Join-Path $root '.claude-accounts\valid\.claude.json')
    }

    It 'token never appears' {
        Mock Invoke-UsageApi { throw '401' }
        $u = Get-AccountUsage (A 'valid') -now $now
        (Format-Usage $u) | Should Not Match 'fake-token'
        ($u | ConvertTo-Json -Depth 5) | Should Not Match 'fake-token'
    }
}

Describe 'Format-Usage, Get-MaxUsage, Select-SuggestedAccount' {
    $expected = 'Session: 2% (resets in 1h00) ' + [char]0xB7 + ' Week: 27% (resets in 3d 0h)'
    It 'format and max' {
        $u = ConvertTo-Usage (New-Util 2 27 $now.AddHours(1)) 'live' $null $now
        Format-Usage $u $now | Should Be $expected
        Get-MaxUsage $u | Should Be 27
    }

    It 'format of the saved value carries the time' {
        $q = $now.AddMinutes(-30)
        $u = ConvertTo-Usage (New-Util 2 27 $now.AddHours(1)) 'saved' $q $now
        Format-Usage $u $now | Should Be ($expected + (' (saved {0})' -f $q.ToString('HH:mm')))
    }

    It 'saved on another day carries the date' {
        $q = $now.AddDays(-3)
        $u = ConvertTo-Usage (New-Util 2 27 $now.AddHours(1)) 'saved' $q $now
        Format-Usage $u $now | Should Be ($expected + (' (saved {0})' -f $q.ToString('dd/MM HH:mm')))
    }

    It 'saved without fetchedAtMs does not invent 1970' {
        $p = Join-Path $root '.claude-accounts\nodate'
        New-Item -ItemType Directory -Force $p | Out-Null
        $state = @{ cachedUsageUtilization = @{ utilization = (New-Util 2 27 $now.AddHours(2)) } }
        [IO.File]::WriteAllText((Join-Path $p '.claude.json'), ($state | ConvertTo-Json -Depth 10))
        $c = [pscustomobject]@{ Name = 'nodate'; Dir = $p; Master = $false }
        $u = ConvertTo-Usage (New-Util 2 27 $now.AddHours(1)) 'saved' $null $now
        Format-Usage $u $now | Should Be ($expected + ' (saved, no date)')
        $u = Get-AccountUsage $c -now $now
        $u.Source | Should Be 'saved'
        $u.When | Should Be $null
    }

    It 'time until reset' {
        Format-Reset $now.AddMinutes(45) $now | Should Be ' (resets in 45min)'
        Format-Reset $now.AddMinutes(125) $now | Should Be ' (resets in 2h05)'
        Format-Reset $now.AddHours(76) $now | Should Be ' (resets in 3d 4h)'
        Format-Reset $now.AddMinutes(-1) $now | Should Be ''
        Format-Reset $null $now | Should Be ''
        $u = ConvertTo-Usage @{ five_hour = @{ utilization = 5; resets_at = $null } } 'live' $null $now
        Format-Usage $u $now | Should Be ('Session: 5% ' + [char]0xB7 + ' Week: ?')
    }

    It 'suggests the one with the lowest maximum' {
        $usages = @{
            a = ConvertTo-Usage (New-Util 90 10 $now.AddHours(1)) 'live' $null $now
            b = ConvertTo-Usage (New-Util 30 50 $now.AddHours(1)) 'live' $null $now
            c = ConvertTo-Usage $null $null $null $now
        }
        Select-SuggestedAccount $usages 'a' | Should Be 'b'
        Select-SuggestedAccount @{ c = $usages.c } 'a' | Should Be $null
    }
}

$env:USERPROFILE = $realProfile
Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
