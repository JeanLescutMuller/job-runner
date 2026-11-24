#!/bin/bash
# Give the dashboard a job's settings (DESIGN §11): ~/opt/job-runner/conf/JOB.conf on the NAS. Run by a project's install.sh
# on the machine it installs on, FILE being the project's deployed copy, ~/opt/<repo>/<job>.conf:
#   on the NAS (the only machine with the dashboard): a symlink to FILE (a FILE outside ~/opt/: a copy);
#   elsewhere: a copy over SSH with job-runner's own key, gated to ops.sh like the statuses, to the address lib.sh uses
#   (_jr_nas_addr, the same lines). GCP cannot reach the NAS: its settings stay on GitHub's side (none today).
# Usage: bash ~/opt/job-runner/put-conf.sh JOB FILE   e.g. put-conf.sh trading-bot.cpl_monitoring ~/opt/trading-bot/cpl_monitoring.conf
set -u; O=$(cd "$(dirname "$0")" && pwd)
[ $# = 2 ] && [[ $1 =~ ^[A-Za-z0-9_-][A-Za-z0-9._-]*$ ]] && [ -f "$2" ] || { echo "usage: put-conf.sh JOB FILE" >&2; exit 2; }
f=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
if [ -d "$O/dashboard" ] && [[ $f = $HOME/opt/* ]]; then mkdir -p "$O/conf" && ln -sfn "$f" "$O/conf/$1.conf" && echo "dashboard settings of $1: linked to $f"; exit
elif [ -d "$O/dashboard" ]; then out=$( (cd "$O" && sh ops.sh put-conf "$1") < "$2") || exit
else
  _jr_nas_addr() {   # as in lib.sh
    if [ -n "${JR_NAS_SSH:-}" ]; then printf '%s\n' $JR_NAS_SSH
    elif [ "$(uname)" = Darwin ]; then
      ssh -G babisnas 2>/dev/null | awk '$1 ~ /^(hostname|port|user|proxycommand)$/ && $2 != "none" { k = $1; $1 = ""; print "-o"; print k "=" substr($0, 2) }'
      echo babisnas
    else printf '%s\n' -p 22 enrices@babisnas; fi
  }
  a=(); while IFS= read -r l; do a+=("$l"); done < <(_jr_nas_addr)
  out=$(ssh -F /dev/null -i "${JR_SSH_KEY:-$HOME/.ssh/job-runner}" -o IdentitiesOnly=yes -o ConnectTimeout=5 -o BatchMode=yes \
        -o LogLevel=ERROR -o HostKeyAlias=babisnas -o UserKnownHostsFile="${JR_KNOWN_HOSTS:-$O/nas_known_hosts}" "${a[@]}" put-conf "$1" < "$2") || exit
fi
echo "dashboard settings of $1: ${out:-sent}"
