#!/usr/bin/env bash
# <command> [account] [--rc|--no-rc] [claude arguments...]   opens Claude Code as an account (default: "default" in accounts.json)
# <command> -l                                               lists the accounts with the logged-in e-mail, RC and usage
# --rc / --no-rc turns Remote Control on or off for this session only (default: "rc" of the account in accounts.json).
# <command> is the "command" key of accounts.json (default cca; see bin/ in ~/.claude-accounts).
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$DIR/lib.sh" || exit 1
clean_parent_session_env >/dev/null

load_accounts || exit 1
CMD=${CFG_COMMAND:-cca}

# Asks y/N on the terminal. Without a terminal there is no way to confirm: answers "no".
confirm() {
    local reply
    [ -r /dev/tty ] && [ -t 0 ] || return 1
    printf '%s (y/N) ' "$1" >&2
    read -r reply </dev/tty || return 1
    [[ $reply =~ ^[yY] ]]
}

if [ $# -gt 0 ] && { [ "$1" = -l ] || [ "$1" = --list ]; }; then
    rows="Account${SEP}Role${SEP}Expected${SEP}Logged in${SEP}RC${SEP}Usage"
    for name in "${ACC_NAME[@]}"; do
        select_account "$name"
        if [ ! -d "$A_DIR" ]; then logged="folder not created (run setup-accounts.sh)"
        elif account_status && [ "$ST_LOGGED" = 1 ]; then
            logged=$ST_EMAIL
            same_email "$ST_EMAIL" "$A_EMAIL" || logged="$logged  <-- DIFFERENT from the configured one"
        else logged='not logged in'; fi
        role=''
        [ "$A_NAME" = "$CFG_PUBLISH" ] && role='main'
        [ "$A_NAME" = "$CFG_CHROME" ] && role="${role:+$role, }Chrome"
        account_usage
        max=$(max_usage)
        flag=''; [ -n "$max" ] && [ "$max" -ge "$CFG_WARN" ] && flag='! '
        name_col=$A_NAME; [ "$A_NAME" = "$CFG_DEFAULT" ] && name_col="$A_NAME *"
        rc_text=off; [ "$A_RC" = 1 ] && rc_text=on
        rows="$rows"$'\n'"${name_col}${SEP}${role}${SEP}${A_EMAIL}${SEP}${logged}${SEP}${rc_text}${SEP}${flag}$(format_usage)"
    done
    printf '%s\n' "$rows" | print_table
    echo
    echo '* = default account (no argument); Chrome = account logged in to the Claude in Chrome extension'
    echo "RC = Remote Control when opening with $CMD (change it on the spot with --rc / --no-rc); ! = usage >= ${CFG_WARN}%"
    exit 0
fi

select_account "$CFG_DEFAULT" || { msg_red "Default account '$CFG_DEFAULT' does not exist in accounts.json"; exit 1; }
if [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; then
    if ! select_account "$1"; then
        msg_red "Account '$1' does not exist. Accounts: $(accounts_list)"
        exit 1
    fi
    shift
fi
split_rc_args "$@"

while IFS= read -r line; do [ -n "$line" ] && msg_gray "[$A_NAME] $line"; done <<EOT
$(sync_account_links)
EOT
line=$(disable_shared_rc)
[ -n "$line" ] && msg_gray "[$A_NAME] $line"
[ "$RC_USER_SETTINGS" = 1 ] && msg_yellow 'You passed --settings: RC follows whatever it says.'

# After claude exits (or cc gets a signal), recreate any link that a program may have broken.
finalize() { sync_account_links >/dev/null 2>&1; }
trap finalize EXIT

if ! account_status || [ "$ST_LOGGED" != 1 ]; then
    msg_yellow "Account $A_NAME is not logged in yet: use /login with $A_EMAIL"
elif ! same_email "$ST_EMAIL" "$A_EMAIL"; then
    msg_red "WARNING: the folder of account $A_NAME is logged in as $ST_EMAIL, but $A_EMAIL was expected."
    confirm 'Open anyway?' || exit 1
fi

# High usage: warns, suggests the account with the most headroom and asks (with -p or without a terminal
# it only warns, on stderr).
non_interactive=0
for arg in "${RC_REST[@]}"; do { [ "$arg" = -p ] || [ "$arg" = --print ]; } && non_interactive=1; done
[ -t 0 ] || non_interactive=1
account_usage
max=$(max_usage)
if [ -n "$max" ] && [ "$max" -ge "$CFG_WARN" ]; then
    msg_yellow "Account $A_NAME has high usage: $(format_usage)"
    current=$A_NAME
    pairs=(); texts=()
    for name in "${ACC_NAME[@]}"; do
        [ "$name" = "$current" ] && continue
        select_account "$name"; account_usage
        pairs[${#pairs[@]}]="$name=$(max_usage)"
        texts[${#texts[@]}]=$(format_usage)
    done
    select_account "$current"
    suggestion=$(suggest_account "$current" "${pairs[@]}")
    for i in "${!pairs[@]}"; do
        n=${pairs[$i]%%=*}; m=${pairs[$i]#*=}
        # Only suggests an account with known usage that is lower than the current one.
        if [ "$n" = "$suggestion" ] && [ -n "$m" ] && [ "$m" -lt "$max" ]; then msg_yellow "Suggestion: $CMD $suggestion (${texts[$i]})"; fi
    done
    if [ "$non_interactive" != 1 ]; then confirm 'Open anyway?' || exit 1; fi
fi

# Session name = folder (account), unless the user is resuming or already named it.
extra=()
named=0
for arg in "${RC_REST[@]}"; do
    case "$arg" in -n|--name|-r|--resume|-c|--continue|-p|--print) named=1 ;; esac
done
[ "$named" = 1 ] || extra=(-n "$(basename "$PWD") ($A_NAME)")
build_claude_args

run_claude "${extra[@]}" "${CLAUDE_ARGS[@]}"
exit $?
