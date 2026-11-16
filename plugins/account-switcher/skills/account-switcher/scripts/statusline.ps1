# Claude Code status line: "<account> . Session: x% (resets in 2h05) . Week: y% (resets in 3d 4h)",
# with the percentage in yellow from usageWarning and red from 95%. Claude Code sends the session JSON on
# stdin and reads the output as UTF-8 (hence the encoding switch: the Windows PowerShell 5.1 default is the OEM codepage).
# On any failure it writes an empty line.
try {
    [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false
    . (Join-Path $PSScriptRoot 'common.ps1')
    $data = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $account = try { Get-CurrentAccount } catch { $null }
    $warn = try { (Get-Accounts).UsageWarning } catch { 80 }
    [Console]::Out.Write((Format-StatusLine $data $account $warn))
} catch {
    [Console]::Out.Write('')
}
