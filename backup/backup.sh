#!/bin/bash
# The job job-runner.backup, the NAS only (DESIGN §13; data-reorganisation tasks B3, E6): an encrypted copy of the encrypted
# folder /volume1/private (one folder per person; ~/data/private links to it) into the restic store on the portable disk, once a
# week. Deployed by install.sh to ~/opt/job-runner/backup.sh; its trigger com.jeanlescut.job-runner.backup (a systemd timer,
# Sundays 02:00 UTC, Persistent) runs it. Run by hand: bash ~/opt/job-runner/backup.sh (a check like any other).
# Requirements:
#   - the store: the /mnt/@usb/*/restic holding a config (the portable disk, whatever its device name). Two or more found:
#     FAILURE, unless one is pinned: its restic id (restic cat config) in ~/.config/job-runner/backup_store.id, then only
#     that store is used (a pinned id found nowhere: FAILURE). Its key: ~/.config/restic/portable.pass, mode 600, never
#     printed. No store, no key, a key readable by group or others: FAILURE with the reason, and a /fail ping
#   - the folder locked in UGOS (no /volume1/private/.unlocked, the sign made once inside it at E4): SKIP "locked", before
#     anything else; nothing read or written, no ping (healthchecks.io emails after the grace); unlocked, the next run works
#   - restic backup /volume1/private (since 2026-11-18, task E6; /volume3/data before, snapshots tagged volume3-data):
#     --host BabisNAS --tag private --one-file-system; without UGOS's #recycle and @eaDir, the sign .unlocked (restored
#     into a plain folder, it would say "unlocked" there) and the restore tests' folders restore_test_* (copies of files
#     already in the store; data-reorganisation's work/tools/nas_restic_restore_test.sh). The first snapshot of this new path has no parent
#     (restic picks a parent by host and path), so it reads every file once, but stores almost nothing new: the content
#     is the same as volume3's, deduplicated chunk by chunk; the runs after it read only what changed
#   - no retention (no forget, no prune): every snapshot kept. The disk's free space below 100 GB or 10 %: FAILURE "LOW
#     SPACE" (the backup itself done); the retention to apply then is in DESIGN §13
#   - restic check, reading data group (ISO week % 52) + 1 of 52: weeks 1-51 read groups 2-52, week 52 group 1, week 53
#     group 2 again: every group about once a year
#   - the hidden folders (their names in ~/.config/job-runner/backup_hidden.txt, one per line; no file: every folder) are
#     data only, never shown: an output line naming a path under one is replaced by one line saying so; a file name
#     in restic check's errors (file "…") is hidden too
#   - healthchecks.io check "babisnas-backup": its ping URL in ~/.config/job-runner/healthchecks_babisnas-backup.url (mode
#     600, made by the user, never printed; passed to curl on stdin): /start, then success or /fail with the summary line.
#     No file: one line "no ping" in the journal, the job works the same
#   - timeout 12 h (a big week: the trading-bot's 151 GB arriving), restic's output kept in the log then too; a lock here,
#     no overlap with a check by hand
#   - summary: "snapshot <id>: N new, N changed of N files, N MiB added, N s; check k/52 ok; disk N GB free (N %)"
B=$HOME/.local/bin/restic HC=$HOME/.config/job-runner/healthchecks_babisnas-backup.url PIN=$HOME/.config/job-runner/backup_store.id
export RESTIC_PASSWORD_FILE=$HOME/.config/restic/portable.pass
HIDDEN=$HOME/.config/job-runner/backup_hidden.txt
hide() {   # the hidden folders' paths (no file: every folder's) and restic check's file names, out of every output line
  local d='[^/]+'; [ -s "$HIDDEN" ] && d=$(grep -v '^$' "$HIDDEN" | paste -sd'|')
  sed -u -E -e "s#.*/volume1/private/($d)/.*#(a line naming a path under a hidden folder of /volume1/private: hidden)#" -e 's/file "[^"]*"/file "(hidden)"/g'
}

if [ "${1:-}" = work ]; then   # the work, run by jr_execute below: bash backup.sh work STORE
  set -o pipefail; export RESTIC_REPOSITORY=$2
  $B unlock 2>&1 | hide || exit                    # removes stale locks only (a check killed before it ended)
  out=$($B backup /volume1/private --exclude '#recycle' --exclude '@eaDir' --exclude '/volume1/private/.unlocked' \
        --exclude '/volume1/private/restore_test_*' --tag private --host BabisNAS --one-file-system --json 2>&1 |
        grep --line-buffered -v '"message_type":"status"' | hide | tee -a /dev/stderr); rc=$?   # in the log as it comes
  s=$(echo "$out" | grep '"message_type":"summary"' | tail -n 1 | jq -r '"snapshot \(.snapshot_id[0:8]): \(.files_new) new,'\
' \(.files_changed) changed of \(.total_files_processed) files, \(.data_added_packed/1048576|floor) MiB added,'\
' \(.total_duration|floor) s"' 2>/dev/null)
  [ $rc = 3 ] && s="${s:-no summary}, some files unreadable (exit 3)"
  n=$((10#$(date -u +%V) % 52 + 1))
  $B check --read-data-subset=$n/52 2>&1 | hide; crc=$?
  read -r size avail <<< "$(df -Pk "$2" | awk 'END {print $2, $4}')"; gb=$((avail / 1048576)) pc=$((avail * 100 / size))
  low=; [ $gb -lt 100 ] || [ $pc -lt 10 ] && low="LOW SPACE (< 100 GB or < 10 %: the retention of DESIGN §13), "
  echo "$low${s:-backup FAILED (exit $rc)}; check $n/52 $([ $crc = 0 ] && echo ok || echo "FAILED (exit $crc)"); disk $gb GB free ($pc %)"
  [ $rc = 0 ] && [ $crc = 0 ] && [ -z "$low" ]; exit
fi

hc_ping() {   # hc_ping [/start|/fail] [BODY]: healthchecks.io, the URL never printed (curl reads it on stdin)
  [ -f "$HC" ] || { echo "healthchecks.io: no ping ($HC missing)"; return; }
  if printf 'url = "%s%s"\n' "$(cat "$HC")" "$1" | curl -fsS -m 10 --retry 2 -o /dev/null --data-raw "${2:-}" -K - 2>/dev/null
  then echo "healthchecks.io: pinged ${1:-success}"; else echo "healthchecks.io: ping ${1:-success} failed (curl exit $?)"; fi
}
fail() { jr_write_status FAILURE "$1"; [ "$JR_DRY_RUN" ] || hc_ping /fail "$1"; exit 1; }   # REASON: before the work

. ~/opt/job-runner/lib.sh                 # defaults: syncs on LOCAL (JR_SYNC_ENV), writes LOCAL + VM (JR_REPORT_ENVS)
[ -f /volume1/private/.unlocked ] || jr_skip "~/data/private (/volume1/private) is locked: unlock it in UGOS"
jr_claim 720                              # a lock here: a check by hand and the timer never overlap
[ -f "$RESTIC_PASSWORD_FILE" ] || fail "no key file $RESTIC_PASSWORD_FILE"
[ "$(ls -ld "$RESTIC_PASSWORD_FILE" | cut -c5-10)" = ------ ] || fail "key file $RESTIC_PASSWORD_FILE readable by group or others: chmod 600 it"
S=(); for d in /mnt/@usb/*/restic; do [ -f "$d/config" ] && S+=("$d"); done
[ ${#S[@]} = 0 ] && fail "no restic store in /mnt/@usb/*/restic: the portable disk is not plugged in, or the store is missing"
if [ -s "$PIN" ]; then
  R=; for d in "${S[@]}"; do [ "$(RESTIC_REPOSITORY=$d $B cat config 2>/dev/null | jq -r .id)" = "$(cat "$PIN")" ] && R=$d; done
  [ "$R" ] || fail "the pinned store ($PIN) is in none of the ${#S[@]} stores found: ${S[*]}"
elif [ ${#S[@]} = 1 ]; then R=${S[0]}
else fail "${#S[@]} stores found (${S[*]}): pin one, its id (restic cat config) in $PIN"; fi
[ "$JR_DRY_RUN" ] || hc_ping /start
jr_execute 720 /bin/bash "$PWD/${0##*/}" work "$R"   # RUNNING, then SUCCESS / FAILURE "exit N: last line" / timeout
[ "$JR_DRY_RUN" ] || if [ "$JR_STATUS" = SUCCESS ]; then hc_ping "" "$JR_TEXT"; else hc_ping /fail "$JR_TEXT"; fi
