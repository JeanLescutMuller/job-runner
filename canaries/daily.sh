#!/bin/bash
# canaries.daily (R4, R5): each UTC day, a Failure on purpose, a Success 30 min later, then Skips until midnight UTC
. ~/opt/job-runner/lib.sh
jr_skip_if SUCCESS day "already succeeded today"
jr_skip_if FAILURE 1800 "failed less than 30 min ago"
jr_execute 1 work/daily.sh
