#!/usr/bin/env bash
. "$(dirname "$0")/helpers.sh"

new_env e '{"main":"a","accounts":{"a":{"email":"a@x"}}}'

# outside a Claude session: nothing is touched, not even user configuration
export CLAUDE_CODE_USE_BEDROCK=1
assert_eq '' "$(clean_parent_session_env)" 'no parent session, nothing removed'
assert_eq 1 "${CLAUDE_CODE_USE_BEDROCK:-}" 'user variable kept'

# inside a session: only parent-session variables go
export CLAUDECODE=1 CLAUDE_CODE_CHILD_SESSION=1 CLAUDE_CODE_SESSION_ID=abc CLAUDE_CODE_MESSAGING_SOCKET=/s CLAUDE_CODE_ENTRYPOINT=cli
export CLAUDE_CONFIG_DIR=/keep/me CLAUDE_CODE_OAUTH_TOKEN=keep ANTHROPIC_API_KEY=keep
removed=$(clean_parent_session_env)
assert_contains "$removed" CLAUDE_CODE_CHILD_SESSION 'reports what it removed'
clean_parent_session_env >/dev/null   # (the call above ran in a subshell)
assert_eq '' "${CLAUDECODE:-}" 'CLAUDECODE removed'
assert_eq '' "${CLAUDE_CODE_CHILD_SESSION:-}" 'child-session flag removed'
assert_eq '' "${CLAUDE_CODE_MESSAGING_SOCKET:-}" 'messaging socket removed'
assert_eq /keep/me "${CLAUDE_CONFIG_DIR:-}" 'CLAUDE_CONFIG_DIR kept'
assert_eq keep "${CLAUDE_CODE_OAUTH_TOKEN:-}" 'OAuth token kept'
assert_eq keep "${ANTHROPIC_API_KEY:-}" 'API key kept'
assert_eq 1 "${CLAUDE_CODE_USE_BEDROCK:-}" 'Bedrock setting kept'

# find_claude skips our own bin/ and falls back to nothing when absent
fresh_home f
mkdir -p "$HOME/.claude-accounts/bin" "$HOME/real"
printf '#!/bin/sh\n' > "$HOME/.claude-accounts/bin/claude"; chmod +x "$HOME/.claude-accounts/bin/claude"
printf '#!/bin/sh\n' > "$HOME/real/claude"; chmod +x "$HOME/real/claude"
. "$SCRIPTS_DIR/lib.sh"
PATH="$HOME/.claude-accounts/bin:$HOME/real:$REAL_PATH"
assert_eq "$HOME/real/claude" "$(find_claude)" 'skips BASE_DIR/bin'

finish
