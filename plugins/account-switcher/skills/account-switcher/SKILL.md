---
name: account-switcher
description: 'Instala e mantém várias contas do Claude Code no Windows (uma principal e quantas secundárias quiser), alternadas com `cc <conta>` sem relogar (CLAUDE_CONFIG_DIR por conta, resto compartilhado com ~/.claude), mais o atalho "cc" na barra de endereço do Explorer. Use para instalar num PC novo, adicionar/remover conta secundária, trocar a conta principal, reinstalar depois de atualizar o plugin, desfazer, diagnosticar o `cc`, ou abrir uma sessão de outra conta (ex.: a principal, para publicar um artefato). Também funciona no macOS e no Linux (scripts bash em scripts-unix/, comando cca): use as instruções da seção "macOS and Linux" quando o sistema não for Windows.'
---

# Account Switcher

O usuário tem **uma conta principal** e **quantas contas secundárias quiser**:
- A principal é a padrão do `cc` e onde os artefatos são publicados, salvo indicação explícita do usuário (com confirmação).
- As secundárias usam o mesmo ambiente e só mudam o login, por exemplo para ter mais cota.
- Os nomes das contas são escolhidos pelo usuário. Não presuma nomes nem quantidade.

Os scripts ficam na pasta `scripts/` ao lado deste SKILL.md e são instalados em `~/.claude-contas`. Rode-os sempre com `powershell -NoProfile -ExecutionPolicy Bypass -File <script>`: a política de execução padrão do Windows bloqueia .ps1.

**Which platform?** On Windows, follow everything below. On macOS or Linux (`uname -s` prints `Darwin` or `Linux`), skip to [macOS and Linux](#macos-and-linux) at the end of this file: the scripts, the config file and the command name are different there.

## Como funciona (para explicar ao usuário)
- Cada conta tem uma pasta de config própria (`CLAUDE_CONFIG_DIR`) com seu login (`.credentials.json`) e seu `.claude.json`.
- Todo o resto aponta para `~/.claude` (a "pasta mestre"): `settings.json`, `history.jsonl`, `CLAUDE.md`, `keybindings.json` por link de arquivo; `projects/`, `skills/`, `plugins/`, `sessions/` etc. por junction. Assim, histórico, memória, skills, plugins e a lista de sessões são iguais em todas as contas.
- A conta já logada em `~/.claude` usa a própria pasta mestre (`"pasta": "~/.claude"`) e roda **sem** `CLAUDE_CONFIG_DIR`.
- `cc [conta] [args]` abre o Claude na conta (sem conta = padrão), confere o e-mail logado com `claude auth status --json` e nomeia a sessão "pasta (conta)". `cc -l` lista as contas, se o RC liga por padrão em cada uma e o uso de cada uma (janela de 5h e semanal, com o tempo até reiniciar).
- **Remote Control por conta:** o `settings.json` é compartilhado, então o `cc` decide o RC de cada sessão passando `--settings ~/.claude-contas/rc/ligado.json` ou `desligado.json`. Liga só nas contas com `"rc": true` no `contas.json`; `cc <conta> --rc [nome]` liga e `--no-rc` desliga, só naquela sessão. O `settings.json` compartilhado fica com `remoteControlAtStartup: false` (gravado pelo `setup-contas.ps1` e conferido a cada `cc`), para que sessões abertas sem o `cc` (claude direto, IDE, app) não liguem o RC.
- **Uso:** o `cc` consulta `api.anthropic.com/api/oauth/usage` com o token lido, só em memória, do `.credentials.json` da própria conta. Se o token venceu (ele só é renovado quando a conta roda), mostra o último uso que a conta salvou no `.claude.json`, com o horário. Ao abrir uma conta com uso igual ou acima de `avisoUso` (padrão 80) na janela de 5h ou na semanal, o `cc` avisa, sugere a conta com mais folga e pergunta antes de abrir (no modo `-p`, só avisa em stderr).
- **Status line:** `statusline.ps1` mostra `<conta> · Sessão: x% (reinicia em 2h05) · Semana: y% (reinicia em 3d 4h)`, com a porcentagem em amarelo a partir de `avisoUso` e em vermelho a partir de 95%. O `setup-contas.ps1` registra no `settings.json` só se não houver outra status line.
- Na barra de endereço do Explorer, o atalho (padrão `cc`) abre o PowerShell na pasta atual com `cc`. O Explorer não repassa a pasta para comandos do App Paths, então `explorer/claude-aqui.ps1` descobre a pasta pela janela do Explorer que está na frente.
- Uma conta nova recebe só as chaves de configuração do `~/.claude.json` (MCPs, projetos confiáveis etc.), nunca os dados da conta. Conectores do claude.ai são por conta e se configuram no site.

## Instalar num PC novo
1. Rode `scripts/instalar.ps1 -Verificar`. Ele mostra o caminho do `claude.exe`, se há symlink (modo desenvolvedor) e conflitos. Se houver PROBLEMA, resolva com o usuário antes de seguir.
2. Rode `claude auth status --json` (sem `CLAUDE_CONFIG_DIR`) para saber qual e-mail já está logado em `~/.claude`.
3. Pergunte ao usuário, de uma vez:
   - nome curto e e-mail da **conta principal**;
   - nome curto e e-mail de cada **secundária**, quantas forem;
   - em qual conta a extensão Claude in Chrome está logada, se o usuário usa a extensão (campo `chrome`; o Claude Code não consegue detectar isso sozinho);
   - o atalho do Explorer (padrão `cc`).
   - em quais contas o Remote Control deve ligar por padrão (campo `"rc": true`; sem ele, o RC fica desligado). Contas de trabalho geralmente ficam desligadas.
   O caso comum é a principal já estar logada em `~/.claude` (passo 2) e as secundárias serem adicionadas depois.
   - **Só uma conta tem `"pasta": "~/.claude"`:** a que está logada lá. As outras ficam em `~/.claude-contas/<nome>` sem precisar do campo. Se nenhuma conta tiver `pasta`, a principal usa `~/.claude`.
   - Se o e-mail logado em `~/.claude` for o de uma secundária, é ela que recebe `"pasta": "~/.claude"`, e a principal ganha pasta própria (com um `/login`). Explique isso ao usuário.
   - Não copie `.credentials.json` de uma pasta para outra.
4. Escreva `~/.claude-contas/contas.json` em UTF-8 sem BOM, no formato de `scripts/contas.exemplo.json`, com `"principal": "<nome>"`. Se o usuário quiser que o `cc` sem argumento abra outra conta, acrescente `"padrao": "<nome>"`; a principal continua sendo a única que publica.
5. Rode `scripts/instalar.ps1`. Ele faz backup na primeira vez, copia os scripts, cria as pastas e os links, põe `~/.claude-contas/bin` no PATH, registra o atalho do Explorer e escreve o bloco de contas no `~/.claude/CLAUDE.md` (entre marcas `<!-- account-switcher:... -->`, preservando o resto do arquivo).
6. Passe ao usuário os próximos passos:
   - abrir um terminal **novo** (o PATH mudou);
   - rodar `cc <conta>` e `/login` uma vez em cada conta não logada;
   - conferir com `cc -l`.

## Manutenção
- **Adicionar conta secundária:** acrescente a conta em `~/.claude-contas/contas.json` e rode `~/.claude-contas/setup-contas.ps1`, que é idempotente e também atualiza o CLAUDE.md. Depois o usuário roda `cc <nova>` e faz `/login`.
- **Mudar o RC padrão de uma conta ou o limite do aviso de uso:** edite `"rc"` da conta ou `"avisoUso"` no `contas.json`. Vale no próximo `cc`.
- **Trocar a principal, o padrão, a conta do Chrome ou o atalho:** edite `contas.json` e rode `setup-contas.ps1`. Se mudou o atalho, rode `instalar.ps1`, que registra o novo; apague à mão a chave antiga em `HKCU\Software\Microsoft\Windows\CurrentVersion\App Paths\<antigo>.exe`.
- **Remover uma conta:** primeiro tire os links da pasta dela com `. ~/.claude-contas/comum.ps1; Remove-LinksConta ((Get-Contas).Contas | ? Nome -eq '<conta>')`. Confira que não sobrou link na pasta (`Get-ChildItem -Force | ? LinkType`). Só então apague a pasta, tire a conta do `contas.json` e rode `setup-contas.ps1`.
- **Depois de atualizar o plugin:** rode `scripts/instalar.ps1` de novo para copiar os scripts novos. Ele não refaz o backup nem toca no `contas.json`.
- **Desfazer:** `~/.claude-contas/desfazer-contas.ps1` remove links, PATH, atalho e o bloco do CLAUDE.md. Com `-ApagarPastas`, apaga também as pastas das contas extras.

## Publicar artefato em outra conta
- **Conta alvo:** a principal, se o usuário não indicou nenhuma. Se ele indicou outra, confirme antes com AskUserQuestion, mostrando nome e e-mail ("Publicar na conta X (email), não na principal?"). Só siga com um sim. Nunca troque a conta alvo por conta própria.
1. Confira a conta da sessão atual com `claude auth status --json`. Se já for a conta alvo, publique aqui.
2. Senão, grave o conteúdo num arquivo e procure com ListAgents uma sessão cujo nome termine em "(<conta alvo>)".
3. Se não houver, rode `~/.claude-contas/abrir-conta.ps1 <conta alvo> <pasta> [-Rc | -NoRc]`, que abre uma aba nova do Windows Terminal (sem ele, uma janela), e procure a sessão de novo.
4. Peça por SendMessage que ela confira a própria conta com `claude auth status --json` e publique o arquivo.
5. O `cc` tira as variáveis `CLAUDE*` herdadas desta sessão (menos `CLAUDE_CONFIG_DIR`); sem isso, a janela nova abriria com "Transcript saving is off" e não apareceria no ListAgents.
6. O modo automático dela pede a aprovação do usuário na janela dela. Isso é esperado; avise o usuário.

Claude in Chrome não precisa disso: funciona a partir de qualquer conta. O campo `chrome` do `contas.json` só registra em qual conta a extensão está logada (aparece no `cc -l` e no CLAUDE.md).

## Nunca
- `Remove-Item -Recurse` (ou apagar pelo Explorer) numa pasta de conta que ainda tem junctions. Isso apaga o conteúdo real de `~/.claude`. Use `Remove-LinksConta` ou `desfazer-contas.ps1`.
- Copiar ou mover `.credentials.json` entre pastas: o token é renovado e a cópia deixa de valer.
- Definir `CLAUDE_CONFIG_DIR` apontando para `~/.claude`: o Claude passaria a procurar `.claude.json` dentro da pasta.
- Usar `$PROFILE` para o `cc`: em PCs com a política de execução padrão, ele não carrega. O `cc` é um `.cmd` no PATH de propósito.

## Diagnóstico
- **Digitar o atalho no Explorer abre uma pasta em vez do Claude:** existe uma pasta com esse nome (o Explorer navega antes de executar). Troque `atalhoExplorer`. `instalar.ps1 -Verificar` procura esses conflitos.
- **Atalho do Explorer dá "Não é possível localizar o tipo [W.U]":** o `Add-Type` falhou porque `TMP` aponta para `C:\Windows\TEMP` (falta `TMP` no ambiente do usuário). O `claude-aqui.ps1` corrige isso na própria sessão; se ainda acontecer, reinstale os scripts. Para corrigir no Windows, crie `TMP` do usuário igual ao `TEMP` (`%USERPROFILE%\AppData\Local\Temp`).
- **"cc não é reconhecido":** o terminal foi aberto antes da instalação. Abra outro.
- **Aviso "logada como X, esperado Y":** o `/login` foi feito com o e-mail errado naquela pasta. Rode `/logout` e `/login` dentro de `cc <conta>`.
- **Mensagem "alteração levada para a mestre":** um programa salvou por cima de um link e o `cc` refez o link. O conteúdo anterior fica em `~/.claude-contas/backups`.
- **Uso aparece como "(salvo HH:mm)":** o token daquela conta venceu, então o valor é o último que ela salvou. Abrir a conta com `cc <conta>` atualiza. O `cc` não renova o token sozinho de propósito.
- **Status line de conta e uso não aparece:** o `settings.json` já tinha outra `statusLine`, e o instalador não mexe nela. Para usar a nossa, tire a outra e rode `setup-contas.ps1`.
- **RC ligou numa conta sem `rc`:** confira se alguém pôs `remoteControlAtStartup: true` no `settings.json` compartilhado (o `cc` volta para `false` ao abrir) ou se a sessão foi aberta com `--rc`.

# macOS and Linux

Same idea, native bash scripts. They live in `scripts-unix/` next to this file and are installed into `~/.claude-accounts`. Run them with `bash <script>` (no execution-policy issues, unlike PowerShell).

## What differs from Windows (explain it to the user)
- Config file: `~/.claude-accounts/accounts.json`, with English keys (`main`, `default`, `publish`, `command`, `chrome`, `usageWarning`, `accounts.<name>.email|dir|rc`). The format is in `scripts-unix/accounts.example.json` and in the README ("macOS and Linux").
- The command is `cca` by default, set by `command`. It is never `cc`: that is the C compiler on these systems. The installer reports any name that is already taken on `PATH`.
- Shared files and folders are symlinks. Only the login stays per account: on Linux it is `.credentials.json`, on macOS it is in the Keychain. Never read, copy or move either.
- On macOS `cca -l` cannot show live usage, because the token is in the Keychain; it shows the last usage Claude saved for the account ("saved"). The status line is live on both systems.
- `PATH` is set with a marked block in the shell startup file (zsh, bash, fish), at the END of `PATH`. `install.sh --no-path` skips it.
- There is no Explorer shortcut.
- Requirements: bash 3.2+, `jq`, `curl`, `claude` already logged in to one account.

## Install on a new computer
1. Run `bash scripts-unix/install.sh --check`. It shows the `claude` path and any PROBLEM (missing `jq`, taken command name). Fix problems with the user before going on.
2. Run `claude auth status --json` (without `CLAUDE_CONFIG_DIR`) to see which e-mail is already logged in to `~/.claude`.
3. Ask the user, in one go: short name and e-mail of the main account and of each secondary one; which account the Claude in Chrome extension is logged in to (if any); which accounts should turn Remote Control on by default (`"rc": true`); and the command name if they do not want `cca`.
   - Only ONE account has `"dir": "~/.claude"`: the one logged in there. If the logged-in e-mail belongs to a secondary account, that account gets `"dir": "~/.claude"` and the main one gets its own folder (and a `/login`). Explain this.
   - Never copy `.credentials.json` or Keychain items between accounts.
4. Write `~/.claude-accounts/accounts.json` (UTF-8, valid JSON) following `scripts-unix/accounts.example.json`, with `"main": "<name>"`.
5. Run `bash scripts-unix/install.sh`. It takes a one-time backup, copies the scripts, creates folders and links, adds the `PATH` block, registers the status line (only if there is none), turns `remoteControlAtStartup` off in the shared `settings.json`, writes the accounts block in `~/.claude/CLAUDE.md`, and ends with `cca -l`.
6. Tell the user: open a **new** terminal (PATH changed), run `cca <account>` and `/login` once in each account that is not logged in, then check with `cca -l`.

## Maintenance
- **Add a secondary account:** add it to `accounts.json` and run `bash ~/.claude-accounts/setup-accounts.sh` (idempotent; it also refreshes CLAUDE.md). Then the user runs `cca <new>` and `/login`.
- **Change RC default, the usage warning, main/default/publish account, the chrome account or the command name:** edit `accounts.json`, then run `setup-accounts.sh` (or `install.sh` if the command name changed; the old wrapper is removed).
- **Remove one account:** remove its links first (`. ~/.claude-accounts/lib.sh; load_accounts; select_account <name>; remove_account_links`) and check that `find ~/.claude-accounts/<name> -maxdepth 1 -type l` prints nothing. Only then delete the folder, remove the entry from `accounts.json` and run `setup-accounts.sh`.
- **After updating the plugin:** run `bash scripts-unix/install.sh` again. It does not redo the backup or touch `accounts.json`.
- **Undo:** `bash ~/.claude-accounts/uninstall.sh [--delete-folders]` removes the links, the `PATH` block, the CLAUDE.md block and our status line, and disables the command. `--delete-folders` also deletes the extra account folders (their logins).

## Publishing an artifact from another account
Same rules as above (target account = the main one unless the user names another, and then confirm with AskUserQuestion). To open a session of the target account use `bash ~/.claude-accounts/open-account.sh <account> <folder> [--rc | --no-rc]`: it opens Terminal.app or iTerm2 on macOS, a tmux window inside tmux, or the first terminal emulator it finds on Linux. Then find the session with ListAgents (its name ends in "(<account>)") and ask it, by SendMessage, to check its account and publish.

## Never
- `rm -r` with a trailing slash on a link inside an account folder (`~/.claude-accounts/<name>/skills/`): it enters the target. Use `uninstall.sh`.
- Read, copy, move or print credentials (`.credentials.json`, Keychain items).
- Set `CLAUDE_CONFIG_DIR` to `~/.claude`: the master-folder account runs without the variable.

## Diagnosis
- **"command not found: cca":** the terminal was opened before the install, or `--no-path` was used. Open a new terminal or add `~/.claude-accounts/bin` to `PATH`.
- **Installer says a command named X already exists:** pick another `command` in `accounts.json`.
- **"WARNING: the folder of account X is logged in as Y":** `/login` used the wrong e-mail in that folder. Run `/logout` and `/login` inside `cca <account>`.
- **"change made in account X was carried over to the master folder":** a program overwrote a link; the previous version is in `~/.claude-accounts/backups`.
- **Usage shows "(saved HH:MM)":** the token is expired or, on macOS, kept in the Keychain. Opening the account updates it.
- **Status line does not show up:** `settings.json` already had another `statusLine`; the installer never replaces it.
- **RC turned on in an account without `rc`:** check for `remoteControlAtStartup: true` in the shared `settings.json` (`cca` resets it to `false`) or a session opened with `--rc`.
- **"invalid settings.json":** the JSON is broken, so nothing was written. Fix it and run `setup-accounts.sh`.
