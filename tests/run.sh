#!/usr/bin/env bash
# Fixture-driven tests for firepot. Needs bash and python3 (JSON assertions only).
# Shim bodies are deliberately single-quoted so they expand when the shim runs, not here.
# shellcheck disable=SC2016
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
SCRIPT="$ROOT/bin/firepot"
LEGACY="$ROOT/bin/node-healthcheck"
VERSION="$(sed -n 's/^NHC_VERSION="\(.*\)"$/\1/p' "$SCRIPT")"
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
shim df '[[ -n "${FAKE_DF_HANG:-}" ]] && exec sleep 30
for a in "$@"; do case "$a" in -i) cat "$FAKE_DF_I"; exit 0 ;; esac; done
if [[ "$*" == *"--"* ]]; then m="${@: -1}"; awk -v m="$m" "NR==1 || \$NF==m" "$FAKE_DF_K"; exit 0; fi
cat "$FAKE_DF_K"'
shim ip 'case "$*" in
  *addr*) printf "1: lo    inet 127.0.0.1/8 scope host lo\n2: eth0    inet 203.0.113.5/24 brd 203.0.113.255 scope global eth0\n" ;;
  *route*) printf "%b" "${FAKE_ROUTE:-default via 203.0.113.1 dev eth0 proto dhcp\\n}" ;;
esac'
shim ping 'target="${@: -1}"; for bad in ${FAKE_PING_FAIL:-}; do [[ "$target" == "$bad" ]] && exit 1; done; exit 0'
shim getent 'case "$2" in good.example) echo "203.0.113.9 STREAM good.example"; echo "203.0.113.9 DGRAM";; *) exit 2;; esac'
shim systemctl 'if [[ "$*" == *"--state=failed"* ]]; then [[ -n "${FAKE_FAILED_UNITS:-}" ]] && printf "%s\n" $FAKE_FAILED_UNITS; exit 0; fi
quiet=0; units=(); for a in "$@"; do case "$a" in --quiet) quiet=1 ;; --user|--|is-active) ;; *) units+=("$a") ;; esac; done
(( quiet == 0 && ${#units[@]} > 1 )) && [[ -n "${FAKE_SYSTEMCTL_NOBATCH:-}" ]] && exit 1
rc=3; for u in "${units[@]}"; do case "$u" in good|good2|user-good) s=active; rc=0 ;; *) s=inactive ;; esac; (( quiet )) || echo "$s"; done
exit "$rc"'
shim ss 'case "$*" in *-H*) [[ -n "${FAKE_SS_OLD:-}" ]] && { echo "ss: invalid option -- H" >&2; exit 1; } ;; *) echo "State Recv-Q Send-Q Local Address:Port Peer Address:Port Process" ;; esac
printf "LISTEN 0 128 0.0.0.0:22 0.0.0.0:*\nLISTEN 0 128 [::]:8080 [::]:*\n"'
shim timedatectl 'echo "${FAKE_NTP:-yes}"'
shim who 'printf "alice pts/0 2026-09-06 10:00\nbob pts/1 2026-09-06 10:05\n"'
shim ssh '# Simulates a remote host by running the piped script locally.
host=""; while [[ $# -gt 0 ]]; do case "$1" in -o) shift 2; continue;; --) shift; host="$1"; shift; break;; *) shift;; esac; done
[[ "$host" == "down.example" ]] && exit 255
[[ "$host" == "bad-report.example" ]] && { printf "%s\n" "{not-json"; exit 0; }
[[ "$host" == "usage.example" ]] && { echo "firepot: unknown option" >&2; exit 3; }
[[ "$host" == "refused.example" ]] && { printf "Warning: noise\nssh: connect to host refused.example port 22: Connection refused\r\n\n" >&2; exit 255; }
[[ "$host" == slow-* ]] && sleep "${FAKE_SSH_DELAY:-1}"
export FAKE_HOSTNAME="$host"
exec bash -c "$1"'

run_nhc() { # args... -> stdout captured to $OUT, exit code in $RC
    OUT="$TMP/out.txt"
    set +e
    PATH="$BIN:$PATH" FIREPOT_PROC="$PROC" FIREPOT_ROOT="$FSROOT" \
        FAKE_DF_K="${DF_K:-$FIX/df-k.txt}" FAKE_DF_I="$FIX/df-i.txt" \
        "${NHC_ENTRY:-$SCRIPT}" "$@" > "$OUT" 2> "$TMP/err.txt"
    RC=$?
    set -e
}

run_legacy_env() { # pre-rename NODE_HEALTHCHECK_* variables only
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
    unset FAKE_PING_FAIL FAKE_FAILED_UNITS FAKE_NTP FAKE_HOSTNAME DF_K
}

# ── Tests ────────────────────────────────────────────────────────────────────

begin "version and help"
run_nhc --version; assert_eq 0 "$RC" "exit"; assert_eq "firepot $VERSION" "$(cat "$OUT")" "version"
assert_eq "" "$(cat "$TMP/err.txt")" "no stderr under the new name"
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

begin "long options and config keys share one table"
reset_env
for opt in --hosts --checks --warn_load --nope; do
    run_nhc "$opt" x; assert_eq 3 "$RC" "$opt is rejected"
    assert_contains "$(cat "$TMP/err.txt")" "unknown option: $opt" "$opt message"
done
run_nhc --nope; assert_contains "$(cat "$TMP/err.txt")" "unknown option" "unknown option named before value check"
printf '$(touch %s/pwned-key) = 1\n' "$TMP" > "$TMP/evil-key.conf"
run_nhc --config "$TMP/evil-key.conf"; assert_eq 3 "$RC" "hostile config key rejected"
if [[ -e "$TMP/pwned-key" ]]; then fail "config key executed a command"; else pass; fi
printf '= 1\n' > "$TMP/empty-key.conf"
run_nhc --config "$TMP/empty-key.conf"; assert_eq 3 "$RC" "empty config key rejected"
assert_contains "$(cat "$TMP/err.txt")" "unknown config key" "empty key message"
run_nhc --json --host node-a --check disk --warn-disk 95 --crit-disk 99
assert_eq 0 "$RC" "threshold flags reach the remote"

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

begin "fleet mode accepts the full default check set"
reset_env
run_nhc --json --host node-a --mounts / --skip inodes
assert_eq 0 "$RC" "default checks over ssh (sessions and swap report info)"
assert_eq "" "$(jget "$OUT" 'd["nodes"][0].get("error", "")')" "no validation error"
assert_eq 17 "$(jget "$OUT" 'len(d["nodes"][0]["checks"])')" "all remote checks kept"
run_nhc --json --host usage.example --check load
assert_eq 2 "$RC" "remote usage error is critical"
assert_eq "remote run failed with exit 3" "$(jget "$OUT" 'd["nodes"][0]["error"]')" "remote exit 3 is not reported as an ssh failure"
run_nhc --no-color --host node-a --check services --services 'a"b'
assert_contains "$(cat "$OUT")" '[crit] services: inactive: a"b (0/1 active)' "text fleet summary decodes JSON escapes"

begin "fleet errors carry the remote's reason"
reset_env
run_nhc --json --host refused.example --host usage.example --check load
assert_eq 2 "$RC" "failed nodes are critical"
assert_json_valid "$OUT" "aggregate with error details"
assert_eq "ssh failed with exit 255" "$(jget "$OUT" 'd["nodes"][0]["error"]')" "error string unchanged"
assert_eq "ssh: connect to host refused.example port 22: Connection refused" "$(jget "$OUT" 'd["nodes"][0]["detail"]')" "ssh's last stderr line is the detail"
assert_eq "firepot: unknown option" "$(jget "$OUT" 'd["nodes"][1]["detail"]')" "remote stderr is the detail"
run_nhc --json --host down.example --check load
assert_eq "False" "$(jget "$OUT" '"detail" in d["nodes"][0]')" "no detail key without stderr"
run_nhc --no-color --host refused.example --check load
assert_contains "$(cat "$OUT")" "    ssh failed with exit 255: ssh: connect to host refused.example port 22: Connection refused" "text detail"

begin "fleet --quiet prints only failing nodes"
reset_env
run_nhc --no-color --quiet --host node-a --host down.example --check load
assert_eq 2 "$RC" "quiet fleet exit"
assert_not_contains "$(cat "$OUT")" "node-a" "ok node hidden"
assert_contains "$(cat "$OUT")" "[CRIT] down.example" "crit node shown"
assert_contains "$(cat "$OUT")" "Overall: CRIT (exit 2)" "quiet fleet summary"

begin "fleet hosts are queried in parallel, reported in order"
reset_env
start=$SECONDS
FAKE_SSH_DELAY=2 run_nhc --json --host slow-a --host slow-b --host slow-c --host slow-d --host node-e --check load
elapsed=$(( SECONDS - start ))
assert_eq 0 "$RC" "parallel fleet exit"
assert_eq "['slow-a', 'slow-b', 'slow-c', 'slow-d', 'node-e']" "$(jget "$OUT" '[n["host"] for n in d["nodes"]]')" "node order follows --host order"
if (( elapsed < 6 )); then pass; else fail "4 hosts x 2 s took ${elapsed}s; expected them to overlap"; fi
FAKE_SSH_DELAY=1 run_nhc --json --parallel 1 --host slow-a --host node-b --check load
assert_eq "['slow-a', 'node-b']" "$(jget "$OUT" '[n["host"] for n in d["nodes"]]')" "--parallel 1 runs one at a time"
printf 'parallel = 2\n' > "$TMP/parallel.conf"
run_nhc --json --config "$TMP/parallel.conf" --host node-a --host node-b --host node-c --check load
assert_eq 3 "$(jget "$OUT" 'len(d["nodes"])')" "parallel config key"
assert_eq "" "$(jget "$OUT" '"".join(n.get("error", "") for n in d["nodes"])')" "parallel is not forwarded to remotes"
for bad in 0 -1 abc 1.5; do run_nhc --parallel "$bad" --host node-a; assert_eq 3 "$RC" "--parallel $bad is a usage error"; done

begin "timeouts that would hang or always fail are usage errors"
reset_env
for bad in 0 -1 0.0; do run_nhc --check peers --peers 203.0.113.1 --ping-timeout "$bad"; assert_eq 3 "$RC" "--ping-timeout $bad"; done
run_nhc --json --check peers --peers 203.0.113.1 --ping-timeout 0.5; assert_eq 0 "$RC" "fractional ping timeout"
for bad in 0 -1 2.5; do run_nhc --host node-a --ssh-timeout "$bad"; assert_eq 3 "$RC" "--ssh-timeout $bad"; done
assert_contains "$(cat "$TMP/err.txt")" "--ssh-timeout" "message names the option"

begin "a closed output pipe ends quietly"
reset_env
closed_pipe() { # runs the script with stdout on a pipe whose reader is gone; prints rc (-13 = SIGPIPE) then stderr
    PATH="$BIN:$PATH" FIREPOT_PROC="$PROC" FIREPOT_ROOT="$FSROOT" FAKE_DF_K="$FIX/df-k.txt" FAKE_DF_I="$FIX/df-i.txt" \
        python3 -c 'import os, subprocess, sys
r, w = os.pipe(); os.close(r)
p = subprocess.run(sys.argv[1:], stdout=w, stderr=subprocess.PIPE)
print(p.returncode); sys.stdout.write(p.stderr.decode())' "$SCRIPT" "$@"
}
assert_eq -13 "$(closed_pipe --no-color --check load,memory)" "text: killed by SIGPIPE like any filter, no error message"
assert_eq -13 "$(closed_pipe --json --check load)" "json: killed by SIGPIPE like any filter, no error message"
assert_eq -13 "$(closed_pipe --no-color --host node-a --check load)" "fleet: killed by SIGPIPE like any filter, no error message"

begin "lists are never glob-expanded"
reset_env
mkdir -p "$TMP/globdir"; touch "$TMP/globdir/good"
( cd "$TMP/globdir" && run_nhc --json --check services --services '*' && cp "$OUT" "$TMP/glob.json"; echo "$RC" > "$TMP/glob.rc" )
assert_eq 2 "$(cat "$TMP/glob.rc")" "'*' is a unit name, not the files in the working directory"
assert_eq "['*']" "$(jget "$TMP/glob.json" 'list(d["checks"][0]["metrics"])')" "literal pattern kept"
run_nhc --json --check services --services 'good,,good2, ,'
assert_eq 0 "$RC" "empty list items are dropped"
assert_eq 2 "$(jget "$OUT" 'len(d["checks"][0]["metrics"])')" "two units"

begin "core count comes from online CPUs, not affinity or OMP_NUM_THREADS"
reset_env
mkdir -p "$FSROOT/sys/devices/system/cpu"; echo "0-3,6,8-9" > "$FSROOT/sys/devices/system/cpu/online"
echo "3.50 1.00 1.00 1/200 1" > "$PROC/loadavg"
OMP_NUM_THREADS=1 run_nhc --json --check load
assert_eq 7 "$(jget "$OUT" 'd["checks"][0]["metrics"]["cores"]')" "cores from sysfs ranges"
assert_eq 0.5 "$(jget "$OUT" 'd["checks"][0]["metrics"]["load1_per_core"]')" "per-core load"
assert_eq 0 "$RC" "not inflated by OMP_NUM_THREADS"

begin "kernel facts are read from /proc when present"
reset_env
mkdir -p "$PROC/sys/kernel"; echo "proc-host" > "$PROC/sys/kernel/hostname"; echo "6.9.9-proc" > "$PROC/sys/kernel/osrelease"
run_nhc --json --check system
assert_eq proc-host "$(jget "$OUT" 'd["host"]')" "hostname from /proc"
assert_eq 6.9.9-proc "$(jget "$OUT" 'd["checks"][0]["metrics"]["kernel"]')" "kernel from /proc"
rm -rf "$PROC/sys"

begin "string metrics stay strings and JSON stays valid"
reset_env
FAKE_HOSTNAME=007 run_nhc --json --check system
assert_json_valid "$OUT" "digits-only hostname with a leading zero"
assert_eq "<class 'str'>" "$(jget "$OUT" 'type(d["checks"][0]["metrics"]["hostname"])')" "hostname metric is a string"
FAKE_HOSTNAME=$'ctl\033[31mchars\001' run_nhc --json --check system
assert_json_valid "$OUT" "control characters dropped"
assert_eq "ctl[31mchars" "$(jget "$OUT" 'd["host"]')" "control characters removed"

begin "mount points with spaces or '=' keep their names"
reset_env
cp "$FIX/df-k.txt" "$TMP/df-odd.txt"
printf '%s\n' "/dev/sdb1 1000 500 500 50% /run/media/u/My Disk" "/dev/sdc1 1000 950 50 95% /mnt/a=b" >> "$TMP/df-odd.txt"
DF_K="$TMP/df-odd.txt" run_nhc --json --check disk
assert_eq 50 "$(jget "$OUT" 'd["checks"][0]["metrics"]["/run/media/u/My Disk"]')" "spaced mount point"
assert_eq 95 "$(jget "$OUT" 'd["checks"][0]["metrics"]["/mnt/a=b"]')" "mount point containing '='"
assert_contains "$(jget "$OUT" 'd["checks"][0]["summary"]')" "/mnt/a=b 95%" "summary names it"

begin "a hung df is reported, not waited on"
reset_env
start=$SECONDS
FAKE_DF_HANG=1 FIREPOT_PROBE_TIMEOUT=1 run_nhc --json --check disk
assert_eq 2 "$RC" "hung df is critical"
assert_contains "$(jget "$OUT" 'd["checks"][0]["summary"]')" "did not answer within 1s" "hang summary"
FAKE_DF_HANG=1 FIREPOT_PROBE_TIMEOUT=1 run_nhc --json --check disk --mounts /nfs
assert_eq 2 "$RC" "hung requested mount is critical"
assert_contains "$(jget "$OUT" 'd["checks"][0]["summary"]')" "no answer within 1s: /nfs" "hung mount named"
if (( SECONDS - start < 15 )); then pass; else fail "df hang was not bounded"; fi
FIREPOT_PROBE_TIMEOUT=abc run_nhc --json --check disk; assert_eq 3 "$RC" "invalid probe timeout"
FIREPOT_PROBE_TIMEOUT=-1 run_nhc --json --check disk; assert_eq 3 "$RC" "negative probe timeout is a usage error"

begin "gateway handles point-to-point and multipath default routes"
reset_env
FAKE_ROUTE='default dev wg0 scope link\n' run_nhc --json --check gateway
assert_eq 0 "$RC" "point-to-point default route is not an unreachable gateway"
assert_eq info "$(jget "$OUT" 'd["checks"][0]["status"]')" "p2p status"
assert_eq wg0 "$(jget "$OUT" 'd["checks"][0]["metrics"]["interface"]')" "p2p interface"
FAKE_ROUTE='default proto static metric 100\n\tnexthop via 203.0.113.7 dev eth0 weight 1\n\tnexthop via 203.0.113.8 dev eth1 weight 1\n' \
    run_nhc --json --check gateway
assert_eq 203.0.113.7 "$(jget "$OUT" 'd["checks"][0]["metrics"]["gateway"]')" "first multipath next hop"
FAKE_ROUTE='default via 203.0.113.1 dev eth0 metric 100\ndefault via 203.0.113.99 dev eth1 metric 200\n' \
    run_nhc --json --check gateway
assert_eq 203.0.113.1 "$(jget "$OUT" 'd["checks"][0]["metrics"]["gateway"]')" "first of several default routes"
FAKE_ROUTE=' ' run_nhc --json --check gateway
assert_eq 1 "$RC" "no default route warns"

begin "ports, units, and probes across tool versions"
reset_env
run_nhc --json --check ports --ports 022,8080; assert_eq 0 "$RC" "leading zeros normalised"
assert_eq "['22', '8080']" "$(jget "$OUT" 'list(d["checks"][0]["metrics"])')" "normalised port keys"
run_nhc --json --check ports --ports 70000; assert_eq 3 "$RC" "out-of-range port is a usage error"
FAKE_SS_OLD=1 run_nhc --json --check ports --ports 22; assert_eq 0 "$RC" "works with ss that lacks -H"
FAKE_SYSTEMCTL_NOBATCH=1 run_nhc --json --check services --services good,bad
assert_eq 2 "$RC" "per-unit fallback exit"
assert_eq "{'good': 1, 'bad': 0}" "$(jget "$OUT" 'd["checks"][0]["metrics"]')" "per-unit fallback states"
FAKE_PING_FAIL="203.0.113.2 203.0.113.4" run_nhc --json --check peers --peers 203.0.113.1,203.0.113.2,203.0.113.3,203.0.113.4
assert_eq "{'203.0.113.1': 1, '203.0.113.2': 0, '203.0.113.3': 1, '203.0.113.4': 0}" "$(jget "$OUT" 'd["checks"][0]["metrics"]')" "parallel pings keep peer order"
for i in 301 302; do mkdir -p "$PROC/$i"; printf 'Name:\tz\nState:\tZ (zombie)\n' > "$PROC/$i/status"; done
set +e
PATH="$MIN_BIN" FIREPOT_PROC="$PROC" "$SCRIPT" --json --check zombies > "$TMP/min-out.txt" 2>/dev/null
set -e
assert_eq skip "$(jget "$TMP/min-out.txt" 'd["checks"][0]["status"]')" "zombies without grep is a clean skip"

begin "runtime edge cases keep the exit-code contract"
reset_env
: > "$PROC/loadavg"
run_nhc --json --check load
assert_eq 0 "$RC" "empty loadavg is a skip, not a crash"
assert_eq skip "$(jget "$OUT" 'd["checks"][0]["status"]')" "empty loadavg status"
printf 'MemTotal: 1000 kB\nSwapTotal: 1000 kB\n' > "$PROC/meminfo"
run_nhc --json --check memory,swap
assert_eq 0 "$RC" "incomplete meminfo exit"
assert_eq "skip skip" "$(jget "$OUT" '" ".join(c["status"] for c in d["checks"])')" "incomplete meminfo skips"
reset_env
sed 's/^check_zombies() {/check_zombies() { false/' "$SCRIPT" > "$TMP/crashy"; chmod +x "$TMP/crashy"
NHC_ENTRY="$TMP/crashy" run_nhc --json --check load,zombies
assert_eq 3 "$RC" "an unexpected failure exits 3, never a health state"
assert_contains "$(cat "$TMP/err.txt")" "unexpected runtime error" "runtime error message"
run_nhc --check load -- extra; assert_eq 3 "$RC" "argument after -- is rejected"
run_nhc --warn-load 1234567890; assert_eq 3 "$RC" "threshold out of range"
run_nhc --json --check load --warn-load 0.125 --crit-load 9; assert_eq 0 "$RC" "fractional thresholds"
run_nhc --json --check load --warn-load 0.1 --crit-load 9; assert_eq 1 "$RC" "value equal to threshold warns"
run_nhc --json --check load --warn-load -1 --crit-load 0.2; assert_eq 1 "$RC" "negative warn threshold"
run_nhc --json --check load --warn-load -0.5 --crit-load -0.25; assert_eq 2 "$RC" "negative crit threshold"

begin "deprecated node-healthcheck alias and pre-rename compatibility"
reset_env
assert_eq "" "$(readlink "$LEGACY" || true)" "bin/node-healthcheck is a regular file, not a symlink (raw URLs must serve the script)"
if cmp -s "$SCRIPT" "$LEGACY"; then assert_eq same same "bin/node-healthcheck is byte-identical to bin/firepot"; else assert_eq same differs "bin/node-healthcheck is byte-identical to bin/firepot (run: cp bin/firepot bin/node-healthcheck)"; fi
run_nhc --json --check load,memory
cp "$OUT" "$TMP/new-name.json"
assert_eq "$VERSION" "$(jget "$OUT" 'd["node-healthcheck"]')" "JSON keeps the node-healthcheck version key"
NHC_ENTRY="$LEGACY" run_nhc --json --check load,memory
assert_eq 0 "$RC" "alias exit"
assert_json_valid "$OUT" "alias json"
assert_eq "$(jget "$TMP/new-name.json" '[(c["name"], c["status"]) for c in d["checks"]]')" \
    "$(jget "$OUT" '[(c["name"], c["status"]) for c in d["checks"]]')" "alias behaves identically"
assert_eq 1 "$(grep -c . "$TMP/err.txt")" "alias prints exactly one stderr line"
assert_contains "$(cat "$TMP/err.txt")" "deprecated" "alias deprecation note"
assert_contains "$(cat "$TMP/err.txt")" "firepot" "alias names the new tool"
NHC_ENTRY="$LEGACY" run_nhc --version
assert_eq "firepot $VERSION" "$(cat "$OUT")" "alias version on stdout is unchanged"
ALIAS_DIR="$TMP/alias-bin"; mkdir -p "$ALIAS_DIR"; ln -s "$SCRIPT" "$ALIAS_DIR/node-healthcheck"
NHC_ENTRY="$ALIAS_DIR/node-healthcheck" run_nhc --version
assert_contains "$(cat "$TMP/err.txt")" "deprecated" "installed absolute alias link also warns"
NHC_ENTRY="$LEGACY" run_nhc --json --host node-a --host node-b --check load
assert_eq 0 "$RC" "fleet via alias"
assert_json_valid "$OUT" "fleet via alias json"
assert_eq "$VERSION $VERSION" "$(jget "$OUT" '" ".join(n["node-healthcheck"] for n in d["nodes"])')" "remote reports keep the version key"
assert_eq "" "$(jget "$OUT" '" ".join(n.get("error", "") for n in d["nodes"]).strip()')" "remote reports validate"
assert_eq 1 "$(grep -c . "$TMP/err.txt")" "fleet via alias: one local note"
# Remotes receive the file on stdin exactly as run_remote sends it ("bash -s").
set +e
stream_out="$(PATH="$BIN:$PATH" FIREPOT_PROC="$PROC" bash -s -- --json --check load < "$LEGACY" 2> "$TMP/stream-err.txt")"
stream_rc=$?
set -e
assert_eq 0 "$stream_rc" "streamed run exit"
assert_eq "" "$(cat "$TMP/stream-err.txt")" "streamed (remote) run prints no deprecation note"
assert_contains "$stream_out" "\"node-healthcheck\":\"$VERSION\"" "streamed run keeps the version key"
LEGACY_SSH_BIN="$TMP/legacy-ssh-bin"; mkdir -p "$LEGACY_SSH_BIN"
cat > "$LEGACY_SSH_BIN/ssh" <<SSH
#!/usr/bin/env bash
# A remote whose report carries only the key a hypothetical future emitter might use.
printf '{"firepot":"$VERSION","host":"node-f","status":"ok","exit_code":0,"checks":[]}\\n'
SSH
chmod +x "$LEGACY_SSH_BIN/ssh"
set +e
PATH="$LEGACY_SSH_BIN:$BIN:$PATH" "$SCRIPT" --json --host node-f --check load > "$TMP/out.txt" 2>/dev/null
RC=$?
set -e
assert_eq 0 "$RC" "validator accepts a firepot-keyed report"
run_legacy_env --json --check load,reboot_required
assert_eq 0 "$RC" "NODE_HEALTHCHECK_* fallback exit"
assert_eq 0.4 "$(jget "$OUT" '[c for c in d["checks"] if c["name"]=="load"][0]["metrics"]["load1"]')" "NODE_HEALTHCHECK_PROC fallback"
mkdir -p "$FSROOT/run"; touch "$FSROOT/run/reboot-required"
run_legacy_env --json --check reboot_required
assert_eq 1 "$RC" "NODE_HEALTHCHECK_ROOT fallback"
set +e
PATH="$BIN:$PATH" FIREPOT_ROOT="$TMP/empty-root" NODE_HEALTHCHECK_ROOT="$FSROOT" FIREPOT_PROC="$PROC" \
    FAKE_DF_K="$FIX/df-k.txt" FAKE_DF_I="$FIX/df-i.txt" "$SCRIPT" --json --check reboot_required > "$TMP/out.txt" 2>/dev/null
RC=$?
set -e
assert_eq 0 "$RC" "FIREPOT_ROOT takes precedence over NODE_HEALTHCHECK_ROOT"
mkdir -p "$TMP/decoy-proc"; printf '9.99 9.99 9.99 1/100 1\n' > "$TMP/decoy-proc/loadavg"
set +e
PATH="$BIN:$PATH" FIREPOT_PROC="$PROC" NODE_HEALTHCHECK_PROC="$TMP/decoy-proc" FIREPOT_ROOT="$FSROOT" \
    FAKE_DF_K="$FIX/df-k.txt" FAKE_DF_I="$FIX/df-i.txt" "$SCRIPT" --json --check load > "$TMP/out.txt" 2>/dev/null
set -e
assert_eq 0.4 "$(jget "$TMP/out.txt" '[c for c in d["checks"] if c["name"]=="load"][0]["metrics"]["load1"]')" \
    "FIREPOT_PROC takes precedence over NODE_HEALTHCHECK_PROC"

echo
echo "firepot tests: $PASS passed, $FAIL failed"
rm -rf "$TMP"
(( FAIL == 0 ))
