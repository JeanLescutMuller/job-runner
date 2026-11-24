#!/bin/bash
mkdir -p data; n=$(( $(cat data/crash.n 2> /dev/null || echo 0) + 1 )); echo $n > data/crash.n
(( n % 2 )) || { echo "execution $n: Success after the previous crash"; exit 0; }
p=$PPID   # up to the check: the bash running canaries/crash.sh
while [ "$p" -gt 1 ] && ! ps -o command= -p "$p" | grep -q 'canaries/crash.sh'; do p=$(ps -o ppid= -p "$p" | tr -d ' '); done
[ "$p" -gt 1 ] || { echo "no check process found"; exit 1; }
echo "execution $n: killing my check $p"; kill -9 "$p"; sleep 5
