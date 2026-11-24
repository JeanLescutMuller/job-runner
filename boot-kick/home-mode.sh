#!/bin/bash
# The home's modes (DESIGN §13), the NAS only. At each boot UGOS sets the whole home tree back to 777 and marks it with its own
# ACL ("+" in ls), under which new files come out 777 whatever the umask (restart test of 2026-11-18: ctime 10:47:15 on every
# entry; N1 had removed group/other write the night before). This puts it back, with one journal line:
#   the home 700; every entry of the user with group or other write (UGOS's 777): go-rwx (chmod also drops the ACL mark);
#   the user's unit files not executable (systemd warns on an executable unit; 777 gave them x).
# Files made by the umask (0022: 644, 755) are left as they are: the home is 700.
# Run by com.jeanlescut.job-runner.home-mode (a oneshot of default.target, so started by the boot kick right after the boot)
# and by canaries/run.sh every 10 min (a later reset). Not in the kick's container: it sees the home read-only, no capability.
before=$(stat -c %a "$HOME") || exit 1
[ "$before" = 700 ] || chmod 700 "$HOME" || { echo "home $HOME: $before, chmod 700 FAILED"; exit 1; }
# Never into another file system: -xdev, and every mount inside the home pruned by name (the Drive's rclone mount
# ~/opt/my-setup/gdrive/mnt/gdrive: a walk there would read the whole Drive through Google's API, and chmod fails there).
prune=(); while read -r _ mnt _; do mnt=$(printf '%b' "$mnt"); case $mnt in "$HOME"/*) prune+=( -path "$mnt" -prune -o );; esac
  done < /proc/self/mounts
writable() { find "$HOME" -xdev "${prune[@]}" -user "$(id -u)" ! -type l -perm /022 "$@"; }
n=$(writable -printf . | wc -c); [ "$n" = 0 ] || writable -exec chmod go-rwx {} +
u=0; for f in "$HOME"/.config/systemd/user/*.service "$HOME"/.config/systemd/user/*.timer; do
  f=$(readlink -f "$f") && [ -O "$f" ] && [ -x "$f" ] && chmod a-x "$f" && u=$((u + 1)); done
if [ "$before" = 700 ] && [ "$n" = 0 ] && [ "$u" = 0 ]; then echo "home $HOME: 700, nothing group/world-writable"
else echo "home $HOME: was $before, now $(stat -c %a "$HOME"); $n entries group/world-writable -> go-rwx; $u unit files -> not executable (repaired)"; fi
