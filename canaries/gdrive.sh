#!/bin/bash
# canaries.gdrive: the NAS only (2026-11-18, data-reorganisation task G2): the Drive is mounted read-only at ~/gdrive by
# my-setup's module gdrive_mount (Docker container gdrive-mount) and readable. Not a test of job-runner: a health check
# of the NAS, shown on the dashboard (FAILURE + the reason); canaries/run.sh also withholds the "babisnas" ping then.
# This machine's name: skill "machine-name" (copy it identically)
m=${JR_MACHINE_NAME:-$(if [ "$(uname)" = Darwin ]; then scutil --get HostName; else cat /etc/hostname; fi 2>/dev/null)} || :
m=${m%%.*}; [[ $m =~ ^[A-Za-z0-9-]+$ ]] || { echo "no machine name: macOS sudo scutil --set HostName <name>; Linux sudo hostnamectl set-hostname <name>" >&2; exit 1; }
[ "$m" = BabisNAS ] || exit 0   # the other machines: no status at all
. ~/opt/job-runner/lib.sh
jr_execute 1 /bin/bash -c 'f=~/gdrive/Personal/about-me/AGENTS_SHARED.md
  if timeout 20 test -s "$f"; then echo "the Drive is mounted: $f readable"
  else echo "the Drive is NOT mounted at ~/gdrive: docker logs gdrive-mount (my-setup doc/gdrive_mount.md)"; exit 1; fi'
