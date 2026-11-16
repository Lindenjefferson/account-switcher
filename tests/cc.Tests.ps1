. (Join-Path $PSScriptRoot '_fake-accounts.ps1')
$realProfile = $env:USERPROFILE
$root = Join-Path ([IO.Path]::GetTempPath()) ("mc-cc-" + [guid]::NewGuid())
. New-FakeEnvironment $root @{ main = 'a'; accounts = @{ a = @{ email = 'a@x' } } }

Describe 'Get-ClaudeArgs' {
    It 'appends the RC --settings' {
        $a = Get-ClaudeArgs ([pscustomobject]@{ On = $true; Rest = @('-p', 'hi'); UserSettings = $false })
        ($a -join ' ') | Should Be ('-p hi --settings ' + (Join-Path $root '.claude-accounts\rc\on.json'))
    }

    It 'off points to off.json' {
        $a = Get-ClaudeArgs ([pscustomobject]@{ On = $false; Rest = @(); UserSettings = $false })
        $a[-1] | Should Be (Join-Path $root '.claude-accounts\rc\off.json')
    }

    It 'does not duplicate the user --settings' {
        $a = Get-ClaudeArgs ([pscustomobject]@{ On = $false; Rest = @('--settings', 'mine.json'); UserSettings = $true })
        @($a | Where-Object { $_ -eq '--settings' }).Count | Should Be 1
        ($a -join ' ') | Should Be '--settings mine.json'
    }
}

$env:USERPROFILE = $realProfile
Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
