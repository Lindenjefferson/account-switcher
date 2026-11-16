#!/usr/bin/env bash
. "$(dirname "$0")/helpers.sh"
export TZ=UTC

new_env sl '{"main":"a","accounts":{"a":{"email":"a@x","dir":"~/.claude"},"b":{"email":"b@x"}}}'
ESC=$'\033'
strip() { printf '%s' "$1" | sed "s/${ESC}\[[0-9;]*m//g"; }
entry() { printf '{"rate_limits":{"five_hour":{"used_percentage":%s},"seven_day":{"used_percentage":%s}}}' "$1" "$2"; }
NOW=1800000000

# colors: yellow from the warning limit, red from 95
out=$(entry 50 85 | format_statusline b 80 $NOW)
assert_contains "$out" "${ESC}[33m85%" 'yellow at 85'
assert_not_contains "$out" "${ESC}[33m50" '50 not colored'
assert_contains "$(entry 96 10 | format_statusline b 80 $NOW)" "${ESC}[31m96%" 'red at 96'
assert_not_contains "$(entry 50 10 | format_statusline b 80 $NOW)" "${ESC}[" 'no color below the limit'
assert_contains "$(entry 70 10 | format_statusline b 70 $NOW)" "${ESC}[33m70%" 'custom limit'

# text
assert_eq 'b · Session: 12% · Week: 27%' "$(strip "$(entry 12 27 | format_statusline b 80 $NOW)")" 'text'
assert_eq 'b · Session: 13% · Week: 27%' "$(strip "$(entry 12.6 27 | format_statusline b 80 $NOW)")" 'rounding'
assert_eq 'Session: 12% · Week: 27%' "$(strip "$(entry 12 27 | format_statusline '' 80 $NOW)")" 'no account'
assert_eq b "$(echo '{"model":"x"}' | format_statusline b 80 $NOW)" 'no rate_limits: only the account'
assert_eq 'b · Session: 5% · Week: ?' "$(strip "$(echo '{"rate_limits":{"five_hour":{"used_percentage":5}}}' | format_statusline b 80 $NOW)")" 'one window'

# reset times come in Unix seconds
out=$(printf '{"rate_limits":{"five_hour":{"used_percentage":85,"resets_at":%s},"seven_day":{"used_percentage":10,"resets_at":%s}}}' $((NOW + 7500)) $((NOW + 76 * 3600)) | format_statusline b 80 $NOW)
assert_contains "$out" "${ESC}[33m85%${ESC}[0m (resets in 2h05)" 'five-hour reset'
assert_contains "$(strip "$out")" 'Week: 10% (resets in 3d 4h)' 'weekly reset'

# invalid JSON: failure, no output
out=$(echo 'not json' | format_statusline b 80 $NOW); assert_eq '' "$out" 'invalid input prints nothing'

# current_account
select_account b; b_dir=$A_DIR
CLAUDE_CONFIG_DIR=$b_dir current_account; assert_eq b "$A_NAME" 'by CLAUDE_CONFIG_DIR'
CLAUDE_CONFIG_DIR="$b_dir/" current_account; assert_eq b "$A_NAME" 'trailing slash'
unset CLAUDE_CONFIG_DIR; current_account; assert_eq a "$A_NAME" 'unset means the master account'
CLAUDE_CONFIG_DIR=/nowhere; assert_fails current_account; unset CLAUDE_CONFIG_DIR

# the script end to end (own process, own HOME), including garbage on stdin
out=$(echo "$(entry 85 10)" | CLAUDE_CONFIG_DIR=$b_dir bash "$SCRIPTS_DIR/statusline.sh")
assert_eq 'b · Session: 85% · Week: 10%' "$(strip "$out")" 'script output'
out=$(echo 'garbage' | bash "$SCRIPTS_DIR/statusline.sh" 2>&1); assert_eq '' "$out" 'script prints nothing on garbage'
out=$(echo "$(entry 1 2)" | HOME=/nonexistent-home bash "$SCRIPTS_DIR/statusline.sh" 2>&1); assert_eq '' "$out" 'script prints nothing without HOME'

# register / unregister
SETTINGS="$HOME/.claude/settings.json"
set_settings() { printf '%s' "$1" > "$SETTINGS"; }
set_settings '{"theme":"dark"}'
register_statusline >/dev/null
assert_contains "$(jq -r .statusLine.command "$SETTINGS")" "$HOME/.claude-accounts/statusline.sh" 'command registered'
assert_eq dark "$(jq -r .theme "$SETTINGS")" 'theme kept'
before=$(cat "$SETTINGS"); assert_eq '' "$(register_statusline)" 'idempotent'; assert_eq "$before" "$(cat "$SETTINGS")" 'idempotent file'

other='{"theme":"dark","statusLine":{"type":"command","command":"other.sh"}}'
set_settings "$other"; assert_contains "$(register_statusline)" 'another statusLine' 'respects another statusLine'; assert_eq "$other" "$(cat "$SETTINGS")" 'other statusLine untouched'

bad='{"theme":"dark",}'
set_settings "$bad"; assert_contains "$(register_statusline)" invalid 'register: invalid JSON'; assert_eq "$bad" "$(cat "$SETTINGS")" 'register leaves invalid JSON'
bad2='{"statusLine":{"type":"command","command":"x/.claude-accounts/statusline.sh"},}'
set_settings "$bad2"; assert_contains "$(unregister_statusline)" invalid 'unregister: invalid JSON'; assert_eq "$bad2" "$(cat "$SETTINGS")" 'unregister leaves invalid JSON'

set_settings '{"theme":"dark"}'; register_statusline >/dev/null; unregister_statusline >/dev/null
assert_eq null "$(jq -r '.statusLine // "null"' "$SETTINGS")" 'removed (first key)'; assert_eq dark "$(jq -r .theme "$SETTINGS")" 'theme kept after removal'
set_settings '{"theme":"dark","statusLine":{"type":"command","command":"sh /h/.claude-accounts/statusline.sh"}}'
unregister_statusline >/dev/null; assert_eq dark "$(jq -r .theme "$SETTINGS")" 'removed (last key)'; assert_eq null "$(jq -r '.statusLine // "null"' "$SETTINGS")" 'last key gone'
set_settings '{"a":1,"statusLine":{"type":"command","command":"/h/.claude-accounts/statusline.sh"},"b":2}'
unregister_statusline >/dev/null; assert_eq '1 2' "$(jq -r '"\(.a) \(.b)"' "$SETTINGS")" 'removed (middle key)'
set_settings '{"statusLine":{"type":"command","command":"/h/.claude-accounts/statusline.sh"}}'
unregister_statusline >/dev/null; assert_eq '{}' "$(jq -c . "$SETTINGS")" 'removed (only key)'
set_settings "$other"; unregister_statusline >/dev/null; assert_eq "$other" "$(cat "$SETTINGS")" 'never removes another statusLine'
set_settings '{"statusLine":{"type":"command","command":"/me/bin/statusline.sh"}}'
unregister_statusline >/dev/null; assert_contains "$(cat "$SETTINGS")" '/me/bin/statusline.sh' 'a statusline.sh of someone else is not ours'

# multi-line, reformatted by the user
set_settings '{
  "theme": "dark",
  "statusLine": {
    "type": "command",
    "command": "/h/.claude-accounts/statusline.sh"
  },
  "x": 1
}'
unregister_statusline >/dev/null; assert_eq '1 dark' "$(jq -r '"\(.x) \(.theme)"' "$SETTINGS")" 'multi-line object removed'

finish
