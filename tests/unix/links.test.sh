#!/usr/bin/env bash
. "$(dirname "$0")/helpers.sh"

new_env l '{"main":"m","accounts":{"m":{"email":"m@x","dir":"~/.claude"},"s":{"email":"s@x"}}}'
echo '{"theme":"dark"}' > "$HOME/.claude/settings.json"
echo 'hist' > "$HOME/.claude/history.jsonl"
mkdir -p "$HOME/.claude/skills" "$HOME/.claude/projects"; echo x > "$HOME/.claude/skills/one.md"
cat > "$HOME/.claude.json" <<'JSON'
{"mcpServers":{"a":{}},"projects":{"/p":{}},"oauthAccount":{"emailAddress":"SECRET@x"},"cachedUsageUtilization":{"x":1},"numStartups":3}
JSON
select_account s

# first sync: links for what exists in the master folder, nothing for what does not
out=$(sync_account_links)
assert_link "$A_DIR/settings.json" 'settings linked'
assert_eq "$HOME/.claude/settings.json" "$(readlink "$A_DIR/settings.json")" 'link target'
assert_link "$A_DIR/skills" 'skills dir linked'
assert_no_file "$A_DIR/CLAUDE.md" 'no link for a file that does not exist in master'
assert_no_file "$A_DIR/rules" 'no link for a dir that does not exist in master'
assert_contains "$out" "link: $A_DIR/settings.json" 'reports the link'

# seed .claude.json: only configuration keys, never account data
seed=$(cat "$A_DIR/.claude.json")
assert_contains "$seed" mcpServers 'seed has mcpServers'
assert_not_contains "$seed" SECRET 'seed has no account data'
assert_not_contains "$seed" cachedUsageUtilization 'seed has no usage cache'
assert_not_contains "$seed" numStartups 'seed has no counters'
assert_eq 600 "$(stat -c %a "$A_DIR/.claude.json" 2>/dev/null || stat -f %Lp "$A_DIR/.claude.json")" 'seed is private (0600)'

# idempotent: second run prints nothing and keeps the seed
echo '{"mine":1}' > "$A_DIR/.claude.json"
out=$(sync_account_links)
assert_eq '' "$out" 'second sync is silent'
assert_eq '{"mine":1}' "$(cat "$A_DIR/.claude.json")" 'existing .claude.json untouched'

# a program replaced the link with a regular file that is NEWER: change goes to master, backup of master kept
rm "$A_DIR/settings.json"; echo '{"theme":"light"}' > "$A_DIR/settings.json"
touch -t 203001010000 "$A_DIR/settings.json"
out=$(sync_account_links)
assert_link "$A_DIR/settings.json" 'relinked'
assert_eq '{"theme":"light"}' "$(cat "$HOME/.claude/settings.json")" 'newer change reached master'
assert_contains "$out" 'carried over to the master folder' 'reports the carry-over'
assert_eq 1 "$(ls "$HOME"/.claude-accounts/backups/relink_s_*_settings.json | wc -l | tr -d ' ')" 'master version backed up'

# regular file that is OLDER: master wins, the local copy is backed up
rm "$A_DIR/history.jsonl"; echo 'old local' > "$A_DIR/history.jsonl"; touch -t 200001010000 "$A_DIR/history.jsonl"
sync_account_links >/dev/null
assert_eq hist "$(cat "$HOME/.claude/history.jsonl")" 'master unchanged'
assert_link "$A_DIR/history.jsonl" 'relinked after older copy'
assert_contains "$(cat "$HOME"/.claude-accounts/backups/relink_s_*_history.jsonl)" 'old local' 'local copy backed up'

# a real folder where a link should be is moved to backups, content preserved
rm "$A_DIR/projects"; mkdir "$A_DIR/projects"; echo keep > "$A_DIR/projects/f.txt"
out=$(sync_account_links)
assert_link "$A_DIR/projects" 'projects relinked'
assert_contains "$out" 'moved to' 'reports the move'
assert_eq keep "$(cat "$HOME"/.claude-accounts/backups/relink_s_*_projects/f.txt)" 'folder content preserved'

# master account never gets links
select_account m; assert_eq '' "$(sync_account_links)" 'master account: nothing to do'

# remove_account_links removes links only, never the master content; keeps the login file and foreign links
select_account s
echo login > "$A_DIR/.credentials.json"
ln -s /tmp "$A_DIR/foreign"
assert_ok account_has_links
remove_account_links
assert_no_file "$A_DIR/settings.json" 'link gone'
assert_no_file "$A_DIR/skills" 'dir link gone'
assert_eq one "$(cat "$HOME/.claude/skills/one.md" | sed 's/x/one/')" 'master skill file intact'
assert_file "$HOME/.claude/skills/one.md" 'master content intact'
assert_file "$HOME/.claude/settings.json" 'master settings intact'
assert_file "$A_DIR/.credentials.json" 'login file kept'
assert_link "$A_DIR/foreign" 'foreign link kept'
assert_fails account_has_links

finish
