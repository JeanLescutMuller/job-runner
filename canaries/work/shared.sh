#!/bin/bash
n=$((RANDOM % 100)); h=$JR_MACHINE_NAME; echo "draw $n on $h"
if   ((n < 70)); then sleep $((30 + RANDOM % 90)); echo "Success on $h"; exit 0
elif ((n < 85)); then sleep 30; echo "Failure on $h" >&2; exit 1
elif ((n < 93)); then echo "WAIT 900 all canary: not now anywhere"; echo "Ask to Wait for all machines, from $h"; exit 75
else echo "WAIT 900 canary: not now on $h"; echo "Ask to Wait for this machine only, on $h"; exit 75
fi
