#!/bin/sh
# The boot kick (DESIGN §13), PID 1 of the container job-runner-boot-kick, on the NAS only. At boot UGOS attaches /home after
# systemd --user has started, so the user's job manager finds no unit and starts no job. Docker starts this container once
# the disks are attached; it waits for the units folder and the user's bus, then does what
#   systemctl --user daemon-reload && systemctl --user start default.target timers.target
# does, through the bus, and sleeps until Docker stops it. Not ready after KICK_WAIT_S: exit 1, Docker starts it again.
# A Docker restart kicks again: harmless (already active units stay as they are).
set -u
log() { echo "$(date -u +%FT%TZ) $*"; }
bus=${DBUS_SESSION_BUS_ADDRESS#unix:path=}
manager() { dbus-send --session --print-reply --reply-timeout=120000 --dest=org.freedesktop.systemd1 /org/freedesktop/systemd1 \
  "org.freedesktop.systemd1.Manager.$@" 2>&1; }

log "start: waiting up to ${KICK_WAIT_S}s for $KICK_UNITS_DIR and $bus"
t=0
until [ -d "$KICK_UNITS_DIR" ] && [ -S "$bus" ]; do
  if [ "$t" -ge "$KICK_WAIT_S" ]; then
    log "FAILED: after ${t}s, units folder $([ -d "$KICK_UNITS_DIR" ] && echo there || echo missing), bus $([ -S "$bus" ] && echo there || echo missing); exit 1, Docker starts me again"
    exit 1
  fi
  sleep 5; t=$((t + 5))
done
log "ready after ${t}s"
out=$(manager Reload) || { log "FAILED: daemon-reload: $out"; exit 1; }
log "daemon-reload done"
for u in default.target timers.target; do
  out=$(manager StartUnit "string:$u" string:replace) || { log "FAILED: start $u: $out"; exit 1; }
  log "start $u: job $(echo "$out" | sed -n 's/.*object path "\(.*\)"/\1/p')"
done
log "done; sleeping until Docker stops me"
trap 'exit 0' TERM INT
while :; do sleep 86400 & wait $!; done
