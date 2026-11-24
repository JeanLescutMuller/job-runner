#!/bin/bash
# canaries.chaos (R5, R8): a random outcome: Success, Failure, WAIT (this machine or all), killed, missing command, slow failure.
# A success counts for 2 h; 20 min between failures; at most 3 failures a day
. ~/opt/job-runner/lib.sh
jr_skip_if SUCCESS 7200 "succeeded in the last 2 h"
jr_skip_if FAILURE 1200 "failed less than 20 min ago"
jr_skip_if FAILURE day "3 failures today" 3
jr_execute 2 work/chaos.sh
w=$(sed -n 's/^WAIT //p' "$JR_LOG" | tail -n 1)                 # its line "WAIT SECONDS [all] reason"
[ $JR_RC != 75 ] || jr_write_status WAIT "${w:-1200 no WAIT line}"
