#!/bin/bash
# Install job-runner on this machine, from this clone's last commit (HEAD), in ~/opt/job-runner (DESIGN §12). Idempotent.
#   Every machine: the library (lib.sh, ops.sh, put-conf.sh); the canaries (canaries/, their data/ kept), started every 10 min
#   by com.jeanlescut.job-runner.canaries (Mac: a LaunchAgent; Linux: a systemd timer); the skills (skills/<name>/, read-only
#   in ~/opt/job-runner/skills/, linked from ~/.claude/skills/ and ~/.agents/skills/).
#   Every machine but the NAS: the NAS's host key, nas_known_hosts (deploy/nas_known_hosts), for reporting there (lib.sh).
#   The NAS (BabisNAS, the env NAS: the VM H-Frank-1 until 2026-11, data-reorganisation V3) also: the gate (gate.sh), the
#   forced command of the job-runner keys (deploy/keys/*.pub) in ~/.ssh/authorized_keys, so they can run only ops.sh's
#   operations; the dashboard (dashboard/: dashboard.py and job-runner's settings conf/), run by
#   com.jeanlescut.job-runner.dashboard on 127.0.0.1:8097, published on the tailnet (http://babisnas:8097; `tailscale serve`
#   needs the operator set once: sudo tailscale set --operator=$USER).
#   The NAS also: the boot kick (boot-kick/, DESIGN §13), the container job-runner-boot-kick that starts the user's
#   systemd jobs at each boot; com.jeanlescut.job-runner.home-mode, a oneshot of default.target that puts the home back to
#   700 (UGOS sets it to 777 at boot); its healthchecks.io ping URL is the user's: ~/.config/job-runner/healthchecks_babisnas.url.
#   And the job job-runner.backup (backup/backup.sh, to ~/opt/job-runner/backup.sh): /volume1/private (the encrypted folder) into the restic store on
#   the portable disk, run by com.jeanlescut.job-runner.backup (a timer, Sundays 02:00 UTC, Persistent); its dashboard
#   settings backup.conf given to the dashboard; its healthchecks.io ping URL: ~/.config/job-runner/healthchecks_babisnas-backup.url.
#   Unit files are real files in ~/opt/job-runner/units/, symlinks where launchd and systemd look.
# Never touches what the checks and the projects own: status/, logs/, claims/, sync/, conf/. Triggers belong to each job's project.
# GCP has no install: a project's image copies lib.sh (e.g. auto-commit's gcp.Dockerfile).
# Usage, the Mac:  bash ~/dev/infra/job-runner/install.sh
#        the NAS:  from a temporary clone too (or a git bundle of the Mac's clone, when not pushed)
# Undo: bash uninstall.sh
set -u; S=$(cd "$(dirname "$0")" && pwd) O=$HOME/opt/job-runner NAS=BabisNAS
# This machine's name: skill "machine-name" (copy it identically)
m=${JR_MACHINE_NAME:-$(if [ "$(uname)" = Darwin ]; then scutil --get HostName; else cat /etc/hostname; fi 2>/dev/null)} || :
m=${m%%.*}; [[ $m =~ ^[A-Za-z0-9-]+$ ]] || { echo "no machine name: macOS sudo scutil --set HostName <name>; Linux sudo hostnamectl set-hostname <name>" >&2; exit 1; }
echo "== job-runner $(git -C "$S" rev-parse --short HEAD) on $m"
mkdir -p "$O/units" "$O/canaries/data"
git -C "$S" archive -o "$O/.install.tar" HEAD lib.sh ops.sh put-conf.sh gate.sh deploy/keys deploy/nas_known_hosts dashboard canaries skills boot-kick backup || exit 1
x() { tar -x -C "$O" -f "$O/.install.tar" "$@"; }

# ---------- The library ----------
x lib.sh ops.sh put-conf.sh && echo "lib.sh $(wc -l < "$O/lib.sh" | tr -d ' ') lines in $O"
[ "$m" = $NAS ] || { x deploy/nas_known_hosts && mv -f "$O/deploy/nas_known_hosts" "$O/nas_known_hosts" && rm -rf "$O/deploy"; }

# ---------- The NAS: the gate and the dashboard ----------
if [ "$m" = $NAS ]; then
  x gate.sh deploy/keys && chmod +x "$O/gate.sh"
  touch ~/.ssh/authorized_keys && cp -p ~/.ssh/authorized_keys ~/.ssh/authorized_keys.bak-job-runner
  for k in "$O"/deploy/keys/*.pub; do c=$(awk '{print $3}' "$k")   # one line per key, replaced if there
    grep -v " $c\$" ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.new
    echo "command=\"$O/gate.sh\",restrict $(cat "$k")" >> ~/.ssh/authorized_keys.new
    chmod 600 ~/.ssh/authorized_keys.new && mv ~/.ssh/authorized_keys.new ~/.ssh/authorized_keys; done
  rm -rf "$O/deploy"; echo "gate: $(grep -c "job-runner/gate.sh" ~/.ssh/authorized_keys) gated keys"
  U=com.jeanlescut.job-runner.dashboard.service
  rm -rf "$O/dashboard" && x dashboard && mkdir -p ~/.config/systemd/user
  printf "[Unit]\nDescription=job-runner dashboard\n[Service]\nExecStart=%%h/.local/bin/python3 %s/dashboard/dashboard.py 8097\nRestart=always\n[Install]\nWantedBy=default.target\n" "$O" > "$O/units/$U"
  ln -sfn "$O/units/$U" ~/.config/systemd/user/$U
  systemctl --user daemon-reload && systemctl --user enable $U 2>&1 | grep -v Created; systemctl --user restart $U
  sleep 1; echo "dashboard $(systemctl --user is-active $U), $(ls "$O/dashboard/conf" | wc -l | tr -d ' ') settings files in job-runner, $(ls "$O/conf" 2>/dev/null | wc -l | tr -d ' ') from the projects"
  tailscale serve status 2>/dev/null | grep -q ":8097" || tailscale serve --bg --http=8097 http://127.0.0.1:8097 > /dev/null 2>&1 ||
    echo "tailscale serve on 8097 failed: once, sudo tailscale set --operator=$USER, then install.sh again"
fi

# ---------- The canaries ----------
C=com.jeanlescut.job-runner.canaries
rm -f "$O/canaries/shared-vm.sh"   # renamed shared-nas (V3, 2026-11): run.sh starts every canaries/*.sh
x canaries
if [ "$(uname)" = Darwin ]; then
  printf "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\"><dict>\n  <key>Label</key><string>%s</string>\n  <key>ProgramArguments</key><array><string>/bin/bash</string><string>%s/canaries/run.sh</string></array>\n  <key>StartInterval</key><integer>600</integer><key>RunAtLoad</key><true/><key>AbandonProcessGroup</key><true/>\n</dict></plist>\n" $C "$O" > "$O/units/$C.plist"
  ln -sfn "$O/units/$C.plist" ~/Library/LaunchAgents/$C.plist
  launchctl bootout gui/$(id -u)/$C 2> /dev/null; sleep 1; launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/$C.plist && echo "LaunchAgent $C loaded"
else
  mkdir -p ~/.config/systemd/user
  printf "[Unit]\nDescription=job-runner canaries\n[Service]\nType=oneshot\nExecStart=/bin/bash %s/canaries/run.sh\nKillMode=process\n" "$O" > "$O/units/$C.service"
  printf "[Unit]\nDescription=job-runner canaries, every 10 min\n[Timer]\nOnActiveSec=1min\nOnUnitActiveSec=10min\nAccuracySec=1s\n[Install]\nWantedBy=timers.target\n" > "$O/units/$C.timer"
  ln -sfn "$O/units/$C.service" ~/.config/systemd/user/$C.service; ln -sfn "$O/units/$C.timer" ~/.config/systemd/user/$C.timer
  systemctl --user daemon-reload && systemctl --user enable --now $C.timer 2>&1 | grep -v Created; echo "timer $C $(systemctl --user is-active $C.timer)"
fi
echo "$(ls "$O"/canaries/*.sh | grep -vc run.sh) canaries"

# ---------- The NAS: the boot kick (UGOS attaches /home after systemd --user has started: DESIGN §13) ----------
if [ "$m" = $NAS ]; then
  rm -rf "$O/boot-kick" && x boot-kick && mkdir -p ~/.config/job-runner && chmod 700 ~/.config/job-runner
  printf "JR_UID=%s\nJR_GID=%s\nJR_HOME=%s\nJR_HOMES=%s\n" "$(id -u)" "$(id -g)" "$HOME" "$(dirname "$HOME")" > "$O/boot-kick/.env"
  docker compose -f "$O/boot-kick/compose.yaml" up -d --build > "$O/boot-kick/.install.log" 2>&1 || { echo "boot kick FAILED:"; tail -5 "$O/boot-kick/.install.log"; }
  echo "boot kick: $(docker inspect -f '{{.State.Status}}, restart {{.HostConfig.RestartPolicy.Name}}' job-runner-boot-kick)"
  H=com.jeanlescut.job-runner.home-mode.service   # the home back to 700 at each boot (the kick starts default.target)
  printf "[Unit]\nDescription=job-runner: the home back to 700 (UGOS sets it to 777 at boot)\n[Service]\nType=oneshot\nExecStart=/bin/bash %s/boot-kick/home-mode.sh\n[Install]\nWantedBy=default.target\n" "$O" > "$O/units/$H"
  ln -sfn "$O/units/$H" ~/.config/systemd/user/$H
  systemctl --user daemon-reload && systemctl --user enable $H 2>&1 | grep -v Created; systemctl --user start $H
  echo "unit $H: $(systemctl --user is-enabled $H), $(journalctl --user -u $H -n 3 -o cat --no-pager 2>/dev/null | grep '^home ' | tail -1)"
  [ -f ~/.config/job-runner/healthchecks_babisnas.url ] || echo "healthchecks.io: no ping URL yet (~/.config/job-runner/healthchecks_babisnas.url)"
  J=com.jeanlescut.job-runner.backup   # the weekly backup of /volume1/private to the portable disk (backup/backup.sh)
  x backup && mv -f "$O/backup/backup.sh" "$O/backup/backup.conf" "$O/" && rmdir "$O/backup"
  printf "[Unit]\nDescription=job-runner.backup: /volume1/private to the portable disk (restic)\n[Service]\nType=oneshot\nExecStart=/bin/bash %s/backup.sh\nTimeoutStartSec=infinity\nNice=10\nIOSchedulingClass=best-effort\nIOSchedulingPriority=7\n" "$O" > "$O/units/$J.service"
  printf "[Unit]\nDescription=job-runner.backup, weekly\n[Timer]\nOnCalendar=Sun *-*-* 02:00:00 UTC\nPersistent=true\n[Install]\nWantedBy=timers.target\n" > "$O/units/$J.timer"
  ln -sfn "$O/units/$J.service" ~/.config/systemd/user/$J.service; ln -sfn "$O/units/$J.timer" ~/.config/systemd/user/$J.timer
  systemctl --user daemon-reload && systemctl --user enable --now $J.timer 2>&1 | grep -v Created
  echo "timer $J $(systemctl --user is-active $J.timer), next $(systemctl --user show $J.timer -p NextElapseUSecRealtime --value)"
  bash "$O/put-conf.sh" job-runner.backup "$O/backup.conf"
  [ -f ~/.config/job-runner/healthchecks_babisnas-backup.url ] || echo "healthchecks.io: no ping URL yet (~/.config/job-runner/healthchecks_babisnas-backup.url)"
fi

# ---------- The skills: read-only copies, linked where Claude Code and Codex look (skill "shell-scripting") ----------
OPT_SKILLS=$O/skills; rm -rf "$O/.skills" && mkdir "$O/.skills" && tar -x -C "$O/.skills" -f "$O/.install.tar" skills
mkdir -p "$OPT_SKILLS"
for dst in "$OPT_SKILLS"/*/; do      # a skill gone from the repo: its link and copy go too
  [ -d "$dst" ] || continue
  dst=${dst%/}; name=$(basename "$dst")
  [ -d "$O/.skills/skills/$name" ] && continue
  for link in "$HOME/.claude/skills/$name" "$HOME/.agents/skills/$name"; do
    [ -L "$link" ] && [ "$(readlink "$link")" = "$dst" ] && rm "$link"
  done
  chmod -R u+w "$dst" && rm -r "$dst" && echo "removed old skill $name"
done
for src in "$O"/.skills/skills/*/; do
  [ -d "$src" ] || continue
  src=${src%/}; name=$(basename "$src"); dst=$OPT_SKILLS/$name
  [ -d "$dst" ] && chmod -R u+w "$dst" && rm -r "$dst"
  cp -R "$src" "$dst" && chmod -R a-w "$dst"
  for home in "$HOME/.claude/skills" "$HOME/.agents/skills"; do
    link=$home/$name
    if [ -d "$link" ] && [ ! -L "$link" ]; then
      if ! diff -rq -x '*.bak' "$link" "$src" > /dev/null 2>&1; then
        echo "WARN: $link is a real folder that differs from $src - kept, not linked"; continue
      fi
      rm -r "$link"
    fi
    mkdir -p "$home"; ln -sfn "$dst" "$link"; echo "skill $name: $link"
  done
done
rm -rf "$O/.skills" "$O/.install.tar"
