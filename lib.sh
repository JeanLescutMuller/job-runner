# job-runner library (DESIGN.md §2, §4–§7, §12). Bash 3.2, needs git and ssh. An entrypoint sets its optional JR_* settings,
# then: . ~/opt/job-runner/lib.sh
# Test hooks, never set in production: NOW (epoch), JR_NAS_DIR (the NAS env as a local folder; missing = unreachable),
# JR_GITHUB_URL (a local bare repo), JR_TEST_LID=open|closed, JR_TEST_POWER=ac|battery, JR_TEST_ONLINE=yes|no,
# JR_TEST_MINUTE_S (seconds in a timeout's minute).

export PATH=$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH LANG=${LANG:-en_US.UTF-8}   # launchd, systemd: a bare PATH

# ---------- Settings, each may be set before loading the library (§4) ----------
# The machine (GCP: "GCP"); the one env pulled (jr_pull) and claimed in (§7): LOCAL, NAS or GITHUB (VM: the NAS's name until
# 2026-11, still read); where every status is written (JR_SYNC_ENV is always added; GCP: never the NAS, it cannot reach it:
# it reports through GITHUB only); logs and statuses kept; this machine's env (LOCAL); the NAS env (~/opt/job-runner there,
# over SSH; on the NAS itself, its own disk): its machine name, its SSH address (unset: the Mac uses its alias babisnas,
# other machines its Tailscale name; _jr_nas_addr), its host key, job-runner's own key there (gated: gate.sh); the env
# GITHUB. Also JR_DRY_RUN=1: decisions for real, jr_execute writes SKIP "dry run" instead of working.
# This machine's name: skill "machine-name" (copy it identically); exported, the work receives it
JR_MACHINE_NAME=${JR_MACHINE_NAME:-$(if [ "$(uname)" = Darwin ]; then scutil --get HostName; else cat /etc/hostname; fi 2>/dev/null)} || :
JR_MACHINE_NAME=${JR_MACHINE_NAME%%.*}; [[ $JR_MACHINE_NAME =~ ^[A-Za-z0-9-]+$ ]] || { echo "no machine name: macOS sudo scutil --set HostName <name>; Linux sudo hostnamectl set-hostname <name>" >&2; exit 1; }
export JR_MACHINE_NAME
: ${JR_SYNC_ENV:=LOCAL} "${JR_REPORT_ENVS:=LOCAL NAS}" ${JR_KEEP_N_LOGS:=50} ${JR_KEEP_N_LOGS_FAILURE:=10} ${JR_KEEP_N_LOGS_SUCCESS:=5} \
  ${JR_KEEP_N_STATUSES:=5000} ${JR_ROOT:=$HOME/opt/job-runner} ${JR_NAS_HOST:=BabisNAS} \
  "${JR_NAS_SSH:=}" "${JR_KNOWN_HOSTS:=$JR_ROOT/nas_known_hosts}" ${JR_SSH_KEY:=$HOME/.ssh/job-runner} \
  ${JR_GITHUB_URL:=https://github.com/JeanLescutMuller/job-runner-sync.git} ${NOW:=$(date +%s)}

# ---------- Laptop in a bag: lid closed on battery (a Mac), nothing at all, not even a status (R12) ----------
case ${JR_TEST_LID:-$(ioreg -r -k AppleClamshellState -d 1 2>/dev/null)} in
  closed | *'"AppleClamshellState" = Yes'*)
    case ${JR_TEST_POWER:-$(pmset -g batt 2>/dev/null)} in
      ac | *"AC Power"*) ;;
      *) echo "job-runner: lid closed, on battery: nothing started" >&2; exit 0 ;;
    esac ;;
esac

# ---------- The job (~/opt/<repo>/entrypoint.sh → <repo>, ~/opt/<repo>/<job>.sh → <repo>.<job>), the check, the files ----------
_jr_ops=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ops.sh            # the operations on an env's folder, beside this file
cd "$(dirname "$0")" || exit 1                                          # the work runs from the job's own folder
JR_JOB=${PWD##*/}; [ "${0##*/}" = entrypoint.sh ] || JR_JOB=$JR_JOB.$(basename "$0" .sh)
# The job's name in Claude Code's telemetry (an OpenTelemetry resource attribute): agent-tracker counts each job's Claude
# usage under it (its doc/tables.md §5, the column `job`). Every program the work starts inherits it.
export OTEL_RESOURCE_ATTRIBUTES=${OTEL_RESOURCE_ATTRIBUTES:+$OTEL_RESOURCE_ATTRIBUTES,}job.name=$JR_JOB
DOW=$(((NOW/86400+3)%7+1)) HOUR=$((NOW%86400/3600)) MINUTE=$((NOW%3600/60))   # UTC; 1 = Monday (1970-01-01: a Thursday)
JR_CHECK=$NOW.$$                                                        # the check id; its pid tells whether it still runs
JR_STATUS= JR_TEXT= JR_CLAIMS= JR_PULLED= JR_WHY= JR_RC= JR_LAST_LINE= JR_T0=$SECONDS _jr_down=
JR_FILE=$JR_ROOT/status/$JR_JOB/$JR_MACHINE_NAME.tsv JR_LOG=$JR_ROOT/logs/$JR_JOB/$JR_MACHINE_NAME/$JR_CHECK.log
_jr_tmp=${JR_LOG%/*}/.tmp.$$ JR_GH=$JR_ROOT/sync/GITHUB/$JR_JOB        # JR_GH: this job's own clone of job-runner-sync
mkdir -p "${JR_LOG%/*}" "${JR_FILE%/*}"; touch "$JR_FILE"
_jr_hm() { printf %02d:%02d $(($1%86400/3600)) $(($1%3600/60)); }   # EPOCH → HH:MM UTC

_jr_envs() {   # "ENV…" → upper case, "_" and "," as spaces, each once, in order; an unknown env: a config error
  local e o=; for e in $(echo "$1" | tr '_,a-z' '  A-Z'); do
    [ $e = VM ] && e=NAS                                                  # its name until 2026-11 (data-reorganisation V3)
    [[ $e =~ ^(LOCAL|NAS|GITHUB)$ ]] || { echo "config error: unknown env $e" >&2; exit 2; }
    [[ $o = *$e* ]] || o+=" $e"; done; echo $o; }
JR_SYNC_ENV=$(_jr_envs "$JR_SYNC_ENV") || exit 2
[[ $JR_SYNC_ENV =~ ^[A-Z]+$ ]] || { echo "config error: one JR_SYNC_ENV" >&2; exit 2; }
_jr_report=$(_jr_envs "LOCAL $JR_REPORT_ENVS $JR_SYNC_ENV") || exit 2     # LOCAL first, always
[ "$JR_MACHINE_NAME" = GCP ] && [ $JR_SYNC_ENV != NAS ] && _jr_report=${_jr_report/ NAS}   # GCP: not on the tailnet
if [ -z "$JR_NAS_DIR" ] && [ "$JR_MACHINE_NAME" = "$JR_NAS_HOST" ]; then   # on the NAS itself: the env NAS is its own disk,
  JR_NAS_DIR=$JR_ROOT _jr_report=${_jr_report/NAS}                         # nothing to copy there
fi
JR_COPY=$JR_ROOT/sync/$JR_SYNC_ENV/status/$JR_JOB                       # the pulled copy of the sync env (GITHUB: the clone)
[ $JR_SYNC_ENV = GITHUB ] && JR_COPY=$JR_GH/status/$JR_JOB
_jr_read=$JR_COPY/*.tsv                                                 # what reads read: every machine's file, as pulled;
[ $JR_SYNC_ENV = LOCAL ] && _jr_read=$JR_FILE JR_PULLED=1                # LOCAL: this machine's own

# ---------- Envs: a shell script run in an env's folder ----------
_jr_nas_addr() {   # the NAS's SSH address for ssh, one word per line: JR_NAS_SSH (words); else the Mac: its alias babisnas
                   # of ~/.ssh/config (the home address first, then Tailscale: data-reorganisation N2) without that alias's
                   # keys (ssh -G); else the NAS's Tailscale name (MagicDNS)
  if [ -n "$JR_NAS_SSH" ]; then printf '%s\n' $JR_NAS_SSH
  elif [ "$(uname)" = Darwin ]; then
    ssh -G babisnas 2>/dev/null | awk '$1 ~ /^(hostname|port|user|proxycommand)$/ && $2 != "none" { k = $1; $1 = ""; print "-o"; print k "=" substr($0, 2) }'
    echo babisnas
  else printf '%s\n' -p 22 enrices@babisnas; fi
}
_jr_git() {   # git in this job's clone, the token given to git only (from the environment or its file), never printed
  JR_SYNC_TOKEN=${JR_SYNC_TOKEN:-$(sed -n 's/^JR_SYNC_TOKEN=//p' ~/.config/job-runner/job-runner-sync.env 2>/dev/null)} GIT_TERMINAL_PROMPT=0 \
    git -C "$JR_GH" -c credential.helper= \
    -c credential.helper='!f() { echo username=x-access-token; echo "password=$JR_SYNC_TOKEN"; }; f' \
    -c user.name=job-runner-$JR_MACHINE_NAME -c user.email=job-runner@localhost -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"
}
_jr_in() {   # _jr_in ENV IN OPERATION ARG…: an operation of ops.sh in ENV's folder, stdin from the file IN.
             #   LOCAL: here. NAS: over SSH with job-runner's own key, which the NAS's gate.sh lets run only ops.sh's
             #   operations (on the NAS itself, or with JR_NAS_DIR: a folder here).
             #   GITHUB: in this job's clone, fetched from main first, then committed (message "$_jr_m<job> <machine>")
             #   and pushed; another machine pushed first: fetch, run again (5 tries). A status file is first tried on the
             #   clone as the pull left it (no fetch).
             # Returns 255 when ENV is unreachable (remembered for the rest of the check), 1 when GITHUB rejected 5 pushes.
  _jr_d=$JR_ROOT
  [[ $_jr_down = *$1* ]] && return 255
  case $1 in
    NAS) _jr_d=$JR_NAS_DIR
        if [ -z "$_jr_d" ]; then
          # Not ~/.ssh/config (its keys are not gated); the shared connection's name is job-runner's own too. The host key
          # is job-runner's own file, known by an alias, not an address ("babisnas ssh-ed25519 …"): home or Tailscale, the same
          _jr_a=(); while IFS= read -r _jr_l; do _jr_a+=("$_jr_l"); done < <(_jr_nas_addr)
          ssh -F /dev/null -i "$JR_SSH_KEY" -o IdentitiesOnly=yes -o ConnectTimeout=5 -o BatchMode=yes -o LogLevel=ERROR \
            -o HostKeyAlias=babisnas -o UserKnownHostsFile="$JR_KNOWN_HOSTS" -o ControlMaster=auto -o ControlPath=~/.ssh/jr-gated-%C \
            -o ControlPersist=60 "${_jr_a[@]}" "${@:3}" <"$2"
          _jr_i=$?; [ $_jr_i != 255 ] && return $_jr_i
        fi ;;
    GITHUB) _jr_d=$JR_GH
        git init -q "$_jr_d"; _jr_git remote add origin "$JR_GITHUB_URL" 2>/dev/null
        for _jr_i in 1 2 3 4 5; do
          if [ $_jr_i != 1 ] || [ "$2" != "$JR_FILE" ] || [ ! -f $JR_GH/.git/FETCH_HEAD ]; then
            _jr_git fetch -q --depth 1 origin main >/dev/null 2>&1 && _jr_git reset -q --hard FETCH_HEAD && _jr_git clean -qfd || break
          fi
          _jr_sh "$@" || return
          _jr_git add -A; _jr_git diff --cached --quiet && return             # nothing changed: nothing to push
          _jr_git commit -qm "$_jr_m$JR_JOB $JR_MACHINE_NAME" && _jr_git push -q origin HEAD:main >/dev/null 2>&1 && return
          sleep $((_jr_i%3+1))
          [ $_jr_i = 5 ] && return 1
        done
        _jr_d= ;;                                                         # fetch failed: unreachable
  esac
  [ -d "$_jr_d" ] && { _jr_sh "$@"; return; }
  _jr_down="$_jr_down $1"; echo "job-runner: $1 unreachable" >&2; return 255
}
_jr_sh() { (cd "$_jr_d" && sh "$_jr_ops" "${@:3}" <"$2"); }   # ENV IN OPERATION ARG…: in $_jr_d

# ---------- Pull: one copy of the sync env, read as often as needed (§7) ----------
_jr_copy() {   # the sync env's status files of this job → $JR_COPY
  _jr_in $JR_SYNC_ENV /dev/null get-statuses $JR_JOB >"$_jr_tmp" &&
    rm -rf "$JR_COPY" && mkdir -p "$JR_COPY" && tar xf "$_jr_tmp" -C "${JR_COPY%/status/*}"
}
_jr_last() {   # FILE… → "ts machine status text": each check's last line, in the order the checks started
  awk -F'\t' '{ m = FILENAME; gsub(/.*\/|\.tsv$/, "", m)                 # the machine: the file name
                k = m FS $1; if (!(k in last)) order[++n] = k              # a check: (machine, check id)
                last[k] = $2 FS m FS $3 FS $4 }
              END { for (i = 1; i <= n; i++) print last[order[i]] }' "$@"
}
_jr_waits() {   # FILE… → "UNTIL MACHINE SCOPE reason": each machine's pending WAIT; a later check other than a SKIP ends one
  _jr_last "$@" | awk -F'\t' '
    $3 == "WAIT" { split($4, w, " "); until[$2] = $1 + w[1]              # text: "SECONDS [all] reason"
                   scope[$2] = w[2] == "all" ? "all" : "machine"
                   why[$2] = substr($4, length(w[1]) + 2); if (scope[$2] == "all") why[$2] = substr(why[$2], 5); next }
    $3 != "SKIP" { until[$2] = 0 }
    END { for (m in until) if (until[m]) print until[m], m, scope[m], why[m] }'
}
jr_pull() {   # one copy of the sync env here; fails if unreachable ($JR_WHY); honors another machine's pending "WAIT … all"
  [ $JR_SYNC_ENV = LOCAL ] && return
  _jr_copy || { JR_WHY="cannot sync: $JR_SYNC_ENV unreachable"; return 1; }
  cp "$JR_FILE" "$JR_COPY/"; JR_PULLED=1                               # this machine's own file: the local one is the truth
  _jr_w=$(_jr_waits "$JR_COPY"/*.tsv | awk -v now=$NOW -v me=$JR_MACHINE_NAME '$1 > now && $2 != me && $3 == "all"' | sort -n | tail -n 1)
  [ "$_jr_w" ] || return 0
  set -- $_jr_w; jr_skip "waiting until $(_jr_hm $1) UTC: ${_jr_w#* * * } (asked by $2)"
}

# ---------- Statuses: RUNNING SUCCESS FAILURE SKIP WAIT; a check's status is the last one it wrote (§2, §6) ----------
jr_write_status() {   # jr_write_status STATUS [TEXT]: appended here, then this whole file copied to each report env
  JR_STATUS=$1 JR_TEXT=${2//[$'\t\r\n']/ }
  printf '%s\t%s\t%s\t%s\n' "$JR_CHECK" $((NOW+SECONDS-JR_T0)) "$1" "$JR_TEXT" >>"$JR_FILE"
  for _jr_e in ${_jr_report#LOCAL}; do _jr_in $_jr_e "$JR_FILE" put-status $JR_JOB $JR_MACHINE_NAME; done; :
}   # an env unreachable now misses nothing: the next copy brings the whole file
jr_skip() { jr_write_status SKIP "$1"; exit 0; }   # REASON: a Skip, the check ends here
jr_summary() { [[ $1 && $JR_STATUS && $1 != "$JR_TEXT" ]] && jr_write_status $JR_STATUS "$1"; :; }   # TEXT: same status
jr_summary_grep() { jr_summary "$(grep -aE "$1" "$JR_LOG" | tail -n 1)"; }   # REGEX: the last line of the work's output matching it
jr_read_statuses_since() {   # jr_read_statuses_since EPOCH [STATUS] → "ts machine status text", one per check (its last status)
  [ "$JR_PULLED" ] || { echo "jr_read_*: call jr_pull first (JR_SYNC_ENV=$JR_SYNC_ENV)" >&2; return 1; }
  _jr_last $_jr_read | awk -F'\t' -v t=$1 -v s=$2 '$1 >= t && (s == "" || $3 == s)' | sort -n
}
jr_skip_if() {   # STATUS day|SECONDS REASON [N=1]: SKIP when N checks ended STATUS since midnight UTC (day), or in the last SECONDS
  local since=$((NOW-NOW%86400)); [ $2 = day ] || since=$((NOW-$2+1))
  [ $(jr_read_statuses_since $since $1 | wc -l) -lt ${4:-1} ] || jr_skip "$3"
}

# ---------- The work: its own process group, TERM then KILL at the timeout (§5, R10) ----------
_jr_run() { exec env -u JR_SYNC_TOKEN "$@"; }   # the work never sees the job-runner-sync token
jr_execute() {        # jr_execute TIMEOUT_MIN CMD… → RUNNING, then SUCCESS (exit 0) or FAILURE; $JR_RC $JR_LAST_LINE $JR_LOG
  if [ "$JR_DRY_RUN" ]; then
    JR_RC=0 JR_LAST_LINE="dry run: ${*:2}"; echo "$JR_LAST_LINE" >>"$JR_LOG"; jr_write_status SKIP "$JR_LAST_LINE"; return
  fi
  jr_write_status RUNNING                                               # overlapping executions allowed unless the job claimed
  set -m; (_jr_run "${@:2}") >>"$JR_LOG" 2>&1 </dev/null &             # job control: the work gets its own process group
  _jr_p=$! _jr_wd=; set +m
  if [ "${1:-0}" -gt 0 ]; then   # the watchdog: TERM to the whole work, KILL 10 s later; stopped as soon as the work ends
    (sleep $(($1*${JR_TEST_MINUTE_S:-60})) && touch "$JR_LOG.timeout" && kill -TERM -$_jr_p && sleep 10 && kill -KILL -$_jr_p) >/dev/null 2>&1 &
    _jr_wd=$!; disown $_jr_wd
  fi
  { wait $_jr_p; } 2>/dev/null; JR_RC=$?                                 # (bash's own "Killed" notices hidden)
  [ "$_jr_wd" ] && { pkill -P $_jr_wd 2>/dev/null; kill $_jr_wd 2>/dev/null; }
  JR_LAST_LINE=$(grep -av '^[[:space:]]*$' "$JR_LOG" | tail -n 1 | cut -c1-200)
  if rm "$JR_LOG.timeout" 2>/dev/null; then
    kill -KILL -$_jr_p 2>/dev/null; JR_RC=124; jr_write_status FAILURE "timeout after $1 min"   # what ignored TERM goes now
  elif [ $JR_RC = 0 ]; then jr_write_status SUCCESS "$JR_LAST_LINE"
  else jr_write_status FAILURE "exit $JR_RC: $JR_LAST_LINE"; fi        # any other code means what the project says:
  return $JR_RC                                                         # its entrypoint rewrites the status after this
}

# ---------- Claims: the job's choice, a lock, not a status (§7) ----------
# LOCAL, NAS: the folder claims/<job> (an atomic mkdir), its file owner = "machine until pid"; held while its pid lives on
# this machine's own disk, else until it expires. GITHUB: the file claims/<job> on main, held until it expires.
# The operations claim and release are in ops.sh.
_jr_where() {   # ENV → where its folder is, for ops.sh's claim and release: here (this machine's own disk), NAS or GITHUB
  if [ $1 = LOCAL ] || { [ $1 = NAS ] && [ "$JR_NAS_DIR" = "$JR_ROOT" ]; }; then echo here; else echo $1; fi
}
_jr_lock() {   # _jr_lock ENV MIN: this check's claim in ENV, else $JR_WHY
  _jr_m="claim " _jr_in $1 /dev/null claim $(_jr_where $1) $JR_JOB $JR_MACHINE_NAME $NOW $((NOW+$2*60)) $$ >"$_jr_tmp"
  set -- $? $1 $(tail -n 1 "$_jr_tmp")                                  # return code, env, the script's last line
  case $1:$2:$3 in
    0:*) JR_CLAIMS+=" $2"; return ;;
    255:*) JR_WHY="cannot claim: $2 unreachable" ;;
    *:running) JR_WHY="previous execution still running (pid $4)" ;;
    *:held) JR_WHY="held by $4 until $(_jr_hm $5) on $2" ;;
    1:GITHUB:) JR_WHY="cannot claim on GITHUB: 5 pushes rejected" ;;
    *) JR_WHY="cannot claim on $2" ;;
  esac; return 1
}
jr_claim() {   # jr_claim MIN: the lock here, then in the sync env, then a pull: the job decides after it, on what it read.
               # Either lock or the pull fails: the claims taken are given back, then SKIP "$JR_WHY"
  if [[ $JR_CLAIMS = *LOCAL* ]] || _jr_lock LOCAL $1; then
    [ $JR_SYNC_ENV = LOCAL ] && return
    _jr_lock $JR_SYNC_ENV $1 && jr_pull && return
  fi
  _jr_release; jr_skip "$JR_WHY"
}
_jr_release() {   # a claim not given back (unreachable) expires after its MIN
  for _jr_e in $JR_CLAIMS; do _jr_m="release " _jr_in $_jr_e /dev/null release $(_jr_where $_jr_e) $JR_JOB $JR_MACHINE_NAME $$; done
  JR_CLAIMS=
}

# ---------- At exit (an EXIT trap, set below: when this entrypoint ends, in this same check) ----------
_jr_exit() {
  local rc=$? f
  case $JR_STATUS in
    '') [ $rc = 0 ] && jr_write_status SUCCESS || jr_write_status FAILURE "exit $rc" ;;
    RUNNING) jr_write_status FAILURE "never finished" ;;
  esac
  _jr_release
  [ "$JR_STATUS" = SKIP ] && rm -f "$JR_LOG"                            # a Skip's log is not kept
  # Every failed log the NAS does not have yet (this one, and any missed while it was unreachable): the NAS's list, then
  # this machine's logs not in it whose check ended FAILURE (from the status file)
  [[ $_jr_report = *NAS* ]] && _jr_in NAS /dev/null list-logs $JR_JOB $JR_MACHINE_NAME >"$_jr_tmp" &&
    for f in $(ls "${JR_LOG%/*}" | grep -vxFf "$_jr_tmp" | awk -F'\t' 'NR == FNR { s[$1 ".log"] = $3; next } s[$0] == "FAILURE"' "$JR_FILE" -); do
      _jr_in NAS "${JR_LOG%/*}/$f" put-log $JR_JOB $JR_MACHINE_NAME $f || break
    done
  rm -f "$_jr_tmp"
}

# ---------- At load (§5): GCP's file back, close a check killed before it ended, this machine's pending WAIT, rotate ----------
_jr_new=   # GCP keeps nothing: its own file, from the sync env (its pids mean nothing here: "x", never alive)
[[ ! -s $JR_FILE && $JR_SYNC_ENV != LOCAL ]] && _jr_copy && [ -s "$JR_COPY/$JR_MACHINE_NAME.tsv" ] &&
  cp "$JR_COPY/$JR_MACHINE_NAME.tsv" "$JR_FILE" && _jr_new=x
read -r _jr_c _ _jr_s _ <<<"$(tail -n 1 "$JR_FILE")"                    # the last check: id, status
[ "$_jr_s" = RUNNING ] && ! kill -0 ${_jr_new:-${_jr_c##*.}} 2>/dev/null &&
  { JR_CHECK=$_jr_c jr_write_status FAILURE "never finished (killed, or the machine stopped)"; JR_STATUS=; }
_jr_w=$(_jr_waits "$JR_FILE")                                           # this machine's own WAIT, whatever its scope
if [[ $_jr_w && ${_jr_w%% *} -gt $NOW ]]; then
  jr_write_status SKIP "waiting until $(_jr_hm ${_jr_w%% *}) UTC: ${_jr_w#* * * }"; rm -f "$_jr_tmp"; exit 0
fi
(cd "${JR_LOG%/*}" && ls -t | awk -F'\t' -v n=$JR_KEEP_N_LOGS -v f=$JR_KEEP_N_LOGS_FAILURE -v s=$JR_KEEP_N_LOGS_SUCCESS '
  NR == FNR { status[$1 ".log"] = $3; next }                            # the status file: the last status of each check
  { keep = n-- > 0                                                      # logs, newest first: the newest N,
    if (status[$0] == "FAILURE" && f-- > 0) keep = 1                    # at least the newest N failed
    if (status[$0] == "SUCCESS" && s-- > 0) keep = 1                    # and successful ones
    if (!keep) print }' "$JR_FILE" - | xargs rm -f)
[ $(wc -l <"$JR_FILE") -gt $JR_KEEP_N_STATUSES ] && tail -n $JR_KEEP_N_STATUSES "$JR_FILE" >"$JR_FILE.tmp" && mv "$JR_FILE.tmp" "$JR_FILE"
trap _jr_exit EXIT

# ---------- Helpers for deciding ----------
jr_age() { echo $((NOW-$(date -r "$1" +%s 2>/dev/null || echo 0))); }   # FILE: seconds since it changed (missing: since 1970)
jr_online() { case $JR_TEST_ONLINE in yes) return 0 ;; no) return 1 ;; esac
  ping -c 1 $([[ $OSTYPE = darwin* ]] && echo -t || echo -W) 3 "${1:-1.1.1.1}" >/dev/null 2>&1 ||
  curl -s -o /dev/null --max-time 5 "https://${1:-1.1.1.1}"; }   # UGOS (the NAS) refuses ping to a normal user ("Operation not permitted"): HTTPS then (2026-11-20)
