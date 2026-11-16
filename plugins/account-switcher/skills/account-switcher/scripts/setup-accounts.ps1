# Updates the accounts block in ~/.claude/CLAUDE.md, creates/updates the folders of the accounts listed
# in accounts.json and puts bin\ on the user PATH.
# Idempotent: safe to run again at any time (for example, after adding an account).
. (Join-Path $PSScriptRoot 'common.ps1')

$cfg = Get-Accounts
if (-not $cfg.Main) { throw '"main" is missing in accounts.json' }
if (-not ($cfg.Accounts.Name -contains $cfg.Default)) { throw "Default account '$($cfg.Default)' does not exist in accounts.json" }
if (-not ($cfg.Accounts.Name -contains $cfg.Publish)) { throw "Main/publish account '$($cfg.Publish)' does not exist in accounts.json" }
if ($cfg.Chrome -and -not ($cfg.Accounts.Name -contains $cfg.Chrome)) { throw "Chrome account '$($cfg.Chrome)' does not exist in accounts.json" }
if (@($cfg.Accounts | Where-Object Master).Count -gt 1) { throw 'More than one account uses the master folder ~/.claude' }

# Before the links: if CLAUDE.md does not exist yet, it must exist to be linked.
Update-ClaudeMd
Write-Host "CLAUDE.md: accounts block updated in $(Join-Path $MasterDir 'CLAUDE.md')"

foreach ($c in $cfg.Accounts) {
    if ($c.Master) { Write-Host "[$($c.Name)] uses the master folder $($c.Dir), nothing to do"; continue }
    $msgs = Sync-AccountLinks $c
    if ($msgs) { $msgs | ForEach-Object { Write-Host "[$($c.Name)] $_" } } else { Write-Host "[$($c.Name)] ok, already set up" }
}

# RC off for sessions opened without cc; status line with account and usage.
foreach ($m in @((Disable-SharedRc), (Register-StatusLine))) { if ($m) { Write-Host $m } }

$bin = Join-Path $BaseDir 'bin'
$path = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not (($path -split ';') -contains $bin)) {
    [Environment]::SetEnvironmentVariable('Path', ($path.TrimEnd(';') + ';' + $bin), 'User')
    Write-Host "PATH: added $bin (takes effect in terminals opened from now on)"
}
