#!/usr/bin/env bash
. "$(dirname "$0")/helpers.sh"
export TZ=UTC

new_env u '{"main":"m","accounts":{"m":{"email":"m@x","dir":"~/.claude"},"valid":{"email":"v@x"},"expired":{"email":"e@x"},"none":{"email":"n@x"},"reset":{"email":"r@x"}}}'
NOW=1800000000   # fixed "now": 2027-01-15 08:00:00 UTC
iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%S.123456+00:00 2>/dev/null || date -u -r "$1" +%Y-%m-%dT%H:%M:%S.123456+00:00; }
util() { printf '{"five_hour":{"utilization":%s,"resets_at":"%s"},"seven_day":{"utilization":%s,"resets_at":"%s"}}' "$1" "$(iso $((NOW + $2)))" "$3" "$(iso $((NOW + $4)))"; }
set_account() { # name expires_at_seconds_or_empty cached_util_json_or_empty
    mkdir -p "$HOME/.claude-accounts/$1"
    [ -n "$2" ] && printf '{"claudeAiOauth":{"accessToken":"tok-fake","expiresAt":%s}}' "$(( $2 * 1000 ))" > "$HOME/.claude-accounts/$1/.credentials.json"
    [ -n "$3" ] && printf '{"cachedUsageUtilization":{"fetchedAtMs":%s,"utilization":%s}}' "$(( (NOW - 1800) * 1000 ))" "$3" > "$HOME/.claude-accounts/$1/.claude.json"
    return 0
}
set_account valid $((NOW + 3600)) "$(util 2 7200 27 259200)"
set_account expired $((NOW - 3600)) "$(util 2 7200 27 259200)"
set_account reset '' "$(util 90 -600 30 259200)"

# the real usage_api: the token travels on curl's stdin, never in its arguments (ps would show those)
unset -f usage_api; . "$SCRIPTS_DIR/lib.sh"
cat > "$HOME/stubs/curl" <<'STUB'
#!/bin/sh
echo "$@" > "$HOME/curl-args.log"; cat > "$HOME/curl-stdin.log"; echo '{"five_hour":{"utilization":1,"resets_at":null}}'
STUB
chmod +x "$HOME/stubs/curl"
assert_eq '{"five_hour":{"utilization":1,"resets_at":null}}' "$(usage_api tok-fake 5)" 'usage_api returns the body'
assert_not_contains "$(cat "$HOME/curl-args.log")" tok-fake 'token not in curl arguments'
assert_contains "$(cat "$HOME/curl-args.log")" '-m 5' 'timeout passed'
assert_contains "$(cat "$HOME/curl-stdin.log")" 'Authorization: Bearer tok-fake' 'token on curl stdin'
assert_contains "$(cat "$HOME/curl-stdin.log")" 'https://api.anthropic.com/api/oauth/usage' 'usage endpoint'
rm "$HOME/stubs/curl"

# a token with odd characters is refused (it would end up in curl's config file)
mkdir -p "$HOME/.claude-accounts/weird"
printf '{"claudeAiOauth":{"accessToken":"a\"b","expiresAt":%s}}' "$(( (NOW + 3600) * 1000 ))" > "$HOME/.claude-accounts/weird/.credentials.json"
A_DIR="$HOME/.claude-accounts/weird"; assert_eq '' "$(account_token $NOW)" 'token with a quote is ignored'

# live usage when the token is valid (the HTTP call is replaced by a stub; the token must reach it)
usage_api() { echo "$1" > "$HOME/token-seen"; echo '{"five_hour":{"utilization":12,"resets_at":null},"seven_day":{"utilization":40,"resets_at":null}}'; }
select_account valid; account_usage 3 $NOW
assert_eq live "$U_SOURCE" 'live source'; assert_eq 12 "$U_FIVE" 'five'; assert_eq 40 "$U_WEEK" 'week'
assert_eq tok-fake "$(cat "$HOME/token-seen")" 'token passed to the API call'

# expired token: never calls the API, falls back to the saved value
usage_api() { echo called > "$HOME/api-called"; return 1; }
select_account expired; account_usage 3 $NOW
assert_eq saved "$U_SOURCE" 'saved source'; assert_eq 2 "$U_FIVE" 'saved five'; assert_eq 27 "$U_WEEK" 'saved week'
assert_no_file "$HOME/api-called" 'API not called with an expired token'

# API failure on a valid token: falls back to saved
select_account valid; account_usage 3 $NOW
assert_eq saved "$U_SOURCE" 'fallback after API failure'

# no folder, no login: nothing known
select_account none; account_usage 3 $NOW
assert_eq '' "$U_SOURCE" 'no source'; assert_eq '-' "$(format_usage $NOW)" 'dash when unknown'

# window that already reset counts as 0 with no reset time
select_account reset; account_usage 3 $NOW
assert_eq 0 "$U_FIVE" 'reset window is 0'; assert_eq '' "$U_RESET_FIVE" 'no reset time'; assert_eq 30 "$U_WEEK" 'other window kept'

# master account reads ~/.claude.json
select_account m; assert_eq "$HOME/.claude.json" "$(state_file)" 'master state file'
select_account valid; assert_eq "$HOME/.claude-accounts/valid/.claude.json" "$(state_file)" 'account state file'

# token never shows up in output
select_account valid; account_usage 3 $NOW
assert_not_contains "$(format_usage $NOW)" tok-fake 'token not in text'

# formatting
usage_convert "$(util 2 3600 27 259200)" live '' $NOW
assert_eq 'Session: 2% (resets in 1h00) · Week: 27% (resets in 3d 0h)' "$(format_usage $NOW)" 'format'
assert_eq 27 "$(max_usage)" 'max'
usage_convert "$(util 2 3600 27 259200)" saved $((NOW - 1800)) $NOW
assert_eq 'Session: 2% (resets in 1h00) · Week: 27% (resets in 3d 0h) (saved 07:30)' "$(format_usage $NOW)" 'saved today shows time'
usage_convert "$(util 2 3600 27 259200)" saved $((NOW - 259200)) $NOW
assert_match "$(format_usage $NOW)" '\(saved 12/01 08:00\)$' 'saved on another day shows date'
usage_convert "$(util 2 3600 27 259200)" saved '' $NOW
assert_match "$(format_usage $NOW)" '\(saved, no date\)$' 'saved without date'
usage_convert '{"five_hour":{"utilization":5,"resets_at":null}}' live '' $NOW
assert_eq 'Session: 5% · Week: ?' "$(format_usage $NOW)" 'missing week'
usage_convert "{\"five_hour\":{\"utilization\":5,\"resets_at\":$((NOW + 60))},\"seven_day\":{\"utilization\":1,\"resets_at\":\"$(date -u -d "@$((NOW + 14400))" +%Y-%m-%dT%H:%M:%S+02:00 2>/dev/null || date -u -r $((NOW + 14400)) +%Y-%m-%dT%H:%M:%S+02:00)\"}}" live '' $NOW
assert_eq 'Session: 5% (resets in 1min) · Week: 1% (resets in 2h00)' "$(format_usage $NOW)" 'unix seconds and +02:00 offsets'

# format_reset
assert_eq ' (resets in 45min)' "$(format_reset $((NOW + 2700)) $NOW)" '45 min'
assert_eq ' (resets in 2h05)' "$(format_reset $((NOW + 7500)) $NOW)" '2h05'
assert_eq ' (resets in 3d 4h)' "$(format_reset $((NOW + 76 * 3600)) $NOW)" '3d 4h'
assert_eq '' "$(format_reset $((NOW - 60)) $NOW)" 'past'
assert_eq '' "$(format_reset '' $NOW)" 'unknown'

# suggest_account: lowest max, never the excluded one, nothing when unknown
assert_eq b "$(suggest_account a a=90 b=50 c=)" 'lowest'
assert_eq '' "$(suggest_account a a=90 c=)" 'none known'
assert_eq a "$(suggest_account b a=10 b=5)" 'excluded skipped'

finish
