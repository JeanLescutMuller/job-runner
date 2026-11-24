#!/bin/bash
# canaries.timeout (R10): alternately a timeout (a child ignores TERM: the KILL 10 s later stops it), then a Success that checks
# nothing of the previous execution survived (a Failure "LEAK" otherwise)
. ~/opt/job-runner/lib.sh
jr_execute 1 work/timeout.sh
