#!/usr/bin/env bash
. "$(dirname "$0")/helpers.sh"

fresh_home o
write_accounts '{"main":"m","accounts":{"m":{"email":"m@x","dir":"~/.claude"},"s":{"email":"s@x"}}}'
mkdir -p "$HOME/work dir"
OPEN="bash $SCRIPTS_DIR/open-account.sh"

# stubs: the OS, the macOS "open" and tmux only record what they were asked; nothing real is opened
cat > "$HOME/stubs/uname" <<'STUB'
#!/bin/sh
echo "${FAKE_OS:-Linux}"
STUB
cat > "$HOME/stubs/open" <<'STUB'
#!/bin/sh
echo "$@" > "$HOME/open-args.log"; cp "$3" "$HOME/launcher-copy.sh"
STUB
cat > "$HOME/stubs/tmux" <<'STUB'
#!/bin/sh
echo "$@" > "$HOME/tmux-args.log"
STUB
chmod +x "$HOME/stubs/"*

# macOS: Terminal.app opens a .command launcher that cds to the folder and execs cc.sh
FAKE_OS=Darwin $OPEN s "$HOME/work dir" --rc >/dev/null 2>&1; assert_eq 0 "$?" 'macOS: succeeds'
assert_match "$(cat "$HOME/open-args.log")" '^-a Terminal .*\.command$' 'macOS: Terminal.app with a .command file'
launcher=$(cat "$HOME/launcher-copy.sh")
assert_contains "$launcher" 'rm -f -- "$0"' 'launcher deletes itself'
assert_contains "$launcher" 'work\ dir' 'folder with a space is quoted'
assert_contains "$launcher" "$HOME/.claude-accounts/cc.sh" 'runs cc.sh'
assert_match "$launcher" 'cc.sh s --rc$' 'passes the account and --rc'
# the launcher really works: run a copy of it with a fake cc.sh
mkdir -p "$HOME/.claude-accounts"; printf '#!/bin/sh\necho "ran in $(pwd) with $*" > "$HOME/ran.log"\n' > "$HOME/.claude-accounts/cc.sh"
cp "$HOME/launcher-copy.sh" "$HOME/l.sh"; (bash "$HOME/l.sh"); assert_eq "ran in $HOME/work dir with s --rc" "$(cat "$HOME/ran.log")" 'launcher runs cc.sh in the folder'

# iTerm2 when TERM_PROGRAM says so
FAKE_OS=Darwin TERM_PROGRAM=iTerm.app $OPEN s "$HOME" >/dev/null 2>&1; assert_match "$(cat "$HOME/open-args.log")" '^-a iTerm ' 'iTerm2 chosen'

# Linux inside tmux: a new tmux window in the folder
rm -f "$HOME/tmux-args.log"
FAKE_OS=Linux TMUX=/tmp/x,1,0 $OPEN s "$HOME/work dir" --no-rc >/dev/null 2>&1; assert_eq 0 "$?" 'tmux: succeeds'
assert_contains "$(cat "$HOME/tmux-args.log")" "new-window -c $HOME/work dir" 'tmux window in the folder'

# Linux without a display or tmux: clear failure and no leftover launcher
before=$(ls "${TMPDIR:-/tmp}" | grep -c '^open-account\.' || true)
out=$(FAKE_OS=Linux DISPLAY= WAYLAND_DISPLAY= TMUX= $OPEN s "$HOME" 2>&1); status=$?
assert_eq 1 "$status" 'no terminal: fails'; assert_contains "$out" 'No terminal could be opened' 'explains and gives the command'
assert_eq "$before" "$(ls "${TMPDIR:-/tmp}" | grep -c '^open-account\.' || true)" 'launcher cleaned up'

# argument validation
assert_fails $OPEN
assert_fails $OPEN nope "$HOME"
assert_fails $OPEN s /does/not/exist
assert_fails $OPEN s "$HOME" extra-arg

finish
