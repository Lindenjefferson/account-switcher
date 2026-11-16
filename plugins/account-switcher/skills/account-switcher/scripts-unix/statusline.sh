#!/usr/bin/env bash
# Claude Code status line: "<account> · Session: x% (resets in 2h05) · Week: y% (resets in 3d 4h)",
# with the percentage in yellow from the usage warning and red from 95%. Claude Code sends the session
# JSON on stdin. On any failure it prints an empty line.
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

render() {
    . "$DIR/lib.sh" || return 1
    local input account=''
    input=$(cat)
    if load_accounts 2>/dev/null && current_account; then account=$A_NAME; else CFG_WARN=80; fi
    printf '%s' "$input" | format_statusline "$account" "$CFG_WARN"
}

output=$(render 2>/dev/null) || output=''
printf '%s' "$output"
