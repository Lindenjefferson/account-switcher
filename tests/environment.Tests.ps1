. (Join-Path $PSScriptRoot '_fake-accounts.ps1')
$realProfile = $env:USERPROFILE
$root = Join-Path ([IO.Path]::GetTempPath()) ("mc-env-" + [guid]::NewGuid())
. New-FakeEnvironment $root @{ main = 'a'; accounts = @{ a = @{ email = 'a@x' } } }
$env:USERPROFILE = $realProfile

Describe 'Clear-ParentSessionEnv' {
    It 'removes the inherited CLAUDE* variables and keeps CLAUDE_CONFIG_DIR' {
        $saved = @{}
        Get-ChildItem Env: | Where-Object Name -like 'CLAUDE*' | ForEach-Object { $saved[$_.Name] = $_.Value }
        try {
            $env:CLAUDE_CODE_CHILD_SESSION = '1'
            $env:CLAUDECODE = '1'
            $env:CLAUDE_CONFIG_DIR = 'C:\x'
            $env:ANTHROPIC_TEST_MC = 'stays'
            $removed = Clear-ParentSessionEnv
            $env:CLAUDE_CODE_CHILD_SESSION | Should Be $null
            $env:CLAUDECODE | Should Be $null
            $env:CLAUDE_CONFIG_DIR | Should Be 'C:\x'
            $env:ANTHROPIC_TEST_MC | Should Be 'stays'
            ($removed -contains 'CLAUDE_CODE_CHILD_SESSION') | Should Be $true
        } finally {
            Remove-Item Env:ANTHROPIC_TEST_MC, Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue
            foreach ($k in $saved.Keys) { Set-Item "Env:$k" $saved[$k] }
        }
    }

    It 'keeps the CLAUDE* variables the user set in their own environment (User/Machine)' {
        $saved = @{}
        Get-ChildItem Env: | Where-Object Name -like 'CLAUDE*' | ForEach-Object { $saved[$_.Name] = $_.Value }
        try {
            $env:CLAUDE_CODE_CHILD_SESSION = '1'
            $env:CLAUDE_CODE_GIT_BASH_PATH = 'C:\Git\bin\bash.exe'
            $removed = Clear-ParentSessionEnv @('CLAUDE_CODE_GIT_BASH_PATH')
            $env:CLAUDE_CODE_GIT_BASH_PATH | Should Be 'C:\Git\bin\bash.exe'
            $env:CLAUDE_CODE_CHILD_SESSION | Should Be $null
            ($removed -contains 'CLAUDE_CODE_GIT_BASH_PATH') | Should Be $false
        } finally {
            Remove-Item Env:CLAUDE_CODE_GIT_BASH_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:ANTHROPIC_TEST_MC, Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue
            foreach ($k in $saved.Keys) { Set-Item "Env:$k" $saved[$k] }
        }
    }
}

Describe 'Repair-SessionTemp' {
    It 'replaces TMP and TEMP that point to the Windows folder with the user temp' {
        $tmp, $temp = $env:TMP, $env:TEMP
        try {
            $env:TMP = 'C:\Windows\TEMP'
            $env:TEMP = 'c:\windows\temp\'
            $replaced = Repair-SessionTemp 'C:\Windows' 'C:\Users\x\AppData\Local\Temp'
            $env:TMP | Should Be 'C:\Users\x\AppData\Local\Temp'
            $env:TEMP | Should Be 'C:\Users\x\AppData\Local\Temp'
            ($replaced -join ',') | Should Be 'TMP,TEMP'
        } finally { $env:TMP, $env:TEMP = $tmp, $temp }
    }

    It 'fills in the one that is empty and keeps the one that points elsewhere' {
        $tmp, $temp = $env:TMP, $env:TEMP
        try {
            Remove-Item Env:TMP -ErrorAction SilentlyContinue
            $env:TEMP = 'D:\my-temp'
            $replaced = Repair-SessionTemp 'C:\Windows' 'C:\Users\x\AppData\Local\Temp'
            $env:TMP | Should Be 'C:\Users\x\AppData\Local\Temp'
            $env:TEMP | Should Be 'D:\my-temp'
            ($replaced -join ',') | Should Be 'TMP'
        } finally { $env:TMP, $env:TEMP = $tmp, $temp }
    }

    It 'does not confuse a folder that shares the Windows prefix' {
        $tmp, $temp = $env:TMP, $env:TEMP
        try {
            $env:TMP = 'C:\WindowsApps\temp'
            $env:TEMP = 'C:\WindowsApps\temp'
            @(Repair-SessionTemp 'C:\Windows' 'C:\Users\x\AppData\Local\Temp').Count | Should Be 0
            $env:TMP | Should Be 'C:\WindowsApps\temp'
        } finally { $env:TMP, $env:TEMP = $tmp, $temp }
    }
}

Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
