#!/bin/bash
# Tests ../lib.sh, the NAS env faked as a local folder (JR_NAS_DIR) and GitHub as a local bare repo (JR_GITHUB_URL).
# Usage: bash test/lib_test.sh > log 2>&1 (PASS/FAIL lines, the count last)
D=$(cd "$(dirname "$0")" && pwd); L=$(cd "$D/.." && pwd)/lib.sh; P=0 F=0 J=test.example_entrypoint
ok() { if [ "$2" = "$3" ]; then P=$((P + 1)); echo "PASS $1"; else F=$((F + 1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
fresh() {   # new fake envs: $JR_PROTO/vm (the NAS), $JR_PROTO/github.git (job-runner-sync, main with a README)
  JR_PROTO=$(mktemp -d); mkdir -p "$JR_PROTO/vm" "$JR_PROTO/home" "$JR_PROTO/seed"
  git init -q --bare -b main "$JR_PROTO/github.git"; git -C "$JR_PROTO/seed" init -q -b main; echo seed > "$JR_PROTO/seed/README.md"
  git -C "$JR_PROTO/seed" add README.md; git -C "$JR_PROTO/seed" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm seed
  git -C "$JR_PROTO/seed" push -q "$JR_PROTO/github.git" main; }
fake() {   # the settings pointing a check at the fake envs; JR_FAKE_NAS=down / JR_FAKE_GITHUB=down make one unreachable
  local a vm=$JR_PROTO/vm gh=file://$JR_PROTO/github.git
  for a; do case $a in JR_FAKE_NAS=down) vm=$JR_PROTO/vm-down ;; JR_FAKE_GITHUB=down) gh=file://$JR_PROTO/none.git ;; esac; done
  echo "JR_NAS_DIR=$vm JR_GITHUB_URL=$gh HOME=$JR_PROTO/home JR_TEST_LID=open"; }
run() {   # run VAR=… …: one check of the example entrypoint, as machine JR_MACHINE_NAME (default mac), with its own LOCAL
  local m=mac a; for a; do case $a in JR_MACHINE_NAME=*) m=${a#*=} ;; esac; done
  env JR_MACHINE_NAME=$m JR_ROOT="$JR_PROTO/local/$m" $(fake "$@") "$@" /bin/bash "$D/example_entrypoint.sh" 2>&1 | grep -v '^job-runner: [A-Z]* unreachable$'; }
day=1791504000   # 2026-10-09 00:00 UTC

echo "== JR_SYNC_ENV=NAS: one pull, then reads of the copy"
export JR_PROTO; fresh
ok "1 NAS down: GCP cannot claim, skips"                "$(run JR_MACHINE_NAME=GCP NOW=$((day + 43200)) JR_FAKE_NAS=down)" "SKIP: cannot claim: NAS unreachable"
ok "2 NAS up: GCP executes; its whole file reaches the NAS" "$(run JR_MACHINE_NAME=GCP NOW=$((day + 43500)) | cut -c1-8; cut -f3 "$JR_PROTO/vm/status/$J/GCP.tsv" | tr '\n' ' ')" "EXECUTED
SKIP RUNNING SUCCESS "
ok "3 the Mac pulls GCP's success, skips"               "$(run NOW=$((day + 46800)))" "SKIP: already committed today"
ok "4 the copy is local: one pull, any number of reads" "$(ls "$JR_PROTO/local/mac/sync/NAS/status/$J")" "GCP.tsv
mac.tsv"
ok "5 JR_SYNC_ENV=LOCAL: nothing pulled, the NAS down changes nothing" "$(run JR_SYNC_ENV=LOCAL NOW=$((day + 2 * 86400)) JR_FAKE_NAS=down | cut -c1-8)" "EXECUTED"
ok "6 two sync envs: a config error"                   "$(run JR_SYNC_ENV='VM GITHUB' NOW=$day)" "config error: one JR_SYNC_ENV"
ok "   the old name VM: read as NAS (V3, 2026-11)"      "$(run JR_SYNC_ENV=VM NOW=$((day + 3 * 86400)) | cut -c1-8; ls "$JR_PROTO/local/mac/sync")" "EXECUTED
NAS"
fresh
mkdir -p "$JR_PROTO/vm/status/$J"; printf 'printf "9.1\\t%s\\tSUCCESS\\tdone\\n" > "%s"\n' $((day + 43210)) "$JR_PROTO/vm/status/$J/GCP.tsv" > "$JR_PROTO/between.sh"
ok "7 GCP succeeds just before the Mac's claim: the pull under the claim sees it, skip" "$(run NOW=$((day + 43200)) BETWEEN="sh $JR_PROTO/between.sh")" "SKIP: already committed today"
fresh
mkdir -p "$JR_PROTO/vm/status/$J"; printf 'printf "9.1\\t%s\\tSKIP\\ttoo early\\n" > "%s"\n' $((day + 43210)) "$JR_PROTO/vm/status/$J/GCP.tsv" > "$JR_PROTO/between.sh"
ok "7b GCP writes a SKIP around the Mac's claim: the claim is kept, executes (TODO #1)" "$(run NOW=$((day + 43200)) BETWEEN="sh $JR_PROTO/between.sh" | cut -c1-8)" "EXECUTED"
fresh
ok "8 GCP: a WAIT for all machines (a shared limit)"    "$(run JR_MACHINE_NAME=GCP NOW=$((day + 43200)) WAITALL='3600 all shared limit' | cut -c1-8)" "EXECUTED"
ok "9 the Mac pulls it: waits too"                       "$(run NOW=$((day + 44000)); tail -n 1 "$JR_PROTO/local/mac/status/$J/mac.tsv" | cut -f3,4)" "SKIP	waiting until 13:00 UTC: shared limit (asked by GCP)"
fresh
ok "10 a WAIT for this machine only does not stop the others" "$(run JR_MACHINE_NAME=GCP NOW=$((day + 43200)) WAITALL='3600 own limit' > /dev/null; run NOW=$((day + 44000)) | cut -c1-8)" "EXECUTED"

echo "== Claims (locks, not statuses)"
fresh
ok "11 GCP claims (the lockfile, the NAS), holds"      "$(run JR_MACHINE_NAME=GCP NOW=$((day + 43200)) HOLD=1)" "HOLDING (claims LOCAL NAS)"
ok "12 the Mac, 5 min later: held, skip"            "$(run NOW=$((day + 43500)))" "SKIP: held by GCP until 12:15 on NAS"
ok "13 the Mac, 20 min later: expired, executes"     "$(run NOW=$((day + 44400)) | cut -c1-8)" "EXECUTED"
ok "14 JR_SYNC_ENV=GITHUB: GCP claims on GitHub"    "$(fresh; run JR_SYNC_ENV=GITHUB JR_MACHINE_NAME=GCP NOW=$day HOLD=1)" "HOLDING (claims LOCAL GITHUB)"
fresh; mkdir -p "$JR_PROTO/local/mac/claims/$J"; sleep 30 & echo "mac 0 $!" > "$JR_PROTO/local/mac/claims/$J/owner"
ok "15 LOCAL: a previous execution still running here: skip" "$(run JR_SYNC_ENV=LOCAL NOW=$day | sed 's/pid [0-9]*/pid N/')" "SKIP: previous execution still running (pid N)"
kill %1 2> /dev/null; wait 2> /dev/null
ok "16 LOCAL: its process gone: the lockfile is taken" "$(run JR_SYNC_ENV=LOCAL NOW=$day | cut -c1-8)" "EXECUTED"

echo "== Statuses: one per check, the last one written; a check killed; logs"
fresh; mkdir -p "$JR_PROTO/aa"
printf '. "%s"; _jr_run() { echo "usage limit"; return 75; }\njr_execute 120 run_pipeline; [ $JR_RC = 75 ] && jr_write_status WAIT "3000 Claude usage limit"\n' "$L" > "$JR_PROTO/aa/entrypoint.sh"
aa() { env JR_MACHINE_NAME=mac JR_ROOT="$JR_PROTO/local/mac" $(fake) "$@" /bin/bash "$JR_PROTO/aa/entrypoint.sh"; }
aa NOW=$((day + 3600)); f=$JR_PROTO/local/mac/status/aa/mac.tsv
ok "17 written: RUNNING, FAILURE (exit 75), WAIT"   "$(cut -f3 "$f" | tr '\n' ' ')" "RUNNING FAILURE WAIT "
ok "   the line: check id, time written, status, text" "$(tail -n 1 "$f" | awk -F'\t' '{ print ($1 ~ /^1791507600\.[0-9]+$/) " " ($2 >= 1791507600) " " $3 " " $4 }')" "1 1 WAIT 3000 Claude usage limit"
ok "   read: the check is a WAIT, no failure today" "$(printf '. "%s"; trap - EXIT; echo "$(jr_read_statuses_since %s | cut -f3) / $(jr_read_statuses_since %s FAILURE | wc -l | tr -d " ")"\n' "$L" $day $day > "$JR_PROTO/aa/r.sh"; mv "$JR_PROTO/aa/r.sh" "$JR_PROTO/aa/entrypoint.sh"; aa NOW=$((day + 7200)))" "WAIT / 0"
printf '. "%s"; echo worked\n' "$L" > "$JR_PROTO/aa/w.sh"
ok "   a check 10 min later: SKIP until the WAIT ends" "$(mv "$JR_PROTO/aa/entrypoint.sh" "$JR_PROTO/aa/e.bak"; cp "$JR_PROTO/aa/w.sh" "$JR_PROTO/aa/entrypoint.sh"; aa NOW=$((day + 3600 + 600)); tail -n 1 "$f" | cut -f3,4)" "SKIP	waiting until 01:50 UTC: Claude usage limit"
ok "   20 min later: still waiting (a SKIP does not end it)" "$(aa NOW=$((day + 3600 + 1200)); tail -n 1 "$f" | cut -f3)" "SKIP"
ok "   after the 50 min: the check goes on" "$(aa NOW=$((day + 3600 + 3060)))" "worked"
mv "$JR_PROTO/aa/e.bak" "$JR_PROTO/aa/entrypoint.sh"
printf '%s.99999\t%s\tRUNNING\t\n' $((day + 9000)) $((day + 9000)) >> "$f"   # a check killed with kill -9 (pid 99999 gone)
printf '. "%s"; _jr_run() { echo boom; return 3; }; jr_execute 5 work\n' "$L" > "$JR_PROTO/aa/entrypoint.sh"
aa NOW=$((day + 10800))
ok "18 the next check closes the killed one"        "$(grep "^$((day + 9000)).99999" "$f" | tail -n 1 | cut -f3,4)" "FAILURE	never finished (killed, or the machine stopped)"
ok "19 a failed log reaches the NAS at the end of its own check" "$(ls "$JR_PROTO/vm/logs/aa/mac" | wc -l | tr -d ' ')" "1"
for i in 1 2 3 4 5 6; do aa NOW=$((day + 20000 + i)) JR_KEEP_N_LOGS=2 JR_KEEP_N_LOGS_FAILURE=3 > /dev/null; done
ok "20 rotation at load: 3 kept (2 newest, at least 3 failed) + this check's own" "$(ls "$JR_PROTO/local/mac/logs/aa/mac" | wc -l | tr -d ' ')" "4"

echo "== The real pieces: timeout, dry run, laptop in a bag, GitHub, GCP, the NAS itself, the token"
fresh; mkdir -p "$JR_PROTO/tt"; f=$JR_PROTO/local/mac/status/tt/mac.tsv
tt() { env JR_MACHINE_NAME=mac JR_ROOT="$JR_PROTO/local/mac" $(fake) "$@" /bin/bash "$JR_PROTO/tt/entrypoint.sh" 2>&1; }
printf '. "%s"; jr_execute 1 sh -c "sleep 41 & sleep 41"\n' "$L" > "$JR_PROTO/tt/entrypoint.sh"
t0=$(date +%s); tt NOW=$day JR_TEST_MINUTE_S=2 > /dev/null; t1=$(date +%s)
ok "21 timeout: FAILURE, the whole group killed, in time" "$(tail -n 1 "$f" | cut -f3,4) $([ $((t1 - t0)) -lt 8 ] && echo fast) $(pgrep -fx 'sleep 41' | wc -l | tr -d ' ')" "FAILURE	timeout after 1 min fast 0"
printf '. "%s"; jr_execute 5 sh -c "echo WORKED"; echo "rc=$JR_RC"\n' "$L" > "$JR_PROTO/tt/entrypoint.sh"
ok "22 dry run: decisions for real, the work not done" "$(tt NOW=$((day + 60)) JR_DRY_RUN=1; tail -n 1 "$f" | cut -f3,4)" "rc=0
SKIP	dry run: sh -c echo WORKED"
ok "23 lid closed on battery: nothing, not even a status" "$(tt NOW=$((day + 120)) JR_TEST_LID=closed JR_TEST_POWER=battery; wc -l < "$f" | tr -d ' ')" "job-runner: lid closed, on battery: nothing started
3"
ok "   lid closed on AC: works"                       "$(tt NOW=$((day + 180)) JR_TEST_LID=closed JR_TEST_POWER=ac)" "rc=0"
fresh
ok "24 GITHUB: GCP's whole file pushed on main"       "$(run JR_SYNC_ENV=GITHUB JR_MACHINE_NAME=GCP NOW=$day | cut -c1-8; git --git-dir="$JR_PROTO/github.git" show main:status/$J/GCP.tsv | cut -f3 | tr '\n' ' ')" "EXECUTED
RUNNING SUCCESS "
ok "   no claim left on main"                          "$(git --git-dir="$JR_PROTO/github.git" ls-tree -r --name-only main | grep -c '^claims/')" "0"
ok "   the Mac, through GitHub: done today, skip"     "$(run JR_SYNC_ENV=GITHUB NOW=$((day + 3600)))" "SKIP: already committed today"
rm -rf "$JR_PROTO/local/GCP"                         # GCP keeps nothing between checks
ok "25 GCP's own file back from the sync env at load" "$(run JR_SYNC_ENV=GITHUB JR_MACHINE_NAME=GCP NOW=$((day + 86400)) | cut -c1-8; cut -f3 "$JR_PROTO/local/GCP/status/$J/GCP.tsv" | tr '\n' ' ')" "EXECUTED
RUNNING SUCCESS RUNNING SUCCESS "
ok "   GCP never reports to the NAS (not on the tailnet): GITHUB only" "$(find "$JR_PROTO/vm" -name GCP.tsv | wc -l | tr -d ' '; [ -s "$JR_PROTO/vm/status/$J/mac.tsv" ] && echo "the Mac's there")" "0
the Mac's there"
fresh
ok "26 on the NAS: the env NAS is its own disk"         "$(run JR_MACHINE_NAME=vmhost JR_NAS_HOST=vmhost JR_NAS_DIR= NOW=$day | cut -c1-8; ls "$JR_PROTO/vm" | wc -l | tr -d ' '; cut -f3 "$JR_PROTO/local/vmhost/status/$J/vmhost.tsv" | tr '\n' ' ')" "EXECUTED
0
RUNNING SUCCESS "
ok "   the Mac's claim there is the NAS's lock too"    "$(run JR_NAS_DIR="$JR_PROTO/local/vmhost" NOW=$((day + 86400)) HOLD=1 > /dev/null; run JR_MACHINE_NAME=vmhost JR_NAS_HOST=vmhost JR_NAS_DIR= NOW=$((day + 86460)) JR_SYNC_ENV=LOCAL)" "SKIP: held by mac until 00:15 on LOCAL"
mkdir -p "$JR_PROTO/tt"; printf '. "%s"; jr_execute 1 sh -c "echo t=\\${JR_SYNC_TOKEN:-none}"; echo "$JR_LAST_LINE"\n' "$L" > "$JR_PROTO/tt/entrypoint.sh"
ok "27 the work never sees the job-runner-sync token" "$(JR_SYNC_TOKEN=secret tt NOW=$((day + 240)))" "t=none"
mkdir -p "$JR_PROTO/mm"; printf '. "%s"; jr_execute 1 sh -c "echo m=\\$JR_MACHINE_NAME"; echo "$JR_LAST_LINE"\n' "$L" > "$JR_PROTO/mm/entrypoint.sh"
mm() { env -u JR_MACHINE_NAME JR_ROOT="$JR_PROTO/local/mm" $(fake) "$@" /bin/bash "$JR_PROTO/mm/entrypoint.sh" 2>&1; }
want=$(if [ "$(uname)" = Darwin ]; then scutil --get HostName; else cat /etc/hostname; fi); want=${want%%.*}
ok "28 the work receives the machine's name (skill \"machine-name\")" "$(mm NOW=$((day + 300)))" "m=$want"
ok "   a name with a domain: cut at the first dot"      "$(mm JR_MACHINE_NAME=GCP.example NOW=$((day + 360)))" "m=GCP"
ok "   no valid name: the check stops, says why"        "$(mm JR_MACHINE_NAME='a b' NOW=$((day + 420)) | cut -c1-15)" "no machine name"
echo "== $P PASS, $F FAIL"
