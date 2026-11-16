#!/usr/bin/env bash
. "$(dirname "$0")/helpers.sh"
export TZ=UTC

fresh_home c
write_accounts '{"main":"m","accounts":{"m":{"email":"m@x","dir":"~/.claude"},"s":{"email":"s@x","rc":true},"t":{"email":"t@x"}}}'
echo '{"theme":"dark"}' > "$HOME/.claude/settings.json"
stub_claude
CC="bash $SCRIPTS_DIR/cc.sh"
WORK="$HOME/proj"; mkdir -p "$WORK"; cd "$WORK" || exit 1
call() { cat "$HOME/claude-call.log"; }

# default account = the master one: no CLAUDE_CONFIG_DIR, session named "folder (account)", RC off
export STUB_EMAIL=m@x
$CC </dev/null 2>/dev/null; status=$?
assert_eq 0 "$status" 'exit status propagated (0)'
assert_contains "$(call)" 'CONFIG_DIR=<unset>' 'master account runs without CLAUDE_CONFIG_DIR'
assert_contains "$(call)" $'ARG=-n\nARG=proj (m)' 'session named folder (account)'
assert_contains "$(call)" "ARG=$HOME/.claude-accounts/rc/off.json" 'RC off for m'
assert_eq false "$(jq -r .remoteControlAtStartup "$HOME/.claude/settings.json")" 'shared settings.json now has RC off'
assert_eq dark "$(jq -r .theme "$HOME/.claude/settings.json")" 'theme kept'

# named account with rc:true; links are created; arguments are forwarded in order
export STUB_EMAIL=s@x
$CC s -p 'hello world' </dev/null 2>/dev/null
assert_contains "$(call)" "CONFIG_DIR=$HOME/.claude-accounts/s" 'CLAUDE_CONFIG_DIR set to the account folder'
assert_contains "$(call)" $'ARG=-p\nARG=hello world' 'arguments with spaces forwarded intact'
assert_not_contains "$(call)" 'ARG=-n' '-p: no session name added'
assert_contains "$(call)" "ARG=$HOME/.claude-accounts/rc/on.json" 'RC on for s'
assert_link "$HOME/.claude-accounts/s/settings.json" 'links created'

# --no-rc is consumed, --rc is not
$CC s --no-rc </dev/null 2>/dev/null; assert_not_contains "$(call)" 'ARG=--no-rc' '--no-rc consumed'; assert_contains "$(call)" 'off.json' '--no-rc turns it off'
export STUB_EMAIL=t@x; $CC t --rc mysession </dev/null 2>/dev/null
assert_contains "$(call)" $'ARG=--rc\nARG=mysession' '--rc forwarded to claude'

# the user's own -n / --resume suppress the automatic name
export STUB_EMAIL=s@x; $CC s --resume abc </dev/null 2>/dev/null; assert_not_contains "$(call)" 'ARG=-n' '--resume: no automatic name'

# exit status of claude is propagated
STUB_EXIT=7 $CC s </dev/null 2>/dev/null; assert_eq 7 "$?" 'exit status 7 propagated'

# unknown account
rm -f "$HOME/claude-call.log"
out=$($CC nope </dev/null 2>&1); status=$?
assert_eq 1 "$status" 'unknown account fails'; assert_contains "$out" "Account 'nope' does not exist" 'message names the account'; assert_contains "$out" 'm, s, t' 'message lists accounts'
assert_no_file "$HOME/claude-call.log" 'claude not run'

# e-mail mismatch without a terminal: refuses to open
STUB_EMAIL=other@x; export STUB_EMAIL
out=$($CC s </dev/null 2>&1); status=$?
assert_eq 1 "$status" 'mismatch aborts without a terminal'; assert_contains "$out" 'WARNING' 'mismatch warning'; assert_no_file "$HOME/claude-call.log" 'claude not run on mismatch'

# not logged in: warns and still opens (so the user can /login)
STUB_LOGGED=0; export STUB_LOGGED
out=$($CC s </dev/null 2>&1); assert_contains "$out" 'not logged in yet: use /login with s@x' 'login hint'; assert_file "$HOME/claude-call.log" 'claude still run'
unset STUB_LOGGED; export STUB_EMAIL=s@x

# parent-session variables are dropped, user configuration is kept
CLAUDECODE=1 CLAUDE_CODE_CHILD_SESSION=1 CLAUDE_CODE_USE_BEDROCK=1 $CC s </dev/null 2>/dev/null
assert_contains "$(call)" 'CLAUDECODE=<unset>' 'CLAUDECODE not inherited'
assert_contains "$(call)" 'CHILD=<unset>' 'child-session flag not inherited'
assert_contains "$(call)" 'USE_BEDROCK=1' 'user configuration inherited'

# a link replaced by a regular file during the session is repaired when claude exits
cat > "$HOME/stubs/claude" <<'STUB'
#!/bin/sh
if [ "$1" = auth ]; then printf '{"loggedIn": true, "email": "s@x"}\n'; exit 0; fi
rm -f "$CLAUDE_CONFIG_DIR/settings.json"; echo '{"theme":"from-session"}' > "$CLAUDE_CONFIG_DIR/settings.json"; touch -t 203001010000 "$CLAUDE_CONFIG_DIR/settings.json"
STUB
$CC s </dev/null 2>/dev/null
assert_link "$HOME/.claude-accounts/s/settings.json" 'link repaired after the session'
assert_eq from-session "$(jq -r .theme "$HOME/.claude/settings.json")" 'session change reached the master folder'
stub_claude

# high usage: warning + suggestion on stderr; with no terminal it still opens
now=$(date +%s)
mk_cache() { printf '{"cachedUsageUtilization":{"fetchedAtMs":%s,"utilization":{"five_hour":{"utilization":%s,"resets_at":null},"seven_day":{"utilization":%s,"resets_at":null}}}}' "$((now * 1000))" "$2" "$3" > "$1"; }
mk_cache "$HOME/.claude-accounts/s/.claude.json" 92 10
mk_cache "$HOME/.claude-accounts/t/.claude.json" 5 6 2>/dev/null || { mkdir -p "$HOME/.claude-accounts/t"; mk_cache "$HOME/.claude-accounts/t/.claude.json" 5 6; }
rm -f "$HOME/claude-call.log"
out=$($CC s </dev/null 2>&1)
assert_contains "$out" 'Account s has high usage: Session: 92%' 'high usage warning'
assert_contains "$out" 'Suggestion: cca t (Session: 5%' 'suggests the account with most headroom'
assert_file "$HOME/claude-call.log" 'non-interactive: still opens'
mk_cache "$HOME/.claude-accounts/s/.claude.json" 50 10
out=$($CC s </dev/null 2>&1); assert_not_contains "$out" 'high usage' 'no warning below the limit'

# -l lists every account with the markers
out=$($CC -l </dev/null 2>&1); status=$?
assert_eq 0 "$status" '-l exits 0'
assert_match "$out" 'Account +Role +Expected +Logged in +RC +Usage' 'table header'
assert_match "$out" 'm \*' 'default marked with *'
assert_match "$out" 's +[^ ]* *s@x' 'row for s'
assert_contains "$out" 'DIFFERENT from the configured one' 'e-mail mismatch flagged (the stub answers s@x for m)'
write_accounts '{"main":"m","accounts":{"m":{"email":"m@x","dir":"~/.claude"},"u":{"email":"u@x"}}}'
out=$($CC -l </dev/null 2>&1); assert_contains "$out" 'folder not created (run setup-accounts.sh)' 'account without a folder'

finish
