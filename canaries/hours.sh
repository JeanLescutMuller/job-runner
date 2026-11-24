#!/bin/bash
# canaries.hours (R3): auto-commit's rule on every machine: not before its hour of the day (UTC, Mon..Sun), once a day
. ~/opt/job-runner/lib.sh
h=(13 14 11 11 13 10 13)
[ $HOUR -lt ${h[DOW-1]} ] && jr_skip "too early: not before ${h[DOW-1]}:00 UTC"
jr_skip_if SUCCESS day "already executed today"
jr_execute 1 sh -c 'echo "executed at $(date -u +%H:%M) UTC"'
