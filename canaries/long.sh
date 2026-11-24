#!/bin/bash
# canaries.long (R11): 14 minutes, longer than the 10-min tick; claimed, so the next check skips "previous execution still running"
. ~/opt/job-runner/lib.sh
jr_skip_if SUCCESS 3600 "succeeded in the last hour"
jr_claim 20
jr_execute 15 sh -c 'for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do echo "minute $i"; sleep 60; done'
