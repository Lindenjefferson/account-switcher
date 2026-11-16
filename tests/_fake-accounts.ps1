# Test helper: builds a fake USERPROFILE with .claude, .claude-accounts\accounts.json and .claude.json,
# and dot-sources common.ps1 pointing at it. Use with dot-source: . New-FakeEnvironment $root @{...}
$Script:ScriptsDir = Join-Path $PSScriptRoot '..\plugins\account-switcher\skills\account-switcher\scripts'

function New-FakeEnvironment([string]$root, [hashtable]$accountsJson) {
    New-Item -ItemType Directory -Force (Join-Path $root '.claude'), (Join-Path $root '.claude-accounts') | Out-Null
    [IO.File]::WriteAllText((Join-Path $root '.claude-accounts\accounts.json'), ($accountsJson | ConvertTo-Json -Depth 10))
    [IO.File]::WriteAllText((Join-Path $root '.claude.json'), '{}')
    $env:USERPROFILE = $root
    . (Join-Path $ScriptsDir 'common.ps1')
}
