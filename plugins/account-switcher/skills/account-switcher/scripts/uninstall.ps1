# Undoes the installation without touching the content of the master folder ~/.claude: removes only the
# links of the extra accounts, takes bin\ off the PATH, removes the Explorer shortcut, the accounts block
# of CLAUDE.md and the account/usage statusLine of settings.json.
# With -DeleteFolders, it also deletes the folders of the extra accounts (their logins; you will need /login again).
param([switch]$DeleteFolders)
. (Join-Path $PSScriptRoot 'common.ps1')

$cfg = Get-Accounts
foreach ($c in $cfg.Accounts) {
    if ($c.Master) { continue }
    Remove-AccountLinks $c
    Write-Host "[$($c.Name)] links removed"
    if ($DeleteFolders -and (Test-Path -LiteralPath $c.Dir)) {
        if (Get-ChildItem -LiteralPath $c.Dir -Recurse -Force | Where-Object { $_.LinkType }) { throw "There are still links in $($c.Dir); nothing deleted" }
        Remove-Item -LiteralPath $c.Dir -Recurse -Force
        Write-Host "[$($c.Name)] folder deleted"
    }
}

$bin = Join-Path $BaseDir 'bin'
$path = [Environment]::GetEnvironmentVariable('Path', 'User')
[Environment]::SetEnvironmentVariable('Path', ((($path -split ';') | Where-Object { $_ -and $_ -ne $bin }) -join ';'), 'User')
Write-Host "PATH: removed $bin"

$key = Get-AppPathsKey $cfg.Shortcut
if (Test-Path $key) { Remove-Item $key -Force; Write-Host "Explorer: shortcut '$($cfg.Shortcut)' removed" }

Remove-ClaudeMdBlock
Write-Host 'CLAUDE.md: accounts block removed'

# The statusLine goes only if it is ours; remoteControlAtStartup false stays (safe without cc).
$m = Unregister-StatusLine
if ($m) { Write-Host $m }

$cc = Join-Path $BaseDir 'cc.ps1'
if (Test-Path $cc) { Rename-Item $cc 'cc.ps1.disabled' -Force; Write-Host 'cc disabled (cc.ps1.disabled); install.ps1 enables it again' }
