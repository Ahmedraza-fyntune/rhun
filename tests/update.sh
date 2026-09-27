#!/bin/sh
# The updater against a fake release folder (file://) with a stub install.sh and a stub target to
# restart into; prints ok/FAIL for each case.
set -u
cd "$(dirname "$0")/.."
w=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$w"' EXIT HUP INT TERM
cur=$(cat VERSION)
fail=0
mkdir -p "$w/proj" "$w/rel/latest/download" "$w/rel/download/v99.0.0"
# the release's installer: records its arguments; fails when the case asks
cat > "$w/rel/download/v99.0.0/install.sh" <<'EOF'
printf '%s\n' "$@" > "$STUB_LOG"
if [ -n "${STUB_FAIL:-}" ]; then echo "downloading"; echo "rhun install: stub failure"; exit 3; fi
EOF
# the installation: restarting runs it
cat > "$w/target" <<EOF
#!/bin/sh
printf 'restarted %s\n' "\$*" > "$w/restart.log"
EOF
chmod +x "$w/target"

# run CASE REPLY SEED TARGET FAIL LINES...: rhun headless with the script LINES, the release's VERSION
# REPLY (none when empty), the state file SEED; output in $w/CASE.out
run() {
    c=$1 reply=$2 seed=$3 target=$4 stubfail=$5
    shift 5
    rm -rf "$w/home" "$w/state" "$w/config" "$w/stub.log" "$w/restart.log"
    mkdir -p "$w/home" "$w/state/rhun" "$w/config"
    if [ -n "$reply" ]; then printf '%s\n' "$reply" > "$w/rel/latest/download/VERSION"; else rm -f "$w/rel/latest/download/VERSION"; fi
    [ -n "$seed" ] && printf '%s\n' "$seed" > "$w/state/rhun/update"
    printf '%s\n' "$@" > "$w/$c.rsc"
    env HOME="$w/home" XDG_CONFIG_HOME="$w/config" XDG_STATE_HOME="$w/state" \
        RHUN_RELEASES_URL="file://$w/rel" RHUN_UPDATE_TARGET="$target" STUB_LOG="$w/stub.log" STUB_FAIL="$stubfail" \
        build/rhun "$w/proj" --headless 800x600 --script "$w/$c.rsc" > "$w/$c.out" 2>&1
}
expect() { # CASE LINE
    if grep -qxF "$2" "$w/$1.out"; then echo "ok   update/$1"; else echo "FAIL update/$1"; cat "$w/$1.out"; fail=1; fi
}
check='cmd check_for_updates'
now=$(date +%s)

run newer 99.0.0 '' "$w/target" '' "$check" wait-update print-update
expect newer "state=available current=$cur latest=99.0.0 error="
run same "$cur" '' "$w/target" '' "$check" wait-update print-update
expect same "state=idle current=$cur latest=$cur error="
run garbage '<html>' '' "$w/target" '' "$check" wait-update print-update
expect garbage "state=idle current=$cur latest= error=unexpected reply"
run missing '' '' "$w/target" '' "$check" wait-update print-update
expect missing "state=idle current=$cur latest= error=download failed"
# the saved answer stands within the hour, and is asked again after it
run throttled 99.0.0 "checked=$now
latest=98.0.0" "$w/target" '' 'wait 5500' wait-update print-update
expect throttled "state=available current=$cur latest=98.0.0 error="
run stale 99.0.0 "checked=1
latest=98.0.0" "$w/target" '' 'wait 5500' wait-update print-update
expect stale "state=available current=$cur latest=99.0.0 error="
if grep -qx 'latest=99.0.0' "$w/state/rhun/update"; then echo "ok   update/saved"; else echo "FAIL update/saved"; fail=1; fi
# a build from source reports what it finds, never checks by itself, never installs
run source 99.0.0 '' '' '' "$check" wait-update 'cmd install_update' wait-update print-update
expect source "state=idle current=$cur latest=99.0.0 error="
run source-auto 99.0.0 '' '' '' 'wait 5500' wait-update print-update
expect source-auto "state=idle current=$cur latest= error="

run install 99.0.0 '' "$w/target" '' "$check" wait-update 'cmd install_update' wait-update print-update
expect install "state=ready current=$cur latest=99.0.0 error="
if [ "$(tr '\n' ' ' < "$w/stub.log")" = "--update --target $w/target --version 99.0.0 " ]; then
    echo "ok   update/install-args"
else
    echo "FAIL update/install-args"; cat "$w/stub.log"; fail=1
fi
run install-fail 99.0.0 '' "$w/target" 1 "$check" wait-update 'cmd install_update' wait-update print-update
expect install-fail "state=available current=$cur latest=99.0.0 error=rhun install: stub failure"
run restart 99.0.0 '' "$w/target" '' "$check" wait-update 'cmd install_update' wait-update 'cmd restart_to_update'
if [ "$(cat "$w/restart.log" 2>/dev/null)" = "restarted $w/proj" ]; then
    echo "ok   update/restart"
else
    echo "FAIL update/restart"; cat "$w/restart.out"; fail=1
fi
exit $fail
