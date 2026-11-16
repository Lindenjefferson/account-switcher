. (Join-Path $PSScriptRoot '_fake-accounts.ps1')
$realProfile = $env:USERPROFILE

# Writes the master folder CLAUDE.md and the template into the fake environment built by New-FakeEnvironment.
function Set-FakeClaudeMd([string]$root, [string]$text) {
    Copy-Item (Join-Path $ScriptsDir 'CLAUDE.template.md') (Join-Path $root '.claude-accounts')
    [IO.File]::WriteAllText((Join-Path $root '.claude\CLAUDE.md'), $text)
    Join-Path $root '.claude\CLAUDE.md'
}

Describe 'CLAUDE.md block' {
    AfterAll { $env:USERPROFILE = $realProfile }
    $stale = "# Mine`n`n<!-- account-switcher:begin -->`nstale-block`n<!-- account-switcher:end -->`n"

    It 'replaces the existing block with the new one, without duplicating or touching the rest' {
        $root = Join-Path $TestDrive 'm1'
        . New-FakeEnvironment $root @{ main = 'a'; accounts = @{ a = @{ email = 'a@x' } } }
        $md = Set-FakeClaudeMd $root ($stale + "`nend of user text`n")
        Update-ClaudeMd
        $t = Get-Content $md -Raw
        $t | Should Not Match 'stale-block'
        ([regex]::Matches($t, '<!-- account-switcher:begin -->')).Count | Should Be 1
        $t | Should Match '# Mine'
        $t | Should Match 'end of user text'
    }

    It 'removes the block' {
        $root = Join-Path $TestDrive 'm2'
        . New-FakeEnvironment $root @{ main = 'a'; accounts = @{ a = @{ email = 'a@x' } } }
        $md = Set-FakeClaudeMd $root $stale
        Remove-ClaudeMdBlock
        (Get-Content $md -Raw).Trim() | Should Be '# Mine'
    }
}
