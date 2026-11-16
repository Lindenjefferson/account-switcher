# cc [account] [--rc|--no-rc] [claude arguments...]   opens Claude Code as an account (default: "default" in accounts.json)
# cc -l                                               lists the accounts with the logged-in e-mail, RC and usage
# --rc / --no-rc turns Remote Control on or off for this session only (default: "rc" of the account in accounts.json).
. (Join-Path $PSScriptRoot 'common.ps1')
$null = Clear-ParentSessionEnv

$cfg = Get-Accounts
$rest = @($args)

if ($rest.Count -and $rest[0] -in '-l', '--list') {
    $(foreach ($c in $cfg.Accounts) {
        $s = if (Test-Path -LiteralPath $c.Dir) { Get-AccountStatus $c } else { $null }
        $loggedIn = if (-not $s) { 'folder not created (run setup-accounts.ps1)' }
                    elseif ($s.loggedIn) { $s.email + $(if ($s.email -ne $c.Email) { '  <-- DIFFERENT from the configured one' }) }
                    else { 'not logged in' }
        $role = @()
        if ($c.Name -eq $cfg.Publish) { $role += 'main' }
        if ($c.Name -eq $cfg.Chrome) { $role += 'Chrome' }
        $usage = Get-AccountUsage $c
        $max = Get-MaxUsage $usage
        [pscustomobject]@{
            Account  = $c.Name + $(if ($c.Name -eq $cfg.Default) { ' *' })
            Role     = ($role -join ', ')
            Expected = $c.Email
            LoggedIn = $loggedIn
            RC       = $(if ($c.Rc) { 'on' } else { 'off' })
            Usage    = $(if ($null -ne $max -and $max -ge $cfg.UsageWarning) { '! ' }) + (Format-Usage $usage)
        }
    }) | Format-Table -AutoSize | Out-String -Width 300 | Write-Host
    Write-Host '* = default account (cc with no argument); Chrome = account logged in to the Claude in Chrome extension'
    Write-Host "RC = Remote Control when opening with cc (change it on the spot with --rc / --no-rc); ! = usage >= $($cfg.UsageWarning)%"
    return
}

$account = $cfg.Accounts | Where-Object Name -eq $cfg.Default
if ($rest.Count -and -not "$($rest[0])".StartsWith('-')) {
    $account = $cfg.Accounts | Where-Object Name -eq $rest[0]
    if (-not $account) {
        Write-Host "Account '$($rest[0])' does not exist. Accounts: $($cfg.Accounts.Name -join ', ')" -ForegroundColor Red
        return
    }
    $rest = @($rest | Select-Object -Skip 1)
}
$rc = Split-RcArgs $account $rest
$rest = $rc.Rest

foreach ($m in (Sync-AccountLinks $account)) { Write-Host "[$($account.Name)] $m" -ForegroundColor DarkGray }
try {
    $m = Disable-SharedRc
    if ($m) { Write-Host "[$($account.Name)] $m" -ForegroundColor DarkGray }
} catch {
    Write-Host "Could not check RC in the shared settings.json: $($_.Exception.Message)" -ForegroundColor Yellow
}
if ($rc.UserSettings) { Write-Host 'You passed --settings: RC follows whatever it says.' -ForegroundColor Yellow }

$s = Get-AccountStatus $account
if (-not $s.loggedIn) {
    Write-Host "Account $($account.Name) is not logged in yet: use /login with $($account.Email)" -ForegroundColor Yellow
} elseif ($s.email -ne $account.Email) {
    Write-Host "WARNING: the folder of account $($account.Name) is logged in as $($s.email), but $($account.Email) was expected." -ForegroundColor Red
    if ((Read-Host 'Open anyway? (y/N)') -notmatch '^[yY]') { return }
}

# High usage: warns, suggests the account with the most headroom and asks (with -p it only warns, on stderr).
$nonInteractive = [bool]($rest | Where-Object { $_ -in '-p', '--print' })
$usage = Get-AccountUsage $account
$max = Get-MaxUsage $usage
if ($null -ne $max -and $max -ge $cfg.UsageWarning) {
    $lines = @("Account $($account.Name) has high usage: $(Format-Usage $usage)")
    $usages = @{}
    foreach ($o in ($cfg.Accounts | Where-Object Name -ne $account.Name)) { $usages[$o.Name] = Get-AccountUsage $o }
    $suggestion = Select-SuggestedAccount $usages $account.Name
    if ($suggestion -and (Get-MaxUsage $usages[$suggestion]) -lt $max) { $lines += "Suggestion: cc $suggestion ($(Format-Usage $usages[$suggestion]))" }
    if ($nonInteractive) {
        $lines | ForEach-Object { [Console]::Error.WriteLine($_) }
    } else {
        $lines | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
        if ((Read-Host 'Open anyway? (y/N)') -notmatch '^[yY]') { return }
    }
}

# Session name = folder (account), unless the user is resuming or already named it.
$extra = @()
if (-not ($rest | Where-Object { $_ -in '-n', '--name', '-r', '--resume', '-c', '--continue', '-p', '--print' })) {
    $extra = @('-n', ('{0} ({1})' -f (Split-Path -Leaf (Get-Location)), $account.Name))
}
$claudeArgs = Get-ClaudeArgs $rc

try {
    Invoke-WithAccount $account { & $Claude @extra @claudeArgs }
} finally {
    $null = Sync-AccountLinks $account
}
