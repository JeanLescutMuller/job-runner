#!/bin/bash
# canaries.sync-down (R7): synced on a GitHub repo that does not exist: every check must skip "cannot sync: GITHUB unreachable"
JR_SYNC_ENV=GITHUB JR_GITHUB_URL=https://github.com/JeanLescutMuller/no-such-sync-repo.git
. ~/opt/job-runner/lib.sh
jr_pull || jr_skip "$JR_WHY"
jr_execute 1 echo "must never run"
