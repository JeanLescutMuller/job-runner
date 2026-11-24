#!/bin/bash
n=$((RANDOM % 100)); echo "draw $n"
if   ((n < 35)); then echo "Success"; exit 0
elif ((n < 55)); then echo "WAIT 10800 all (must be ignored: exit 1)"; echo "Failure, exit 1 (on stderr)" >&2; exit 1
elif ((n < 60)); then echo "Ask to Wait, exit 75, no WAIT line"; exit 75
elif ((n < 65)); then echo "WAIT 900 chaos: not now here"; echo "Ask to Wait, exit 75, 15 min for this machine"; exit 75
elif ((n < 70)); then echo "WAIT 1500 all chaos: not now anywhere"; echo "Ask to Wait, exit 75, 25 min for all machines"; exit 75
elif ((n < 80)); then echo "killed by SIGKILL"; kill -9 $$
elif ((n < 90)); then echo "missing command, exit 127"; exec /nonexistent/command
else echo "exit 255 after 70 s"; sleep 70; exit 255
fi
