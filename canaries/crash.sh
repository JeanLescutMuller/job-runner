#!/bin/bash
# canaries.crash (R13): alternately kills its own check (as a sudden restart would), then a Success; the next check must close
# the killed one: FAILURE "never finished (killed, or the machine stopped)"
. ~/opt/job-runner/lib.sh
jr_execute 15 work/crash.sh
