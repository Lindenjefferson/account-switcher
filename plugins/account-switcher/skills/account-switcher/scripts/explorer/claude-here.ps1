# Called by claude-here.cmd. Explorer does not pass the current folder to App Paths commands,
# so we take the folder of the front-most Explorer window (active tab = window title).
. (Join-Path $PSScriptRoot '..\common.ps1')
$null = Repair-SessionTemp
Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern IntPtr GetTopWindow(IntPtr h);
[DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
'@

function Get-ExplorerFolder {
    $h = [W.U]::GetTopWindow([IntPtr]::Zero)
    while ($h -ne [IntPtr]::Zero) {
        $cls = New-Object System.Text.StringBuilder 256
        [void][W.U]::GetClassName($h, $cls, 256)
        if ($cls.ToString() -eq 'CabinetWClass' -and [W.U]::IsWindowVisible($h)) {
            $title = New-Object System.Text.StringBuilder 512
            [void][W.U]::GetWindowText($h, $title, 512)
            $tabs = @((New-Object -ComObject Shell.Application).Windows() | Where-Object { $_.HWND -eq [int64]$h })
            $tab = $tabs | Where-Object { $_.LocationName -eq $title.ToString() } | Select-Object -First 1
            if (-not $tab) { $tab = $tabs | Select-Object -First 1 }
            if ($tab) { try { return $tab.Document.Folder.Self.Path } catch { } }
            return $null
        }
        $h = [W.U]::GetWindow($h, 2)  # GW_HWNDNEXT
    }
}

$folder = Get-ExplorerFolder
if ($folder -and (Test-Path -LiteralPath $folder -PathType Container)) { Set-Location -LiteralPath $folder }

& (Join-Path $PSScriptRoot '..\cc.ps1') @args
