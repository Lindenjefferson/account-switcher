#!/usr/bin/env bash
. "$(dirname "$0")/helpers.sh"

new_env md '{"main":"a","default":"b","chrome":"a","accounts":{"a":{"email":"a@x","dir":"~/.claude"},"b":{"email":"b@x & co"},"c":{"email":"c@x","dir":"~/elsewhere/c"}}}'
MD="$HOME/.claude/CLAUDE.md"

# no file yet: created with the block only
update_claude_md
assert_contains "$(cat "$MD")" '<!-- account-switcher:begin -->' 'begin marker'
assert_contains "$(cat "$MD")" '| a | main | a@x | `~/.claude` (master folder) |' 'main row'
assert_contains "$(cat "$MD")" '| b | secondary, default of cca | b@x & co | `~/.claude-accounts/b` |' 'default row, & kept literally'
assert_contains "$(cat "$MD")" '| c | secondary | c@x | `~/elsewhere/c` |' 'custom dir shown'
assert_contains "$(cat "$MD")" 'publish on the main account, a (a@x)' 'publish account and e-mail'
assert_contains "$(cat "$MD")" '`a` (a@x)' 'chrome account'
assert_not_contains "$(cat "$MD")" '{{' 'no placeholder left'

# user text around the block survives; the block is replaced, not duplicated
printf '# Mine\n\n<!-- account-switcher:begin -->\nold\n<!-- account-switcher:end -->\n\nend of user text\n' > "$MD"
update_claude_md
assert_not_contains "$(cat "$MD")" STALE-BLOCK-TEXT 'old block replaced'
assert_eq 1 "$(grep -c 'account-switcher:begin' "$MD")" 'one block'
assert_contains "$(cat "$MD")" '# Mine' 'text before kept'
assert_contains "$(cat "$MD")" 'end of user text' 'text after kept'
update_claude_md; assert_eq 1 "$(grep -c 'account-switcher:begin' "$MD")" 'idempotent'

# existing file without block: appended after a blank line
printf '# Only user text\n' > "$MD"; update_claude_md
assert_eq '# Only user text' "$(head -1 "$MD")" 'user text first'
assert_contains "$(cat "$MD")" 'account-switcher:begin' 'block appended'

# removal leaves only the user text; a file that held only the block is deleted
remove_claude_md_block
assert_eq '# Only user text' "$(cat "$MD")" 'block removed'
rm "$MD"; update_claude_md; remove_claude_md_block; assert_no_file "$MD" 'file removed when only the block was in it'
remove_claude_md_block   # missing file: no error
assert_ok true

# no chrome configured
new_env md2 '{"main":"a","accounts":{"a":{"email":"a@x"}}}'
update_claude_md; assert_contains "$(cat "$HOME/.claude/CLAUDE.md")" 'logged in to account not set' 'chrome not set'

# a CLAUDE.md that is a symlink (dotfiles) stays a symlink
echo '# dot' > "$HOME/dotfile.md"; rm -f "$HOME/.claude/CLAUDE.md"; ln -s "$HOME/dotfile.md" "$HOME/.claude/CLAUDE.md"
update_claude_md; assert_link "$HOME/.claude/CLAUDE.md" 'symlink preserved'; assert_contains "$(cat "$HOME/dotfile.md")" 'account-switcher:begin' 'written through the link'

finish
