#!/usr/bin/env bash
# open-account.sh <account> [folder] [--rc | --no-rc]
# Opens a new terminal window with "cc <account>" in the given folder (default: current folder). Used by a
# session of one account to open a session of another account (e.g. the one that can publish artifacts)
# and then talk to it through SendMessage. The user sees and approves it in that window.
# macOS: Terminal.app (iTerm2 when TERM_PROGRAM says so). Linux: tmux window when inside tmux, else the
# first terminal emulator found.
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$DIR/lib.sh" || exit 1

account=''; folder=''; extra=()
for arg in "$@"; do
    case "$arg" in
        --rc|--no-rc) extra[${#extra[@]}]=$arg ;;
        *) if [ -z "$account" ]; then account=$arg; elif [ -z "$folder" ]; then folder=$arg
           else msg_red "Unexpected argument: $arg"; exit 1; fi ;;
    esac
done
[ -n "$account" ] || { msg_red 'Usage: open-account.sh <account> [folder] [--rc | --no-rc]'; exit 1; }
[ -n "$folder" ] || folder=$PWD

load_accounts || exit 1
account_exists "$account" || { msg_red "Account '$account' does not exist in accounts.json"; exit 1; }
[ -d "$folder" ] || { msg_red "Folder does not exist: $folder"; exit 1; }
folder=$(cd "$folder" && pwd)

# The calling session passes CLAUDECODE, CLAUDE_CODE_CHILD_SESSION and its messaging socket; inherited, the
# new session would behave like a child (no history) and talk over the wrong channel.
clean_parent_session_env >/dev/null

# A throwaway launcher script avoids any quoting trouble with AppleScript or terminal command lines.
launcher=$(mktemp "${TMPDIR:-/tmp}/open-account.XXXXXX") || exit 1
mv -- "$launcher" "$launcher.command" && launcher="$launcher.command"
{
    echo '#!/usr/bin/env bash'
    echo 'rm -f -- "$0"'
    printf 'cd %q || exit 1\n' "$folder"
    printf 'exec bash %q %q' "$BASE_DIR/cc.sh" "$account"
    for arg in "${extra[@]}"; do printf ' %q' "$arg"; done
    echo
} > "$launcher"
chmod +x "$launcher"

opened=0
if [ "$(uname -s)" = Darwin ]; then
    if [ "${TERM_PROGRAM:-}" = iTerm.app ]; then open -a iTerm "$launcher" && opened=1
    else open -a Terminal "$launcher" && opened=1; fi
elif [ -n "${TMUX:-}" ] && command -v tmux >/dev/null 2>&1; then
    tmux new-window -c "$folder" "bash $(printf '%q' "$launcher")" && opened=1
elif [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    for term in x-terminal-emulator gnome-terminal konsole xfce4-terminal kitty alacritty xterm; do
        command -v "$term" >/dev/null 2>&1 || continue
        case "$term" in
            gnome-terminal) "$term" -- bash "$launcher" ;;
            xfce4-terminal) "$term" -x bash "$launcher" ;;
            kitty) "$term" bash "$launcher" ;;
            *) "$term" -e bash "$launcher" ;;
        esac && { opened=1; break; }
    done
fi
if [ "$opened" != 1 ]; then
    rm -f -- "$launcher"
    msg_red "No terminal could be opened. Run it yourself: cd '$folder' && bash '$BASE_DIR/cc.sh' $account ${extra[*]}"
    exit 1
fi
echo "Window opened: cc $account ${extra[*]} in $folder. Use ListAgents to find the session '$(basename "$folder") ($account)'."
