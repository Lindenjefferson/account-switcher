#!/usr/bin/env bash
# Updates the accounts block in ~/.claude/CLAUDE.md and creates/updates the folders of the accounts listed
# in accounts.json. PATH is handled by install.sh. Idempotent: safe to run again at any time (for example,
# after adding an account).
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$DIR/lib.sh" || exit 1

load_accounts || exit 1
count=0; for flag in "${ACC_MASTER[@]}"; do [ "$flag" = 1 ] && count=$((count + 1)); done
[ "$count" -le 1 ] || { msg_red 'More than one account uses the master folder ~/.claude'; exit 1; }
CFG_COMMAND=${CFG_COMMAND:-cca}
command_re='^[[:alnum:]_][[:alnum:]_.-]*$'
[[ $CFG_COMMAND =~ $command_re ]] || { msg_red "Invalid command name: '$CFG_COMMAND'"; exit 1; }

# Before the links: if CLAUDE.md does not exist yet, it must exist to be linked.
update_claude_md || exit 1
echo "CLAUDE.md: accounts block updated in $MASTER_DIR/CLAUDE.md"

for name in "${ACC_NAME[@]}"; do
    select_account "$name"
    if [ "$A_MASTER" = 1 ]; then echo "[$A_NAME] uses the master folder $A_DIR, nothing to do"; continue; fi
    messages=$(sync_account_links)
    if [ -n "$messages" ]; then while IFS= read -r line; do echo "[$A_NAME] $line"; done <<< "$messages"
    else echo "[$A_NAME] ok, already set up"; fi
done

# RC off for sessions opened without cc; status line with account and usage.
for line in "$(disable_shared_rc)" "$(register_statusline)"; do [ -n "$line" ] && echo "$line"; done
exit 0
