# Account Switcher

A [Claude Code](https://code.claude.com) plugin that runs several Claude Code accounts on one computer: one main account and as many secondary ones as you like, switched with a short command (`cc <account>` on Windows, `cca <account>` on macOS and Linux) without logging in again. Only the login is per account; settings, history, memory, skills and plugins are shared. It also shows each account's usage. **Windows** (PowerShell) and **macOS / Linux** (bash) are both supported; the macOS / Linux part is described in [macOS and Linux](#macos-and-linux).

The goal is to switch accounts (for example, to get more quota) without losing anything: history, memory, skills, plugins and the session list stay the same whichever account is open.

## Purpose and principles

- **Only the login changes.** Each account has its own `.credentials.json` and `.claude.json`; everything else points to `~/.claude`.
- **One main account.** It is where artifacts are published and, unless `accounts.json` names another in `default`, the one `cc` opens with no argument. Publishing from another account only with your confirmation.
- **No copied credentials.** Each account does its own `/login`. The token is never copied between folders or written to disk by `cc`.
- **Reversible.** The install takes a backup the first time, and `uninstall.ps1` removes everything it put in place.

## How it works (Windows)

- Each account has its own config folder (`CLAUDE_CONFIG_DIR`) at `~/.claude-accounts/<account>`, holding its login.
- Inside that folder, `settings.json`, `history.jsonl`, `CLAUDE.md` and `keybindings.json` are links to the ones in `~/.claude` (the "master folder"), and `projects/`, `skills/`, `plugins/`, `sessions/` and the others are junctions. The account that was already logged in to `~/.claude` uses the master folder itself and runs without `CLAUDE_CONFIG_DIR`.
- `cc [account]` opens Claude in the account (no account means the default one), checks the logged-in e-mail and names the session "folder (account)".
- `cc -l` lists the accounts with each one's usage (5-hour and weekly windows, with the time until reset) and whether Remote Control turns on by default in it.
- When you open an account whose usage is above the limit (80% by default), `cc` warns you, suggests the account with the most room and asks before opening.
- The status line shows the account and the session and week usage (for example `Session: 42% (resets in 2h05) . Week: 17% (resets in 3d 4h)`), in yellow from the limit and in red from 95%.
- **Remote Control per account:** it turns on only in accounts with `"rc": true` in `accounts.json`; `cc <account> --rc` and `--no-rc` change that one session only. Sessions opened without `cc` do not turn RC on.
- **Explorer shortcut:** typing `cc` (or `cc <account>`) in the Explorer address bar opens Claude in the current folder. The shortcut name is configurable (`explorerShortcut`).
- The block with the account rules is written into `~/.claude/CLAUDE.md` between the markers `<!-- account-switcher:begin -->` and `<!-- account-switcher:end -->`, without touching the rest of the file.

## Quick start (Windows)

**You need:**

- Windows with Windows PowerShell 5.1 (it ships with Windows; the scripts call `powershell.exe`);
- [Claude Code](https://code.claude.com) installed and logged in to one account;
- preferably Windows developer mode: without it, the shared files use hard links instead of symlinks.

**Install:** the marketplace lives in this repository:

```
/plugin marketplace add Lindenjefferson/account-switcher
/plugin install account-switcher@account-switcher
```

Then, in a Claude Code session, ask **"install the account-switcher skill"**. It checks the PC, asks for the accounts (short name and e-mail of the main and secondary accounts, the Claude in Chrome account, the Explorer shortcut and in which accounts RC turns on), installs, and tells you what is missing.

**Install without the skill:** `install.ps1` only requires that `~/.claude-accounts/accounts.json` already exists. (If you have an older install in `~/.claude-contas`, do **not** create that file by hand: skip to [Upgrading from an older install](#upgrading-from-an-older-install-windows) and just run `install.ps1`.) With the repository cloned (or the installed plugin folder), from `plugins/account-switcher/skills/account-switcher/scripts/`:

1. Copy `accounts.example.json` to `~/.claude-accounts/accounts.json` and edit it with your accounts (UTF-8 without BOM; the keys are in "The `accounts.json` (Windows)", below).
2. Run `powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Check`. It shows where `claude.exe` is, whether symlinks work and any conflicts, without changing anything; fix whatever shows up as PROBLEM.
3. Run the same command without `-Check`. It takes a backup the first time, copies the scripts to `~/.claude-accounts`, creates the folders and links, puts `~/.claude-accounts/bin` on the PATH, registers the Explorer shortcut, writes the block in `~/.claude/CLAUDE.md` and ends with a `cc -l`.

**Use:**

1. Open a **new** terminal (the install changed the PATH).
2. Run `cc <account>` and do `/login` once in each account that is not logged in yet.
3. Check with `cc -l`. From then on, just `cc <account>` in the terminal or in the Explorer address bar.

## macOS and Linux

The same idea for macOS and Linux, written in bash (it runs on the bash 3.2 that ships with macOS) instead of PowerShell. It lives in [`plugins/account-switcher/skills/account-switcher/scripts-unix/`](plugins/account-switcher/skills/account-switcher/scripts-unix) and is independent from the Windows scripts.

**What is the same:** every account has its own folder (`CLAUDE_CONFIG_DIR`) with its own login, and everything else (settings, history, `CLAUDE.md`, projects, skills, plugins, sessions) is shared with `~/.claude`. One main account, per-account Remote Control, usage per account in `-l` and in the status line, a warning (and a suggestion of another account) when usage is high, and a `CLAUDE.md` block with the rules.

**What is different:**

| | Windows | macOS / Linux |
|---|---|---|
| Command | `cc` | `cca` by default (key `command`). `cc` is the C compiler on these systems, so the installer refuses a name that already exists on `PATH` |
| Scripts and config | `~/.claude-accounts`, `accounts.json` | `~/.claude-accounts`, `accounts.json` (same names, same keys, see below; Windows adds `explorerShortcut`) |
| Shared folders and files | junctions, symlinks or hard links | symlinks |
| `PATH` | user `PATH` | a marked block in your shell startup file (zsh, bash and fish are handled), appended at the **end** of `PATH`. `--no-path` skips it |
| Explorer address bar shortcut | yes | not applicable |
| Opening another account's session | `open-account.ps1` (Windows Terminal) | `open-account.sh` (Terminal.app or iTerm2 on macOS; tmux or the first terminal emulator found on Linux) |
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


## The `accounts.json` (Windows)

It lives at `~/.claude-accounts/accounts.json`, in the format of [`accounts.example.json`](plugins/account-switcher/skills/account-switcher/scripts/accounts.example.json). Keys the scripts read:

| Key | What it is | If missing |
|---|---|---|
| `main` | Name of the main account: the one that publishes artifacts and, without `default`, the one `cc` opens with no argument | Required |
| `default` | Account `cc` opens with no argument, when it is not the main one | The main one |
| `publish` | Account that publishes artifacts (the one shown as "main" in `cc -l` and in the `CLAUDE.md` block) | The main one |
| `explorerShortcut` | What you type in the Explorer address bar | `cc` |
| `chrome` | Name of the account the Claude in Chrome extension is logged in to; informational only (shown in `cc -l` and in `CLAUDE.md`), because Claude Code cannot detect it | No Chrome account |
| `usageWarning` | Usage percentage (1 to 100) from which `cc` warns and the status line turns yellow | 80 |
| `accounts` | Object with one entry per account; key = short account name | Required |
| `accounts.<name>.email` | Expected e-mail; `cc` compares it with the login in the folder and warns if it differs | |
| `accounts.<name>.dir` | Config folder of the account. Only one account may use `"~/.claude"` (the master folder): the one already logged in there | `~/.claude-accounts/<name>`; if no account has `dir`, the main one uses `~/.claude` |
| `accounts.<name>.rc` | `true` turns Remote Control on when opening the account with `cc` | Off |

`setup-accounts.ps1` checks that `default`, `publish` and `chrome` point to existing accounts and that only one account uses the master folder.

## Components (Windows)

| Piece | What it does |
|---|---|
| [`SKILL.md`](plugins/account-switcher/skills/account-switcher/SKILL.md) | Script for installing, maintaining, diagnosing and the rules |
| `common.ps1` | Functions every other script loads: reading `accounts.json`, the accounts' links and junctions, usage per account, Remote Control, the status line, the `CLAUDE.md` block and the migration from older installs |
| `install.ps1` | Checks the PC (`-Check`), takes a backup and installs everything; migrates an older install |
| `setup-accounts.ps1` | Rebuilds folders, links and the `CLAUDE.md` block from `accounts.json`; idempotent |
| `uninstall.ps1` | Removes links, PATH entry, shortcut and the `CLAUDE.md` block (`-DeleteFolders` also deletes the extra account folders) |
| `cc.ps1` and `bin/cc.cmd` | The `cc` command |
| `statusline.ps1` | The status line with account and usage |
| `open-account.ps1` | Opens a Windows Terminal tab (or a window) in another account (`-Account`, `-Folder`, `-Rc`, `-NoRc`) |
| `explorer/` | The Explorer address bar shortcut (`claude-here.cmd` and `claude-here.ps1`) |
| `CLAUDE.template.md` | Template of the rules block in `~/.claude/CLAUDE.md` |
| `accounts.example.json` | Example configuration |
| `rc/on.json` and `rc/off.json` | The two `--settings` files `cc` passes to Claude to turn Remote Control on or off for the session. They are not in the repository: `cc` creates them in `~/.claude-accounts/rc` the first time it needs them |

The scripts live in [`plugins/account-switcher/skills/account-switcher/scripts/`](plugins/account-switcher/skills/account-switcher/scripts) and are copied to `~/.claude-accounts` on install.

## Tests

The tests are in [`tests/`](tests). For Windows, run `Invoke-Pester tests` from the repository root. They use **Pester 3.4, which ships with Windows PowerShell 5.1** (Pester 4 also works); the old test syntax (`Should Be`) does not run on Pester 5. Each test file builds a fake user profile in a temporary folder and points `common.ps1` at it, so nothing in your `~/.claude` or your `accounts.json` is touched. The macOS / Linux tests are separate: `bash tests/unix/run.sh` (see [macOS and Linux](#macos-and-linux)).

## Glossary

- **Master folder:** `~/.claude`, the original Claude Code config folder. It holds settings, history, memory, skills and plugins; the other accounts' folders point to it.
- **Symlink, hard link and junction:** the three kinds of Windows link the scripts use so an account sees the master folder's files. Files use symlinks (they need developer mode) or, without it, hard links; folders use junctions. Deleting a junction with `Remove-Item -Recurse` deletes the real content, which is why the scripts do the removal.
- **RC (Remote Control):** the Claude Code feature for controlling the session from the app or the website. Here it turns on per account, only in sessions opened with `cc`.
- **Publishing artifacts:** creating an Artifact, a Claude Doc or another claude.ai publication from Claude Code. The publication goes out under the account logged in to the session, which is why one account is fixed for it (the main one, or `publish`).
- **App Paths:** the Windows registry key (`HKCU\Software\Microsoft\Windows\CurrentVersion\App Paths`) that makes the Explorer address bar recognize the `cc` shortcut.

## What stays on your PC

- `~/.claude-accounts`: the scripts, `accounts.json`, the account folders and the backups.
- `accounts.json`, with your real accounts, stays on the PC and never goes into the repository.
- A block in `~/.claude/CLAUDE.md`, the `~/.claude-accounts/bin` folder on the PATH and the Explorer shortcut in the user registry.

## Updating

After updating the plugin, ask the skill to reinstall or run `install.ps1` again: it copies the new scripts, does not redo the backup and does not touch `accounts.json`. To add or remove accounts or change the main account or the shortcut, see the "Maintenance" section of [`SKILL.md`](plugins/account-switcher/skills/account-switcher/SKILL.md).

### Upgrading from an older install (Windows)

Versions before this release had Portuguese names: they installed into `~/.claude-contas` with a `contas.json` and scripts such as `instalar.ps1`. Running the new `install.ps1` migrates that install automatically (`Move-LegacyInstall` in `common.ps1`).

**Before you run it:** close every Claude Code session and terminal that uses an account from `~/.claude-contas` (Windows will not rename a folder that has files open), and run `install.ps1` from a plain PowerShell window. If the rename fails, the script says so and has changed nothing.

**Order of events:** `install.ps1` first checks everything (`claude.exe`, your old `contas.json`, the Explorer shortcut name) and stops before touching anything if a check fails. Only then does it migrate:

- renames `~/.claude-contas` to `~/.claude-accounts` (the account folders, their logins and the junctions inside them are not touched);
- converts `contas.json` to `accounts.json` with the new English keys; the old file is kept in `backups\contas.json.before-migration`;
- deletes the old script files and old `rc\*.json` files (the new install replaces them);
- renames the `CLAUDE.md` block markers to `<!-- account-switcher:begin -->` / `<!-- account-switcher:end -->`;
- repoints the status line in `settings.json` to the new folder (if `settings.json` is invalid JSON it says so and leaves the file alone);
- takes the old `bin` folder off the user PATH (the new install adds `~/.claude-accounts/bin`);
- then the usual install runs, and the Explorer shortcut is registered again, now pointing to `explorer\claude-here.cmd`.

Every step checks its own precondition, so if the run is interrupted you can simply run `install.ps1` again. `install.ps1 -Check` reports a pending migration without changing anything.

**Things to know:**

- If both `~/.claude-contas` and `~/.claude-accounts` already exist (for example because you created `accounts.json` by hand first), nothing is migrated and `install.ps1` warns about it: the accounts in the new folder would start without logins. Move or delete the new folder (it only holds scripts and `accounts.json`) and run `install.ps1` again to keep your old logins.
- Other files can still mention the old folder, for example Claude's plugin registry under `~/.claude\plugins` if you installed a plugin from a secondary account. `install.ps1` only lists such files as warnings; it does not rewrite them.
- `cc -l` is now the only listing flag: `--listar` and `--contas` are gone.

This was written without access to a Windows machine where it could be run end to end. The pure parts (the conversion of `contas.json` and the migration steps on a fake profile) are covered by Pester tests, but the whole sequence, including the PATH and registry steps, has not been tried on a real older install. Take your own copy of `~/.claude-contas\contas.json` first if the setup matters to you.

## Contributing

- Code, comments, messages and docs are in English.
- Edit the scripts in the repository, in `plugins/account-switcher/skills/account-switcher/scripts/`, never the copy in `~/.claude-accounts`: the next `install.ps1` overwrites the copy.
- To test a change on your PC, run `install.ps1` again (it only copies the scripts and redoes what is missing).
- `.ps1` files are ASCII only: no accents anywhere, because Windows PowerShell 5.1 reads a `.ps1` without a BOM as ANSI. Characters such as the middle dot shown on screen are built from char codes in the script. `.ps1` and `.cmd` are saved with CRLF (`.gitattributes`).
- Run `Invoke-Pester tests` before opening the PR and add tests in `tests/` for what changed. The Pester note above applies: 3.4 ships with Windows PowerShell 5.1, 4 works, and the old `Should Be` syntax does not run on Pester 5. If you touch the macOS / Linux scripts, run `bash tests/unix/run.sh` too.
- The `.sh` scripts live in `scripts-unix/`, UTF-8 with LF, compatible with the bash 3.2 that ships with macOS (no associative arrays, no `mapfile`), with code and messages in English.
- The `docs/superpowers` folder is the project history of past deliveries (written in Portuguese), not usage documentation.

## License

[MIT](LICENSE). Made and used day to day by the author; issues and suggestions are welcome, with no guarantee of support.
