#!/bin/bash
# canaries.audit, on the NAS only (the hub: it holds every machine's statuses; the VM until 2026-11): work/audit.py checks the promises the canaries test;
# a Failure lists the problems. Acknowledge the ones seen so far: date +%s > ~/opt/job-runner/canaries/data/audit.ack
# This machine's name: skill "machine-name" (copy it identically)
m=${JR_MACHINE_NAME:-$(if [ "$(uname)" = Darwin ]; then scutil --get HostName; else cat /etc/hostname; fi 2>/dev/null)} || :
m=${m%%.*}; [[ $m =~ ^[A-Za-z0-9-]+$ ]] || { echo "no machine name: macOS sudo scutil --set HostName <name>; Linux sudo hostnamectl set-hostname <name>" >&2; exit 1; }
[ "$m" = BabisNAS ] || exit 0
. ~/opt/job-runner/lib.sh
jr_skip_if SUCCESS 3600 "audited in the last hour"
jr_execute 2 python3 work/audit.py
jr_summary_grep '^AUDIT'
