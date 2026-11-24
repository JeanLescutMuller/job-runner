#!/bin/bash
# The canaries' tick (Mac: LaunchAgent com.jeanlescut.job-runner.canaries every 10 min; Linux: its timer, the same): starts every
# canary, each its own check, as a real job's trigger would. A canary is any canaries/*.sh but this file (job canaries.<name>).
# The NAS: puts the home back to 700 if it drifted (boot-kick/home-mode.sh). Then pings this machine's healthchecks.io check, if it has one (DESIGN §13): its ping URL in
# ~/.config/job-runner/healthchecks_<machine, lower case>.url (mode 600; e.g. the NAS's check "babisnas"), never printed.
# The NAS: no ping while the Drive is not mounted at ~/gdrive (my-setup's gdrive_mount; canaries.gdrive shows why on the dashboard).
cd "$(dirname "$0")" || exit 1
[ -f data/drill-nas-down ] && export JR_NAS_SSH=nas-down.invalid   # the drill (doc/drill.md): the NAS unreachable from here
for f in *.sh; do [ "$f" = run.sh ] || nohup /bin/bash "$PWD/$f" > /dev/null 2>&1 & done
# This machine's name: skill "machine-name" (copy it identically)
m=${JR_MACHINE_NAME:-$(if [ "$(uname)" = Darwin ]; then scutil --get HostName; else cat /etc/hostname; fi 2>/dev/null)} || :
m=${m%%.*}; [[ $m =~ ^[A-Za-z0-9-]+$ ]] || { echo "no machine name: macOS sudo scutil --set HostName <name>; Linux sudo hostnamectl set-hostname <name>" >&2; exit 1; }
[ "$m" = BabisNAS ] && /bin/bash ../boot-kick/home-mode.sh   # the NAS: the home back to 700 if UGOS reset it (DESIGN §13)
hc=~/.config/job-runner/healthchecks_$(echo "$m" | tr '[:upper:]' '[:lower:]').url
gd=; [ "$m" = BabisNAS ] && ! timeout 20 test -s ~/gdrive/Personal/about-me/AGENTS_SHARED.md \
  && gd="the Drive is NOT mounted at ~/gdrive (docker logs gdrive-mount)" && echo "gdrive: $gd"
if [ ! -f "$hc" ]; then echo "healthchecks.io: no ping ($hc missing)"
elif [ -n "$gd" ]; then echo "healthchecks.io: not pinged ($gd)"
elif printf 'url = "%s"\n' "$(cat "$hc")" | curl -fsS -m 10 --retry 2 -o /dev/null -K - 2> /dev/null; then echo "healthchecks.io: pinged"
else echo "healthchecks.io: ping failed (curl exit $?)"; fi
