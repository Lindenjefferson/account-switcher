#!/usr/bin/env bash
# Test helpers for the macOS/Linux scripts. Plain bash, no framework: each *.test.sh runs in its own
# process, builds a fake HOME in a temp folder and never touches the real ~/.claude.

SCRIPTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../plugins/account-switcher/skills/account-switcher/scripts-unix" && pwd)
REAL_PATH=$PATH
TESTS_RUN=0; TESTS_FAILED=0
TMP_ROOTS=()

cleanup_tmp() { local d; for d in "${TMP_ROOTS[@]}"; do rm -rf -- "$d"; done; }
trap cleanup_tmp EXIT

pass() { TESTS_RUN=$((TESTS_RUN + 1)); }
fail() {
    local msg="$*"
    [ ${#msg} -gt 300 ] && msg="${msg:0:300}..."
    TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "  FAIL: $msg" >&2
}

# assert_eq expected actual message
assert_eq() { if [ "$1" = "$2" ]; then pass; else fail "$3: expected [$1] got [$2]"; fi; }
# assert_match text regex message / assert_no_match
assert_match() { if [[ $1 =~ $2 ]]; then pass; else fail "$3: [$1] does not match /$2/"; fi; }
assert_no_match() { if [[ $1 =~ $2 ]]; then fail "$3: [$1] matches /$2/"; else pass; fi; }
assert_contains() { case "$1" in *"$2"*) pass ;; *) fail "$3: [$1] does not contain [$2]" ;; esac; }
assert_not_contains() { case "$1" in *"$2"*) fail "$3: [$1] contains [$2]" ;; *) pass ;; esac; }
assert_file() { if [ -f "$1" ]; then pass; else fail "$2: file missing: $1"; fi; }
assert_no_file() { if [ ! -e "$1" ] && [ ! -L "$1" ]; then pass; else fail "$2: should not exist: $1"; fi; }
assert_link() { if [ -L "$1" ]; then pass; else fail "$2: not a symlink: $1"; fi; }
assert_ok() { if "$@"; then pass; else fail "command failed: $*"; fi; }
assert_fails() { if "$@" >/dev/null 2>&1; then fail "command should have failed: $*"; else pass; fi; }

# fresh_home name : creates a fake HOME (resolved with pwd -P) and exports it. No lib is loaded yet.
fresh_home() {
    local root
    root=$(mktemp -d "${TMPDIR:-/tmp}/cc-test-$1.XXXXXX") || exit 1
    root=$(cd "$root" && pwd -P)
    TMP_ROOTS[${#TMP_ROOTS[@]}]=$root
    export HOME=$root
    mkdir -p "$HOME/.claude" "$HOME/.claude-accounts" "$HOME/stubs"
    echo '{}' > "$HOME/.claude.json"
    cp "$SCRIPTS_DIR/CLAUDE.template.md" "$HOME/.claude-accounts/"
    unset ZDOTDIR XDG_CONFIG_HOME CLAUDE_CONFIG_DIR CLAUDECODE CLAUDE_CODE_CHILD_SESSION CLAUDE_CODE_SESSION_ID
    export PATH="$HOME/stubs:$REAL_PATH"
}

# write_accounts <json> : writes the fake accounts.json.
write_accounts() { printf '%s' "$1" > "$HOME/.claude-accounts/accounts.json"; }

# new_env name <json> : fake HOME + accounts.json + the library loaded and accounts parsed.
new_env() {
    fresh_home "$1"
    write_accounts "$2"
    . "$SCRIPTS_DIR/lib.sh"
    load_accounts
}

# stub_claude : a fake claude that logs its arguments and environment and answers "auth status".
# STUB_LOGGED / STUB_EMAIL control the answer; STUB_EXIT the exit code of a normal run.
stub_claude() {
    cat > "$HOME/stubs/claude" <<'STUB'
#!/bin/sh
if [ "$1" = auth ] && [ "$2" = status ]; then
    if [ "${STUB_LOGGED:-1}" = 1 ]; then printf '{"loggedIn": true, "email": "%s"}\n' "${STUB_EMAIL:-}"
    else echo '{"loggedIn": false}'; fi
    exit 0
fi
{
    echo "CONFIG_DIR=${CLAUDE_CONFIG_DIR-<unset>}"
    echo "CLAUDECODE=${CLAUDECODE-<unset>}"
    echo "CHILD=${CLAUDE_CODE_CHILD_SESSION-<unset>}"
    echo "USE_BEDROCK=${CLAUDE_CODE_USE_BEDROCK-<unset>}"
    for a in "$@"; do echo "ARG=$a"; done
} > "$HOME/claude-call.log"
exit "${STUB_EXIT:-0}"
STUB
    chmod +x "$HOME/stubs/claude"
}

finish() {
    if [ "$TESTS_FAILED" -gt 0 ]; then echo "$(basename "$0"): $TESTS_FAILED of $TESTS_RUN checks FAILED" >&2; exit 1; fi
    echo "$(basename "$0"): $TESTS_RUN checks ok"
}
