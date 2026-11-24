#!/bin/bash
# Runs every job's real entrypoint (~/dev/<category>/<repo>/…, beside this repo) against ../lib.sh, the NAS faked as a folder and GitHub as a local bare repo, the work replaced
# by a stub (_jr_run: prints $OUT, exits $RC). Checks the status each check ends with. Usage: bash test/examples_test.sh > log 2>&1
D=$(cd "$(dirname "$0")/.." && pwd); P=0 F=0
ok() { if [ "$2" = "$3" ]; then P=$((P + 1)); echo "PASS $1"; else F=$((F + 1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
H=$(mktemp -d); mkdir -p "$H/opt/job-runner" "$H/stores/vm" "$H/seed"
git init -q --bare -b main "$H/stores/github.git"; git -C "$H/seed" init -q -b main; echo seed > "$H/seed/README.md"; git -C "$H/seed" add README.md
git -C "$H/seed" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm seed; git -C "$H/seed" push -q "$H/stores/github.git" main
cat > "$H/opt/job-runner/lib.sh" <<'LIB'
. "$JR_LIB"
_jr_run() { printf '%s\n' "${OUT:-done}"; return "${RC:-0}"; }
jr_online() { return 0; }
trap '_jr_exit; echo "RESULT $JR_STATUS"' EXIT
LIB
M=chan-lescut-macbook-pro
run() {   # run <repo>/<file> VAR=…: one check, as machine JR_MACHINE_NAME (default the Mac), the job's real entrypoint (src) deployed
          # as ~/opt/<repo>/<file> and run from there
  local m=$M a r f=${1#*/} s=$(src "$1"); for a in "${@:2}"; do case $a in JR_MACHINE_NAME=*) m=${a#*=} ;; esac; done
  local p; p=$(ls "$R/$s" "$R"/*/"$s" 2>/dev/null | head -1)
  [ -n "$p" ] || { echo "MISSING ~/dev/<category>/$s"; return; }
  r=$H/opt/${1%%/*}; mkdir -p "$r"; cp "$p" "$r/$f"
  (cd "$r" && env HOME="$H" JR_LIB="$D/lib.sh" JR_NAS_DIR="$H/stores/vm" JR_GITHUB_URL="file://$H/stores/github.git" JR_TEST_LID=open JR_ROOT="$H/stores/local/$m" NOW=1791547200 JR_MACHINE_NAME=$m "${@:2}" /bin/bash "$f" 2>&1 | sed -n 's/^RESULT //p') | grep . ||
    { j=${r##*/}; [ "$f" = entrypoint.sh ] || j=$j.$(basename "$f" .sh)   # stopped at load (sync env, a WAIT): its status file
      tail -n 1 "$H/stores/local/$m/status/$j/$m.tsv" | cut -f3; }; }
hold() { mkdir -p "$H/stores/local/$M/claims/$1"; sleep 30 & echo "$M 0 $!" > "$H/stores/local/$M/claims/$1/owner"; }   # a live execution holds the lockfile
# Each job: where its project deploys it (~/opt/<repo>/<file>, the job's name) ← its source in the project's repo
R=${DEV_ROOT:-$HOME/dev}   # ~/dev: the repos are in ~/dev/<category>/<repo> (a flat ~/dev/<repo> still found)
src() { case $1 in   # where the project's repo keeps it
  jobs/auto-job-apply.sh) echo jobs/applying/auto-job-apply/entrypoint.sh ;;
  auto-commit/entrypoint.sh) echo auto-commit/src/entrypoint.sh ;;
  trading-bot/daily-global-scraping.sh) echo trading-bot/dev/1_global_scraping/deployment/daily-global-scraping.sh ;;
  trading-bot/cpl_monitoring*.sh|trading-bot/copy-trading-shadow-test.sh) echo trading-bot/dev/4_copy_trading/deployment/${1#*/} ;;
  agent-tracker/*.sh) echo agent-tracker/jobs/${1#*/} ;;
  marketplace-seller/entrypoint.sh) echo marketplace-seller/src/entrypoint.sh ;;
esac; }
# NOW = Fri 2026-10-09 12:00 UTC
mkdir -p "$H/opt/jobs/applying/auto-job-apply"   # its pipeline folder, where the entrypoint cds
ok "auto-job-apply: usage limit (75) = wait"           "$(run jobs/auto-job-apply.sh RC=75 OUT='retry-after 5400')" WAIT
ok "auto-job-apply: 30 min later: still waiting"       "$(run jobs/auto-job-apply.sh NOW=1791549000)" SKIP
ok "auto-job-apply: a run by hand still going (76)"    "$(run jobs/auto-job-apply.sh NOW=1791554400 RC=76)" SKIP
ok "auto-job-apply: success after the wait"           "$(run jobs/auto-job-apply.sh NOW=1791558000 OUT='SUMMARY 4 sent')" SUCCESS
ok "auto-job-apply: then skip today"                   "$(run jobs/auto-job-apply.sh NOW=1791561600)" SKIP
ok "auto-commit (Mac, 12:00, Friday): too early"   "$(run auto-commit/entrypoint.sh)" SKIP
ok "auto-commit (GCP, 14:00): success"             "$(run auto-commit/entrypoint.sh JR_MACHINE_NAME=GCP NOW=1791554400 OUT='x - Success - 3 commits')" SUCCESS
ok "auto-commit (Mac, 15:00): skip, done by GCP"   "$(run auto-commit/entrypoint.sh NOW=1791558000)" SKIP
hold trading-bot.daily-global-scraping
ok "trading-bot: a run still going here: skip"     "$(run trading-bot/daily-global-scraping.sh)" SKIP
kill %1 2> /dev/null; wait 2> /dev/null
ok "trading-bot: exit 0 without its last line"     "$(run trading-bot/daily-global-scraping.sh OUT='12 leaders to scrape right now')" FAILURE
ok "trading-bot: success"                          "$(run trading-bot/daily-global-scraping.sh NOW=1791548700 OUT='12 leaders to scrape right now
## END OF PYTHON MAIN SCRIPT ##')" SUCCESS
ok "trading-bot: its summary"                      "$(cut -f4 "$H/stores/local/$M/status/trading-bot.daily-global-scraping/$M.tsv" | tail -n 1)" "to scrape per stage: 12 leaders"
ok "trading-bot: its run folder, main.log inside"  "$(ls "$H"/opt/trading-bot/v*/logs/python_process/*/main.log | wc -l | tr -d ' ')" 2
ok "trading-bot: then skip 24 h"                   "$(run trading-bot/daily-global-scraping.sh NOW=1791552000)" SKIP
mkdir -p "$H/opt/agent-statusline/state/heartbeat"   # no heartbeat file: idle
ok "claude-quota: the poller says fresh (exit 10): skip" "$(run agent-tracker/claude-quota.sh RC=10 OUT='quota fresh enough (40 s) · sync ↑1 ↓0')" SKIP
ok "claude-quota: a poll, success"                 "$(run agent-tracker/claude-quota.sh NOW=1791547500 OUT='5h 42% · 7d 18% · sync ↑1 ↓0')" SUCCESS
ok "claude-quota: 429: wait, on this machine"      "$(run agent-tracker/claude-quota.sh NOW=1791547900 RC=75 OUT='sync ↑0 ↓0 · retry-after 1820')" WAIT
ok "claude-quota: the Mac, its own pending WAIT: skip" "$(run agent-tracker/claude-quota.sh NOW=1791548000)" SKIP
ok "claude-quota: the VM polls despite the Mac's 429" "$(run agent-tracker/claude-quota.sh JR_MACHINE_NAME=H-Frank-1 NOW=1791548000 OUT='5h 42% · 7d 18%')" SUCCESS
ok "claude-quota: the Mac, the sync failing for 30 min (exit 1): failure" "$(run agent-tracker/claude-quota.sh NOW=1791550000 RC=1 OUT='quota fresh enough (40 s) · H-Frank-1 not reached')" FAILURE
ok "codex-quota: the poller skips (exit 10)"       "$(run agent-tracker/codex-quota.sh RC=10 OUT='skip: a Codex session file is fresh')" SKIP
mkdir -p "$H/.codex" && touch "$H/.codex/auth.json"
ok "codex-plan-history: success"                   "$(run agent-tracker/codex-plan-history.sh)" SUCCESS
ok "codex-plan-history: then skip 24 h"            "$(run agent-tracker/codex-plan-history.sh NOW=1791550800)" SKIP
hold agent-tracker.aggregates
ok "aggregates: the previous run still going: skip" "$(run agent-tracker/aggregates.sh)" SKIP
kill %1 2> /dev/null; wait 2> /dev/null
ok "aggregates: success"                           "$(run agent-tracker/aggregates.sh OUT='slots: 3 written (… → …), 12 requests')" SUCCESS
ok "aggregates: the Mac, the VM unreachable: failure" "$(run agent-tracker/aggregates.sh NOW=1791548000 RC=1 OUT='slots: 1 written (… → …), 3 requests · H-Frank-1 not reached')" FAILURE
ok "cpl_monitoring: success, its CPL line"        "$(run trading-bot/cpl_monitoring.sh OUT='CPL 12 leaders, 3 orders')" SUCCESS
ok "cpl_monitoring_pack: success"                  "$(run trading-bot/cpl_monitoring_pack.sh OUT='packed 2026-10-08')" SUCCESS
ok "cpl_monitoring_pack: then skip today"          "$(run trading-bot/cpl_monitoring_pack.sh NOW=1791550800)" SKIP
MS=marketplace-seller/entrypoint.sh; mkdir -p "$H/opt/marketplace-seller/src"   # where the entrypoint runs src/check.py (stubbed)
ok "marketplace-seller: nothing to sell: no check, nothing recorded" "$(run $MS 2> /dev/null)" ""
mkdir -p "$H/opt/marketplace-seller/state"; echo bike > "$H/opt/marketplace-seller/state/to_sell.txt"   # an item for sale: the job runs
ok "marketplace-seller: success, its SUMMARY line"  "$(run $MS OUT='SUMMARY nothing due; bike 130→120 on 2026-11-11')" SUCCESS
ok "marketplace-seller: its summary"                "$(cut -f4 "$H/stores/local/$M/status/marketplace-seller/$M.tsv" | tail -n 1)" "SUMMARY nothing due; bike 130→120 on 2026-11-11"
ok "marketplace-seller: its Chrome open (13): skip, not a try" "$(run $MS NOW=1791549000 RC=13)" SKIP
ok "marketplace-seller: logged out (10): failure"   "$(run $MS NOW=1791550800 RC=10 OUT='SUMMARY logged out of Facebook')" FAILURE
ok "marketplace-seller: page changed (11): failure" "$(run $MS NOW=1791554400 RC=11 OUT='SUMMARY page changed')" FAILURE
ok "marketplace-seller: 3rd failure"                "$(run $MS NOW=1791558000 RC=10 OUT='SUMMARY logged out of Facebook')" FAILURE
ok "marketplace-seller: after 3 failures: skip today" "$(run $MS NOW=1791561600)" SKIP
ok "marketplace-seller: next UTC day: tries again"  "$(run $MS NOW=1791633600 OUT='SUMMARY nothing due')" SUCCESS
echo "== $P PASS, $F FAIL"
