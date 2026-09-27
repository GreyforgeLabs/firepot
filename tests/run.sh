#!/usr/bin/env bash
# Fixture-driven tests for node-healthcheck. Needs bash and python3 (JSON assertions only).
# Shim bodies are deliberately single-quoted so they expand when the shim runs, not here.
# shellcheck disable=SC2016
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
SCRIPT="$ROOT/bin/node-healthcheck"
TMP="$HERE/.tmp"
rm -rf "$TMP"
mkdir -p "$TMP"

PASS=0
FAIL=0
CURRENT=""

pass() { PASS=$(( PASS + 1 )); }
fail() { FAIL=$(( FAIL + 1 )); echo "FAIL: $CURRENT: $*" >&2; }
begin() { CURRENT="$1"; }

assert_eq() { # expected actual label
    if [[ "$1" == "$2" ]]; then pass; else fail "$3: expected '$1', got '$2'"; fi
}
assert_contains() { # haystack needle label
    if [[ "$1" == *"$2"* ]]; then pass; else fail "$3: '$2' not found in: $1"; fi
}
assert_not_contains() {
    if [[ "$1" != *"$2"* ]]; then pass; else fail "$3: '$2' unexpectedly found in: $1"; fi
}

# jq-free JSON access: jget FILE PYTHON_EXPR (document bound to d)
jget() {
    python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$1" "$2"
}
assert_json_valid() {
    if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$1" 2>/dev/null; then pass; else fail "$2: invalid JSON: $(cat "$1")"; fi
}

# ── Fixture ──────────────────────────────────────────────────────────────────

FIX="$TMP/fixture"
PROC="$FIX/proc"
FSROOT="$FIX/root"
BIN="$FIX/bin"
mkdir -p "$PROC" "$FSROOT" "$BIN"

healthy_proc() {
    echo "0.40 0.30 0.20 1/200 4242" > "$PROC/loadavg"
    echo "123456.78 400000.00" > "$PROC/uptime"
    cat > "$PROC/meminfo" <<'MEM'
MemTotal:       16000000 kB
MemFree:         4000000 kB
MemAvailable:   10000000 kB
SwapTotal:       4000000 kB
SwapFree:        3600000 kB
MEM
    rm -rf "$PROC"/[0-9]*
    mkdir -p "$PROC/100"; printf 'Name:\tsleep\nState:\tS (sleeping)\n' > "$PROC/100/status"
}

cat > "$FIX/df-k.txt" <<'DF'
Filesystem     1024-blocks     Used Available Capacity Mounted on
/dev/root        100000000 40000000  60000000      40% /
/dev/data        200000000 182000000 18000000      91% /data
DF
cat > "$FIX/df-i.txt" <<'DF'
Filesystem      Inodes  IUsed   IFree IUse% Mounted on
/dev/root      6000000 1200000 4800000   20% /
/dev/data      1000000  850000  150000   85% /data
DF

shim() { # name, then body
    local name="$1"; shift
    printf '#!/usr/bin/env bash\n%s\n' "$*" > "$BIN/$name"
    chmod +x "$BIN/$name"
}
shim hostname 'printf "%s\n" "${FAKE_HOSTNAME:-testnode}"'
shim uname 'echo 6.1.0-test'
shim nproc 'echo 4'
shim df 'for a in "$@"; do case "$a" in -i) cat "$FAKE_DF_I"; exit 0 ;; esac; done
if [[ "$*" == *"--"* ]]; then m="${@: -1}"; awk -v m="$m" "NR==1 || \$NF==m" "$FAKE_DF_K"; exit 0; fi
cat "$FAKE_DF_K"'
shim ip 'case "$*" in
  *addr*) printf "1: lo    inet 127.0.0.1/8 scope host lo\n2: eth0    inet 203.0.113.5/24 brd 203.0.113.255 scope global eth0\n" ;;
  *route*) printf "default via 203.0.113.1 dev eth0 proto dhcp\n" ;;
esac'
shim ping 'target="${@: -1}"; for bad in ${FAKE_PING_FAIL:-}; do [[ "$target" == "$bad" ]] && exit 1; done; exit 0'
shim getent 'case "$2" in good.example) echo "203.0.113.9 STREAM good.example"; echo "203.0.113.9 DGRAM";; *) exit 2;; esac'
shim systemctl 'if [[ "$*" == *"--state=failed"* ]]; then [[ -n "${FAKE_FAILED_UNITS:-}" ]] && printf "%s\n" $FAKE_FAILED_UNITS; exit 0; fi
unit="${@: -1}"; case "$unit" in good|good2|user-good) exit 0;; *) exit 3;; esac'
shim ss 'printf "LISTEN 0 128 0.0.0.0:22 0.0.0.0:*\nLISTEN 0 128 [::]:8080 [::]:*\n"'
shim timedatectl 'echo "${FAKE_NTP:-yes}"'
shim who 'printf "alice pts/0 2026-09-06 10:00\nbob pts/1 2026-09-06 10:05\n"'
shim ssh '# Simulates a remote host by running the piped script locally.
host=""; while [[ $# -gt 0 ]]; do case "$1" in -o) shift 2; continue;; --) shift; host="$1"; shift; break;; *) shift;; esac; done
[[ "$host" == "down.example" ]] && exit 255
[[ "$host" == "bad-report.example" ]] && { printf "%s\n" "{not-json"; exit 0; }
export FAKE_HOSTNAME="$host"
exec bash -c "$1"'

run_nhc() { # args... -> stdout captured to $OUT, exit code in $RC
    OUT="$TMP/out.txt"
    set +e
    PATH="$BIN:$PATH" NODE_HEALTHCHECK_PROC="$PROC" NODE_HEALTHCHECK_ROOT="$FSROOT" \
        FAKE_DF_K="$FIX/df-k.txt" FAKE_DF_I="$FIX/df-i.txt" \
        "$SCRIPT" "$@" > "$OUT" 2> "$TMP/err.txt"
    RC=$?
    set -e
}

reset_env() {
    healthy_proc
    rm -rf "$FSROOT"; mkdir -p "$FSROOT"
    unset FAKE_PING_FAIL FAKE_FAILED_UNITS FAKE_NTP FAKE_HOSTNAME
}

# ── Tests ────────────────────────────────────────────────────────────────────

begin "version and help"
run_nhc --version; assert_eq 0 "$RC" "exit"; assert_contains "$(cat "$OUT")" "node-healthcheck 1.1.0" "version"
run_nhc --help; assert_eq 0 "$RC" "exit"; assert_contains "$(cat "$OUT")" "Exit codes" "help"

begin "healthy baseline is exit 0 with valid JSON"
reset_env
run_nhc --json --mounts / --skip inodes
assert_eq 0 "$RC" "exit"
assert_json_valid "$OUT" "json"
assert_eq ok "$(jget "$OUT" 'd["status"]')" "status"
assert_eq 0 "$(jget "$OUT" 'd["exit_code"]')" "exit_code"
assert_eq testnode "$(jget "$OUT" 'd["host"]')" "host"
assert_eq 17 "$(jget "$OUT" 'len(d["checks"])')" "check count"
assert_eq 0.1 "$(jget "$OUT" '[c for c in d["checks"] if c["name"]=="load"][0]["metrics"]["load1_per_core"]')" "load per core"
assert_eq 37.5 "$(jget "$OUT" '[c for c in d["checks"] if c["name"]=="memory"][0]["metrics"]["used_percent"]')" "memory percent"
assert_eq skip "$(jget "$OUT" '[c for c in d["checks"] if c["name"]=="services"][0]["status"]')" "services skipped when unconfigured"
assert_eq 123456 "$(jget "$OUT" '[c for c in d["checks"] if c["name"]=="system"][0]["metrics"]["uptime_seconds"]')" "uptime"

begin "disk and inode thresholds"
reset_env
run_nhc --json --check disk,inodes
assert_eq 2 "$RC" "exit"
assert_eq crit "$(jget "$OUT" 'd["checks"][0]["status"]')" "disk crit"
assert_contains "$(jget "$OUT" 'd["checks"][0]["summary"]')" "/data 91%" "disk summary"
assert_eq 91 "$(jget "$OUT" 'd["checks"][0]["metrics"]["/data"]')" "disk metric"
assert_eq warn "$(jget "$OUT" 'd["checks"][1]["status"]')" "inodes warn"
run_nhc --json --check disk --mounts /
assert_eq 0 "$RC" "mounts filter exit"
assert_eq 1 "$(jget "$OUT" 'len(d["checks"][0]["metrics"])')" "mounts filter count"
run_nhc --json --check disk --mounts /not-present
assert_eq 2 "$RC" "explicit missing mount is critical"
assert_eq crit "$(jget "$OUT" 'd["checks"][0]["status"]')" "missing mount status"
assert_contains "$(jget "$OUT" 'd["checks"][0]["summary"]')" "/not-present" "missing mount named"
run_nhc --json --check disk --warn-disk 95 --crit-disk 99
assert_eq 0 "$RC" "raised thresholds"

begin "load thresholds scale with cores"
reset_env
echo "9.00 8.00 7.00 1/200 1" > "$PROC/loadavg"
run_nhc --json --check load; assert_eq 2 "$RC" "crit at 2.25/core"
run_nhc --json --check load --crit-load 3; assert_eq 1 "$RC" "warn under raised crit"
run_nhc --json --check load --warn-load 3 --crit-load 4; assert_eq 0 "$RC" "ok under raised warn"

begin "memory and swap thresholds"
reset_env
sed -i 's/^MemAvailable:.*/MemAvailable:     700000 kB/' "$PROC/meminfo"
run_nhc --json --check memory; assert_eq 2 "$RC" "memory crit"
assert_eq 95.6 "$(jget "$OUT" 'd["checks"][0]["metrics"]["used_percent"]')" "memory percent"
sed -i 's/^SwapFree:.*/SwapFree:        1600000 kB/' "$PROC/meminfo"
run_nhc --json --check swap; assert_eq 1 "$RC" "swap warn"
sed -i 's/^SwapTotal:.*/SwapTotal:             0 kB/' "$PROC/meminfo"
run_nhc --json --check swap; assert_eq 0 "$RC" "no swap is info"
assert_eq info "$(jget "$OUT" 'd["checks"][0]["status"]')" "no swap status"

begin "services, ports, peers, dns"
reset_env
run_nhc --json --check services --services good,bad
assert_eq 2 "$RC" "inactive service is crit"
assert_contains "$(jget "$OUT" 'd["checks"][0]["summary"]')" "inactive: bad" "service summary"
assert_eq 0 "$(jget "$OUT" 'd["checks"][0]["metrics"]["bad"]')" "service metric"
run_nhc --json --check services --services "good good2"; assert_eq 0 "$RC" "space separated list"
run_nhc --json --check user_services --user-services user-good; assert_eq 0 "$RC" "user service"
run_nhc --json --check ports --ports 22,8080; assert_eq 0 "$RC" "ports listening"
run_nhc --json --check ports --ports 22,9999; assert_eq 2 "$RC" "missing port"
assert_contains "$(jget "$OUT" 'd["checks"][0]["summary"]')" "9999" "port summary"
run_nhc --json --check ports --ports 22,abc; assert_eq 3 "$RC" "invalid port is usage error"
run_nhc --json --check peers --peers 203.0.113.1; assert_eq 0 "$RC" "peer up"
FAKE_PING_FAIL="203.0.113.2" run_nhc --json --check peers --peers 203.0.113.1,203.0.113.2; assert_eq 2 "$RC" "peer down"
run_nhc --json --check dns --dns good.example; assert_eq 0 "$RC" "dns ok"
assert_eq 203.0.113.9 "$(jget "$OUT" 'd["checks"][0]["metrics"]["address"]')" "dns address"
run_nhc --json --check dns --dns bad.example; assert_eq 2 "$RC" "dns fail"
run_nhc --json --check dns; assert_eq 0 "$RC" "dns unconfigured skips"

begin "configured targets fail when their probe commands are unavailable"
MIN_BIN="$TMP/min-bin"
mkdir -p "$MIN_BIN"
for binary in bash date hostname tr; do ln -s "$(command -v "$binary")" "$MIN_BIN/$binary"; done
for spec in 'services --services good' 'ports --ports 22' 'peers --peers 203.0.113.1' 'dns --dns good.example'; do
    read -r check flag target <<< "$spec"
    set +e
    PATH="$MIN_BIN" "$SCRIPT" --json --check "$check" "$flag" "$target" > "$TMP/min-out.txt" 2> "$TMP/min-err.txt"
    min_rc=$?
    set -e
    assert_eq 2 "$min_rc" "$check missing probe exit"
    assert_eq crit "$(jget "$TMP/min-out.txt" 'd["checks"][0]["status"]')" "$check missing probe status"
done

begin "gateway, network, failed units, time sync, reboot, zombies, sessions"
reset_env
run_nhc --json --check gateway; assert_eq 0 "$RC" "gateway ok"
assert_eq 203.0.113.1 "$(jget "$OUT" 'd["checks"][0]["metrics"]["gateway"]')" "gateway address"
FAKE_PING_FAIL="203.0.113.1" run_nhc --json --check gateway; assert_eq 2 "$RC" "gateway down"
run_nhc --json --check network; assert_eq 0 "$RC" "network"
assert_eq 1 "$(jget "$OUT" 'd["checks"][0]["metrics"]["interfaces"]')" "loopback excluded"
FAKE_FAILED_UNITS="foo.service" run_nhc --json --check failed_units; assert_eq 1 "$RC" "failed unit warns"
assert_contains "$(jget "$OUT" 'd["checks"][0]["summary"]')" "foo.service" "failed unit named"
FAKE_NTP=no run_nhc --json --check time_sync; assert_eq 1 "$RC" "unsynced warns"
mkdir -p "$FSROOT/var/run"; touch "$FSROOT/var/run/reboot-required"; printf 'linux-image\nlibc6\n' > "$FSROOT/var/run/reboot-required.pkgs"
run_nhc --json --check reboot_required; assert_eq 1 "$RC" "reboot warns"
assert_contains "$(jget "$OUT" 'd["checks"][0]["summary"]')" "linux-image libc6" "reboot packages"
for i in 201 202 203 204 205 206; do mkdir -p "$PROC/$i"; printf 'State:\tZ (zombie)\n' > "$PROC/$i/status"; done
run_nhc --json --check zombies; assert_eq 1 "$RC" "zombies warn"
assert_eq 6 "$(jget "$OUT" 'd["checks"][0]["metrics"]["count"]')" "zombie count"
run_nhc --json --check sessions; assert_eq 0 "$RC" "sessions info"
assert_eq 2 "$(jget "$OUT" 'd["checks"][0]["metrics"]["count"]')" "session count"

begin "check selection and usage errors"
reset_env
run_nhc --json --check load,memory; assert_eq 2 "$(jget "$OUT" 'len(d["checks"])')" "explicit checks"
run_nhc --json --skip disk,inodes,swap --mounts /; assert_eq 15 "$(jget "$OUT" 'len(d["checks"])')" "skipped checks"
run_nhc --check nope; assert_eq 3 "$RC" "unknown check"
run_nhc --skip nope; assert_eq 3 "$RC" "unknown skip"
run_nhc --warn-mem abc; assert_eq 3 "$RC" "non-numeric threshold"
run_nhc --nope; assert_eq 3 "$RC" "unknown option"
run_nhc --services; assert_eq 3 "$RC" "missing value"
assert_contains "$(cat "$TMP/err.txt")" "requires a value" "missing value message"

begin "config file is parsed, not sourced"
reset_env
cat > "$TMP/test.conf" <<'CONF'
# comment line
services = good, bad   # trailing comment
ports = "22"
warn_disk = 95
crit_disk = 99
skip = inodes
CONF
run_nhc --json --config "$TMP/test.conf" --check services,ports,disk,inodes
assert_eq 2 "$RC" "config services crit"
assert_eq 3 "$(jget "$OUT" 'len(d["checks"])')" "config skip applied"
assert_eq ok "$(jget "$OUT" '[c for c in d["checks"] if c["name"]=="disk"][0]["status"]')" "config thresholds"
printf 'services = $(touch %s/pwned)\n' "$TMP" > "$TMP/evil.conf"
run_nhc --json --config "$TMP/evil.conf" --check services
if [[ -e "$TMP/pwned" ]]; then fail "config executed a command"; else pass; fi
printf 'bogus = 1\n' > "$TMP/bad.conf"
run_nhc --config "$TMP/bad.conf"; assert_eq 3 "$RC" "unknown config key"
run_nhc --config "$TMP/missing.conf"; assert_eq 3 "$RC" "missing config"

begin "JSON escaping survives hostile strings"
reset_env
FAKE_HOSTNAME=$'te"st\\node\ttab' run_nhc --json --check system
assert_json_valid "$OUT" "escaped json"
assert_eq $'te"st\\node\ttab' "$(jget "$OUT" 'd["host"]')" "host roundtrip"

begin "text mode output controls"
reset_env
run_nhc --no-color --mounts / --skip inodes
assert_eq 0 "$RC" "text exit"
assert_not_contains "$(cat "$OUT")" $'\033[' "no ansi"
assert_contains "$(cat "$OUT")" "Overall: OK (exit 0)" "summary line"
run_nhc --no-color --quiet --check disk,load
assert_contains "$(cat "$OUT")" "[CRIT] disk" "quiet keeps crit"
assert_not_contains "$(cat "$OUT")" "[OK  ] load" "quiet hides ok"
run_nhc --check load
assert_contains "$(cat "$OUT")" $'\033[32m' "colour by default"

begin "multi-node aggregation over ssh"
reset_env
run_nhc --json --host node-a --host node-b --check load,memory
assert_eq 0 "$RC" "two healthy nodes"
assert_json_valid "$OUT" "aggregate json"
assert_eq 2 "$(jget "$OUT" 'len(d["nodes"])')" "node count"
assert_eq node-b "$(jget "$OUT" 'd["nodes"][1]["host"]')" "remote hostname"
assert_eq 2 "$(jget "$OUT" 'len(d["nodes"][0]["checks"])')" "remote check selection forwarded"
run_nhc --json --host node-a --host down.example --check load
assert_eq 2 "$RC" "unreachable node is crit"
assert_eq crit "$(jget "$OUT" 'd["nodes"][1]["status"]')" "down node status"
assert_contains "$(jget "$OUT" 'd["nodes"][1]["error"]')" "ssh failed" "down node error"
run_nhc --json --host node-a --host bad-report.example --check load
assert_eq 2 "$RC" "invalid remote JSON is critical"
assert_json_valid "$OUT" "aggregate with invalid remote JSON"
assert_contains "$(jget "$OUT" 'd["nodes"][1]["error"]')" "invalid remote report" "invalid report error"
run_nhc --no-color --host node-a --check disk
assert_eq 2 "$RC" "remote crit propagates"
assert_contains "$(cat "$OUT")" "[CRIT] node-a" "text node line"
assert_contains "$(cat "$OUT")" "[crit] disk: /data 91%" "text failing check"
run_nhc --json --host node-a --config "$TMP/test.conf" --check services
assert_eq 2 "$RC" "config lists forwarded to remote"
assert_contains "$(jget "$OUT" 'd["nodes"][0]["checks"][0]["summary"]')" "inactive: bad" "remote used config services"

echo
echo "node-healthcheck tests: $PASS passed, $FAIL failed"
rm -rf "$TMP"
(( FAIL == 0 ))
