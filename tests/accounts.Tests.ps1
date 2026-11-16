. (Join-Path $PSScriptRoot '_fake-accounts.ps1')
$realProfile = $env:USERPROFILE

Describe 'Get-Accounts: rc and usageWarning' {
    AfterAll { $env:USERPROFILE = $realProfile }

    It 'rc true only when explicit' {
        . New-FakeEnvironment (Join-Path $TestDrive 'p1') @{
            main = 'a'
            accounts = @{ a = @{ email = 'a@x'; rc = $true }; b = @{ email = 'b@x' }; c = @{ email = 'c@x'; rc = 'true' } }
        }
        $accts = (Get-Accounts).Accounts
        ($accts | Where-Object Name -eq 'a').Rc | Should Be $true
        ($accts | Where-Object Name -eq 'b').Rc | Should Be $false
        ($accts | Where-Object Name -eq 'c').Rc | Should Be $false
    }

    It 'usageWarning defaults to 80' {
        . New-FakeEnvironment (Join-Path $TestDrive 'p2') @{ main = 'a'; accounts = @{ a = @{ email = 'a@x' } } }
        (Get-Accounts).UsageWarning | Should Be 80
        . New-FakeEnvironment (Join-Path $TestDrive 'p3') @{ main = 'a'; usageWarning = 70; accounts = @{ a = @{ email = 'a@x' } } }
        (Get-Accounts).UsageWarning | Should Be 70
        . New-FakeEnvironment (Join-Path $TestDrive 'p4') @{ main = 'a'; usageWarning = 'x'; accounts = @{ a = @{ email = 'a@x' } } }
        (Get-Accounts).UsageWarning | Should Be 80
    }
}
