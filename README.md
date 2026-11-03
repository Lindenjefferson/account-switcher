# account-switcher

> *In English:* a Claude Code plugin for Windows that runs several Claude Code accounts on one PC, switched with `cc <account>` without logging in again. Only the login is per account; settings, history, memory, skills and plugins are shared. It also shows each account's usage and adds a `cc` shortcut to the Explorer address bar. The docs are in Portuguese.

Várias contas do [Claude Code](https://code.claude.com) no mesmo PC com Windows: uma conta principal e quantas secundárias você quiser, alternadas com `cc <conta>` sem relogar. Cada conta tem só o login separado; o resto do ambiente é o mesmo em todas.

O objetivo é trocar de conta (por exemplo, para ter mais cota) sem perder nada: o histórico, a memória, as skills, os plugins e a lista de sessões continuam iguais, qualquer que seja a conta aberta.

## Propósito e princípios

- **Só o login muda.** Cada conta tem o próprio `.credentials.json` e `.claude.json`; todo o resto aponta para `~/.claude`.
- **Uma conta principal.** É a padrão do `cc` e onde os artefatos são publicados. Publicar em outra conta só com a sua confirmação.
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

- Windows com PowerShell;
- [Claude Code](https://code.claude.com) instalado e logado numa conta;
- o modo desenvolvedor do Windows, de preferência: sem ele, os arquivos compartilhados usam hard link em vez de symlink.

**Instalar:** o plugin é listado no marketplace `linden-plugins`, que mora no repositório [`claude-pipeline`](https://github.com/Lindenjefferson/claude-pipeline):

```
/plugin marketplace add Lindenjefferson/claude-pipeline
/plugin install account-switcher@linden-plugins
```

Depois, numa sessão do Claude Code, peça **"instala a skill account-switcher"**. Ela verifica o PC, pergunta as contas (nome curto e e-mail da principal e das secundárias, a conta do Claude in Chrome, o atalho do Explorer e em quais contas o RC liga), instala e diz o que falta.

**Usar:**

1. Abra um terminal **novo** (a instalação mudou o PATH).
2. Rode `cc <conta>` e faça `/login` uma vez em cada conta que ainda não está logada.
3. Confira com `cc -l`. Daí em diante, é só `cc <conta>` no terminal ou na barra do Explorer.

## Componentes

| Peça | O que faz |
|---|---|
| [`SKILL.md`](plugins/account-switcher/skills/account-switcher/SKILL.md) | Roteiro de instalação, manutenção, diagnóstico e regras |
| `instalar.ps1` | Verifica o PC (`-Verificar`), faz backup e instala tudo |
| `setup-contas.ps1` | Refaz pastas, links e o bloco do `CLAUDE.md` a partir do `contas.json`; idempotente |
| `desfazer-contas.ps1` | Remove links, PATH, atalho e o bloco do `CLAUDE.md` |
| `cc.ps1` e `bin/cc.cmd` | O comando `cc` |
| `statusline.ps1` | A status line com conta e uso |
| `abrir-conta.ps1` | Abre uma aba do Windows Terminal (ou uma janela) em outra conta |
| `explorer/` | O atalho da barra de endereço do Explorer |
| `modelo-CLAUDE.md` | Modelo do bloco de regras do `~/.claude/CLAUDE.md` |
| `contas.exemplo.json` | Exemplo de configuração |

Os scripts ficam em [`plugins/account-switcher/skills/account-switcher/scripts/`](plugins/account-switcher/skills/account-switcher/scripts) e são copiados para `~/.claude-contas` na instalação. Os testes, em [`tests/`](tests), rodam com Pester (`Invoke-Pester tests`).

## O que fica no seu PC

- `~/.claude-contas`: os scripts, o `contas.json`, as pastas das contas e os backups.
- O `contas.json`, com as suas contas reais, fica só no PC e nunca vai para o repositório.
- Um bloco no `~/.claude/CLAUDE.md`, a pasta `~/.claude-contas/bin` no PATH e o atalho do Explorer no registro do usuário.

## Quando não usar

- macOS ou Linux: os scripts são só para Windows.
- Para separar ambientes: as contas compartilham settings, memória e histórico de propósito. Se você quer uma conta com configuração própria, este plugin não é para isso.

## Atualização

Depois de atualizar o plugin, peça à skill para reinstalar ou rode `instalar.ps1` de novo: ele copia os scripts novos, não refaz o backup e não toca no `contas.json`. Para adicionar ou remover contas, mudar a principal ou o atalho, veja a seção "Manutenção" do [`SKILL.md`](plugins/account-switcher/skills/account-switcher/SKILL.md).

Feito e usado no dia a dia pelo autor; issues e sugestões são bem-vindas, sem garantia de suporte.
