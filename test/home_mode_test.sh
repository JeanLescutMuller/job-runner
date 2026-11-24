#!/bin/bash
# Tests ../boot-kick/home-mode.sh after a UGOS-like reset (chmod -R 777) of a fake HOME, without a reboot. Linux (GNU find,
# stat -c): the NAS. Usage: bash test/home_mode_test.sh
D=$(cd "$(dirname "$0")/.." && pwd); P=0 F=0; H=$(mktemp -d) O=$(mktemp -d)
ok() { if [ "$2" = "$3" ]; then P=$((P + 1)); echo "PASS $1"; else F=$((F + 1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
hm() { HOME=$H bash "$D/boot-kick/home-mode.sh" "$@"; }
modes() { (cd "$H" && for f in "$@"; do echo "$(stat -c %a "$f") $f"; done); }
gitc() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}" > /dev/null; }
r=$H/dev/infra/repo; mkdir -p "$r/bin" "$H/.local/bin" "$H/.local/share/tool" "$H/opt/proj/.venv/bin" "$H/.config/systemd/user"
printf 'text\n' > "$r/a.txt"; printf '#!/bin/bash\necho\n' > "$r/bin/run.sh"; printf 'echo no shebang\n' > "$r/noshebang.sh"
printf '#!/usr/bin/env python3\n' > "$r/lib.py"; chmod 755 "$r/bin/run.sh" "$r/noshebang.sh"; : > "$r/empty"
gitc "$r" init -q; gitc "$r" add -A; gitc "$r" commit -qm t
printf '#!/bin/sh\n' > "$r/untracked.sh"; chmod 755 "$r/untracked.sh"; printf 'notes\n' > "$r/notes.txt"
cp /bin/true "$H/.local/bin/elf"; printf '#!/bin/sh\n' > "$H/.local/share/tool/tool.sh"; ln -s ../share/tool/tool.sh "$H/.local/bin/tool"
cp /bin/true "$H/opt/proj/.venv/bin/python"; printf '#!/home/x/.venv/bin/python\n' > "$H/opt/proj/.venv/bin/pip"
printf '[Unit]\n' > "$H/.config/systemd/user/x.service"; printf '\177ELFbut-short' > "$H/opt/proj/elf-magic"
mkdir -p "$O/linked/.git"; ln -s "$O/linked" "$H/dev/infra/linked"   # like about-me: a link into the Drive, never touched
printf 'x\n' > "$O/linked/f"; chmod 777 "$O/linked/f"
chmod -R 777 "$H"   # UGOS's reset
ok "1 a reset: repaired" "$(hm | sed -E "s|$H|H|; s/[0-9]+ (entries|of their)/N \\1/g")" "home H: was 777, now 700; N entries group/world-writable -> go-rwx, N of their files -> not executable (no #! or ELF); 2 repo files -> git's mode; 0 unit files -> not executable (repaired)"
ok "2 every mode" "$(modes . dev dev/infra/repo dev/infra/repo/bin dev/infra/repo/{a.txt,bin/run.sh,noshebang.sh,lib.py,empty,untracked.sh,notes.txt} \
  .local/bin/elf .local/share/tool/tool.sh opt/proj/.venv/bin/{python,pip} opt/proj/elf-magic .config/systemd/user/x.service)" "700 .
700 dev
700 dev/infra/repo
700 dev/infra/repo/bin
600 dev/infra/repo/a.txt
700 dev/infra/repo/bin/run.sh
700 dev/infra/repo/noshebang.sh
600 dev/infra/repo/lib.py
600 dev/infra/repo/empty
700 dev/infra/repo/untracked.sh
600 dev/infra/repo/notes.txt
700 .local/bin/elf
700 .local/share/tool/tool.sh
700 opt/proj/.venv/bin/python
700 opt/proj/.venv/bin/pip
700 opt/proj/elf-magic
600 .config/systemd/user/x.service"
ok "3 git sees no mode change" "$(git -C "$r" diff --summary)" ""
ok "4 a link to a repo elsewhere: not followed" "$(stat -c %a "$O/linked/f")" "777"
ok "5 nothing writable: nothing done" "$(hm | sed "s|$H|H|")" "home H: 700, nothing group/world-writable"
chmod u+x "$r/a.txt"; chmod u-x "$r/bin/run.sh"
ok "6 --repos: git's mode back without a reset" "$(hm --repos | sed "s|$H|H|"; modes dev/infra/repo/a.txt dev/infra/repo/bin/run.sh)" "home H: was 700, now 700; 0 entries group/world-writable -> go-rwx, 0 of their files -> not executable (no #! or ELF); 2 repo files -> git's mode; 0 unit files -> not executable (repaired)
600 dev/infra/repo/a.txt
700 dev/infra/repo/bin/run.sh"
rm -rf "$H" "$O"
echo "== $P PASS, $F FAIL"; [ "$F" = 0 ]
