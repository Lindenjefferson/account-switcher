#!/usr/bin/env bash
. "$(dirname "$0")/helpers.sh"

# main account without "dir" uses the master folder; the others get ~/.claude-accounts/<name>
new_env a '{"main":"p","accounts":{"p":{"email":"p@x","rc":true},"s":{"email":"s@x"},"t":{"email":"t@x","rc":"true"}}}'
assert_eq p "$CFG_MAIN" 'main'
assert_eq p "$CFG_DEFAULT" 'default falls back to main'
assert_eq p "$CFG_PUBLISH" 'publish falls back to main'
assert_eq 80 "$CFG_WARN" 'default warning'
select_account p; assert_eq "$HOME/.claude" "$A_DIR" 'main dir'; assert_eq 1 "$A_MASTER" 'main is master'; assert_eq 1 "$A_RC" 'rc true'
select_account s; assert_eq "$HOME/.claude-accounts/s" "$A_DIR" 'secondary dir'; assert_eq 0 "$A_MASTER" 'secondary not master'; assert_eq 0 "$A_RC" 'rc off by default'
select_account t; assert_eq 0 "$A_RC" 'rc only when boolean true'
assert_eq 'p, s, t' "$(accounts_list)" 'file order kept'

# explicit dir: only that account is the master one; "~" expands; trailing slash ignored
new_env b '{"main":"p","default":"s","publish":"s","command":"zz","chrome":"p","usageWarning":70,"accounts":{"p":{"email":"p@x","dir":"~/custom/"},"s":{"email":"s@x","dir":"~/.claude/"}}}'
select_account p; assert_eq "$HOME/custom" "$A_DIR" 'tilde expanded, slash trimmed'; assert_eq 0 "$A_MASTER" 'p not master'
select_account s; assert_eq 1 "$A_MASTER" 's is master (explicit dir)'
assert_eq s "$CFG_DEFAULT" 'default'; assert_eq s "$CFG_PUBLISH" 'publish'; assert_eq zz "$CFG_COMMAND" 'command'
assert_eq p "$CFG_CHROME" 'chrome'; assert_eq 70 "$CFG_WARN" 'warning'

# usageWarning validation
new_env c '{"main":"p","usageWarning":"x","accounts":{"p":{"email":"p@x"}}}'; assert_eq 80 "$CFG_WARN" 'string warning -> 80'
new_env c '{"main":"p","usageWarning":150,"accounts":{"p":{"email":"p@x"}}}'; assert_eq 80 "$CFG_WARN" 'out of range -> 80'
new_env c '{"main":"p","usageWarning":7.5,"accounts":{"p":{"email":"p@x"}}}'; assert_eq 80 "$CFG_WARN" 'non-integer -> 80'

# invalid inputs are rejected with a non-zero status
fresh_home d
write_accounts '{"main":"p","accounts":{"../x":{"email":"a@x"}}}'; . "$SCRIPTS_DIR/lib.sh" 2>/dev/null
assert_fails load_accounts
write_accounts '{"main":"p","accounts":{"-x":{"email":"a@x"}}}'; assert_fails load_accounts
write_accounts '{"main":"p","accounts":{"a b":{"email":"a@x"}}}'; assert_fails load_accounts
write_accounts '{"accounts":{"a":{"email":"a@x"}}}'; assert_fails load_accounts
write_accounts '{"main":"a","accounts":{}}'; assert_fails load_accounts
write_accounts 'not json'; assert_fails load_accounts
rm "$HOME/.claude-accounts/accounts.json"; assert_fails load_accounts

# select_account on an unknown name
new_env e '{"main":"p","accounts":{"p":{"email":"p@x"}}}'
assert_fails select_account nope

# empty e-mail is kept as an empty field (not shifted)
new_env f '{"main":"p","accounts":{"p":{"dir":"~/.claude"},"q":{"email":"q@x"}}}'
select_account q; assert_eq 'q@x' "$A_EMAIL" 'email of q'
select_account p; assert_eq '' "$A_EMAIL" 'missing email is empty'

finish
