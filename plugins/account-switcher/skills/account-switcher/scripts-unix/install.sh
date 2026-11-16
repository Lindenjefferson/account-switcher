#!/usr/bin/env bash
# install.sh [--check] [--no-path]
# Copies the scripts of this folder to ~/.claude-accounts, takes a backup the first time, creates the accounts
# (setup-accounts.sh), puts the command on PATH and updates the global CLAUDE.md.
# Prerequisite: ~/.claude-accounts/accounts.json already written (see accounts.example.json).
# --check:   only checks the environment and lists conflicts, changing nothing.
# --no-path: does not edit the shell startup files (you add ~/.claude-accounts/bin to PATH yourself).
SOURCE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$SOURCE/lib.sh" || exit 1
. "$SOURCE/shellrc.sh" || exit 1

check_only=0; edit_path=1
for arg in "$@"; do
    case "$arg" in
        --check) check_only=1 ;;
        --no-path) edit_path=0 ;;
        *) msg_red "Unknown argument: $arg (use --check and/or --no-path)"; exit 1 ;;
    esac
done

# ---- checks ----
problems=(); warnings=()
command -v jq >/dev/null 2>&1 || problems[${#problems[@]}]="jq not found (macOS: brew install jq; Debian/Ubuntu: apt install jq)"
command -v curl >/dev/null 2>&1 || problems[${#problems[@]}]="curl not found"
[ -x "$CLAUDE" ] || problems[${#problems[@]}]="claude not found (looked on PATH and in $CLAUDE)"
if [ ! -f "$BASE_DIR/accounts.json" ]; then
    problems[${#problems[@]}]="missing $BASE_DIR/accounts.json (copy accounts.example.json and edit it)"
elif command -v jq >/dev/null 2>&1; then
    if load_accounts; then
        CFG_COMMAND=${CFG_COMMAND:-cca}
        command_re='^[[:alnum:]_][[:alnum:]_.-]*$'
        if ! [[ $CFG_COMMAND =~ $command_re ]]; then
            problems[${#problems[@]}]="invalid \"command\" in accounts.json: '$CFG_COMMAND'"
        else
            # bin/ goes to the END of PATH, so anything that already has this name wins and ours would never run.
            # "cc" is the C compiler on macOS and Linux, which is why the default command is cca.
            existing=$(PATH=$(printf '%s' "$PATH" | tr ':' '\n' | grep -vxF "$BASE_DIR/bin" | paste -sd: -) command -v "$CFG_COMMAND" 2>/dev/null)
            [ -n "$existing" ] && problems[${#problems[@]}]="a command named '$CFG_COMMAND' already exists ($existing): pick another \"command\" in accounts.json"
        fi
    else
        problems[${#problems[@]}]="accounts.json is not usable (see the message above)"
    fi
fi
case "${SHELL##*/}" in zsh|bash|fish) ;; *) warnings[${#warnings[@]}]="unrecognized shell (${SHELL:-unset}): the PATH block goes to ~/.profile" ;; esac

echo "claude: $CLAUDE"
echo "command: ${CFG_COMMAND:-cca}"
for w in "${warnings[@]}"; do msg_yellow "WARNING: $w"; done
for p in "${problems[@]}"; do msg_red "PROBLEM: $p"; done
[ "$check_only" = 1 ] && exit 0
if [ ${#problems[@]} -gt 0 ]; then msg_red 'Fix the problems above before installing.'; exit 1; fi

# ---- backup (first installation only) ----
if ! ls -d "$BASE_DIR"/backups/install_* >/dev/null 2>&1; then
    backup="$BASE_DIR/backups/install_$(date +%Y-%m-%d_%H%M%S)"
    mkdir -p -- "$backup/.claude/plugins"
    [ -f "$MASTER_STATE" ] && cp -p -- "$MASTER_STATE" "$backup/"
    for f in settings.json history.jsonl CLAUDE.md; do [ -f "$MASTER_DIR/$f" ] && cp -p -- "$MASTER_DIR/$f" "$backup/.claude/"; done
    for f in "$MASTER_DIR"/plugins/*.json; do [ -f "$f" ] && cp -p -- "$f" "$backup/.claude/plugins/"; done
    echo "backup: $backup"
fi

# ---- copy the scripts (never overwrites accounts.json) ----
mkdir -p -- "$BASE_DIR/bin"
if [ "$(cd "$BASE_DIR" && pwd -P)" != "$(cd "$SOURCE" && pwd -P)" ]; then
    for f in "$SOURCE"/*.sh "$SOURCE"/CLAUDE.template.md "$SOURCE"/accounts.example.json; do
        [ -f "$f" ] && cp -p -- "$f" "$BASE_DIR/"
    done
fi
chmod +x "$BASE_DIR"/*.sh
rm -f -- "$BASE_DIR/cc.sh.disabled"

# The command is a tiny wrapper in bin/, named after "command" in accounts.json. Wrappers left by an
# earlier name are removed (only the ones that carry our marker).
for f in "$BASE_DIR"/bin/*; do
    [ -f "$f" ] && [ "${f##*/}" != "$CFG_COMMAND" ] && grep -qF "$MARK_WRAPPER" "$f" && rm -f -- "$f"
done
rm -f -- "$BASE_DIR/bin/$CFG_COMMAND"      # never write through a symlink someone put there
cat > "$BASE_DIR/bin/$CFG_COMMAND" <<WRAPPER
#!/bin/sh
$MARK_WRAPPER
dir=\$(cd "\$(dirname "\$0")/.." && pwd)
[ -f "\$dir/cc.sh" ] || { echo "$CFG_COMMAND is disabled (uninstall.sh was run); run install.sh to enable it again" >&2; exit 1; }
exec bash "\$dir/cc.sh" "\$@"
WRAPPER
chmod +x "$BASE_DIR/bin/$CFG_COMMAND"
echo "scripts copied to $BASE_DIR"

# ---- accounts and CLAUDE.md ----
bash "$BASE_DIR/setup-accounts.sh" || exit 1

# ---- PATH ----
if [ "$edit_path" = 1 ]; then
    add_path_block
    path_has_bin || echo "Open a NEW terminal so that '$CFG_COMMAND' is found."
else
    echo "PATH: not edited (--no-path). Add this to your shell startup file: export PATH=\"\$PATH:$BASE_DIR/bin\""
fi

bash "$BASE_DIR/cc.sh" -l
