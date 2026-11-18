. (Join-Path $PSScriptRoot '_contas-falsas.ps1')
$perfilReal = $env:USERPROFILE
$raiz = Join-Path ([IO.Path]::GetTempPath()) ("mc-amb-" + [guid]::NewGuid())
. New-AmbienteFalso $raiz @{ principal = 'a'; contas = @{ a = @{ email = 'a@x' } } }
$env:USERPROFILE = $perfilReal

Describe 'Clear-AmbienteSessaoPai' {
    It 'tira as variaveis CLAUDE* herdadas e mantem CLAUDE_CONFIG_DIR' {
        $guardado = @{}
        Get-ChildItem Env: | Where-Object Name -like 'CLAUDE*' | ForEach-Object { $guardado[$_.Name] = $_.Value }
        try {
            $env:CLAUDE_CODE_CHILD_SESSION = '1'
            $env:CLAUDECODE = '1'
            $env:CLAUDE_CONFIG_DIR = 'C:\x'
            $env:ANTHROPIC_TESTE_MC = 'fica'
            $tirados = Clear-AmbienteSessaoPai
            $env:CLAUDE_CODE_CHILD_SESSION | Should Be $null
            $env:CLAUDECODE | Should Be $null
            $env:CLAUDE_CONFIG_DIR | Should Be 'C:\x'
            $env:ANTHROPIC_TESTE_MC | Should Be 'fica'
            ($tirados -contains 'CLAUDE_CODE_CHILD_SESSION') | Should Be $true
        } finally {
            Remove-Item Env:ANTHROPIC_TESTE_MC, Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue
            foreach ($k in $guardado.Keys) { Set-Item "Env:$k" $guardado[$k] }
        }
    }

    It 'mantem as CLAUDE* que o usuario definiu no ambiente dele (User/Machine)' {
        $guardado = @{}
        Get-ChildItem Env: | Where-Object Name -like 'CLAUDE*' | ForEach-Object { $guardado[$_.Name] = $_.Value }
        try {
            $env:CLAUDE_CODE_CHILD_SESSION = '1'
            $env:CLAUDE_CODE_GIT_BASH_PATH = 'C:\Git\bin\bash.exe'
            $tirados = Clear-AmbienteSessaoPai @('CLAUDE_CODE_GIT_BASH_PATH')
            $env:CLAUDE_CODE_GIT_BASH_PATH | Should Be 'C:\Git\bin\bash.exe'
            $env:CLAUDE_CODE_CHILD_SESSION | Should Be $null
            ($tirados -contains 'CLAUDE_CODE_GIT_BASH_PATH') | Should Be $false
        } finally {
            Remove-Item Env:CLAUDE_CODE_GIT_BASH_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:ANTHROPIC_TESTE_MC, Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue
            foreach ($k in $guardado.Keys) { Set-Item "Env:$k" $guardado[$k] }
        }
    }
}

Describe 'Clear-AmbienteSessaoPai fora das CLAUDE*' {
    It 'tira NO_COLOR e as GIT_* que a sessao pai define, para a janela nova abrir com cor' {
        $nomes = 'NO_COLOR', 'GIT_TERMINAL_PROMPT', 'GIT_EDITOR', 'GIT_ASKPASS'
        $guardado = @{}
        foreach ($n in $nomes) { $guardado[$n] = [Environment]::GetEnvironmentVariable($n, 'Process') }
        try {
            $cc = $env:CLAUDECODE
            $env:CLAUDECODE = '1'
            foreach ($n in $nomes) { Set-Item "Env:$n" '1' }
            $tirados = Clear-AmbienteSessaoPai @()
            foreach ($n in $nomes) {
                [Environment]::GetEnvironmentVariable($n, 'Process') | Should Be $null
                ($tirados -contains $n) | Should Be $true
            }
        } finally {
            foreach ($n in $nomes) { [Environment]::SetEnvironmentVariable($n, $guardado[$n], 'Process') }
            [Environment]::SetEnvironmentVariable('CLAUDECODE', $cc, 'Process')
        }
    }

    It 'tira uma GIT_ASKPASS vazia herdada, sem erro' {
        $comum = Join-Path $PSScriptRoot '..\plugins\account-switcher\skills\account-switcher\scripts\comum.ps1'
        $psi = New-Object Diagnostics.ProcessStartInfo 'powershell.exe'
        $psi.Arguments = "-NoProfile -Command `". '$comum'; `$null = Clear-AmbienteSessaoPai @(); " +
            "if (Test-Path Env:GIT_ASKPASS) { 'ficou' } else { 'saiu' }`""
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.EnvironmentVariables['GIT_ASKPASS'] = ''
        $psi.EnvironmentVariables['CLAUDECODE'] = '1'
        $p = [Diagnostics.Process]::Start($psi)
        $saida = $p.StandardOutput.ReadToEnd()
        $erro = $p.StandardError.ReadToEnd()
        $p.WaitForExit()
        $saida.Trim() | Should Be 'saiu'
        $erro | Should BeNullOrEmpty
    }

    It 'fora de uma sessao do Claude, mantem NO_COLOR (o cc digitado no shell do usuario)' {
        $antes, $cc = $env:NO_COLOR, $env:CLAUDECODE
        try {
            Remove-Item Env:CLAUDECODE -ErrorAction SilentlyContinue
            $env:NO_COLOR = '1'
            $null = Clear-AmbienteSessaoPai @()
            $env:NO_COLOR | Should Be '1'
        } finally {
            [Environment]::SetEnvironmentVariable('NO_COLOR', $antes, 'Process')
            [Environment]::SetEnvironmentVariable('CLAUDECODE', $cc, 'Process')
        }
    }

    It 'mantem NO_COLOR quando o usuario o definiu no ambiente dele (User/Machine)' {
        $antes = $env:NO_COLOR
        try {
            $env:NO_COLOR = '1'
            $tirados = Clear-AmbienteSessaoPai @('NO_COLOR')
            $env:NO_COLOR | Should Be '1'
            ($tirados -contains 'NO_COLOR') | Should Be $false
        } finally { [Environment]::SetEnvironmentVariable('NO_COLOR', $antes, 'Process') }
    }
}

Describe 'Repair-TempSessao' {
    It 'troca TMP e TEMP que apontam para a pasta do Windows pela temp do usuario' {
        $tmp, $temp = $env:TMP, $env:TEMP
        try {
            $env:TMP = 'C:\Windows\TEMP'
            $env:TEMP = 'c:\windows\temp\'
            $trocadas = Repair-TempSessao 'C:\Windows' 'C:\Users\x\AppData\Local\Temp'
            $env:TMP | Should Be 'C:\Users\x\AppData\Local\Temp'
            $env:TEMP | Should Be 'C:\Users\x\AppData\Local\Temp'
            ($trocadas -join ',') | Should Be 'TMP,TEMP'
        } finally { $env:TMP, $env:TEMP = $tmp, $temp }
    }

    It 'preenche a que estiver vazia e mantem a que ja aponta para outro lugar' {
        $tmp, $temp = $env:TMP, $env:TEMP
        try {
            Remove-Item Env:TMP -ErrorAction SilentlyContinue
            $env:TEMP = 'D:\minha-temp'
            $trocadas = Repair-TempSessao 'C:\Windows' 'C:\Users\x\AppData\Local\Temp'
            $env:TMP | Should Be 'C:\Users\x\AppData\Local\Temp'
            $env:TEMP | Should Be 'D:\minha-temp'
            ($trocadas -join ',') | Should Be 'TMP'
        } finally { $env:TMP, $env:TEMP = $tmp, $temp }
    }

    It 'nao confunde pasta com o mesmo prefixo do Windows' {
        $tmp, $temp = $env:TMP, $env:TEMP
        try {
            $env:TMP = 'C:\WindowsApps\temp'
            $env:TEMP = 'C:\WindowsApps\temp'
            @(Repair-TempSessao 'C:\Windows' 'C:\Users\x\AppData\Local\Temp').Count | Should Be 0
            $env:TMP | Should Be 'C:\WindowsApps\temp'
        } finally { $env:TMP, $env:TEMP = $tmp, $temp }
    }
}

Remove-Item -LiteralPath $raiz -Recurse -Force -ErrorAction SilentlyContinue
