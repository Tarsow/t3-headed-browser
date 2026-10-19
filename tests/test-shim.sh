#!/bin/bash
# Tests for t3-headed-browser with a fake T3 home, fake browsers and a fake X
# socket. Needs bash, python3 (to create the socket) and coreutils.
# Run: bash tests/test-shim.sh
# Checks are single-quoted on purpose: check() evaluates them after each step,
# and they read variables (out, status) set just before.
# shellcheck disable=SC2016,SC2034,SC2001
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
tool="$here/../t3-headed-browser"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

export T3CODE_HOME="$work/t3" XDG_CONFIG_HOME="$work/config" T3_HEADED_BROWSER_X11_DIR="$work/x11"
unset T3_HEADED_BROWSER T3_HEADED_BROWSER_DISPLAY
log="$work/calls.log"
shell_dir="$T3CODE_HOME/tools/chrome-headless-shell/linux64/154.0.0.0"
shell="$shell_dir/chrome-headless-shell"
passed=0 failed=0

pass() { passed=$((passed + 1)); echo "ok   $1"; }
fail() { failed=$((failed + 1)); echo "FAIL $1"; [ -n "${2:-}" ] && sed 's/^/     /' <<<"$2"; }
check() { if eval "$2"; then pass "$1"; else fail "$1" "$(cat "$log" 2>/dev/null)"; fi; }

# The stock headless shell: records that it ran.
mkdir -p "$shell_dir"
cat >"$shell" <<EOF
#!/bin/bash
echo "REAL \$*" >>"$log"
EOF
chmod 755 "$shell"

# A fake Chromium. Launched windowless with a profile, it takes the profile lock
# like Chromium does and runs until killed or for two seconds. Launched again on
# the same profile, it records the page it was asked to open and exits.
browser="$work/fake-browser"
cat >"$browser" <<EOF
#!/bin/bash
echo "BROWSER DISPLAY=\$DISPLAY \$*" >>"$log"
echo "\$XAUTHORITY" >"$work/xauthority"
profile=""
for arg in "\$@"; do case \$arg in --user-data-dir=*) profile=\${arg#*=} ;; esac; done
case " \$* " in
  *" --no-startup-window "*)
    if [ -n "\$profile" ]; then
      mkdir -p "\$profile"
      ln -sfn "\$(hostname)-\$\$" "\$profile/SingletonLock"
      for _ in \$(seq 40); do [ -e "$work/stop" ] && break; sleep 0.05; done
      exit 7
    fi ;;
esac
EOF
chmod 755 "$browser"

x11_up() { mkdir -p "$work/x11"; python3 -c "import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])" "$work/x11/X99"; }
x11_down() { rm -f "$work/x11/X99"; }
run_shim() { : >"$log"; "$shell" "$@"; }

echo "# install"
x11_up
out=$("$tool" install --browser "$browser" 2>&1)
check "install reports the shimmed shell" '[[ $out == *"shimmed $shell"* ]]'
check "original binary kept as .real" '[ -x "$shell.real" ] && grep -q REAL "$shell.real"'
check "shim carries the marker" '[ "$(sed -n 2p "$shell")" = "# t3-headed-browser shim" ]'
check "config saved" 'grep -qx "browser=$browser" "$XDG_CONFIG_HOME/t3-headed-browser/config" && grep -qx "display=:99" "$XDG_CONFIG_HOME/t3-headed-browser/config"'
"$tool" install >/dev/null 2>&1
check "reinstall keeps one .real and refreshes the shim" '[ "$(find "$shell_dir" -name "chrome-headless-shell*" | wc -l)" = 2 ] && grep -q REAL "$shell.real"'
check "status lists the shim" '[[ $("$tool" status) == *"shimmed:  $shell"* ]]'

echo "# shim"
run_shim --version
check "--version runs the original shell" 'grep -qx "REAL --version" "$log"'

run_shim --no-startup-window --headless --hide-scrollbars --user-data-dir="$work/tmpprofile" --remote-debugging-pipe
check "shared browser launch drops headless flags" 'grep -q "^BROWSER DISPLAY=:99 --no-startup-window --user-data-dir=$work/tmpprofile --remote-debugging-pipe$" "$log"'
check "shared browser launch opens no extra page" '[ "$(grep -c "^BROWSER" "$log")" = 1 ]'

run_shim --headless --hide-scrollbars --user-data-dir="$work/profile" --remote-debugging-pipe about:blank
status=$?
check "persistent launch starts the browser windowless" 'grep -q "^BROWSER DISPLAY=:99 --no-startup-window --user-data-dir=$work/profile --remote-debugging-pipe about:blank$" "$log"'
check "persistent launch opens the first page in the same profile" 'grep -q "^BROWSER DISPLAY=:99 --user-data-dir=$work/profile --no-first-run about:blank$" "$log"'
check "shim exits with the browser's status" '[ "$status" = 7 ]'

DISPLAY=:0 XAUTHORITY="$work/desktop-xauthority" run_shim --no-startup-window --headless
check "another display's XAUTHORITY is replaced with ~/.Xauthority" '[ "$(cat "$work/xauthority")" = "$HOME/.Xauthority" ]'

DISPLAY=:99 XAUTHORITY="$work/xvfb-xauthority" run_shim --no-startup-window --headless
check "XAUTHORITY for the configured display is kept" '[ "$(cat "$work/xauthority")" = "$work/xvfb-xauthority" ]'

T3_HEADED_BROWSER_DISPLAY=:42 run_shim --headless --no-startup-window
check "missing display falls back to the original shell" 'grep -qx "REAL --headless --no-startup-window" "$log"'

T3_HEADED_BROWSER="$work/missing" run_shim --headless --no-startup-window
check "missing browser falls back to the original shell" 'grep -qx "REAL --headless --no-startup-window" "$log"'

x11_down
run_shim --headless --no-startup-window
check "stopped X server falls back to the original shell" 'grep -qx "REAL --headless --no-startup-window" "$log"'

echo "# new T3 browser version"
new_dir="$T3CODE_HOME/tools/chrome-headless-shell/linux64/155.0.0.0"
mkdir -p "$new_dir" && cp "$shell.real" "$new_dir/chrome-headless-shell"
out=$("$tool" install 2>&1)
check "install reuses the saved browser" '[[ $out == *"shimmed $new_dir/chrome-headless-shell"* ]] && grep -q "$browser" "$new_dir/chrome-headless-shell"'

echo "# uninstall"
"$tool" uninstall >/dev/null
check "uninstall restores the originals" 'grep -q REAL "$shell" && grep -q REAL "$new_dir/chrome-headless-shell" && [ ! -e "$shell.real" ]'
check "status shows the originals" '[[ $("$tool" status) == *"original: $shell"* ]]'

echo "# errors"
check "install rejects a bad display" '! "$tool" install --display 99 2>/dev/null'
check "install rejects a missing browser" '! "$tool" install --browser "$work/missing" 2>/dev/null'
check "unknown command exits 2" '"$tool" frobnicate >/dev/null 2>&1; [ $? = 2 ]'

echo
echo "$passed passed, $failed failed"
[ "$failed" = 0 ]
