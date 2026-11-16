# install.ps1 [-Check]
# Copies the scripts of this folder to ~/.claude-accounts, takes a backup the first time, creates the accounts
# (setup-accounts.ps1), registers the Explorer shortcut and updates the global CLAUDE.md.
# Prerequisite: ~/.claude-accounts/accounts.json already written (see accounts.example.json).
# An install made by an older version (~/.claude-contas, contas.json) is migrated automatically.
# -Check: only checks the environment and lists conflicts (and a pending migration), changing nothing.
param([switch]$Check)
$source = $PSScriptRoot
. (Join-Path $source 'common.ps1')

# ---- checks (nothing is changed until all of them pass) ----
$problems = @(); $warnings = @()
if (-not (Test-Path $Claude)) { $problems += "claude.exe not found (looked on PATH and in $Claude)" }

# The config file to read: the new one, or the old contas.json of an install that is still to be migrated.
$migrating = Test-LegacyInstall
$cfgFile = Join-Path $BaseDir 'accounts.json'
$shortcut = 'cc'
$cfgSource = if (Test-Path $cfgFile) { $cfgFile } elseif ($migrating) { Get-LegacyConfigPath } else { $null }
if (-not $cfgSource) {
    if (-not $migrating) { $problems += "missing $cfgFile (copy accounts.example.json and edit it)" }
} else {
    try {
        $raw = Get-Content -LiteralPath $cfgSource -Raw -Encoding UTF8 | ConvertFrom-Json
        $name = if ($raw.explorerShortcut) { $raw.explorerShortcut } elseif ($raw.atalhoExplorer) { $raw.atalhoExplorer } else { $null }
        if ($name) { $shortcut = $name }
    } catch {
        $problems += "$cfgSource is not valid JSON ($($_.Exception.Message)): fix it and run install.ps1 again"
    }
}
if ($migrating) { $warnings += "an older install was found (${LegacyBaseDir}): running install.ps1 without -Check migrates it to $BaseDir. Close every Claude Code session and terminal that uses it first" }
elseif ((Test-Path -LiteralPath $LegacyBaseDir) -and (Test-Path -LiteralPath $BaseDir)) {
    $warnings += "both ${LegacyBaseDir} and $BaseDir exist, so nothing is migrated and the accounts in $BaseDir start without logins. To keep your old logins, move or delete $BaseDir (it only holds scripts and accounts.json) and run install.ps1 again"
}

$tmp = Join-Path $env:TEMP ("mc-linktest-" + [guid]::NewGuid())
New-Item -ItemType Directory $tmp | Out-Null
Set-Content "$tmp\a.txt" 'x'
cmd /c mklink "$tmp\b.txt" "$tmp\a.txt" 2>$null | Out-Null
$symlinkOk = Test-Link "$tmp\b.txt"
Remove-Item $tmp -Recurse -Force
if (-not $symlinkOk) { $warnings += 'symlinks unavailable (developer mode is off): shared files will use hard links' }

# The Explorer address bar navigates to a folder with the same name before running the shortcut.
$places = @($env:USERPROFILE, [Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('MyDocuments'),
            [Environment]::GetFolderPath('MyPictures'), [Environment]::GetFolderPath('MyMusic'),
            [Environment]::GetFolderPath('MyVideos'), (Join-Path $env:USERPROFILE 'Downloads'))
foreach ($l in $places) {
    if ($l -and (Test-Path -LiteralPath (Join-Path $l $shortcut) -PathType Container)) {
        $problems += "the folder '$(Join-Path $l $shortcut)' exists: typing '$shortcut' in Explorer would open that folder. Pick another explorerShortcut."
    }
}
$other = Get-Command 'cc' -ErrorAction SilentlyContinue | Where-Object { $_.Source -and $_.Source -notlike "$BaseDir*" -and $_.Source -notlike "$LegacyBaseDir*" }
if ($other) { $warnings += "a 'cc' command already exists in $($other.Source -join ', '); in the terminal, whichever comes first on PATH wins" }
$policy = Get-ExecutionPolicy -Scope CurrentUser
if ($policy -in 'Undefined', 'Restricted', 'AllSigned') { $warnings += "the user ExecutionPolicy is ${policy}: that is why cc is a .cmd (it does not depend on `$PROFILE)" }

Write-Host "claude.exe: $Claude"
Write-Host "symlink: $(if ($symlinkOk) { 'ok' } else { 'no' })"
$warnings | ForEach-Object { Write-Host "WARNING: $_" -ForegroundColor Yellow }
$problems | ForEach-Object { Write-Host "PROBLEM: $_" -ForegroundColor Red }
if ($Check) { return }
if ($problems) { throw 'Fix the problems above before installing.' }

# ---- migration from the Portuguese-named install ----
if ($migrating) {
    Move-LegacyInstall | ForEach-Object { Write-Host $_ }
}

# ---- backup (first install only) ----
if (-not (Get-ChildItem (Join-Path $BaseDir 'backups') -Directory -Filter 'install_*' -ErrorAction SilentlyContinue)) {
    $b = Join-Path $BaseDir ("backups\install_" + (Get-Date -Format 'yyyy-MM-dd_HHmmss'))
    New-Item -ItemType Directory -Force "$b\.claude\plugins" | Out-Null
    foreach ($f in @("$env:USERPROFILE\.claude.json")) { if (Test-Path $f) { Copy-Item $f $b } }
    foreach ($f in 'settings.json', 'history.jsonl', 'CLAUDE.md') { $p = Join-Path $MasterDir $f; if (Test-Path $p) { Copy-Item $p "$b\.claude\" } }
    Copy-Item (Join-Path $MasterDir 'plugins\*.json') "$b\.claude\plugins\" -ErrorAction SilentlyContinue
    Write-Host "backup: $b"
}

# ---- copy the scripts (never overwrites accounts.json) ----
Get-ChildItem $source -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($source.Length).TrimStart('\')
    $dest = Join-Path $BaseDir $rel
    New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
    Copy-Item $_.FullName $dest -Force
}
$disabled = Join-Path $BaseDir 'cc.ps1.disabled'
if (Test-Path $disabled) { Remove-Item $disabled }
Write-Host "scripts copied to $BaseDir"

# ---- old bin\ folder off the user PATH (setup-accounts.ps1 adds the new one) ----
$oldBin = (Join-Path $LegacyBaseDir 'bin').TrimEnd('\')
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath) {
    $kept = @(($userPath -split ';') | Where-Object { $_ -and $_.TrimEnd('\') -ne $oldBin })
    if ($kept.Count -ne @(($userPath -split ';') | Where-Object { $_ }).Count) {
        [Environment]::SetEnvironmentVariable('Path', ($kept -join ';'), 'User')
        Write-Host "migration: $oldBin taken off the user PATH"
    }
}

# ---- accounts, PATH and CLAUDE.md ----
& (Join-Path $BaseDir 'setup-accounts.ps1')

# ---- Explorer shortcut ----
$key = Get-AppPathsKey $shortcut
New-Item $key -Force | Out-Null
Set-ItemProperty $key -Name '(default)' -Value (Join-Path $BaseDir 'explorer\claude-here.cmd')
Write-Host "Explorer: type '$shortcut' or '$shortcut <account>' in the address bar"

& (Join-Path $BaseDir 'cc.ps1') -l

# Things the migration cannot safely rewrite: tell the user instead of guessing.
foreach ($f in @(Find-LegacyPathReferences)) {
    Write-Host "WARNING: $f still mentions .claude-contas (for example a plugin install path). Check it by hand if something stops working." -ForegroundColor Yellow
}
