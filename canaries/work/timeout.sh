#!/bin/bash
mkdir -p data; n=$(( $(cat data/timeout.n 2> /dev/null || echo 0) + 1 )); echo $n > data/timeout.n
if (( n % 2 )); then
  (trap '' TERM; exec sleep 8011) &   # an ignored signal stays ignored after exec: only the KILL stops it
  echo "execution $n: sleeping past the timeout"; sleep 8012
elif pgrep -f 'sleep 801[12]' > /dev/null; then
  echo "LEAK: processes of the previous execution survived its timeout"; pkill -9 -f 'sleep 801[12]'; exit 1
else echo "execution $n: the previous timeout stopped every process"; fi
