---
name: account-switcher
description: 'Installs and maintains several Claude Code accounts on Windows (one main account and as many secondary ones as you like), switched with `cc <account>` without logging in again (CLAUDE_CONFIG_DIR per account, everything else shared with ~/.claude), plus the "cc" shortcut in the Explorer address bar. Use it to install on a new PC, add or remove a secondary account, change the main account, reinstall after updating the plugin, upgrade an older install (migrated automatically), undo, diagnose `cc`, or open a session of another account (e.g. the main one, to publish an artifact). Also works on macOS and Linux (bash scripts in scripts-unix/, command cca): follow the "macOS and Linux" section when the system is not Windows.'
---

# Account Switcher

The user has **one main account** and **as many secondary accounts as they like**:
- The main one is the default of `cc` and where artifacts are published, unless the user explicitly says otherwise (with confirmation).
- The secondary ones share the same environment and only change the login, for example to get more quota.
- The account names are chosen by the user. Do not assume names or how many there are.

The scripts live in the `scripts/` folder next to this SKILL.md and are installed into `~/.claude-accounts`. Always run them with `powershell -NoProfile -ExecutionPolicy Bypass -File <script>`: the default Windows execution policy blocks .ps1 files.

**Which platform?** On Windows, follow everything below. On macOS or Linux (`uname -s` prints `Darwin` or `Linux`), skip to [macOS and Linux](#macos-and-linux) at the end of this file: the scripts, the config file and the command name are different there.

## How it works (to explain to the user)
- Each account has its own config folder (`CLAUDE_CONFIG_DIR`) with its login (`.credentials.json`) and its `.claude.json`.
- Everything else points to `~/.claude` (the "master folder"): `settings.json`, `history.jsonl`, `CLAUDE.md`, `keybindings.json` through file links; `projects/`, `skills/`, `plugins/`, `sessions/` etc. through junctions. So history, memory, skills, plugins and the session list are the same in every account.
- The account already logged in to `~/.claude` uses the master folder itself (`"dir": "~/.claude"`) and runs **without** `CLAUDE_CONFIG_DIR`.
- `cc [account] [args]` opens Claude in the account (no account = the default), checks the logged-in e-mail with `claude auth status --json` and names the session "folder (account)". `cc -l` lists the accounts, whether RC turns on by default in each, and each one's usage (5-hour and weekly windows, with the time until reset).
- **Remote Control per account:** `settings.json` is shared, so `cc` decides the RC of each session by passing `--settings ~/.claude-accounts/rc/on.json` or `off.json`. It turns on only in accounts with `"rc": true` in `accounts.json`; `cc <account> --rc [name]` turns it on and `--no-rc` off, for that session only. The shared `settings.json` keeps `remoteControlAtStartup: false` (written by `setup-accounts.ps1` and checked on every `cc`), so sessions opened without `cc` (claude directly, IDE, app) do not turn RC on.
- **Usage:** `cc` queries `api.anthropic.com/api/oauth/usage` with the token read, in memory only, from the account's own `.credentials.json`. If the token expired (it is only renewed when the account runs), it shows the last usage the account saved in `.claude.json`, with the time. When you open an account whose usage is at or above `usageWarning` (default 80) in the 5-hour or the weekly window, `cc` warns, suggests the account with the most room and asks before opening (in `-p` mode it only warns on stderr).
- **Status line:** `statusline.ps1` shows `<account> . Session: x% (resets in 2h05) . Week: y% (resets in 3d 4h)` (with a middle dot as the separator), with the percentage in yellow from `usageWarning` and in red from 95%. `setup-accounts.ps1` registers it in `settings.json` only if there is no other status line.
- In the Explorer address bar, the shortcut (default `cc`, key `explorerShortcut`) opens PowerShell in the current folder with `cc`. Explorer does not pass the folder to App Paths commands, so `explorer/claude-here.ps1` finds the folder from the Explorer window that is in front.
- A new account gets only the configuration keys of `~/.claude.json` (MCPs, trusted projects etc.), never the account data. claude.ai connectors are per account and are set up on the website.

## Install on a new PC
0. If `~/.claude-contas` already exists, this is an upgrade of an older install, not a new install: follow "Upgrading from an older install" under Maintenance and do not write `accounts.json` by hand.
1. Run `scripts/install.ps1 -Check`. It shows the path of `claude.exe`, whether symlinks work (developer mode) and conflicts. If there is a PROBLEM, fix it with the user before going on.
2. Run `claude auth status --json` (without `CLAUDE_CONFIG_DIR`) to see which e-mail is already logged in to `~/.claude`.
3. Ask the user, all at once:
   - short name and e-mail of the **main account**;
   - short name and e-mail of each **secondary account**, however many there are;
   - which account the Claude in Chrome extension is logged in to, if the user uses the extension (field `chrome`; Claude Code cannot detect it by itself);
   - the Explorer shortcut (default `cc`, field `explorerShortcut`);
   - in which accounts Remote Control should turn on by default (field `"rc": true`; without it, RC stays off). Work accounts are usually left off.
   The common case is the main account already being logged in to `~/.claude` (step 2) and the secondary ones being added later.
   - **Only one account has `"dir": "~/.claude"`:** the one logged in there. The others live in `~/.claude-accounts/<name>` without needing the field. If no account has `dir`, the main one uses `~/.claude`.
   - If the e-mail logged in to `~/.claude` belongs to a secondary account, that account gets `"dir": "~/.claude"`, and the main account gets its own folder (with a `/login`). Explain this to the user.
   - Do not copy `.credentials.json` from one folder to another.
4. Write `~/.claude-accounts/accounts.json` in UTF-8 without BOM, in the format of `scripts/accounts.example.json`, with `"main": "<name>"`. If the user wants `cc` with no argument to open another account, add `"default": "<name>"`; the main account stays the only one that publishes.
5. Run `scripts/install.ps1`. It takes a backup the first time, copies the scripts, creates the folders and links, puts `~/.claude-accounts/bin` on the PATH, registers the Explorer shortcut and writes the accounts block in `~/.claude/CLAUDE.md` (between the markers `<!-- account-switcher:begin -->` and `<!-- account-switcher:end -->`, preserving the rest of the file).
6. Give the user the next steps:
   - open a **new** terminal (the PATH changed);
   - run `cc <account>` and `/login` once in each account that is not logged in;
   - check with `cc -l`.

## Maintenance
- **Add a secondary account:** add the account to `~/.claude-accounts/accounts.json` and run `~/.claude-accounts/setup-accounts.ps1`, which is idempotent and also updates CLAUDE.md. Then the user runs `cc <new>` and does `/login`.
- **Change an account's default RC or the usage warning limit:** edit `"rc"` of the account or `"usageWarning"` in `accounts.json`. It takes effect on the next `cc`.
- **Change the main account, the default, the Chrome account or the shortcut:** edit `accounts.json` and run `setup-accounts.ps1`. If you changed the shortcut, run `install.ps1`, which registers the new one; delete the old key by hand at `HKCU\Software\Microsoft\Windows\CurrentVersion\App Paths\<old>.exe`.
- **Remove an account:** first take the links out of its folder with `. ~/.claude-accounts/common.ps1; Remove-AccountLinks ((Get-Accounts).Accounts | ? Name -eq '<account>')`. Check that no link is left in the folder (`Get-ChildItem -Force | ? LinkType`). Only then delete the folder, remove the account from `accounts.json` and run `setup-accounts.ps1`.
- **After updating the plugin:** run `scripts/install.ps1` again to copy the new scripts. It does not redo the backup or touch `accounts.json`.
- **Upgrading from an older install:** versions before this release installed into `~/.claude-contas` with a Portuguese `contas.json`. First check whether `~/.claude-contas` exists. If it does, ask the user to close every Claude Code session and terminal that uses an account from it (Windows will not rename a folder with open files), and run `scripts/install.ps1` from a plain PowerShell. It checks everything first and stops without changes if a check fails; then it migrates (`Move-LegacyInstall` in `common.ps1`): renames `~/.claude-contas` to `~/.claude-accounts` (account folders, logins and junctions are not touched), converts `contas.json` to `accounts.json` (the old file stays in `backups\contas.json.before-migration`), deletes the old script files, renames the CLAUDE.md block markers, repoints the status line in `settings.json`, takes the old `bin` folder off the user PATH, and then does the usual install (the Explorer shortcut is registered again, pointing to `explorer\claude-here.cmd`). Every step checks its own precondition, so an interrupted run can just be repeated. If both `~/.claude-contas` and `~/.claude-accounts` exist, nothing is migrated and the installer warns: do NOT write `accounts.json` by hand first on a machine that has the old folder, or the new accounts start without logins. Other files that mention the old folder (e.g. `~/.claude\plugins\*.json`) are only reported as warnings. Tell the user to open a new terminal afterwards. `scripts/install.ps1 -Check` reports a pending migration without changing anything. Be upfront that this migration was written without a Windows machine to run it end to end: the pure parts are covered by tests, the PATH and registry steps are not.
- **Undo:** `~/.claude-accounts/uninstall.ps1` removes links, PATH entry, shortcut and the CLAUDE.md block. With `-DeleteFolders`, it also deletes the extra accounts' folders.

## Publish an artifact from another account
- **Target account:** the main one, if the user named none. If they named another, confirm first with AskUserQuestion, showing name and e-mail ("Publish to account X (email), not to the main one?"). Only go ahead on a yes. Never change the target account on your own.
1. Check the current session's account with `claude auth status --json`. If it already is the target account, publish here.
2. Otherwise, save the content to a file and look with ListAgents for a session whose name ends in "(<target account>)".
3. If there is none, run `~/.claude-accounts/open-account.ps1 <target account> <folder> [-Rc | -NoRc]` (parameters `-Account`, `-Folder`, `-Rc`, `-NoRc`), which opens a new Windows Terminal tab (without it, a window), and look for the session again.
4. Ask it by SendMessage to check its own account with `claude auth status --json` and publish the file.
5. `cc` removes the `CLAUDE*` variables inherited from this session (except `CLAUDE_CONFIG_DIR`); without that, the new window would open with "Transcript saving is off" and would not show up in ListAgents.
6. Its auto mode asks for the user's approval in its own window. This is expected; tell the user.

Claude in Chrome does not need this: it works from any account. The `chrome` field of `accounts.json` only records which account the extension is logged in to (it shows in `cc -l` and in CLAUDE.md).

## Never
- `Remove-Item -Recurse` (or deleting from Explorer) on an account folder that still has junctions. That deletes the real content of `~/.claude`. Use `Remove-AccountLinks` or `uninstall.ps1`.
- Copy or move `.credentials.json` between folders: the token is renewed and the copy stops being valid.
- Set `CLAUDE_CONFIG_DIR` pointing to `~/.claude`: Claude would start looking for `.claude.json` inside the folder.
- Use `$PROFILE` for `cc`: on PCs with the default execution policy, it does not load. `cc` is a `.cmd` on the PATH on purpose.

## Diagnosis
- **Typing the shortcut in Explorer opens a folder instead of Claude:** a folder with that name exists (Explorer navigates before executing). Change `explorerShortcut`. `install.ps1 -Check` looks for these conflicts.
- **Explorer shortcut gives "Unable to find type [W.U]":** `Add-Type` failed because `TMP` points to `C:\Windows\TEMP` (`TMP` is missing from the user environment). `claude-here.ps1` fixes this in its own session; if it still happens, reinstall the scripts. To fix it in Windows, create a user `TMP` equal to `TEMP` (`%USERPROFILE%\AppData\Local\Temp`).
- **"cc is not recognized":** the terminal was opened before the install. Open another one.
- **Warning "the folder of account X is logged in as Y, but Z was expected":** `/login` was done with the wrong e-mail in that folder. Run `/logout` and `/login` inside `cc <account>`.
- **Message "change made in account X was carried over to the master folder":** a program saved over a link and `cc` rebuilt the link. The previous content is in `~/.claude-accounts/backups`.
- **Usage shows "(saved HH:mm)":** that account's token expired, so the value is the last one it saved. Opening the account with `cc <account>` updates it. `cc` does not renew the token by itself, on purpose.
- **Account and usage status line does not show up:** `settings.json` already had another `statusLine`, and the installer does not touch it. To use ours, remove the other one and run `setup-accounts.ps1`.
- **RC turned on in an account without `rc`:** check whether someone put `remoteControlAtStartup: true` in the shared `settings.json` (`cc` sets it back to `false` when it opens) or whether the session was opened with `--rc`.

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
