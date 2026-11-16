#!/usr/bin/env bash
# Regression tests for problems found in code review.
. "$(dirname "$0")/helpers.sh"

# the tests must never leave the fake HOME (a real ZDOTDIR must not redirect the rc file)
export ZDOTDIR=/nonexistent-zdotdir-must-not-be-used
fresh_home z
assert_eq '' "${ZDOTDIR:-}" 'fresh_home unsets ZDOTDIR'

# accounts that would make a script act on the wrong folder are rejected
bad() { write_accounts "$1"; . "$SCRIPTS_DIR/lib.sh"; assert_fails load_accounts; }
bad '{"main":"m","accounts":{"m":{"email":"m@x"},"s":{"email":"s@x","dir":"~"}}}'
bad '{"main":"m","accounts":{"m":{"email":"m@x"},"s":{"email":"s@x","dir":"/"}}}'
bad '{"main":"m","accounts":{"m":{"email":"m@x"},"s":{"email":"s@x","dir":"~/.claude/sub"}}}'
bad '{"main":"m","accounts":{"m":{"email":"m@x"},"s":{"email":"s@x","dir":"~/a/../b"}}}'
bad '{"main":"m","accounts":{"m":{"email":"m@x"},"s":{"email":"s@x","dir":"~/x"},"t":{"email":"t@x","dir":"~/x/"}}}'
for reserved in bin rc backups x.sh x.json x.md x.disabled; do
    bad "{\"main\":\"m\",\"accounts\":{\"m\":{\"email\":\"m@x\"},\"$reserved\":{\"email\":\"s@x\"}}}"
done
bad '{"main":"m","default":"ghost","accounts":{"m":{"email":"m@x"}}}'
bad '{"main":"m","publish":"ghost","accounts":{"m":{"email":"m@x"}}}'
bad '{"main":"m","chrome":"ghost","accounts":{"m":{"email":"m@x"}}}'

# an e-mail with a newline cannot split a record into a phantom account
write_accounts '{"main":"m","accounts":{"m":{"email":"a@x\nphantom\u001fb"}}}'; assert_ok load_accounts
assert_eq 1 "${#ACC_NAME[@]}" 'newline in e-mail: still one account'

# uninstall --delete-folders never deletes a custom dir, only folders inside ~/.claude-accounts
new_env u '{"main":"m","accounts":{"m":{"email":"m@x","dir":"~/.claude"},"s":{"email":"s@x","dir":"~/Documents/custom"},"t":{"email":"t@x"}}}'
mkdir -p "$HOME/Documents/custom" "$HOME/.claude-accounts/t"; echo precious > "$HOME/Documents/custom/f.txt"; echo login > "$HOME/.claude-accounts/t/.credentials.json"
bash "$SCRIPTS_DIR/uninstall.sh" --delete-folders >/dev/null 2>&1
assert_eq precious "$(cat "$HOME/Documents/custom/f.txt")" 'custom dir kept'
assert_no_file "$HOME/.claude-accounts/t" 'folder inside ~/.claude-accounts deleted'

# default account missing at run time: clear error, nothing written
new_env d '{"main":"m","accounts":{"m":{"email":"m@x","dir":"~/.claude"}}}'; stub_claude
write_accounts '{"main":"m","default":"ghost","accounts":{"m":{"email":"m@x","dir":"~/.claude"}}}'
out=$(bash "$SCRIPTS_DIR/cc.sh" </dev/null 2>&1); status=$?
assert_eq 1 "$status" 'invalid default aborts'; assert_contains "$out" 'does not exist' 'says why'; assert_no_file "$HOME/claude-call.log" 'claude not run'
assert_no_file "$HOME/.claude/settings.json" 'settings.json not written'

# e-mail comparison ignores case (like the Windows version)
new_env e '{"main":"m","accounts":{"m":{"email":"Me@Example.com","dir":"~/.claude"}}}'; stub_claude
STUB_EMAIL=me@example.COM bash "$SCRIPTS_DIR/cc.sh" </dev/null >/dev/null 2>&1; assert_eq 0 "$?" 'different case is the same e-mail'
assert_ok same_email A@B.C a@b.c; assert_fails same_email a@b.c x@b.c

# PATH block: a begin marker without an end marker is left alone, never duplicated
fresh_home p; . "$SCRIPTS_DIR/lib.sh"; . "$SCRIPTS_DIR/shellrc.sh"; export SHELL=/bin/zsh
printf 'export A=1\n# >>> account-switcher >>>\nexport B=2\n' > "$HOME/.zshrc"
before=$(cat "$HOME/.zshrc"); remove_path_block >/dev/null 2>&1
assert_eq "$before" "$(cat "$HOME/.zshrc")" 'unbalanced block: file untouched'
# appending never rewrites existing content, with or without a trailing newline
printf 'export A=1' > "$HOME/.zshrc"; add_path_block >/dev/null
assert_eq 'export A=1' "$(head -1 "$HOME/.zshrc")" 'first line kept'; assert_eq 1 "$(grep -c 'account-switcher >>>' "$HOME/.zshrc")" 'one block'
remove_path_block >/dev/null; assert_eq 'export A=1' "$(cat "$HOME/.zshrc")" 'round trip restores the file'

# CLAUDE.md: markers in the wrong order are not treated as a block
printf 'x\n<!-- account-switcher:end -->\nmid\n<!-- account-switcher:begin -->\ny\n' > "$HOME/.claude/CLAUDE.md"
before=$(cat "$HOME/.claude/CLAUDE.md"); remove_claude_md_block; assert_eq "$before" "$(cat "$HOME/.claude/CLAUDE.md")" 'out-of-order markers: untouched'
# a symlinked CLAUDE.md that only held our block stays a symlink (emptied, not deleted)
new_env sy '{"main":"a","accounts":{"a":{"email":"a@x"}}}'
update_claude_md; mv "$HOME/.claude/CLAUDE.md" "$HOME/dot.md"; ln -s "$HOME/dot.md" "$HOME/.claude/CLAUDE.md"
remove_claude_md_block; assert_link "$HOME/.claude/CLAUDE.md" 'symlink kept'; assert_eq 0 "$(wc -c < "$HOME/dot.md" | tr -d ' ')" 'target emptied'
# indentation of the user's first line survives removal
printf '    indented\n\n' > "$HOME/dot.md"; update_claude_md; remove_claude_md_block
assert_eq '    indented' "$(cat "$HOME/dot.md")" 'leading indentation preserved'

# wrapper in bin/ that is a symlink is replaced, not written through
fresh_home w; write_accounts '{"main":"m","accounts":{"m":{"email":"m@x"}}}'; stub_claude; export SHELL=/bin/zsh
mkdir -p "$HOME/.claude-accounts/bin"; echo untouched > "$HOME/victim"; ln -s "$HOME/victim" "$HOME/.claude-accounts/bin/cca"
bash "$SCRIPTS_DIR/install.sh" --no-path >/dev/null 2>&1
assert_eq untouched "$(cat "$HOME/victim")" 'symlink target not overwritten'

# date_fmt picks the right flavour of date
. "$SCRIPTS_DIR/lib.sh"; assert_eq 2023-11-14 "$(TZ=UTC date_fmt 1700000000 %Y-%m-%d)" 'date_fmt'

finish
