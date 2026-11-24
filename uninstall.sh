#!/bin/bash
# Remove what install.sh made on this machine: the canaries' trigger, the skills' links and copies, the code in ~/opt/job-runner;
# where they are (the NAS; the VM until 2026-11) also the dashboard (its unit, the tailscale serve on 8097) and the gate (the
# job-runner keys' lines in ~/.ssh/authorized_keys, so those keys no longer get in); on the NAS the boot kick (its container and image), the unit home-mode and the job job-runner.backup (its trigger and files). Keeps the data: status/, logs/, claims/, sync/, conf/, canaries/data/.
# Every job of this machine stops working: its entrypoint sources ~/opt/job-runner/lib.sh.
# Usage: bash uninstall.sh
set -u; O=$HOME/opt/job-runner NAS=BabisNAS
# This machine's name: skill "machine-name" (copy it identically)
m=${JR_MACHINE_NAME:-$(if [ "$(uname)" = Darwin ]; then scutil --get HostName; else cat /etc/hostname; fi 2>/dev/null)} || :
m=${m%%.*}; [[ $m =~ ^[A-Za-z0-9-]+$ ]] || { echo "no machine name: macOS sudo scutil --set HostName <name>; Linux sudo hostnamectl set-hostname <name>" >&2; exit 1; }

C=com.jeanlescut.job-runner.canaries U=com.jeanlescut.job-runner.dashboard
if [ "$(uname)" = Darwin ]; then
  launchctl bootout gui/$(id -u)/$C 2> /dev/null; rm -f ~/Library/LaunchAgents/$C.plist && echo "LaunchAgent $C removed"
else
  systemctl --user disable --now $C.timer $U.service 2> /dev/null
  rm -f ~/.config/systemd/user/$C.service ~/.config/systemd/user/$C.timer ~/.config/systemd/user/$U.service
  systemctl --user daemon-reload; echo "units $C, $U removed"
fi
if grep -q "job-runner/gate.sh" ~/.ssh/authorized_keys 2> /dev/null; then   # the hub: the NAS (the VM until 2026-11)
  tailscale serve --http=8097 off > /dev/null 2>&1; echo "tailscale serve on 8097 off"
  cp -p ~/.ssh/authorized_keys ~/.ssh/authorized_keys.bak-job-runner &&
    grep -v "job-runner/gate.sh" ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.new; chmod 600 ~/.ssh/authorized_keys.new &&
    mv ~/.ssh/authorized_keys.new ~/.ssh/authorized_keys && echo "gate: job-runner keys removed from authorized_keys"
fi
if [ "$m" = $NAS ] && [ -f "$O/boot-kick/compose.yaml" ]; then
  docker compose -f "$O/boot-kick/compose.yaml" down --rmi all > /dev/null 2>&1; rm -rf "$O/boot-kick"; echo "boot kick removed"
  H=com.jeanlescut.job-runner.home-mode.service
  systemctl --user disable $H 2> /dev/null; rm -f ~/.config/systemd/user/$H "$O/units/$H"; systemctl --user daemon-reload; echo "unit $H removed"
fi
if [ "$m" = $NAS ]; then   # the backup job: its timer, then a check still running, then its files (the store on the disk kept)
  J=com.jeanlescut.job-runner.backup
  systemctl --user disable --now $J.timer 2> /dev/null; systemctl --user stop $J.service 2> /dev/null
  rm -f ~/.config/systemd/user/$J.service ~/.config/systemd/user/$J.timer "$O/backup.sh" "$O/backup.conf"
  systemctl --user daemon-reload; echo "job job-runner.backup removed (its store on the portable disk kept)"
fi
for dst in "$O"/skills/*/; do
  [ -d "$dst" ] || continue
  dst=${dst%/}; name=$(basename "$dst")
  for link in "$HOME/.claude/skills/$name" "$HOME/.agents/skills/$name"; do
    [ -L "$link" ] && [ "$(readlink "$link")" = "$dst" ] && rm "$link" && echo "removed $link"
  done
done
[ -d "$O/skills" ] && chmod -R u+w "$O/skills"
rm -rf "$O/skills" "$O/units" "$O/dashboard" "$O/lib.sh" "$O/ops.sh" "$O/put-conf.sh" "$O/gate.sh" "$O/nas_known_hosts"
for f in "$O"/canaries/*.sh; do [ -f "$f" ] && rm "$f"; done; rm -rf "$O/canaries/work"
echo "code removed from $O; kept: $(cd "$O" 2>/dev/null && ls | tr '\n' ' ')"
