# Account Switcher

> *In English:* a Claude Code plugin that runs several Claude Code accounts on one computer, switched with a short command (`cc <account>` on Windows, `cca <account>` on macOS and Linux) without logging in again. Only the login is per account; settings, history, memory, skills and plugins are shared. It also shows each account's usage. **Windows** (PowerShell) and **macOS / Linux** (bash) are both supported. The Windows docs are in Portuguese; the macOS / Linux docs are in English.

Várias contas do [Claude Code](https://code.claude.com) no mesmo PC com Windows (e, em inglês, no macOS e no Linux, veja [macOS and Linux](#macos-and-linux)): uma conta principal e quantas secundárias você quiser, alternadas com `cc <conta>` sem relogar. Cada conta tem só o login separado; o resto do ambiente é o mesmo em todas.

O objetivo é trocar de conta (por exemplo, para ter mais cota) sem perder nada: o histórico, a memória, as skills, os plugins e a lista de sessões continuam iguais, qualquer que seja a conta aberta.

## Propósito e princípios

- **Só o login muda.** Cada conta tem o próprio `.credentials.json` e `.claude.json`; todo o resto aponta para `~/.claude`.
- **Uma conta principal.** É onde os artefatos são publicados e, se o `contas.json` não disser outra em `padrao`, a que o `cc` abre sem argumento. Publicar em outra conta só com a sua confirmação.
- **Nada de credencial copiada.** Cada conta faz o próprio `/login`. O token nunca é copiado entre pastas nem gravado em disco pelo `cc`.
- **Reversível.** A instalação faz backup na primeira vez e `desfazer-contas.ps1` tira tudo o que ela pôs.

## Como funciona

- Cada conta tem uma pasta de config própria (`CLAUDE_CONFIG_DIR`) em `~/.claude-contas/<conta>`, com o login dela.
- Dentro dessa pasta, `settings.json`, `history.jsonl`, `CLAUDE.md` e `keybindings.json` são links para os de `~/.claude` (a "pasta mestre"), e `projects/`, `skills/`, `plugins/`, `sessions/` e as outras são junctions. A conta que já estava logada em `~/.claude` usa a própria pasta mestre e roda sem `CLAUDE_CONFIG_DIR`.
- `cc [conta]` abre o Claude na conta (sem conta, a padrão), confere o e-mail logado e nomeia a sessão "pasta (conta)".
- `cc -l` lista as contas com o uso de cada uma (janela de 5h e semanal, com o tempo até reiniciar) e se o Remote Control liga por padrão nela.
- Ao abrir uma conta com uso acima do limite (padrão 80%), o `cc` avisa, sugere a conta com mais folga e pergunta antes de abrir.
- A status line mostra a conta e o uso da sessão e da semana, em amarelo a partir do limite e em vermelho a partir de 95%.
- **Remote Control por conta:** liga só nas contas com `"rc": true` no `contas.json`; `cc <conta> --rc` e `--no-rc` mudam só aquela sessão. Sessões abertas sem o `cc` não ligam o RC.
- **Atalho no Explorer:** digitar `cc` (ou `cc <conta>`) na barra de endereço abre o Claude na pasta atual.
- O bloco de regras das contas é escrito no `~/.claude/CLAUDE.md` entre as marcas `<!-- account-switcher:... -->`, sem mexer no resto do arquivo.

## Começo rápido

**Você precisa de:**

- Windows com o Windows PowerShell 5.1 (já vem no Windows; os scripts chamam `powershell.exe`);
- [Claude Code](https://code.claude.com) instalado e logado numa conta;
- o modo desenvolvedor do Windows, de preferência: sem ele, os arquivos compartilhados usam hard link em vez de symlink.

**Instalar:** o marketplace mora neste repositório:

```
/plugin marketplace add Lindenjefferson/account-switcher
/plugin install account-switcher@account-switcher
```

Depois, numa sessão do Claude Code, peça **"instala a skill account-switcher"**. Ela verifica o PC, pergunta as contas (nome curto e e-mail da principal e das secundárias, a conta do Claude in Chrome, o atalho do Explorer e em quais contas o RC liga), instala e diz o que falta.

**Instalar sem a skill:** o `instalar.ps1` só exige que o `~/.claude-contas/contas.json` já exista. Com o repositório clonado (ou a pasta do plugin instalado), a partir de `plugins/account-switcher/skills/account-switcher/scripts/`:

1. Copie `contas.exemplo.json` para `~/.claude-contas/contas.json` e edite com as suas contas (UTF-8 sem BOM; as chaves estão em "O `contas.json`", abaixo).
2. Rode `powershell -NoProfile -ExecutionPolicy Bypass -File .\instalar.ps1 -Verificar`. Ele mostra onde está o `claude.exe`, se há symlink e conflitos, sem alterar nada; resolva o que aparecer como PROBLEMA.
3. Rode o mesmo comando sem `-Verificar`. Ele faz backup na primeira vez, copia os scripts para `~/.claude-contas`, cria as pastas e os links, põe `~/.claude-contas/bin` no PATH, registra o atalho do Explorer, escreve o bloco no `~/.claude/CLAUDE.md` e termina com um `cc -l`.

**Usar:**

1. Abra um terminal **novo** (a instalação mudou o PATH).
2. Rode `cc <conta>` e faça `/login` uma vez em cada conta que ainda não está logada.
3. Confira com `cc -l`. Daí em diante, é só `cc <conta>` no terminal ou na barra do Explorer.

## macOS and Linux

The same idea for macOS and Linux, written in bash (it runs on the bash 3.2 that ships with macOS) instead of PowerShell. It lives in [`plugins/account-switcher/skills/account-switcher/scripts-unix/`](plugins/account-switcher/skills/account-switcher/scripts-unix) and is independent from the Windows scripts: nothing in the Windows version changed.

**What is the same:** every account has its own folder (`CLAUDE_CONFIG_DIR`) with its own login, and everything else (settings, history, `CLAUDE.md`, projects, skills, plugins, sessions) is shared with `~/.claude`. One main account, per-account Remote Control, usage per account in `-l` and in the status line, a warning (and a suggestion of another account) when usage is high, and a `CLAUDE.md` block with the rules.

**What is different:**

| | Windows | macOS / Linux |
|---|---|---|
| Command | `cc` | `cca` by default (key `command`). `cc` is the C compiler on these systems, so the installer refuses a name that already exists on `PATH` |
| Scripts and config | `~/.claude-contas`, `contas.json` | `~/.claude-accounts`, `accounts.json` (English keys, see below) |
| Shared folders and files | junctions, symlinks or hard links | symlinks |
| `PATH` | user `PATH` | a marked block in your shell startup file (zsh, bash and fish are handled), appended at the **end** of `PATH`. `--no-path` skips it |
| Explorer address bar shortcut | yes | not applicable |
| Opening another account's session | `abrir-conta.ps1` (Windows Terminal) | `open-account.sh` (Terminal.app or iTerm2 on macOS; tmux or the first terminal emulator found on Linux) |
| Live usage | token from `.credentials.json` | Linux: same, when Claude keeps its login in `.credentials.json`. **macOS keeps the login in the Keychain**, which the scripts never read, so `-l` shows the last usage Claude saved for the account (marked "saved"). The **status line** is live on both, because Claude Code sends it the numbers |

**Requirements:** bash 3.2 or newer, [`jq`](https://jqlang.github.io/jq/) (preinstalled on recent macOS; otherwise `brew install jq` or your package manager), `curl`, and Claude Code installed and logged in to one account.

**Install:** the marketplace is the same (`/plugin marketplace add Lindenjefferson/account-switcher`, then `/plugin install account-switcher@account-switcher`), then ask Claude to "install the account-switcher skill" and it will follow the macOS / Linux steps in [`SKILL.md`](plugins/account-switcher/skills/account-switcher/SKILL.md). Without the skill, from the plugin folder:

1. Copy `accounts.example.json` to `~/.claude-accounts/accounts.json` and edit it.
2. Run `bash install.sh --check`. It prints where `claude` is and any problem (missing `jq`, a command name that is already taken) without changing anything.
3. Run `bash install.sh`. It makes a one-time backup, copies the scripts to `~/.claude-accounts`, creates the account folders and links, adds the `PATH` block, writes the `CLAUDE.md` block and ends with `cca -l`.
4. Open a **new** terminal, run `cca <account>` and `/login` once in every account that is not logged in yet.

**`accounts.json`:**

| Key | What it is | If missing |
|---|---|---|
| `main` | Name of the main account: the one that publishes artifacts and, without `default`, the one `cca` opens with no argument | Required |
| `default` | Account `cca` opens with no argument | The main one |
| `publish` | Account that publishes artifacts | The main one |
| `command` | Name of the command installed in `~/.claude-accounts/bin` | `cca` |
| `chrome` | Account the Claude in Chrome extension is logged in to (informational) | Not set |
| `usageWarning` | Usage percentage (1 to 100) from which `cca` warns and the status line turns yellow | 80 |
| `accounts` | One entry per account; key = short name (letters, digits, `_`, `.`, `-`) | Required |
| `accounts.<name>.email` | Expected e-mail; the command compares it with the logged-in one and warns on a mismatch | |
| `accounts.<name>.dir` | Config folder. Only one account may use `"~/.claude"` (the master folder) | `~/.claude-accounts/<name>`; if no account has `dir`, the main one uses `~/.claude` |
| `accounts.<name>.rc` | `true` turns Remote Control on when opening the account with `cca` | Off |

**Use:** `cca <account>` opens Claude in that account (`cca` alone opens the default), `cca -l` lists the accounts, `--rc` / `--no-rc` change Remote Control for that session only. Everything after the account name goes to `claude`. Maintenance (`setup-accounts.sh` after adding an account, `install.sh` after updating the plugin, `uninstall.sh [--delete-folders]`) is described in [`SKILL.md`](plugins/account-switcher/skills/account-switcher/SKILL.md).

**Safety:** it never touches the Keychain or any credentials file; the usage token (Linux) is read in memory and handed to `curl` through stdin, so it does not show up in `ps`; `settings.json` and `CLAUDE.md` are edited in place with text insertions (your formatting and symlinks are kept) and are not written at all if the JSON is already broken; `uninstall.sh` removes only links that point into `~/.claude`.

**Tests:** `bash tests/unix/run.sh` (no framework, no network, a fake `HOME` per test file, so your `~/.claude` is never touched). They pass on macOS (bash 3.2) and on Debian (bash 5.2, GNU `date`, `jq` 1.6).

## O `contas.json`

Fica em `~/.claude-contas/contas.json`, no formato de [`contas.exemplo.json`](plugins/account-switcher/skills/account-switcher/scripts/contas.exemplo.json). Chaves que os scripts leem:

| Chave | O que é | Se faltar |
|---|---|---|
| `principal` | Nome da conta principal: a que publica artefatos e, sem `padrao`, a que o `cc` abre sem argumento | Obrigatória |
| `padrao` | Conta que o `cc` abre sem argumento, quando não é a principal | A principal |
| `publicar` | Conta que publica artefatos (é a que aparece como "principal" no `cc -l` e no bloco do `CLAUDE.md`) | A principal |
| `atalhoExplorer` | O que se digita na barra de endereço do Explorer | `cc` |
| `chrome` | Nome da conta em que a extensão Claude in Chrome está logada; só informativo (aparece no `cc -l` e no `CLAUDE.md`), porque o Claude Code não detecta isso | Sem conta do Chrome |
| `avisoUso` | Porcentagem de uso (1 a 100) a partir da qual o `cc` avisa e a status line fica amarela | 80 |
| `contas` | Objeto com uma entrada por conta, chave = nome curto da conta | Obrigatória |
| `contas.<nome>.email` | E-mail esperado; o `cc` compara com o login da pasta e avisa se for outro | — |
| `contas.<nome>.pasta` | Pasta de config da conta. Só uma conta pode ter `"~/.claude"` (a pasta mestre): a que já está logada lá | `~/.claude-contas/<nome>`; se nenhuma conta tiver `pasta`, a principal usa `~/.claude` |
| `contas.<nome>.rc` | `true` liga o Remote Control ao abrir a conta com o `cc` | Desligado |

O `setup-contas.ps1` confere que `padrao`, `publicar` e `chrome` apontam para contas existentes e que só uma conta usa a pasta mestre.

## Componentes

| Peça | O que faz |
|---|---|
| [`SKILL.md`](plugins/account-switcher/skills/account-switcher/SKILL.md) | Roteiro de instalação, manutenção, diagnóstico e regras |
| `comum.ps1` | Funções que todos os outros scripts carregam: leitura do `contas.json`, links e junctions das contas, uso por conta, Remote Control, status line e o bloco do `CLAUDE.md` |
| `instalar.ps1` | Verifica o PC (`-Verificar`), faz backup e instala tudo |
| `setup-contas.ps1` | Refaz pastas, links e o bloco do `CLAUDE.md` a partir do `contas.json`; idempotente |
| `desfazer-contas.ps1` | Remove links, PATH, atalho e o bloco do `CLAUDE.md` |
| `cc.ps1` e `bin/cc.cmd` | O comando `cc` |
| `statusline.ps1` | A status line com conta e uso |
| `abrir-conta.ps1` | Abre uma aba do Windows Terminal (ou uma janela) em outra conta |
| `explorer/` | O atalho da barra de endereço do Explorer |
| `modelo-CLAUDE.md` | Modelo do bloco de regras do `~/.claude/CLAUDE.md` |
| `contas.exemplo.json` | Exemplo de configuração |
| `rc/ligado.json` e `rc/desligado.json` | Os dois `--settings` que o `cc` passa ao Claude para ligar ou desligar o Remote Control da sessão. Não estão no repositório: o `cc` os cria em `~/.claude-contas/rc` na primeira vez que precisa |

Os scripts ficam em [`plugins/account-switcher/skills/account-switcher/scripts/`](plugins/account-switcher/skills/account-switcher/scripts) e são copiados para `~/.claude-contas` na instalação.

## Testes

Os testes ficam em [`tests/`](tests) e rodam na raiz do repositório com `Invoke-Pester tests`. Eles usam o **Pester 3.4, que já vem com o Windows PowerShell 5.1** (o Pester 4 também serve); a sintaxe antiga dos testes (`Should Be`) não roda no Pester 5. Cada arquivo de teste monta um perfil de usuário falso numa pasta temporária e aponta o `comum.ps1` para ele, então nada do seu `~/.claude` nem do seu `contas.json` é tocado. Os testes do macOS / Linux são outros: `bash tests/unix/run.sh` (veja [macOS and Linux](#macos-and-linux)).

## Glossário

- **Pasta mestre:** `~/.claude`, a pasta de config original do Claude Code. É onde ficam settings, histórico, memória, skills e plugins; as pastas das outras contas apontam para ela.
- **Symlink, hard link e junction:** os três tipos de link do Windows que os scripts usam para que uma conta enxergue os arquivos da pasta mestre. Arquivos usam symlink (exige o modo desenvolvedor) ou, sem ele, hard link; pastas usam junction. Apagar uma junction com `Remove-Item -Recurse` apaga o conteúdo real, por isso a remoção é feita pelos scripts.
- **RC (Remote Control):** o recurso do Claude Code de controlar a sessão pelo app ou pelo site. Aqui ele liga por conta, só nas sessões abertas pelo `cc`.
- **Publicar artefatos:** criar um Artifact, um Claude Doc ou outra publicação no claude.ai a partir do Claude Code. A publicação sai na conta logada na sessão, por isso tem uma conta fixa para isso (a principal, ou `publicar`).
- **App Paths:** a chave do registro do Windows (`HKCU\Software\Microsoft\Windows\CurrentVersion\App Paths`) que faz a barra de endereço do Explorer reconhecer o atalho `cc`.

## O que fica no seu PC

- `~/.claude-contas`: os scripts, o `contas.json`, as pastas das contas e os backups.
- O `contas.json`, com as suas contas reais, fica só no PC e nunca vai para o repositório.
- Um bloco no `~/.claude/CLAUDE.md`, a pasta `~/.claude-contas/bin` no PATH e o atalho do Explorer no registro do usuário.

## Atualização

Depois de atualizar o plugin, peça à skill para reinstalar ou rode `instalar.ps1` de novo: ele copia os scripts novos, não refaz o backup e não toca no `contas.json`. Para adicionar ou remover contas, mudar a principal ou o atalho, veja a seção "Manutenção" do [`SKILL.md`](plugins/account-switcher/skills/account-switcher/SKILL.md).

## Contribuindo

- Edite os scripts no repositório, em `plugins/account-switcher/skills/account-switcher/scripts/`, nunca a cópia em `~/.claude-contas`: o próximo `instalar.ps1` sobrescreve a cópia.
- Para testar uma mudança no seu PC, rode `instalar.ps1` de novo (ele só copia os scripts e refaz o que falta).
- Arquivos `.ps1` ficam só em ASCII (sem acentos): o Windows PowerShell 5.1 lê `.ps1` sem BOM como ANSI. Os acentos que aparecem na tela saem de códigos de caractere no próprio script. `.ps1` e `.cmd` são gravados com CRLF (`.gitattributes`).
- Rode `Invoke-Pester tests` antes de abrir o PR e acrescente testes em `tests/` para o que mudou. Se mexer nos scripts do macOS / Linux, rode também `bash tests/unix/run.sh`.
- Os scripts `.sh` ficam em `scripts-unix/`, em UTF-8 com LF, compatíveis com o bash 3.2 do macOS (sem arrays associativos, sem `mapfile`), com código e mensagens em inglês.
- A pasta `docs/superpowers` é o histórico de projeto de entregas passadas, não documentação de uso.

## Licença

[MIT](LICENSE). Feito e usado no dia a dia pelo autor; issues e sugestões são bem-vindas, sem garantia de suporte.
