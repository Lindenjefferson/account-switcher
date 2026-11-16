. (Join-Path $PSScriptRoot '_fake-accounts.ps1')
$realProfile = $env:USERPROFILE
$root = Join-Path ([IO.Path]::GetTempPath()) ("mc-rc-" + [guid]::NewGuid())
. New-FakeEnvironment $root @{ main = 'personal'; accounts = @{ personal = @{ email = 'p@x'; rc = $true }; work1 = @{ email = 'e@x' } } }
$accts = (Get-Accounts).Accounts
$personal = $accts | Where-Object Name -eq 'personal'
$work = $accts | Where-Object Name -eq 'work1'
$settings = Join-Path $root '.claude\settings.json'
function Set-Settings([string]$text) { [IO.File]::WriteAllText($settings, $text) }
function Get-Settings { Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json }

Describe 'Split-RcArgs' {
    It 'account default' {
        (Split-RcArgs $personal @()).On | Should Be $true
        (Split-RcArgs $work @()).On | Should Be $false
    }

    It '--rc turns it on and stays in the args' {
        $d = Split-RcArgs $work @('--rc', 'my-session')
        $d.On | Should Be $true
        ($d.Rest -join ' ') | Should Be '--rc my-session'
    }

    It '--no-rc turns it off and leaves the args' {
        $d = Split-RcArgs $personal @('--no-rc', '-p', 'hi')
        $d.On | Should Be $false
        ($d.Rest -join ' ') | Should Be '-p hi'
    }

    It 'the last one wins' {
        (Split-RcArgs $work @('--rc', '--no-rc')).On | Should Be $false
        (Split-RcArgs $personal @('--no-rc', '--remote-control')).On | Should Be $true
    }

    It 'user settings detected' {
        (Split-RcArgs $work @('--settings', 'x.json')).UserSettings | Should Be $true
        (Split-RcArgs $work @('-p', 'hi')).UserSettings | Should Be $false
    }
}

Describe 'Get-RcFile' {
    It 'rc files' {
        (Get-Content (Get-RcFile $false) -Raw | ConvertFrom-Json).remoteControlAtStartup | Should Be $false
        (Get-Content (Get-RcFile $true) -Raw | ConvertFrom-Json).remoteControlAtStartup | Should Be $true
        Get-RcFile $true | Should Be (Join-Path $root '.claude-accounts\rc\on.json')
    }
}

Describe 'Disable-SharedRc' {
    It 'shared: true becomes false' {
        Set-Settings "{`n  `"theme`": `"dark`",`n  `"remoteControlAtStartup`": true`n}"
        Disable-SharedRc | Should Not BeNullOrEmpty
        $s = Get-Settings
        $s.remoteControlAtStartup | Should Be $false
        $s.theme | Should Be 'dark'
    }

    It 'shared: inserts when missing' {
        Set-Settings '{"theme":"dark"}'
        Disable-SharedRc | Should Not BeNullOrEmpty
        $s = Get-Settings
        $s.remoteControlAtStartup | Should Be $false
        $s.theme | Should Be 'dark'
    }

    It 'shared: empty object' {
        Set-Settings '{}'
        $null = Disable-SharedRc
        (Get-Settings).remoteControlAtStartup | Should Be $false
    }

    It 'shared: already false is left alone' {
        Set-Settings '{"remoteControlAtStartup": false, "theme":"dark"}'
        $before = (Get-Item $settings).LastWriteTimeUtc
        Start-Sleep -Milliseconds 50
        Disable-SharedRc | Should Be $null
        (Get-Item $settings).LastWriteTimeUtc | Should Be $before
    }

    It 'shared: invalid JSON is not rewritten' {
        $broken = '{"theme":"dark",}'
        Set-Settings $broken
        Disable-SharedRc | Should Match 'invalid'
        Get-Content -LiteralPath $settings -Raw | Should Be $broken
    }

    It 'shared: empty file becomes an object' {
        Set-Settings ''
        $null = Disable-SharedRc
        (Get-Settings).remoteControlAtStartup | Should Be $false
    }

    It 'shared: missing file' {
        Remove-Item $settings -ErrorAction SilentlyContinue
        $null = Disable-SharedRc
        (Get-Settings).remoteControlAtStartup | Should Be $false
    }
}

$env:USERPROFILE = $realProfile
Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
