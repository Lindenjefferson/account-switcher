#!/usr/bin/env bash
. "$(dirname "$0")/helpers.sh"

new_env r '{"main":"personal","accounts":{"personal":{"email":"p@x","rc":true},"work":{"email":"w@x"}}}'
SETTINGS="$HOME/.claude/settings.json"
set_settings() { printf '%s' "$1" > "$SETTINGS"; }
get() { jq -r "$1" "$SETTINGS"; }

# split_rc_args
select_account personal; split_rc_args
assert_eq 1 "$RC_ON" 'account default on'
select_account work; split_rc_args
assert_eq 0 "$RC_ON" 'account default off'
split_rc_args --rc my-session
assert_eq 1 "$RC_ON" '--rc turns on'; assert_eq '--rc my-session' "${RC_REST[*]}" '--rc stays for claude'
select_account personal; split_rc_args --no-rc -p hi
assert_eq 0 "$RC_ON" '--no-rc turns off'; assert_eq '-p hi' "${RC_REST[*]}" '--no-rc consumed'
select_account work; split_rc_args --rc --no-rc; assert_eq 0 "$RC_ON" 'last one wins (off)'
select_account personal; split_rc_args --no-rc --remote-control; assert_eq 1 "$RC_ON" 'last one wins (on)'
split_rc_args --settings x.json; assert_eq 1 "$RC_USER_SETTINGS" '--settings detected'
split_rc_args --settings=x.json; assert_eq 1 "$RC_USER_SETTINGS" '--settings= detected'
split_rc_args -p hi; assert_eq 0 "$RC_USER_SETTINGS" 'no --settings'
split_rc_args 'two words' ''; assert_eq 2 "${#RC_REST[@]}" 'arguments with spaces and empty ones survive'

# build_claude_args
select_account personal; split_rc_args -p hi; build_claude_args
assert_eq "-p hi --settings $HOME/.claude-accounts/rc/on.json" "${CLAUDE_ARGS[*]}" 'adds the on settings'
select_account work; split_rc_args; build_claude_args
assert_eq "$HOME/.claude-accounts/rc/off.json" "${CLAUDE_ARGS[1]}" 'off settings file'
split_rc_args --settings mine.json; build_claude_args
assert_eq '--settings mine.json' "${CLAUDE_ARGS[*]}" 'user settings wins, no duplicate'
assert_eq false "$(jq -r .remoteControlAtStartup "$HOME/.claude-accounts/rc/off.json")" 'off.json content'
assert_eq true "$(jq -r .remoteControlAtStartup "$HOME/.claude-accounts/rc/on.json")" 'on.json content'

# disable_shared_rc
set_settings "{
  \"theme\": \"dark\",
  \"remoteControlAtStartup\": true
}"
assert_ok test -n "$(disable_shared_rc)"
assert_eq false "$(get .remoteControlAtStartup)" 'true became false'
assert_eq dark "$(get .theme)" 'other keys kept'

set_settings '{"theme":"dark"}'
disable_shared_rc >/dev/null
assert_eq false "$(get .remoteControlAtStartup)" 'inserted when missing'; assert_eq dark "$(get .theme)" 'theme kept after insert'

set_settings '{}'; disable_shared_rc >/dev/null; assert_eq false "$(get .remoteControlAtStartup)" 'empty object'
set_settings ''; disable_shared_rc >/dev/null; assert_eq false "$(get .remoteControlAtStartup)" 'empty file'
rm -f "$SETTINGS"; disable_shared_rc >/dev/null; assert_eq false "$(get .remoteControlAtStartup)" 'missing file'

set_settings '{"remoteControlAtStartup": false, "theme":"dark"}'
before=$(cat "$SETTINGS")
assert_eq '' "$(disable_shared_rc)" 'already false: silent'
assert_eq "$before" "$(cat "$SETTINGS")" 'already false: file untouched'

bad='{"theme":"dark",}'
set_settings "$bad"
assert_contains "$(disable_shared_rc)" 'invalid settings.json' 'invalid JSON reported'
assert_eq "$bad" "$(cat "$SETTINGS")" 'invalid JSON never rewritten'

# a settings.json that is a symlink stays a symlink (dotfiles users)
echo '{"theme":"dark"}' > "$HOME/real-settings.json"; rm -f "$SETTINGS"; ln -s "$HOME/real-settings.json" "$SETTINGS"
disable_shared_rc >/dev/null
assert_link "$SETTINGS" 'symlink preserved'
assert_eq false "$(jq -r .remoteControlAtStartup "$HOME/real-settings.json")" 'written through the symlink'

finish
