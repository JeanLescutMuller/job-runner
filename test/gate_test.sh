#!/bin/bash
# Tests ../gate.sh and ../ops.sh as the NAS runs them for a job-runner key, in a fake HOME. Usage: bash test/gate_test.sh
D=$(cd "$(dirname "$0")/.." && pwd); P=0 F=0; H=$(mktemp -d); mkdir -p "$H/opt/job-runner"; cp "$D/ops.sh" "$D/gate.sh" "$H/opt/job-runner/"
ok() { if [ "$2" = "$3" ]; then P=$((P + 1)); echo "PASS $1"; else F=$((F + 1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
gate() { echo "${2:-}" | HOME=$H SSH_ORIGINAL_COMMAND=$1 sh "$H/opt/job-runner/gate.sh" 2>&1; echo "rc=$?"; }
ok "1 put-status writes the status file"   "$(gate 'put-status auto-job-apply mac' 'a line' | tail -1; cat "$H/opt/job-runner/status/auto-job-apply/mac.tsv")" "rc=0
a line"
ok "2 get-statuses sends a tar of it"      "$(HOME=$H SSH_ORIGINAL_COMMAND='get-statuses auto-job-apply' sh "$H/opt/job-runner/gate.sh" | tar tf - | sort | tail -1)" "status/auto-job-apply/mac.tsv"
ok "3 claim, then held for another machine" "$(gate 'claim NAS job1 mac 100 1000 7' > /dev/null; gate 'claim NAS job1 vm 200 1300 8' | head -1)" "held mac 1000"
ok "4 release by its owner"                "$(gate 'release NAS job1 mac 7' | tail -1; ls "$H/opt/job-runner/claims")" "rc=0"
ok "5 another command: refused"            "$(gate 'rm -rf /tmp/x' | tr '\n' ' ')" "job-runner gate: refused: rm rc=2 "
ok "6 a path in an argument: refused"      "$(gate 'put-status ../../.ssh authorized_keys' x | tr '\n' ' ')" "job-runner gate: refused argument rc=2 "
ok "7 shell syntax in an argument: refused" "$(gate 'list-logs a;ls b' | tr '\n' ' ')" "job-runner gate: refused argument rc=2 "
ok "8 .. alone: refused"                   "$(gate 'list-logs .. x' | tr '\n' ' ')" "job-runner gate: refused argument rc=2 "
ok "9 a glob is not expanded"              "$(gate 'list-logs * x' | tr '\n' ' ')" "job-runner gate: refused argument rc=2 "
ok "11 put-conf writes the job's settings" "$(gate 'put-conf trading-bot.cpl_monitoring' 'ORDER=11' | tail -1; cat "$H/opt/job-runner/conf/trading-bot.cpl_monitoring.conf")" "rc=0
ORDER=11"
ok "10 no command: refused"                "$(gate '' | tr '\n' ' ')" "job-runner gate: refused:  rc=2 "
# put-conf.sh on the NAS (it has dashboard/): a project's deployed file is linked, any other file copied
cp "$D/put-conf.sh" "$H/opt/job-runner/"; mkdir -p "$H/opt/job-runner/dashboard" "$H/opt/proj"; echo ORDER=5 > "$H/opt/proj/x.conf"; echo ORDER=6 > "$H/y.conf"
HOME=$H bash "$H/opt/job-runner/put-conf.sh" proj.x "$H/opt/proj/x.conf" > /dev/null; HOME=$H bash "$H/opt/job-runner/put-conf.sh" proj.y "$H/y.conf" > /dev/null
ok "12 put-conf.sh on the NAS: ~/opt/<repo>/ file linked" "$(readlink "$H/opt/job-runner/conf/proj.x.conf")" "$H/opt/proj/x.conf"
ok "13 put-conf.sh on the NAS: other file copied" "$([ -L "$H/opt/job-runner/conf/proj.y.conf" ] || cat "$H/opt/job-runner/conf/proj.y.conf")" "ORDER=6"
ok "14 put-conf over a working link: kept" "$(gate 'put-conf proj.x' 'ORDER=9' | head -1; readlink "$H/opt/job-runner/conf/proj.x.conf")" "kept: linked on the NAS
$H/opt/proj/x.conf"
echo "== $P PASS, $F FAIL"
