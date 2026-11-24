#!/bin/bash
# The home's modes (DESIGN §13), the NAS only. At each boot UGOS sets the whole home tree back to 777 and marks it with its own
# ACL ("+" in ls), under which new files come out 777 whatever the umask (restart test of 2026-11-18: ctime 10:47:15 on every
# entry; N1 had removed group/other write the night before; UGOS 1.20 and 1.21, ~249,000 entries). This puts it back, with one
# journal line:
#   the home 700; every entry of the user with group or other write (UGOS's 777): go-rwx (chmod also drops the ACL mark);
#   among those, a regular file keeps its exec bit only if it starts with "#!" or is an ELF binary (venvs' bin/, ~/.local/bin,
#   uv's Pythons), then in every repo ~/dev/*/* git's recorded mode wins (100644: no x; 100755: u+x), so git sees no
#   "mode change" (until 2026-11-24 my-setup's fix_nas_repo_modes.py did this by hand after each boot: 4,588 files, 19 repos);
#   the user's unit files not executable (systemd warns on an executable unit; 777 gave them x).
# Files made by the umask (0022: 644, 755) are left as they are: the home is 700. Nothing group/world-writable (every 10-min run
# but the first after a reset): one find, nothing changed. Caveat of the repos' step: an exec bit set by hand on a tracked file
# and not committed yet is removed (git add it first).
# Usage: home-mode.sh [--repos]   --repos: the repos' step even when nothing was group/world-writable (the skill nas-restart).
# Run by com.jeanlescut.job-runner.home-mode (a oneshot of default.target, so started by the boot kick right after the boot)
# and by canaries/run.sh every 10 min (a later reset). Not in the kick's container: it sees the home read-only, no capability.
export LC_ALL=C   # read -n counts bytes
before=$(stat -c %a "$HOME") || exit 1
[ "$before" = 700 ] || chmod 700 "$HOME" || { echo "home $HOME: $before, chmod 700 FAILED"; exit 1; }
# Never into another file system: -xdev, and every mount inside the home pruned by name (the Drive's rclone mount
# ~/opt/my-setup/gdrive/mnt/gdrive: a walk there would read the whole Drive through Google's API, and chmod fails there).
prune=(); while read -r _ mnt _; do mnt=$(printf '%b' "$mnt"); case $mnt in "$HOME"/*) prune+=( -path "$mnt" -prune -o );; esac
  done < /proc/self/mounts
writable() { find "$HOME" -xdev "${prune[@]}" -user "$(id -u)" ! -type l -perm /022 "$@"; }
n=$(writable -printf . | wc -c) x=0 g=0
if [ "$n" != 0 ]; then   # first the exec bits (the files still carry UGOS's group write that finds them), then go-rwx
  x=$(writable -type f -perm -u=x -print0 | while IFS= read -r -d '' f; do h=; [ -r "$f" ] || continue
    IFS= read -r -n 4 -d '' h 2> /dev/null < "$f"; case $h in '#!'* | $'\177ELF') ;; *) printf '%s\0' "$f" ;; esac
  done | xargs -0 -r chmod -c a-x | wc -l)
  writable -exec chmod go-rwx {} +
fi
if [ "$n" != 0 ] || [ "${1:-}" = --repos ]; then   # git's recorded mode wins over the rule above
  g=$(for d in "$HOME"/dev/*/*/.git; do r=${d%/.git}; [ -L "$r" ] && continue   # about-me: a link into the Drive
    git -C "$r" diff --raw -z 2> /dev/null | while IFS= read -r -d '' m && IFS= read -r -d '' p; do case $m in
      ':100644 100755 '*) chmod -c a-x "$r/$p" ;; ':100755 100644 '*) chmod -c u+x "$r/$p" ;; esac; done; done | wc -l)
fi
u=0; for f in "$HOME"/.config/systemd/user/*.service "$HOME"/.config/systemd/user/*.timer; do
  f=$(readlink -f "$f") && [ -O "$f" ] && [ -x "$f" ] && chmod a-x "$f" && u=$((u + 1)); done
if [ "$before" = 700 ] && [ "$n" = 0 ] && [ "$g" = 0 ] && [ "$u" = 0 ]; then echo "home $HOME: 700, nothing group/world-writable"
else echo "home $HOME: was $before, now $(stat -c %a "$HOME"); $n entries group/world-writable -> go-rwx, $x of their files -> not executable (no #! or ELF); $g repo files -> git's mode; $u unit files -> not executable (repaired)"; fi
