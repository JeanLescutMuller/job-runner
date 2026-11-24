#!/bin/bash
# Tests ../boot-kick/home-mode.sh (the security part: no group/other access, unit files not executable) after a UGOS-like reset
# (chmod -R 777) of a fake HOME, without a reboot. The exec bits are the skill nas-restart's (my-setup), tested there.
# Linux (GNU find, stat -c): the NAS. Usage: bash test/home_mode_test.sh
D=$(cd "$(dirname "$0")/.." && pwd); P=0 F=0; H=$(mktemp -d) O=$(mktemp -d)
ok() { if [ "$2" = "$3" ]; then P=$((P + 1)); echo "PASS $1"; else F=$((F + 1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
hm() { HOME=$H bash "$D/boot-kick/home-mode.sh" "$@"; }
modes() { (cd "$H" && for f in "$@"; do echo "$(stat -c %a "$f") $f"; done); }
mkdir -p "$H/dev/infra/repo/bin" "$H/.config/systemd/user"
printf 'text\n' > "$H/dev/infra/repo/a.txt"; printf '#!/bin/sh\n' > "$H/dev/infra/repo/bin/run.sh"
printf '[Unit]\n' > "$H/.config/systemd/user/x.service"; ln -s repo/a.txt "$H/dev/infra/link"
mkdir -p "$O/linked"; ln -s "$O/linked" "$H/dev/infra/linked"   # like about-me: a link into the Drive, never touched
printf 'x\n' > "$O/linked/f"; chmod 777 "$O/linked/f"
chmod -R 777 "$H"   # UGOS's reset
ok "1 a reset: repaired" "$(hm | sed -E "s|$H|H|; s/[0-9]+ entries/N entries/")" "home H: was 777, now 700; N entries group/world-writable -> go-rwx; 1 unit files -> not executable (repaired)"
ok "2 every mode: no group or other access" "$(modes . dev dev/infra/repo dev/infra/repo/bin dev/infra/repo/a.txt dev/infra/repo/bin/run.sh .config/systemd/user/x.service)" "700 .
700 dev
700 dev/infra/repo
700 dev/infra/repo/bin
700 dev/infra/repo/a.txt
700 dev/infra/repo/bin/run.sh
600 .config/systemd/user/x.service"
ok "3 a link to a folder elsewhere: not followed" "$(stat -c %a "$O/linked/f")" "777"
ok "4 nothing writable: nothing done" "$(hm | sed "s|$H|H|")" "home H: 700, nothing group/world-writable"
chmod 644 "$H/dev/infra/repo/a.txt"; chmod 755 "$H/dev/infra/repo/bin/run.sh"
ok "5 the umask's modes (644, 755): left alone" "$(hm > /dev/null; modes dev/infra/repo/a.txt dev/infra/repo/bin/run.sh)" "644 dev/infra/repo/a.txt
755 dev/infra/repo/bin/run.sh"
rm -rf "$H" "$O"
echo "== $P PASS, $F FAIL"; [ "$F" = 0 ]
