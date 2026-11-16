#!/usr/bin/env bash
# uninstall.sh [--delete-folders]
# Undoes the installation without touching the content of the master folder ~/.claude: removes only the
# links of the extra accounts, the PATH block in the shell startup files, the accounts block of CLAUDE.md
# and the account/usage statusLine of settings.json. With --delete-folders it also deletes the folders of
# the extra accounts (their logins; you will need /login again).
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$DIR/lib.sh" || exit 1
. "$DIR/shellrc.sh" || exit 1

delete_folders=0
for arg in "$@"; do
    case "$arg" in
        --delete-folders) delete_folders=1 ;;
        *) msg_red "Unknown argument: $arg (use --delete-folders)"; exit 1 ;;
    esac
done

load_accounts || exit 1
for name in "${ACC_NAME[@]}"; do
    select_account "$name"
    [ "$A_MASTER" = 1 ] && continue
    remove_account_links
    echo "[$A_NAME] links removed"
    if [ "$delete_folders" = 1 ] && [ -d "$A_DIR" ]; then
        # Only ever delete a folder that lives inside ~/.claude-accounts (never a custom dir, never the folder itself).
        case "$A_DIR" in
            "$BASE_DIR"/?*) ;;
            *) msg_yellow "[$A_NAME] folder $A_DIR is outside $BASE_DIR: links removed, folder kept (delete it yourself if you want)"; continue ;;
        esac
        if account_has_links; then msg_red "There are still links in $A_DIR; nothing deleted"; exit 1; fi
        # rm -r never follows symlinks, but the check above guarantees none to the master folder is left.
        rm -rf -- "$A_DIR"
        echo "[$A_NAME] folder deleted"
    fi
done

remove_path_block
remove_claude_md_block
echo 'CLAUDE.md: accounts block removed'

# The statusLine goes only if it is ours; remoteControlAtStartup false stays (safe without cc).
line=$(unregister_statusline); [ -n "$line" ] && echo "$line"

if [ -f "$BASE_DIR/cc.sh" ]; then mv -- "$BASE_DIR/cc.sh" "$BASE_DIR/cc.sh.disabled"; echo 'command disabled (cc.sh.disabled); install.sh enables it again'; fi
exit 0
