#!/bin/bash
# canaries.shared-nas (R7, R8, R11): shared by the machines through the env NAS (canaries.shared-vm until 2026-11, the env VM): one Success per hour whichever machine,
# never two executions at once, failures and "WAIT … all" across machines. 30 s to 2 min, so the machines race
JR_SYNC_ENV=NAS
. ~/opt/job-runner/lib.sh
jr_claim 5                               # the lock, then the pull: decided below on what it read
jr_skip_if SUCCESS 3600 "a machine succeeded in the last hour"
jr_skip_if FAILURE 600 "a machine failed less than 10 min ago"
jr_execute 3 work/shared.sh
w=$(sed -n 's/^WAIT //p' "$JR_LOG" | tail -n 1)
[ $JR_RC != 75 ] || jr_write_status WAIT "$w"
