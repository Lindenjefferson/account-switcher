#!/usr/bin/env bash
# User PATH on macOS and Linux. The counterpart of changing the user PATH on Windows is writing a block
# between markers in the shell startup file. Use with "source", after lib.sh.
# The block only appends ~/.claude-accounts/bin to the END of PATH, never the front: nothing that already
# exists is shadowed.

# File that receives the PATH block, according to the user's login shell.
shellrc_target() {
    local f
    case "${SHELL##*/}" in
        zsh) printf '%s' "${ZDOTDIR:-$HOME}/.zshrc" ;;
        bash)
            if [ "$(uname -s)" = Darwin ]; then
                # macOS terminals open login shells: bash reads .bash_profile (or the first one that exists).
                for f in .bash_profile .bash_login .profile; do
                    [ -f "$HOME/$f" ] && { printf '%s' "$HOME/$f"; return 0; }
                done
                printf '%s' "$HOME/.bash_profile"
            else printf '%s' "$HOME/.bashrc"; fi ;;
        fish) printf '%s' "$HOME/.config/fish/conf.d/account-switcher.fish" ;;
        *) printf '%s' "$HOME/.profile" ;;
    esac
}

# Every file that may hold the block (used to undo).
shellrc_candidates() {
    printf '%s\n' "${ZDOTDIR:-$HOME}/.zshrc" "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" \
        "$HOME/.bash_login" "$HOME/.profile" "$HOME/.config/fish/conf.d/account-switcher.fish" | awk '!seen[$0]++'
}

shellrc_block() {
    if [ "$1" = fish ]; then
        printf '%s\n%s\n%s\n' "$MARK_PATH_BEGIN" 'fish_add_path --append --path "$HOME/.claude-accounts/bin"' "$MARK_PATH_END"
    else
        printf '%s\n%s\n%s\n' "$MARK_PATH_BEGIN" \
            'case ":$PATH:" in *":$HOME/.claude-accounts/bin:"*) ;; *) export PATH="$PATH:$HOME/.claude-accounts/bin" ;; esac' \
            "$MARK_PATH_END"
    fi
}

# Does the PATH of the current session already have ~/.claude-accounts/bin?
path_has_bin() { case ":$PATH:" in *":$BASE_DIR/bin:"*) return 0 ;; *) return 1 ;; esac; }

# Puts the block in the shell file. Prints what it did (nothing if it was already there).
add_path_block() {
    local f current kind=posix
    f=$(shellrc_target)
    [ "${f##*.}" = fish ] && kind=fish
    if [ -f "$f" ] && grep -qF "$MARK_PATH_BEGIN" "$f"; then return 0; fi
    mkdir -p -- "$(dirname "$f")" || return 1
    if [ -s "$f" ]; then
        # Append only: the existing content is never rewritten. A newline first if the last byte is not one.
        { [ -n "$(tail -c 1 "$f")" ] && printf '\n'; printf '\n'; shellrc_block "$kind"; } >> "$f"
    else
        shellrc_block "$kind" > "$f"
    fi
    echo "PATH: block added to $f (takes effect in terminals opened from now on)"
}

# Removes the block from every candidate file. Never deletes a user's file, only our own (fish) when it ends up empty.
remove_path_block() {
    local f current head tail new
    while IFS= read -r f; do
        [ -f "$f" ] && grep -qF "$MARK_PATH_BEGIN" "$f" || continue
        current=$(cat "$f"; printf x); current=${current%x}
        # Both markers, BEGIN first: otherwise the file is not ours to edit.
        if [[ $current != *"$MARK_PATH_BEGIN"*"$MARK_PATH_END"* ]]; then
            msg_yellow "PATH: $f has a begin marker without a matching end marker; left untouched, remove the block by hand"
            continue
        fi
        head=${current%%"$MARK_PATH_BEGIN"*}
        tail=${current#*"$MARK_PATH_BEGIN"}; tail=${tail#*"$MARK_PATH_END"}
        # Drop the blank line the installer put before the block and the line break after it.
        head=${head%$'\n'}; head=${head%$'\n'}
        case "$tail" in $'\n'*) tail=${tail#$'\n'} ;; esac
        if [ -n "$head" ] && [ -n "$tail" ]; then new="$head"$'\n'"$tail"
        elif [ -n "$head" ]; then new="$head"$'\n'
        else new=$tail; fi
        if [ -z "$new" ] && [ "${f##*/}" = account-switcher.fish ]; then rm -f -- "$f"; else printf '%s' "$new" > "$f"; fi
        echo "PATH: block removed from $f"
    done <<EOT
$(shellrc_candidates)
EOT
}
