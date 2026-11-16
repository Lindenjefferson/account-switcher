# open-account.ps1 <account> [folder] [-Rc | -NoRc]
# Opens a new Windows Terminal tab (or, without it, a window) running "cc <account>" in the given
# folder (default: current folder). Used by a session of one account to open a session of another account
# (e.g. the one that can publish artifacts) and then talk to it through SendMessage. The user sees and
# approves it in that window. -Rc / -NoRc become cc's --rc / --no-rc (with -File, a bare --rc would be
# read as a parameter of this script).
param([Parameter(Mandatory)][string]$Account, [string]$Folder = (Get-Location).Path,
      [switch]$Rc, [switch]$NoRc)
. (Join-Path $PSScriptRoot 'common.ps1')

if (-not ((Get-Accounts).Accounts.Name -contains $Account)) { throw "Account '$Account' does not exist in accounts.json" }
if (-not (Test-Path -LiteralPath $Folder -PathType Container)) { throw "Folder does not exist: $Folder" }

$extra = @()
if ($Rc) { $extra += '--rc' }
if ($NoRc) { $extra += '--no-rc' }

# The calling session passes CLAUDECODE, CLAUDE_CODE_CHILD_SESSION and its messaging socket;
# inherited, the new session behaves like a child (no history) and talks over the wrong channel.
$null = Clear-ParentSessionEnv

# Start-Process opens cc.cmd in a classic console (conhost), without colors; Windows Terminal does not.
$cc = Join-Path $BaseDir 'bin\cc.cmd'
$wt = Get-Command wt.exe -ErrorAction SilentlyContinue
if ($wt) {
    & $wt.Source -w new -d $Folder $cc $Account @extra
} else {
    Start-Process -FilePath $cc -ArgumentList (@($Account) + $extra) -WorkingDirectory $Folder
}
Write-Host "Window opened: cc $Account $($extra -join ' ') in $Folder. Use ListAgents to find the session '$(Split-Path -Leaf $Folder) ($Account)'."
