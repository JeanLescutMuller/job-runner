#!/bin/bash
# A test entrypoint (auto-commit's decision; the work is "echo"): its settings, the library, the claim (and its
# pull), then reads of that copy, the work. Where statuses and claims go is the library's business (../lib.sh).
: "${JR_SYNC_ENV:=NAS}"                  # read and claim on the NAS (tests may override)
. "$(dirname "$0")/../lib.sh"
skip() { JR_WHY=$1; jr_skip "$1"; }
trap '_jr_exit; [ "$JR_STATUS" = SKIP ] && [ "$JR_TEXT" = "$JR_WHY" ] && echo "SKIP: $JR_WHY"' EXIT   # the skips with a reason

[ -n "${BETWEEN:-}" ] && eval "$BETWEEN" # tests: another machine acts just before the claim
jr_claim 15                              # then one copy of the NAS's statuses; held or unreachable: SKIP "$JR_WHY"
today=$((NOW - NOW % 86400))
[ -n "$(jr_read_statuses_since "$today" SUCCESS)" ] && skip "already committed today"
[ -n "${HOLD:-}" ] && { echo "HOLDING (claims$JR_CLAIMS)"; trap - EXIT; exit 0; }   # tests: leave the claims held
jr_execute 10 ${WORK:-echo "3 commits pushed"}
[ -n "${WAITALL:-}" ] && jr_write_status WAIT "$WAITALL"
echo "EXECUTED (read $JR_SYNC_ENV)"
