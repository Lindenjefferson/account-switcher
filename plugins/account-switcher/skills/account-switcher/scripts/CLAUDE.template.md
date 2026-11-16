# Claude Code accounts on this PC

This PC has one main Claude Code account and some secondary ones, all sharing the same environment. Only the login changes from one to the other.

| Account | Role | E-mail | Config folder |
|---|---|---|---|
{{TABLE}}

- I open each account with `cc <account>`, in the terminal or in the Explorer address bar (`{{SHORTCUT}}` / `{{SHORTCUT}} <account>`). Scripts and `accounts.json` live in `~/.claude-accounts`.
- To find out which account this session is running as, run `claude auth status --json` (`email` field). The session name, "folder (account)", also tells.
- Remote Control only turns on when opened through `cc`: for accounts with `"rc": true` in `accounts.json`, or with `cc <account> --rc`. The shared `settings.json` has `remoteControlAtStartup: false`; do not change it to `true`, because that would turn RC on for the accounts where the user does not want it.
- `cc -l` shows the usage of each account (5h and weekly) and whether RC is on by default for it. The status line shows the account and the usage of the session.

## What is shared
- Each account has its own login (`.credentials.json`) and `.claude.json`. The claude.ai connectors are per account too.
- Everything else points to `~/.claude`: settings.json, history.jsonl, this CLAUDE.md (links) and projects/, skills/, plugins/, sessions/ (junctions).
- So sessions of different accounts can see each other through ListAgents/SendMessage, and memory and project history are the same in all of them.
- Claude in Chrome works from any account (it uses Chrome's own logins). The extension is logged in to account {{CHROME}}. If the user says it changed, update `chrome` in `accounts.json` and run `setup-accounts.ps1`.

## Prohibitions
- **Publishing artifacts** (Artifact, Claude Docs or any publication on claude.ai) happens on the account logged in to Claude Code, not the Chrome one:
  - **With no account indicated, publish on the main account, {{PUBLISH}} ({{PUBLISH_EMAIL}}).**
  - **If the user indicates another account, ask for confirmation first** (AskUserQuestion), showing its name and e-mail, for example: "Publish on account X (email), not on the main one?". Only go ahead on an explicit yes. Never pick another account on your own.
  - Check the current session's account with `claude auth status --json`. If it already is the target account, publish here.
  - If not, write the content to a file and use ListAgents to look for a session whose name ends in "(<target account>)". If there is none, open one with `powershell -NoProfile -ExecutionPolicy Bypass -File ~/.claude-accounts/open-account.ps1 <target account> <folder>` (with `-Rc` or `-NoRc` to turn Remote Control on or off in it).
  - Ask it through SendMessage to check its own account and publish. The user approves in its window.
- **Never copy or move `.credentials.json`** between account folders. Each account runs `/login` in its own folder.
- **Never delete the `~/.claude-accounts/<account>` folders with `Remove-Item -Recurse`**: with junctions that deletes the real content in `~/.claude`. To undo, use `~/.claude-accounts/uninstall.ps1`.
- **Do not set `CLAUDE_CONFIG_DIR` to `~/.claude`**: the master-folder account runs without the variable, otherwise Claude looks for `.claude.json` in the wrong place.
- To add, remove or reinstall accounts, use the `account-switcher` skill.
