#!/bin/bash
mkdir -p data; today=$(date -u +%F)
[ "$(cat data/daily.failed 2> /dev/null)" = "$today" ] || { echo "$today" > data/daily.failed; echo "first try of $today fails on purpose"; exit 1; }
echo "retry of $today succeeds"
