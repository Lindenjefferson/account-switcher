# Functions shared by the scripts in ~/.claude-accounts.
# Each account has its own config folder (CLAUDE_CONFIG_DIR) with its own login;
# everything else points to the master folder ~/.claude through symlinks (files) or junctions (folders).
# .ps1 files stay ASCII only: Windows PowerShell 5.1 reads a .ps1 without BOM as ANSI.

$Script:BaseDir     = Join-Path $env:USERPROFILE '.claude-accounts'
$Script:MasterDir   = Join-Path $env:USERPROFILE '.claude'
$Script:MasterState = Join-Path $env:USERPROFILE '.claude.json'  # .claude.json of the account that lives in the master folder
$Script:LegacyBaseDir = Join-Path $env:USERPROFILE '.claude-contas'  # where versions before the English rename installed

$Script:Claude = Get-Command claude.exe -CommandType Application -ErrorAction SilentlyContinue |
    Where-Object { $_.Source -notlike "$BaseDir*" } | Select-Object -First 1 -ExpandProperty Source
if (-not $Claude) { $Script:Claude = Join-Path $env:USERPROFILE '.local\bin\claude.exe' }

# What is shared with the master folder. Login (.credentials.json), .claude.json,
# cache, state, shell-snapshots, backups etc. stay separate per account.
$Script:SharedFiles = @('settings.json', 'history.jsonl', 'CLAUDE.md', 'keybindings.json')
$Script:SharedDirs  = @('projects', 'file-history', 'session-env', 'sessions', 'skills',
                        'plugins', 'dev-mods', 'agents', 'commands', 'output-styles', 'hooks', 'rules')

# Keys of ~/.claude.json copied into a new account (configuration, not account data).
$Script:SeedKeys = @('mcpServers', 'projects', 'githubRepoPaths', 'hasCompletedOnboarding',
                     'lastOnboardingVersion', 'installMethod', 'autoUpdates', 'autoUpdatesProtectedForNative',
                     'claudeInChromeDefaultEnabled', 'hasCompletedClaudeInChromeOnboarding',
                     'cachedChromeExtensionInstalled')

$Script:MarkBegin  = '<!-- account-switcher:begin -->'
$Script:MarkEnd    = '<!-- account-switcher:end -->'
$Script:BlockRegex = '(?s)<!-- account-switcher:begin -->.*?<!-- account-switcher:end -->'

function Get-Accounts {
    $cfg = Get-Content (Join-Path $BaseDir 'accounts.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $main = if ($cfg.main) { $cfg.main } else { $cfg.default }
    # Only one account uses the master folder ~/.claude: the one with "dir" or, if none has it, the main one.
    $anyDir = [bool]($cfg.accounts.PSObject.Properties | Where-Object { $_.Value.dir })
    $list = foreach ($p in $cfg.accounts.PSObject.Properties) {
        $dir = if ($p.Value.dir) { $p.Value.dir -replace '^~', $env:USERPROFILE }
               elseif (-not $anyDir -and $p.Name -eq $main) { $MasterDir }
               else { Join-Path $BaseDir $p.Name }
        $dir = [IO.Path]::GetFullPath($dir)
        [pscustomobject]@{
            Name   = $p.Name
            Email  = $p.Value.email
            Dir    = $dir
            Master = ($dir.TrimEnd('\') -eq $MasterDir.TrimEnd('\'))
            # Remote Control when opening with cc: only on with an explicit "rc": true.
            Rc     = ($p.Value.rc -is [bool] -and $p.Value.rc)
        }
    }
    $warn = 80
    if ($cfg.usageWarning -is [int] -and $cfg.usageWarning -ge 1 -and $cfg.usageWarning -le 100) { $warn = $cfg.usageWarning }
    # "main" is the default account of cc and where artifacts are published; "default"/"publish" split the two roles.
    [pscustomobject]@{
        Main    = $main
        Default = $(if ($cfg.default) { $cfg.default } else { $main })
        Publish = $(if ($cfg.publish) { $cfg.publish } else { $main })
        Shortcut = $(if ($cfg.explorerShortcut) { $cfg.explorerShortcut } else { 'cc' })
        # Account the Claude in Chrome extension is logged in to (told by the user; it cannot be detected).
        Chrome  = $cfg.chrome
        # Percentage (5h or weekly) from which cc warns and the status line turns yellow.
        UsageWarning = $warn
        Accounts = @($list)
    }
}

function Test-Link([string]$path) {
    $i = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    return ($i -and $i.LinkType)
}

function Write-TextNoBom([string]$path, [string]$text) {
    [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding $false))
}

# A file symlink needs developer mode (or admin). Without it, fall back to a hard link, which also works;
# if a program saves over it and breaks the link, Sync-AccountLinks recreates it.
function New-FileLink([string]$link, [string]$target) {
    cmd /c mklink "$link" "$target" 2>$null | Out-Null
    if (-not (Test-Link $link)) { cmd /c mklink /H "$link" "$target" 2>$null | Out-Null }
    if (-not (Test-Path -LiteralPath $link)) { throw "Could not create a link from $link to $target" }
}

function Test-FileLinkOk([string]$link, [string]$target) {
    $i = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
    if (-not $i) { return $false }
    if ($i.LinkType -eq 'SymbolicLink') { return $true }
    if ($i.LinkType -eq 'HardLink') {
        # A hard link only counts if it still points to the same file in the master folder.
        $a = cmd /c fsutil hardlink list "$target" 2>$null
        $name = $link.Substring(2)  # fsutil lists without the drive letter
        return [bool]($a | Where-Object { $_ -ieq $name })
    }
    return $false
}

# Makes sure the account has all its links. If a file link turned into a regular file (some programs
# save by writing a temp file and renaming it over the link), the newer version goes to the master folder
# before the link is recreated, so no change is lost. Returns the messages of what it did.
function Sync-AccountLinks($account) {
    $msgs = @()
    if ($account.Master) { return $msgs }
    New-Item -ItemType Directory -Force $account.Dir | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'

    foreach ($name in $SharedFiles) {
        $target = Join-Path $MasterDir $name
        $link = Join-Path $account.Dir $name
        if (-not (Test-Path -LiteralPath $target)) { continue }
        if (Test-FileLinkOk $link $target) { continue }
        if (Test-Path -LiteralPath $link) {
            $local = Get-Item -LiteralPath $link -Force
            $bak = Join-Path $BaseDir ("backups\relink_{0}_{1}_{2}" -f $account.Name, $stamp, $name)
            New-Item -ItemType Directory -Force (Split-Path $bak) | Out-Null
            if ($local.LastWriteTime -gt (Get-Item -LiteralPath $target).LastWriteTime) {
                Copy-Item -LiteralPath $target $bak
                Copy-Item -LiteralPath $link $target -Force
                $msgs += "${name}: change made in account $($account.Name) was carried over to the master folder (previous version in $bak)"
            } else {
                Copy-Item -LiteralPath $link $bak
            }
            Remove-Item -LiteralPath $link -Force
        }
        New-FileLink $link $target
        $msgs += "link: $link"
    }

    foreach ($name in $SharedDirs) {
        $target = Join-Path $MasterDir $name
        $link = Join-Path $account.Dir $name
        if (-not (Test-Path -LiteralPath $target)) { continue }
        if (Test-Link $link) { continue }
        if (Test-Path -LiteralPath $link) {
            # Real folder created by Claude before the link existed: keep it under backups and link.
            $bak = Join-Path $BaseDir ("backups\relink_{0}_{1}_{2}" -f $account.Name, $stamp, $name)
            New-Item -ItemType Directory -Force (Split-Path $bak) | Out-Null
            Move-Item -LiteralPath $link $bak
            $msgs += "${name}: local folder of account $($account.Name) moved to $bak"
        }
        New-Item -ItemType Junction -Path $link -Target $target | Out-Null
        $msgs += "junction: $link"
    }

    # Initial .claude.json: only the configuration keys of the master one, no account data.
    $state = Join-Path $account.Dir '.claude.json'
    $source = Join-Path $env:USERPROFILE '.claude.json'
    if (-not (Test-Path -LiteralPath $state) -and (Test-Path -LiteralPath $source)) {
        $orig = Get-Content $source -Raw -Encoding UTF8 | ConvertFrom-Json
        $new = [ordered]@{}
        foreach ($k in $SeedKeys) { if ($null -ne $orig.$k) { $new[$k] = $orig.$k } }
        Write-TextNoBom $state (([pscustomobject]$new) | ConvertTo-Json -Depth 100)
        $msgs += "initial state: $state"
    }
    return $msgs
}

# Removes only the links (never the content of the master folder).
function Remove-AccountLinks($account) {
    if ($account.Master -or -not (Test-Path -LiteralPath $account.Dir)) { return }
    Get-ChildItem -LiteralPath $account.Dir -Force | Where-Object { $_.LinkType } | ForEach-Object {
        if ($_.PSIsContainer) { [IO.Directory]::Delete($_.FullName, $false) } else { [IO.File]::Delete($_.FullName) }
    }
    foreach ($name in $SharedFiles) {
        # Hard links do not show up as LinkType in every version; only remove it if it is still
        # the same file as the master one (a copy that diverged stays, so no change is lost).
        $f = Join-Path $account.Dir $name
        if ((Test-Path -LiteralPath $f) -and (Test-FileLinkOk $f (Join-Path $MasterDir $name))) { [IO.File]::Delete($f) }
    }
}

function Invoke-WithAccount($account, [scriptblock]$block) {
    $before = $env:CLAUDE_CONFIG_DIR
    try {
        # The master-folder account runs without the variable, otherwise Claude looks for .claude.json inside ~/.claude.
        if ($account.Master) { Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue } else { $env:CLAUDE_CONFIG_DIR = $account.Dir }
        & $block
    } finally {
        if ($null -ne $before) { $env:CLAUDE_CONFIG_DIR = $before } else { Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue }
    }
}

# A cc run from inside a Claude session (open-account.ps1, "!" in the prompt) inherits that session's
# CLAUDE* variables; with CLAUDE_CODE_CHILD_SESSION the new session neither saves a transcript nor shows
# up in ListAgents. Drops those, except CLAUDE_CONFIG_DIR (cc controls it itself) and the ones the user
# set in their own environment (User/Machine), such as CLAUDE_CODE_GIT_BASH_PATH. Returns the names dropped.
function Get-PersistentClaudeNames {
    foreach ($scope in 'User', 'Machine') {
        [Environment]::GetEnvironmentVariables($scope).Keys | Where-Object { "$_" -like 'CLAUDE*' }
    }
}

function Clear-ParentSessionEnv([string[]]$persistent = @(Get-PersistentClaudeNames)) {
    Get-ChildItem Env: | Where-Object {
        $_.Name -like 'CLAUDE*' -and $_.Name -ne 'CLAUDE_CONFIG_DIR' -and $persistent -notcontains $_.Name
    } | ForEach-Object {
        Remove-Item "Env:$($_.Name)"
        $_.Name
    }
}

# Without TMP in the user environment, Windows inherits the machine one (C:\Windows\TEMP). There, the
# Add-Type compiler writes the .cs and cannot read it back ("source file could not be found").
# Points TMP and TEMP of this session to the user temp folder when they are empty or inside the Windows
# folder. Does not touch the user's saved environment. Returns the names it changed.
function Repair-SessionTemp([string]$windowsDir = $env:windir, [string]$userTemp = (Join-Path $env:LOCALAPPDATA 'Temp')) {
    $prefix = $windowsDir.TrimEnd('\') + '\'
    foreach ($name in 'TMP', 'TEMP') {
        $value = [Environment]::GetEnvironmentVariable($name)
        if (-not $value -or ($value.TrimEnd('\') + '\').StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            Set-Item "Env:$name" $userTemp
            $name
        }
    }
}

function Get-AccountStatus($account) {
    Invoke-WithAccount $account { & $Claude auth status --json 2>$null | ConvertFrom-Json }
}

# ---- usage (5h and weekly windows), the same as /usage shows ----
# The account token is read from its .credentials.json in memory only: never copied, written,
# printed or refreshed here. Without a valid token, the last usage Claude saved in the account is used.

function Get-StateFile($account) {
    if ($account.Master) { $MasterState } else { Join-Path $account.Dir '.claude.json' }
}

function Get-AccountToken($account, [datetime]$now = (Get-Date)) {
    try {
        $f = Join-Path $account.Dir '.credentials.json'
        if (-not (Test-Path -LiteralPath $f)) { return $null }
        $o = (Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json).claudeAiOauth
        $limit = [DateTimeOffset]::new($now.AddSeconds(60)).ToUnixTimeMilliseconds()
        if (-not $o.accessToken -or [int64]$o.expiresAt -le $limit) { return $null }
        return $o.accessToken
    } catch { return $null }
}

function Invoke-UsageApi([string]$token, [int]$timeoutSec = 3) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Invoke-RestMethod -Uri 'https://api.anthropic.com/api/oauth/usage' -TimeoutSec $timeoutSec -ErrorAction Stop -Headers @{
        Authorization    = "Bearer $token"
        'anthropic-beta' = 'oauth-2025-04-20'
    }
}

function ConvertTo-LocalDate($v) {
    if (-not $v) { return $null }
    if ($v -is [datetime]) { return $v.ToLocalTime() }
    # The status line receives resets_at in Unix seconds; the usage API, as ISO text.
    if ($v -is [ValueType]) { return [DateTimeOffset]::FromUnixTimeSeconds([int64]$v).LocalDateTime }
    try { return [DateTimeOffset]::Parse([string]$v, [Globalization.CultureInfo]::InvariantCulture).LocalDateTime } catch { return $null }
}

function ConvertTo-Usage($util, [string]$source, $when, [datetime]$now = (Get-Date)) {
    $r = [ordered]@{ Five = $null; Week = $null; ResetFive = $null; ResetWeek = $null; Source = $null; When = $null }
    if (-not $util) { return [pscustomobject]$r }
    foreach ($j in @(@('five_hour', 'Five', 'ResetFive'), @('seven_day', 'Week', 'ResetWeek'))) {
        $w = $util.($j[0])
        if ($null -eq $w -or $null -eq $w.utilization) { continue }
        $reset = ConvertTo-LocalDate $w.resets_at
        # A window that already reset: its usage went back to zero.
        if ($reset -and $reset -le $now) { $r[$j[1]] = 0 }
        else { $r[$j[1]] = [int][math]::Round([double]$w.utilization); $r[$j[2]] = $reset }
    }
    if ($null -ne $r.Five -or $null -ne $r.Week) { $r.Source = $source; $r.When = $when }
    [pscustomobject]$r
}

# Source is 'live' (from the API) or 'saved' (the last value Claude stored in the account).
function Get-AccountUsage($account, [int]$timeoutSec = 3, [datetime]$now = (Get-Date)) {
    $token = Get-AccountToken $account $now
    if ($token) {
        try { return ConvertTo-Usage (Invoke-UsageApi $token $timeoutSec) 'live' $null $now } catch { }
    }
    try {
        $f = Get-StateFile $account
        if (Test-Path -LiteralPath $f) {
            $c = (Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json).cachedUsageUtilization
            if ($c) {
                $when = if ($c.fetchedAtMs) { [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$c.fetchedAtMs).LocalDateTime } else { $null }
                return ConvertTo-Usage $c.utilization 'saved' $when $now
            }
        }
    } catch { }
    ConvertTo-Usage $null $null $null $now
}

function Get-MaxUsage($usage) {
    $v = @($usage.Five, $usage.Week) | Where-Object { $null -ne $_ }
    if (-not $v) { return $null }
    ($v | Measure-Object -Maximum).Maximum
}

# "Session: x% . Week: y%" (with a middle dot), from the ready-made text of each window.
$Script:Dot = [char]0xB7
function Format-Windows([string]$five, [string]$week) {
    'Session: {0} {1} Week: {2}' -f $five, $Dot, $week
}

# " (resets in 2h05)" until the window resets; empty when unknown or already past.
function Format-Reset($reset, [datetime]$now = (Get-Date)) {
    if (-not $reset -or $reset -le $now) { return '' }
    $min = [int][math]::Floor(($reset - $now).TotalMinutes)
    $t = if ($min -lt 60) { '{0}min' -f $min }
         elseif ($min -lt 1440) { '{0}h{1:00}' -f [math]::Floor($min / 60), ($min % 60) }
         else { '{0}d {1}h' -f [math]::Floor($min / 1440), [math]::Floor(($min % 1440) / 60) }
    " (resets in $t)"
}

function Format-Usage($usage, [datetime]$now = (Get-Date)) {
    if ($null -eq (Get-MaxUsage $usage)) { return '-' }
    $p = { param($x, $reset) if ($null -eq $x) { '?' } else { "$x%" + (Format-Reset $reset $now) } }
    $t = Format-Windows (& $p $usage.Five $usage.ResetFive) (& $p $usage.Week $usage.ResetWeek)
    if ($usage.Source -eq 'saved') {
        # A value saved on another day carries the date, so it does not look like today's.
        $t += if (-not $usage.When) { ' (saved, no date)' }
              elseif ($usage.When.Date -eq $now.Date) { ' (saved {0})' -f $usage.When.ToString('HH:mm') }
              else { ' (saved {0})' -f $usage.When.ToString('dd/MM HH:mm') }
    }
    $t
}

function Select-SuggestedAccount([hashtable]$usages, [string]$exclude) {
    $c = foreach ($k in $usages.Keys) {
        $m = Get-MaxUsage $usages[$k]
        if ($k -ne $exclude -and $null -ne $m) { [pscustomobject]@{ Name = $k; Max = $m } }
    }
    ($c | Sort-Object Max | Select-Object -First 1).Name
}

# ---- Remote Control per account ----
# settings.json is shared between accounts, so cc decides the RC of each session by passing --settings
# with a file from rc\ (the command line wins over the user's settings.json).

function Split-RcArgs($account, [object[]]$arguments) {
    $on = [bool]$account.Rc
    $rest = @()
    foreach ($a in @($arguments)) {
        if ($a -eq '--no-rc') { $on = $false; continue }
        # --rc [name] stays in the arguments: claude itself accepts it and uses the name.
        if ($a -in '--rc', '--remote-control') { $on = $true }
        $rest += $a
    }
    [pscustomobject]@{
        On           = $on
        Rest         = $rest
        UserSettings = [bool]($rest | Where-Object { "$_" -eq '--settings' -or "$_".StartsWith('--settings=') })
    }
}

function Get-RcFile([bool]$on) {
    $f = Join-Path $BaseDir ('rc\{0}.json' -f $(if ($on) { 'on' } else { 'off' }))
    if (-not (Test-Path -LiteralPath $f)) {
        New-Item -ItemType Directory -Force (Split-Path $f) | Out-Null
        Write-TextNoBom $f ('{{ "remoteControlAtStartup": {0} }}' -f "$on".ToLower())
    }
    $f
}

# Final arguments for claude: the user's plus the --settings with the RC decision.
# If the user passed their own --settings, it wins and cc adds no other.
function Get-ClaudeArgs($rcDecision) {
    if ($rcDecision.UserSettings) { return @($rcDecision.Rest) }
    @($rcDecision.Rest) + @('--settings', (Get-RcFile $rcDecision.On))
}

# Inserts a '"key": value' pair right after the first "{" of a JSON text, without reformatting the rest.
function Add-JsonFirstKey([string]$text, [string]$pair) {
    if ($text -match '^\s*\{\s*\}\s*$') { return "{`n  $pair`n}`n" }
    $i = $text.IndexOf('{')
    if ($i -lt 0) { throw 'settings.json has no JSON object' }
    $text.Substring(0, $i + 1) + "`n  $pair," + $text.Substring($i + 1)
}

function Test-JsonValid([string]$text) {
    try { $null = $text | ConvertFrom-Json -ErrorAction Stop; return $true } catch { return $false }
}

$Script:InvalidSettingsMsg = 'invalid settings.json (broken JSON): left untouched; fix the file and run setup-accounts.ps1'

# A missing or empty file counts as {}. Valid = $false when the user's JSON is already broken:
# in that case no function writes anything.
function Get-MasterSettings {
    $f = Join-Path $MasterDir 'settings.json'
    $t = if (Test-Path -LiteralPath $f) { Get-Content -LiteralPath $f -Raw -Encoding UTF8 } else { $null }
    if (-not "$t".Trim()) { $t = '{}' }
    [pscustomobject]@{ File = $f; Text = $t; Valid = (Test-JsonValid $t) }
}

# Sessions opened without cc (claude directly, IDE, app) never turn RC on by themselves.
function Disable-SharedRc {
    $s = Get-MasterSettings
    if (-not $s.Valid) { return $InvalidSettingsMsg }
    $key = '"remoteControlAtStartup"\s*:\s*'
    if ($s.Text -match ($key + 'false')) { return $null }
    if ($s.Text -match ($key + 'true')) {
        $new = $s.Text -replace ($key + 'true'), '"remoteControlAtStartup": false'
        $msg = "settings.json: remoteControlAtStartup was true; now false (cc turns RC on only for accounts with rc or with --rc)"
    } else {
        $new = Add-JsonFirstKey $s.Text '"remoteControlAtStartup": false'
        $msg = 'settings.json: remoteControlAtStartup false written (RC only turns on through cc)'
    }
    if (-not (Test-JsonValid $new)) { return $InvalidSettingsMsg }
    Write-TextNoBom $s.File $new
    $msg
}

# ---- status line: account and session usage (statusline.ps1) ----

function Get-CurrentAccount {
    $accounts = (Get-Accounts).Accounts
    if (-not $env:CLAUDE_CONFIG_DIR) { return $accounts | Where-Object Master | Select-Object -First 1 }
    $dir = [IO.Path]::GetFullPath($env:CLAUDE_CONFIG_DIR).TrimEnd('\')
    $accounts | Where-Object { $_.Dir.TrimEnd('\') -ieq $dir } | Select-Object -First 1
}

function Format-StatusLine($data, $account, [int]$warn, [datetime]$now = (Get-Date)) {
    $e = [char]27
    $pct = {
        param($window)
        $v = $window.used_percentage
        if ($null -eq $v) { return '?' }
        $n = [int][math]::Round([double]$v)
        $color = if ($n -ge 95) { '31' } elseif ($n -ge $warn) { '33' } else { $null }
        $t = if ($color) { "$e[${color}m$n%$e[0m" } else { "$n%" }
        $t + (Format-Reset (ConvertTo-LocalDate $window.resets_at) $now)
    }
    $parts = @()
    if ($account) { $parts += $account.Name }
    $rl = $data.rate_limits
    if ($rl -and ($rl.five_hour -or $rl.seven_day)) {
        $parts += Format-Windows (& $pct $rl.five_hour) (& $pct $rl.seven_day)
    }
    $parts -join " $Dot "
}

$Script:StatusLineMark = 'statusline.ps1'

function Register-StatusLine {
    $s = Get-MasterSettings
    if (-not $s.Valid) { return $InvalidSettingsMsg }
    if ($s.Text -match '"statusLine"\s*:') {
        if ($s.Text -match [regex]::Escape($StatusLineMark)) { return $null }
        return 'settings.json already has another statusLine: left untouched (the account and usage one stays unregistered)'
    }
    $cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File \"{0}/{1}\"' -f ($BaseDir -replace '\\', '/'), $StatusLineMark
    $new = Add-JsonFirstKey $s.Text ('"statusLine": {{"type": "command", "command": "{0}"}}' -f $cmd)
    if (-not (Test-JsonValid $new)) { return $InvalidSettingsMsg }
    Write-TextNoBom $s.File $new
    'settings.json: statusLine registered (account and session usage)'
}

function Unregister-StatusLine {
    $s = Get-MasterSettings
    if (-not $s.Valid) { return $InvalidSettingsMsg }
    $obj = '"statusLine"\s*:\s*\{[^{}]*' + [regex]::Escape($StatusLineMark) + '[^{}]*\}'
    if ($s.Text -notmatch $obj) { return $null }
    $new = [regex]::Replace($s.Text, $obj + '\s*,\s*', '')
    if ($new -eq $s.Text) { $new = [regex]::Replace($s.Text, ',\s*' + $obj, '') }
    if ($new -eq $s.Text) { $new = [regex]::Replace($s.Text, $obj, '') }
    if (-not (Test-JsonValid $new)) { return $InvalidSettingsMsg }
    Write-TextNoBom $s.File $new
    'settings.json: account and usage statusLine removed'
}

# Updates the block between the markers in ~/.claude/CLAUDE.md from CLAUDE.template.md.
function Update-ClaudeMd {
    $cfg = Get-Accounts
    $template = Get-Content (Join-Path $BaseDir 'CLAUDE.template.md') -Raw -Encoding UTF8
    $rows = foreach ($c in $cfg.Accounts) {
        $role = if ($c.Name -eq $cfg.Publish) { 'main' } else { 'secondary' }
        if ($c.Name -eq $cfg.Default -and $cfg.Default -ne $cfg.Publish) { $role += ', default of cc' }
        $p = if ($c.Master) { '`~/.claude` (master folder)' } else { '`~/.claude-accounts/' + $c.Name + '`' }
        '| {0} | {1} | {2} | {3} |' -f $c.Name, $role, $c.Email, $p
    }
    $pub = $cfg.Accounts | Where-Object Name -eq $cfg.Publish
    $chr = $cfg.Accounts | Where-Object Name -eq $cfg.Chrome
    $chrome = if ($chr) { '`{0}` ({1})' -f $chr.Name, $chr.Email } else { 'not set' }
    $block = $template.Replace('{{TABLE}}', ($rows -join "`n")).
        Replace('{{PUBLISH}}', $cfg.Publish).Replace('{{PUBLISH_EMAIL}}', $pub.Email).Replace('{{SHORTCUT}}', $cfg.Shortcut).
        Replace('{{CHROME}}', $chrome)
    $block = "$MarkBegin`n$($block.Trim())`n$MarkEnd"

    $md = Join-Path $MasterDir 'CLAUDE.md'
    $current = if (Test-Path $md) { Get-Content $md -Raw -Encoding UTF8 } else { '' }
    $m = [regex]::Match($current, $BlockRegex)
    if ($m.Success) {
        $new = $current.Substring(0, $m.Index) + $block + $current.Substring($m.Index + $m.Length)
    } elseif ($current.Trim()) {
        $new = $current.TrimEnd() + "`n`n" + $block + "`n"
    } else {
        $new = $block + "`n"
    }
    Write-TextNoBom $md $new
}

function Remove-ClaudeMdBlock {
    $md = Join-Path $MasterDir 'CLAUDE.md'
    if (-not (Test-Path $md)) { return }
    $current = Get-Content $md -Raw -Encoding UTF8
    $m = [regex]::Match($current, $BlockRegex)
    if (-not $m.Success) { return }
    $new = ($current.Substring(0, $m.Index) + $current.Substring($m.Index + $m.Length)).Trim()
    if ($new) { Write-TextNoBom $md ($new + "`n") } else { Remove-Item $md }
}

function Get-AppPathsKey([string]$shortcut) { "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\$shortcut.exe" }

# ---- migration from the Portuguese-named install (~/.claude-contas, contas.json) ----
# Versions before the English rename installed into ~/.claude-contas with a contas.json in Portuguese.
# install.ps1 calls Move-LegacyInstall, which renames that folder and rewrites everything that pointed
# into it. Nothing is deleted except the old script files, which the new install replaces.
# Every step checks its own precondition, so a run that stopped half way can simply be repeated.

# Old JSON key -> new JSON key (top level and per account).
$Script:LegacyTopKeys = [ordered]@{ principal = 'main'; padrao = 'default'; publicar = 'publish'
                                    atalhoExplorer = 'explorerShortcut'; chrome = 'chrome'; avisoUso = 'usageWarning'; contas = 'accounts' }
$Script:LegacyAccountKeys = [ordered]@{ email = 'email'; pasta = 'dir'; rc = 'rc' }
$Script:LegacyScripts = @('comum.ps1', 'instalar.ps1', 'setup-contas.ps1', 'desfazer-contas.ps1', 'abrir-conta.ps1',
                          'contas.exemplo.json', 'modelo-CLAUDE.md', 'explorer\claude-aqui.cmd', 'explorer\claude-aqui.ps1',
                          'rc\ligado.json', 'rc\desligado.json', 'cc.ps1.desativado')
$Script:LegacyBlockBegin = '<!-- account-switcher:inicio -->'
$Script:LegacyBlockEnd   = '<!-- account-switcher:fim -->'
$Script:LegacyStatusPath = '.claude-contas/statusline.ps1'

# Where the old contas.json is right now: still in the old folder, or already in the new one.
function Get-LegacyConfigPath {
    foreach ($dir in $LegacyBaseDir, $BaseDir) {
        $f = Join-Path $dir 'contas.json'
        if (Test-Path -LiteralPath $f) { return $f }
    }
    $null
}

# What is left to migrate, as a list of short descriptions (empty = nothing).
function Get-LegacyLeftovers {
    $left = @()
    if ((Test-Path -LiteralPath $LegacyBaseDir) -and -not (Test-Path -LiteralPath $BaseDir)) { $left += 'old folder name' }
    if ((Test-Path -LiteralPath (Join-Path $BaseDir 'contas.json')) -and -not (Test-Path -LiteralPath (Join-Path $BaseDir 'accounts.json'))) { $left += 'contas.json' }
    if (Test-Path -LiteralPath $BaseDir) {
        foreach ($rel in $LegacyScripts) { if (Test-Path -LiteralPath (Join-Path $BaseDir $rel)) { $left += "old file $rel" } }
        if (Get-ChildItem -LiteralPath (Join-Path $BaseDir 'backups') -Directory -Filter 'instalacao_*' -ErrorAction SilentlyContinue) { $left += 'old backup names' }
    }
    $s = Get-MasterSettings
    if ($s.Valid -and $s.Text.Contains($LegacyStatusPath)) { $left += 'statusLine path' }
    $md = Join-Path $MasterDir 'CLAUDE.md'
    if ((Test-Path -LiteralPath $md) -and (Get-Content -LiteralPath $md -Raw -Encoding UTF8).Contains($LegacyBlockBegin)) { $left += 'CLAUDE.md markers' }
    $left
}

# True when there is something to migrate (see Get-LegacyLeftovers).
function Test-LegacyInstall { @(Get-LegacyLeftovers).Count -gt 0 }

# Turns the text of an old contas.json into the text of the new accounts.json. Keys that are not
# known are kept as they are; a "pasta" that pointed into .claude-contas now points into .claude-accounts.
function Convert-LegacyAccountsJson([string]$text) {
    $old = $text | ConvertFrom-Json
    $new = [ordered]@{}
    foreach ($p in $old.PSObject.Properties) {
        if ($p.Name -eq 'contas') {
            $accounts = [ordered]@{}
            foreach ($a in $p.Value.PSObject.Properties) {
                $entry = [ordered]@{}
                foreach ($f in $a.Value.PSObject.Properties) {
                    $key = if ($LegacyAccountKeys.Contains($f.Name)) { $LegacyAccountKeys[$f.Name] } else { $f.Name }
                    $value = $f.Value
                    if ($key -eq 'dir' -and $value -is [string]) { $value = $value -replace '\.claude-contas', '.claude-accounts' }
                    $entry[$key] = $value
                }
                $accounts[$a.Name] = $entry
            }
            $new['accounts'] = $accounts
        } else {
            $key = if ($LegacyTopKeys.Contains($p.Name)) { $LegacyTopKeys[$p.Name] } else { $p.Name }
            $new[$key] = $p.Value
        }
    }
    ($new | ConvertTo-Json -Depth 10)
}

# Renames ~/.claude-contas to ~/.claude-accounts and fixes what pointed into it. Returns the messages.
# Does not touch the user PATH or the registry (install.ps1 does, because those are Windows only).
function Move-LegacyInstall {
    $msgs = @()
    if (-not (Test-LegacyInstall)) { return $msgs }

    # First read and convert the old config in memory: if it is broken we stop here, with nothing changed.
    $newJson = Join-Path $BaseDir 'accounts.json'
    $oldJson = Get-LegacyConfigPath
    $converted = $null
    if ($oldJson -and -not (Test-Path -LiteralPath $newJson)) {
        try { $converted = Convert-LegacyAccountsJson (Get-Content -LiteralPath $oldJson -Raw -Encoding UTF8) }
        catch { throw "$oldJson is not valid JSON ($($_.Exception.Message)). Fix it and run install.ps1 again. Nothing was changed." }
    }

    if ((Test-Path -LiteralPath $LegacyBaseDir) -and -not (Test-Path -LiteralPath $BaseDir)) {
        # Same volume: a rename, so the account folders and the junctions inside them are not touched.
        # It fails while a program (a Claude session, a terminal) has a file open inside the folder.
        try { Move-Item -LiteralPath $LegacyBaseDir -Destination $BaseDir -ErrorAction Stop }
        catch { throw "Could not rename $LegacyBaseDir to ${BaseDir}: $($_.Exception.Message) Close every Claude Code session and terminal that uses it, then run install.ps1 again. Nothing was changed." }
        $msgs += "migration: $LegacyBaseDir renamed to $BaseDir"
    }

    $oldJson = Join-Path $BaseDir 'contas.json'
    if ($null -ne $converted) {
        Write-TextNoBom $newJson $converted
        $msgs += 'migration: contas.json converted to accounts.json'
    }
    if (Test-Path -LiteralPath $oldJson) {
        # Only after accounts.json exists: the old file is kept, out of the way.
        $keep = Join-Path $BaseDir 'backups\contas.json.before-migration'
        New-Item -ItemType Directory -Force (Split-Path $keep) | Out-Null
        Move-Item -LiteralPath $oldJson $keep -Force
        $msgs += 'migration: the old contas.json is in backups\contas.json.before-migration'
    }

    foreach ($rel in $LegacyScripts) {
        $f = Join-Path $BaseDir $rel
        if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force }
    }
    Get-ChildItem -LiteralPath (Join-Path $BaseDir 'backups') -Directory -Filter 'instalacao_*' -ErrorAction SilentlyContinue | ForEach-Object {
        Rename-Item -LiteralPath $_.FullName ($_.Name -replace '^instalacao_', 'install_')
    }

    # The shared settings.json still points the status line at the old folder.
    $s = Get-MasterSettings
    if ($s.Text.Contains($LegacyStatusPath)) {
        if ($s.Valid) {
            $fixed = $s.Text.Replace($LegacyStatusPath, '.claude-accounts/statusline.ps1')
            if (Test-JsonValid $fixed) { Write-TextNoBom $s.File $fixed; $msgs += 'migration: statusLine of settings.json points to the new folder' }
        } else {
            $msgs += "migration: WARNING $($s.File) is not valid JSON, so its statusLine still points to the old folder; fix the file and run install.ps1 again"
        }
    }

    # The CLAUDE.md block used Portuguese markers; Update-ClaudeMd rewrites the block under the new ones.
    $md = Join-Path $MasterDir 'CLAUDE.md'
    if (Test-Path -LiteralPath $md) {
        $text = Get-Content -LiteralPath $md -Raw -Encoding UTF8
        if ($text.Contains($LegacyBlockBegin)) {
            $text = $text.Replace($LegacyBlockBegin, $MarkBegin).Replace($LegacyBlockEnd, $MarkEnd)
            Write-TextNoBom $md $text
            $msgs += 'migration: CLAUDE.md block markers renamed'
        }
    }
    $msgs
}

# Files that still mention the old folder and that the migration cannot safely rewrite (Claude writes
# absolute paths into its plugin registry, for example). Returns their paths; the install only reports them.
function Find-LegacyPathReferences {
    $files = @(Join-Path $MasterDir 'settings.json')
    $files += @(Get-ChildItem -LiteralPath (Join-Path $MasterDir 'plugins') -Filter '*.json' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    foreach ($f in $files) {
        if ((Test-Path -LiteralPath $f) -and ((Get-Content -LiteralPath $f -Raw -Encoding UTF8) -match '\.claude-contas')) { $f }
    }
}
