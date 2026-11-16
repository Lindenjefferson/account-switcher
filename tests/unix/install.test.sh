#!/usr/bin/env bash
. "$(dirname "$0")/helpers.sh"

fresh_home i
write_accounts '{"main":"m","chrome":"m","accounts":{"m":{"email":"m@x","dir":"~/.claude","rc":true},"s":{"email":"s@x"}}}'
stub_claude; export STUB_EMAIL=m@x
export SHELL=/bin/zsh
printf '# my zshrc\nexport FOO=1' > "$HOME/.zshrc"          # no trailing newline on purpose
echo '{"theme":"dark"}' > "$HOME/.claude/settings.json"
echo '# my notes' > "$HOME/.claude/CLAUDE.md"
mkdir -p "$HOME/.claude/skills" "$HOME/.claude/plugins"; echo keep > "$HOME/.claude/skills/k.md"; echo '{}' > "$HOME/.claude/plugins/installed.json"
INSTALL="bash $SCRIPTS_DIR/install.sh"
B="$HOME/.claude-accounts"

# --check changes nothing
$INSTALL --check >/dev/null 2>&1; assert_eq 0 "$?" '--check passes'
assert_no_file "$B/lib.sh" '--check copies nothing'; assert_eq '# my zshrc
export FOO=1' "$(cat "$HOME/.zshrc")" '--check leaves zshrc alone'

# install
out=$($INSTALL 2>&1); status=$?
assert_eq 0 "$status" 'install succeeds'
for f in lib.sh cc.sh install.sh setup-accounts.sh uninstall.sh statusline.sh open-account.sh shellrc.sh CLAUDE.template.md accounts.example.json; do assert_file "$B/$f" "copied $f"; done
assert_ok test -x "$B/cc.sh"; assert_ok test -x "$B/statusline.sh"; assert_ok test -x "$B/bin/cca"
assert_eq 1 "$(ls -d "$B"/backups/install_* | wc -l | tr -d ' ')" 'one backup'
assert_file "$(ls -d "$B"/backups/install_*)/.claude/settings.json" 'settings backed up'
assert_file "$(ls -d "$B"/backups/install_*)/.claude/plugins/installed.json" 'plugin json backed up'
assert_contains "$out" 'Open a NEW terminal' 'tells the user to open a new terminal'
assert_link "$B/s/settings.json" 'account s linked'
assert_eq keep "$(cat "$B/s/skills/k.md")" 'shared skill visible through the account'
assert_contains "$(cat "$HOME/.claude/CLAUDE.md")" '# my notes' 'user CLAUDE.md text kept'
assert_contains "$(cat "$HOME/.claude/CLAUDE.md")" 'account-switcher:begin' 'accounts block written'
assert_contains "$(jq -r .statusLine.command "$HOME/.claude/settings.json")" "$B/statusline.sh" 'statusLine registered'
assert_eq false "$(jq -r .remoteControlAtStartup "$HOME/.claude/settings.json")" 'RC off in shared settings'
assert_eq dark "$(jq -r .theme "$HOME/.claude/settings.json")" 'theme kept'
assert_eq 1 "$(grep -c 'account-switcher >>>' "$HOME/.zshrc")" 'PATH block in .zshrc'
assert_contains "$(cat "$HOME/.zshrc")" 'export FOO=1' 'zshrc content kept'
assert_contains "$out" 'Account' 'cc -l ran at the end'

# the generated command works through PATH
export PATH="$B/bin:$PATH"
(cd "$HOME" && STUB_EMAIL=s@x cca s </dev/null >/dev/null 2>&1); assert_eq 0 "$?" 'cca runs'
assert_contains "$(cat "$HOME/claude-call.log")" "CONFIG_DIR=$B/s" 'cca opened account s'

# second install: idempotent, no second backup, no second PATH block, accounts.json untouched
before=$(cat "$B/accounts.json")
$INSTALL >/dev/null 2>&1; assert_eq 0 "$?" 'reinstall succeeds'
assert_eq 1 "$(ls -d "$B"/backups/install_* | wc -l | tr -d ' ')" 'no second backup'
assert_eq 1 "$(grep -c 'account-switcher >>>' "$HOME/.zshrc")" 'no second PATH block'
assert_eq "$before" "$(cat "$B/accounts.json")" 'accounts.json untouched'
assert_eq 1 "$(grep -c 'account-switcher:begin' "$HOME/.claude/CLAUDE.md")" 'one CLAUDE.md block'

# changing "command" replaces our old wrapper but never someone else's file
echo '#!/bin/sh' > "$B/bin/foreign"; chmod +x "$B/bin/foreign"
write_accounts '{"main":"m","command":"acc","accounts":{"m":{"email":"m@x","dir":"~/.claude"},"s":{"email":"s@x"}}}'
$INSTALL >/dev/null 2>&1
assert_file "$B/bin/acc" 'new wrapper'; assert_no_file "$B/bin/cca" 'old wrapper removed'; assert_file "$B/bin/foreign" 'foreign file kept'
write_accounts '{"main":"m","accounts":{"m":{"email":"m@x","dir":"~/.claude"},"s":{"email":"s@x"}}}'
$INSTALL >/dev/null 2>&1

# uninstall: links, PATH block, CLAUDE.md block, statusLine go; master content and the login stay
echo login > "$B/s/.credentials.json"
bash "$SCRIPTS_DIR/uninstall.sh" >/dev/null 2>&1; assert_eq 0 "$?" 'uninstall succeeds'
assert_no_file "$B/s/settings.json" 'link removed'
assert_file "$B/s/.credentials.json" 'login kept without --delete-folders'
assert_eq keep "$(cat "$HOME/.claude/skills/k.md")" 'master content intact'
assert_eq '# my notes' "$(cat "$HOME/.claude/CLAUDE.md")" 'CLAUDE.md block removed, user text kept'
assert_eq null "$(jq -r '.statusLine // "null"' "$HOME/.claude/settings.json")" 'statusLine removed'
assert_eq 0 "$(grep -c 'account-switcher' "$HOME/.zshrc")" 'PATH block removed'
assert_eq '# my zshrc
export FOO=1' "$(cat "$HOME/.zshrc")" 'zshrc back to its original text'
assert_file "$B/cc.sh.disabled" 'command disabled'
out=$("$B/bin/cca" 2>&1); assert_contains "$out" 'is disabled' 'disabled command explains itself'
bash "$SCRIPTS_DIR/install.sh" >/dev/null 2>&1; assert_file "$B/cc.sh" 'install re-enables the command'; assert_no_file "$B/cc.sh.disabled" 'disabled marker gone'

# uninstall --delete-folders removes the account folder but never the master content
bash "$SCRIPTS_DIR/uninstall.sh" --delete-folders >/dev/null 2>&1
assert_no_file "$B/s" 'account folder deleted'
assert_eq keep "$(cat "$HOME/.claude/skills/k.md")" 'master content intact after --delete-folders'
assert_file "$HOME/.claude/settings.json" 'master settings intact after --delete-folders'
assert_fails bash "$SCRIPTS_DIR/uninstall.sh" --bogus

# problems are reported: a command name that already exists, a bad name, a missing accounts.json
write_accounts '{"main":"m","command":"ls","accounts":{"m":{"email":"m@x","dir":"~/.claude"}}}'
out=$(bash "$SCRIPTS_DIR/install.sh" --check 2>&1); assert_contains "$out" "a command named 'ls' already exists" 'existing command detected'
assert_fails bash "$SCRIPTS_DIR/install.sh"
printf '#!/bin/sh\n' > "$HOME/stubs/cc"; chmod +x "$HOME/stubs/cc"   # stands for the C compiler, which may not be installed
write_accounts '{"main":"m","command":"cc","accounts":{"m":{"email":"m@x","dir":"~/.claude"}}}'
out=$(bash "$SCRIPTS_DIR/install.sh" --check 2>&1); assert_contains "$out" "a command named 'cc' already exists" 'the C compiler is never shadowed'
write_accounts '{"main":"m","command":"a/b","accounts":{"m":{"email":"m@x","dir":"~/.claude"}}}'
out=$(bash "$SCRIPTS_DIR/install.sh" --check 2>&1); assert_contains "$out" 'PROBLEM' 'invalid command name'
rm "$B/accounts.json"; out=$(bash "$SCRIPTS_DIR/install.sh" --check 2>&1); assert_contains "$out" 'missing' 'missing accounts.json'

# --no-path leaves the shell files alone; bash and fish pick the right file
fresh_home j; write_accounts '{"main":"m","accounts":{"m":{"email":"m@x"}}}'; stub_claude; export STUB_EMAIL=m@x
export SHELL=/bin/zsh; bash "$SCRIPTS_DIR/install.sh" --no-path >/dev/null 2>&1
assert_no_file "$HOME/.zshrc" '--no-path: no zshrc created'
. "$SCRIPTS_DIR/lib.sh"; . "$SCRIPTS_DIR/shellrc.sh"
SHELL=/bin/fish; assert_eq "$HOME/.config/fish/conf.d/account-switcher.fish" "$(shellrc_target)" 'fish target'
SHELL=/bin/bash; if [ "$(uname -s)" = Darwin ]; then assert_eq "$HOME/.bash_profile" "$(shellrc_target)" 'bash on macOS'; else assert_eq "$HOME/.bashrc" "$(shellrc_target)" 'bash on Linux'; fi
SHELL=/bin/zsh; add_path_block >/dev/null; assert_contains "$(cat "$HOME/.zshrc")" '.claude-accounts/bin' 'block created in a new zshrc'
remove_path_block >/dev/null; assert_eq 0 "$(wc -c < "$HOME/.zshrc" | tr -d ' ')" 'file left empty (not deleted: it is the user'"'"'s)'
SHELL=/bin/fish; add_path_block >/dev/null; assert_file "$HOME/.config/fish/conf.d/account-switcher.fish" 'fish file created'
remove_path_block >/dev/null; assert_no_file "$HOME/.config/fish/conf.d/account-switcher.fish" 'our own fish file deleted'
# the block only appends to the END of PATH
unset PATH_SAVE; blk=$(shellrc_block posix); p=$(PATH=/usr/bin:/bin bash -c "$blk"$'\necho "$PATH"')
assert_eq "/usr/bin:/bin:$HOME/.claude-accounts/bin" "$p" 'appended at the end of PATH'
p=$(PATH="/usr/bin:/bin:$HOME/.claude-accounts/bin" bash -c "$blk"$'\necho "$PATH"'); assert_eq "/usr/bin:/bin:$HOME/.claude-accounts/bin" "$p" 'not added twice'

finish
