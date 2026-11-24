# Design — job-runner

Each job is one Bash script, its **entrypoint** (`~/opt/<repo>/entrypoint.sh`), started by the machine's trigger. It may set a few `JR_*` settings, sources the **library** (`~/opt/job-runner/lib.sh`), decides whether to work with a few helpers and its own code, runs its work through `jr_execute` (timeout, crash, log), and writes its status. Statuses are kept in **envs**: this machine (`LOCAL`), the NAS (`NAS`) and GitHub `job-runner-sync` (`GITHUB`), each with the same layout, `status/<job>/<machine>.tsv`. A check shares one env with the other machines, `JR_SYNC_ENV`: it pulls it once (`jr_pull`), reads that copy, and claims there; it writes to every env of `JR_REPORT_ENVS` it can reach, in real time. The NAS holds everything, and the dashboard reads it. The guiding principle: **the least code that meets [`REQUIREMENTS.md`](REQUIREMENTS.md)**. Words as defined in [`AGENTS.md`](AGENTS.md). Every job of October 2026, written this way: [`doc/examples.md`](doc/examples.md). Status: agreed with the user 2026-10-10, built and minimized the same day ([`lib.sh`](lib.sh), §12), in production since; tests in [`test/`](test/), open work in Todoist (skill `tasks`, `Repo: job-runner`; [`todo.html`](todo.html)).

| | |
|---|---|
| Command | none of its own: a trigger runs `/bin/bash ~/opt/<repo>/entrypoint.sh`, which sources `~/opt/job-runner/lib.sh` · the dashboard (NAS) |
| Reads | statuses from one env (`JR_SYNC_ENV`) |
| Writes | `~/opt/job-runner/status/<job>/<machine>.tsv` here, copied whole to each env of `JR_REPORT_ENVS` up now; `~/opt/job-runner/logs/<job>/<machine>/` (failed ones also to the NAS); claims |
| Acts | yes: runs the job's work |
| Consumed by | the dashboard and alerts (the NAS), the other machines (claims, statuses), the canaries' audit |

```
 entrypoint.sh
   JR_SYNC_ENV=GITHUB                  optional settings, before loading (defaults: LOCAL · LOCAL NAS · the host name · 50 logs…)
   . lib.sh ─────────────────────────  at load: JR_MACHINE_NAME NOW DOW HOUR · close a check killed before it ended · rotate
                                       logs and statuses · this machine's pending WAIT → SKIP · the report envs reachable
   jr_claim 15 ──────────────────────  optional: a lock here (lockfile), and in JR_SYNC_ENV, then one copy of it
     (or jr_pull alone) ─────────────  one copy of JR_SYNC_ENV without a lock (or skip / go on alone: the job's choice)
   decide ── jr_read_statuses_since ─  from that copy, no network
   jr_execute 10 ./main.sh ──────────  RUNNING · the work as a child (process group, timeout, crash seen) · SUCCESS / FAILURE
   jr_write_status / jr_summary ─────  the project's own meaning of a code, a better text: replaces this check's status
   (end of the script) ──────────────  EXIT trap: a status if none · claims released · a Skip's log deleted · failed logs to the NAS
```

## 1. A library the job calls, not a framework

**Choice:** a job is its entrypoint, a plain Bash script the developer writes (§9). It sets a few optional `JR_*` settings, sources `lib.sh` and calls what it needs (§4). No job file, no options, no runner process. Serves R1–R3.

**Why:** with a framework, every rule about when to execute becomes a job-file option, and a job with its own logic does not fit: agent-tracker's quota poll (then named agent-usage-tracker) already decides for itself (2026-10-09). What every job needs: records, the dashboard, decommissioning; a shared job only auto-commit.

| Need | The job uses |
|---|---|
| nothing special | `. lib.sh` + `jr_execute` |
| its own rule for when to work | its own code, then `jr_write_status SKIP "…"` |
| another machine's results, once across machines | `JR_SYNC_ENV=NAS` or `GITHUB`, then `jr_read_*`, `jr_claim` (§7) |

**Rejected:**

| Alternative | Why it lost |
|---|---|
| a framework (a job file of options, a skip hook, a result hook) | every new rule is a new option in the tool; the decision split between the job and its config (Q8) |
| a separate runner, `run.sh JOB -- COMMAND` (first draft, 2026-10-09) | two commands where one does; `jr_execute` gives the same protection from inside the script (§5) |
| a pure library with no child process for the work | it cannot record its own crash or `kill -9`, nor kill what the work started at the timeout |
| ready-made rules (`jr_success_since`, `jr_failed_within`, `jr_fresh`…, second draft) | one line of the job's own Bash each, once the statuses can be read (`jr_read_*`); the user preferred the plain code (2026-10-09) |
| a Python library too | the user: "everything in Bash for the moment" (2026-10-09) |

## 2. Statuses: one per check, the last one written

**Choice:** a check writes statuses (`RUNNING`, `SUCCESS`, `FAILURE`, `SKIP`, `WAIT`) to the reachable envs of `JR_REPORT_ENVS` (`JR_SYNC_ENV` included) (§6, §7); **the check's status is the last one it wrote**, and readers count each check once, by that status. Each line carries the check's id, so the stores stay append-only. Serves R8.

| Who | Writes | When |
|---|---|---|
| `jr_execute` | `RUNNING` | the work starts |
| `jr_execute` | `SUCCESS` if the work exited 0, else `FAILURE` (killed at the timeout too); text: the work's last line | the work ends |
| the entrypoint | `jr_write_status STATUS [TEXT]` (a skip, or a meaning `jr_execute` cannot know: auto-job-apply's 75 is `WAIT "3000 all …"`), `jr_summary TEXT` (the same status, a better text) | whenever; it replaces what came before in this check |
| the library, at exit | `SUCCESS` (exit 0) or `FAILURE`, if the check wrote nothing; `FAILURE "never finished"` if its last status is still `RUNNING` | the entrypoint ends |

Worked example, auto-job-apply hitting the usage limit: `RUNNING` → `FAILURE "exit 75: retry-after 5400"` (jr_execute) → `WAIT "5400 Claude usage limit"` (the entrypoint): the check is a WAIT, and "3 failures today" does not count it.

**No standard exit codes** (the user, 2026-10-10): only 0 means something to the library. Any other code means what its project says, and its entrypoint writes the status after `jr_execute` (auto-job-apply: 75 → `WAIT` for as long as it says, 76 → `SKIP`; codex-quota: 10 → `SKIP`).

**Rejected:** codes 10 / 11–14 for SKIP and WAIT (the user's first idea, then dropped: a project's codes are its own, and `rsync` 10–14 are errors); `jr_execute` writing no status (third draft: every entrypoint had to map codes itself; the user, 2026-10-10: "it could simplify things"); a "working now" message separate from `RUNNING` (the user: RUNNING is just a status); a marker line (`skip: …`) with codes 10/11 (first draft); `jr_success` / `jr_skip` / … (second draft; `jr_skip` came back on 2026-10-10, when the user asked for the least code, §12).

## 3. The summary line

**Choice:** the TEXT of the last declaration; otherwise the entrypoint's last non-empty output line; cut to 200 characters. Serves R9. **Rejected:** a `SUMMARY` regex setting (the entrypoint greps `$JR_LOG` when it needs to).

## 4. Settings and helpers

**Settings:** shell variables, each optional, set **before** loading the library (so it can use them while loading); the library fills the ones not set. Serves R2–R7, R14.

| Setting | Default | Means |
|---|---|---|
| `JR_MACHINE_NAME` | the skill `machine-name` (macOS: `scutil --get HostName`; Linux: `/etc/hostname`; cut at the first dot; none: the check stops with an error) | the machine's name in every file; exported, the work receives it; GCP sets `JR_MACHINE_NAME=GCP` in its image's environment (random host names) |
| `JR_SYNC_ENV` | `LOCAL` | the one env shared with the other machines: pulled by `jr_pull`, claimed in (§7) |
| `JR_REPORT_ENVS` | `LOCAL NAS` | where to write statuses; `JR_SYNC_ENV` is always added (a check must write where others read) |
| `JR_KEEP_N_LOGS`, `JR_KEEP_N_LOGS_FAILURE`, `JR_KEEP_N_LOGS_SUCCESS` | 50, 10, 5 | logs kept: the newest N, and at least the newest N failed / successful |
| `JR_KEEP_N_STATUSES` | 5000 | lines kept in this machine's status file |

The library also gives `NOW`, `DOW` (1 = Monday), `HOUR`, `MINUTE` (UTC) and `JR_JOB` (from the file's place: `~/opt/<repo>/entrypoint.sh` → `<repo>`, `~/opt/<repo>/<job>.sh` → `<repo>.<job>`, as its trigger's name).

**Helpers:**

| Helper | Does |
|---|---|
| `jr_execute TIMEOUT_MIN CMD…` | the work (§5): `RUNNING`, then `SUCCESS` (exit 0) or `FAILURE`; sets `$JR_RC`, `$JR_LAST_LINE`, `$JR_LOG` |
| `jr_write_status STATUS [TEXT]` | a status for this check (§2), replacing the one before |
| `jr_skip REASON` | `SKIP` with its reason; the check ends here |
| `jr_skip_if STATUS day\|SECONDS REASON [N]` | `jr_skip REASON` when N checks (default 1) ended STATUS since midnight UTC (`day`) or in the last SECONDS: "already done", "3 failures today", "failed less than 20 min ago", each one line in the job's own order |
| `jr_summary TEXT` | the same status, a better text; nothing if TEXT is empty |
| `jr_summary_grep REGEX` | `jr_summary` with the last line of the work's output matching REGEX |
| `jr_pull` | one copy of the sync env, here; fails if unreachable; honors another machine's `WAIT … all` (§7) |
| `jr_read_statuses_since EPOCH [STATUS]` | prints `ts machine status text`, one line per check since EPOCH (its last status): this machine's with `LOCAL`, every machine's as pulled otherwise; for a rule `jr_skip_if` cannot say |
| `jr_claim MIN` | optional, a lock, not a status (§7); held elsewhere or unreachable: the claims taken are given back and the check skips with the reason |
| `jr_age FILE`, `jr_online [HOST]` | seconds since FILE changed; internet up |

## 5. What the library does by itself: at load, in `jr_execute`, at exit

| When | The library |
|---|---|
| loaded (`. lib.sh`, the entrypoint's first lines) | fills the settings (§4) · lid closed on battery: exits, nothing recorded (R12) · a `RUNNING` left by a check killed before it ended (`kill -9`, power off; its pid, in the check id, is gone) → `FAILURE "never finished"` · **rotation**: logs beyond `JR_KEEP_N_*` deleted, the status file cut to `JR_KEEP_N_STATUSES` lines (R14) · the report envs reachable now (§7) · a pending `WAIT` of this machine (its last `WAIT`, not ended by a later check other than a Skip) → `SKIP "waiting until HH:MM UTC: reason"` and stop |
| `jr_execute` | writes `RUNNING`; runs the work as a child in its own process group, its output to `$JR_LOG`; at the timeout TERM to the whole group, KILL 10 s later (R10); a crash or `kill -9` of the work is seen; writes `SUCCESS` or `FAILURE`. It takes no claim: overlapping executions are allowed unless the job called `jr_claim` |
| the entrypoint ends (an **EXIT trap**, set at load, which bash runs when the script finishes, after an `exit` or an error too: the end of **this same** check) | a status if the check wrote none (exit 0 → `SUCCESS`, else `FAILURE`), `FAILURE "never finished"` if still `RUNNING` · claims released · a Skip's log deleted · **failed logs to the NAS**: every log of a check that ended `FAILURE` and that the NAS does not have yet (this check's, and any missed while the NAS was unreachable) |

**Why these:** each one is the same for every job and easy to get wrong.

## 6. Envs: the same layout everywhere; the NAS holds everything

**Since 2026-11 (data-reorganisation V3, the user's U17):** the env `NAS` (BabisNAS) is what the env `VM` (H-Frank-1) was; `VM` is still read as `NAS` (`JR_SYNC_ENV=VM`). The Mac reaches it by its alias `babisnas` (home address first, then Tailscale), other machines by its Tailscale address; GCP, not on the tailnet, never reports there: it reports through `GITHUB` only, where the dashboard reads it.

**Choice:** every env holds statuses the same way, `status/<job>/<machine>.tsv`, under `~/opt/job-runner/` on a machine and at the root of `job-runner-sync` on GitHub; failed logs under `logs/<job>/<machine>/`. One writer per file: a machine writes only its own file, so two machines never conflict; a reader of a remote env reads every machine's file of the job. On the Mac, `~/opt/job-runner/status/job-applications.auto-job-apply/` holds one file, `chan-lescut-macbook-pro.tsv`; on the NAS it holds every machine's, the NAS's own included. Serves R13, R15–R18.

| Line (tab-separated) | Example | Means |
|---|---|---|
| check id | `1791547200.23255` | the check's start (epoch) and pid: unique for (job, machine); the pid tells whether it still runs |
| status ts | `1791549660` | when this line was written, epoch UTC |
| status | `SUCCESS` | `RUNNING` · `SUCCESS` · `FAILURE` · `SKIP` · `WAIT` |
| text | `Done: 3 sessions` | the summary or the reason; for `WAIT`: `SECONDS [all] reason` (§7) |

The machine is the file's name. A check's lines share its id; its status is its last line.

**Writing:** a line is appended to this machine's file, then **the whole file is copied** to each reachable env of `JR_REPORT_ENVS` (`JR_SYNC_ENV` included): over SSH to the NAS (into a temporary file, then renamed), a push to `job-runner-sync` (`main`; another machine pushed first: fetch, copy the file again, push, 5 tries). An env unreachable now misses nothing: the next copy carries every line. No queue (the user, 2026-10-10). The dashboard reads the NAS's `status/`; **alert settings** (e.g. red after 26 h with no success) are a settings file per job, sent to the NAS by the job's project, never in an entrypoint (§11).

**Why:** the dashboard and the failed logs are on the NAS; git as the main path costs a push per start and end.

**Rejected:** a queue of lines not yet sent (a copy of the whole file catches up by itself); one shared file per job (two machines writing it at once); `state/` and `hub/` as other names for the same thing (one word: status, the user 2026-10-10).

## 7. One sync env: pulled once, read locally, written and claimed in real time

**Choice** (the user, 2026-10-10):

| Setting | Default | Means |
|---|---|---|
| `JR_SYNC_ENV` | `LOCAL` | **the one env** shared with the other machines: `LOCAL` (none), `NAS` or `GITHUB` |
| `JR_REPORT_ENVS` | `LOCAL NAS` | the envs every status is written to, in real time; `JR_SYNC_ENV` is always added |

```
jr_pull ──────────────── one copy of the sync env's status/<job>/*.tsv  →  ~/opt/job-runner/sync/<env>/status/<job>/
                         unreachable: fails, $JR_WHY = "cannot sync: NAS unreachable"; the job decides (skip, or go on alone)
                         another machine's pending "WAIT … all" there: SKIP, the check stops
jr_read_* ────────────── read that copy, as often as needed (no network); LOCAL: this machine's own file
jr_claim MIN ─────────── real time: the lockfile here, then the sync env (NAS: an atomic mkdir; GitHub: a push on main);
                         then a pull: the decisions after it read a copy nobody else can change before this check ends
jr_write_status ──────── real time: appended here, the whole file copied to every report env reachable (the sync env included)
```

**Why the pull is a helper and not automatic at load:** the job chooses when, and what an unreachable env means. e.g. auto-commit claims first and skips if it cannot (it must coordinate); a job reading other machines' statuses without claiming pulls by itself.

**Why the claim comes before the decision** (the user, 2026-10-10, TODO #1): a lock file is taken first, then the decision is made, as with a Unix lock. Holding the claim, no other machine can be working, and whatever one finished before is in the pull. Decided before the claim, a copy a few seconds old can miss a machine that succeeded and released meanwhile (a second day of commits); the library guessed it by comparing the copy before and after, and gave the claim back for any new line, a SKIP included: a once-a-day machine lost its day (2026-10-10). Cost: a claim taken and given back by each check past its own local skips (GitHub: two pushes). The same order for a job with a lockfile only (auto-job-apply): two of its own checks never decide on a file the other is about to change.

**WAIT and its scope:** `WAIT "SECONDS reason"` is for this machine, `WAIT "SECONDS all reason"` for every machine that pulls it. A machine honors its own WAITs at load (its own file), and the other machines' `all` WAITs in `jr_pull`: so an `all` WAIT reaches the machines that pull the env it was written to. Use `all` only when the limit is shared by every machine: auto-job-apply's Claude usage limit (one account) is; agent-tracker's 429 from `GET /api/oauth/usage` is not (it is counted per machine's login token, verified 2026-10-10), so its WAIT stays on the machine that got it.

| Job | `JR_SYNC_ENV` | Unreachable |
|---|---|---|
| one machine, or each machine for itself (auto-job-apply, trading-bot, agent-resume…) | `LOCAL` | — |
| once across machines, needing GitHub anyway (auto-commit) | `GITHUB` | skip |

**Rejected:** a read over the network per call (a round trip each: 8 for one auto-commit execution, ~10 s on GitHub; now 1 pull + 1 claim and its pull + the writes); an order of fallback envs with a heartbeat (2026-10-09/10, the user chose one env); a claim in both envs, "claim wherever reachable", 2 out of 3 envs.

## 8. Proven parts, kept

The dashboard (now reading the NAS's `status/`), the failed logs on the NAS, `decommission.sh`, the trigger names (`com.jeanlescut.<repo>[.<job>]`), UTC everywhere; git claims on `job-runner-sync` (5 tries, 1–3 s apart). **Why:** proven by the canaries and four real jobs in October 2026.

## 9. Triggers and entrypoints

**Choice:** each project ships its entrypoint and its triggers (on the Mac always a tick). A trigger runs `/bin/bash ~/opt/<repo>/entrypoint.sh`; a project with several jobs has one script per job (`~/opt/<repo>/<job>.sh`, job `<repo>.<job>`). The same script on every machine; a difference per machine is a `case` in it. Run by hand, the same command: a check like any other, recorded.

## 10. A rule, in the entrypoint

| Rule | In the entrypoint |
|---|---|
| the work, with a timeout | `jr_execute TIMEOUT_MIN COMMAND` |
| skip after a success today, a recent failure, N failures | a `jr_skip_if` line each (from this machine's records with the default `LOCAL`), then `skip` |
| one success for all machines, skip when the sync env is down | `JR_SYNC_ENV=NAS` or `GITHUB`, `jr_claim MIN` (it pulls), then the `jr_skip_if` lines |
| any other reason to skip | plain code, ending in `skip` |
| the work's own exit codes | a `case $JR_RC` |
| a summary taken from the log | `jr_write_status SUCCESS "$(grep … "$JR_LOG" \| tail -1)"` |
| red after too long without a success | the dashboard's `RED_AFTER_MIN` (§11); an alert on the phone through `task`: `ALERT` (§11) |
| how many logs and statuses are kept | `JR_KEEP_N_LOGS`, `JR_KEEP_N_LOGS_FAILURE`, `JR_KEEP_N_LOGS_SUCCESS`, `JR_KEEP_N_STATUSES` |

## 11. The dashboard's settings: an optional file per job, in its project, linked or sent to the NAS by its install.sh

What is not the entrypoint's business (thresholds, how a job looks on the dashboard) is a settings file, never code in an entrypoint. Since 2026-10-12 (the user) a job's file lives **in its own project**, beside its entrypoint, deployed with it in `~/opt/<repo>/`, and the project's `install.sh` gives it to the dashboard with [`put-conf.sh`](put-conf.sh): a symlink when the job's machine is the NAS, a copy sent over SSH otherwise (the dashboard runs on the NAS only; a Mac job has nothing on the NAS but its statuses): knowledge about a project's jobs stays in that project, and a new job needs no edit of job-runner. job-runner keeps only `_default.conf` and its canaries' files. First choice (2026-10-10): every file in job-runner's repo, so that a threshold would not need a project's OK and deploy.

```
 the NAS                                                       the NAS, ~/opt/job-runner/
   ~/opt/<repo>/<job>.conf                ◀── symlink ──────   conf/<repo>.<job>.conf
 the NAS itself (the trading-bot since 2026-11-20)
   ~/opt/trading-bot/cpl_monitoring.conf ◀── symlink ─────────   conf/trading-bot.cpl_monitoring.conf
 the VM (until it goes; nothing on the NAS)
   ~/opt/<repo>/<job>.conf ── copy, SSH (Tailscale) ──────────▶   conf/<repo>.<job>.conf
 the Mac (nothing on the NAS)
   ~/opt/jobs/auto-job-apply.conf ── copy, SSH ────────────────▶   conf/jobs.auto-job-apply.conf
                                                               dashboard/conf/_default.conf      (job-runner's)
                                                               dashboard/conf/canaries*.conf     (job-runner's)

 read for a job, the last value wins:  _default  →  <repo>  →  <repo>.<job>       (in each: dashboard/conf/, then conf/)
```

| Step | Who | How |
|---|---|---|
| Write the file | the project | `<job>.conf` beside `<job>.sh` (`entrypoint.conf` beside `entrypoint.sh`), optional; `install.sh` deploys it beside the entrypoint in `~/opt/<repo>/` |
| Give it to the dashboard | the project's `install.sh`, on the machine it installs on | `bash ~/opt/job-runner/put-conf.sh <full job name> ~/opt/<repo>/<job>.conf`: on the NAS a symlink to it; elsewhere a copy over SSH with job-runner's own key, gated to `ops.sh put-conf` (works from GCP too) |
| Change a threshold | the project | edit the file, re-run its `install.sh` |
| Decommission | whoever removes the job | `ssh babisnas 'f=~/opt/job-runner/conf/<job>.conf; { cat $f 2>/dev/null; echo DECOMMISSIONED=1; } > $f.new && mv -f $f.new $f'`: a real file replaces a link (never written through it), the job's other settings kept; no repo, no deploy; a job that comes back gives its file again, which clears it |

| Rule | |
|---|---|
| Format | `KEY=value`, one per line; `#` starts a comment (a value ends at ` #`); never executed, only parsed |
| Per machine | `KEY@<machine>=value` (e.g. `SILENT_AFTER_MIN@chan-lescut-macbook-pro=2880`); at each level it beats the plain `KEY` |
| Read | at every page load (a few small files): a change shows on the next refresh, no restart |
| A mistake | an unknown key or a bad value is shown on the dashboard as a yellow line naming the file and line; the rest still applies |
| A shared job | several machines give its file: when the NAS is one of them, its link stays (a copy from another machine never replaces a working link); otherwise the last sent wins |
| Removing all settings | give an empty file: a file missing in the project is never removed on the NAS |
| A project uninstalled from the NAS | its link points to nothing: a yellow line on the dashboard until the job is decommissioned |

| Key | Default | Means |
|---|---|---|
| `RED_AFTER_MIN` | 1560 | red: no SUCCESS on any machine for this long |
| `ALERT` | minor-within_a_day | a job turning red is a task through `task` (`~/dev/agents/tasks`, D19, 2026-10-23): `<cost_if_undone>-<complete_by>` (`task --help`), or `off`; the task "Job <job> is red" in Personal › Projects - IT › <repo>, completed when it is no longer red (checked every 5 min by the dashboard; `dashboard-alerts.txt`) |
| `ALERT_WHY_COST`, `ALERT_WHY_BY` | (a sentence each, in `_default.conf`) | why that cost and that deadline: `task` requires `--why_cost_if_undone` and `--why_complete_by` (the user, 2026-10-28); a conf that changes `ALERT` changes them too |
| `RED_AFTER_FAILURES` | 3 | red: this many FAILUREs in a row; orange from the first |
| `SILENT_AFTER_MIN` | 1560 (the Mac 2880) | grey: this machine wrote no status for this job for this long |
| `TITLE` | the job's name | the name shown |
| `GROUP` | the repo | jobs of one group are shown together |
| `ORDER` | 50 | smaller first |
| `HISTORY` | 20 | checks shown in the job's history |
| `FOLD` | `SKIP` | statuses folded into a count in the history (`SKIP WAIT` for a job checking every minute) |
| `DECOMMISSIONED` | 0 | 1: folded at the bottom, never red or grey |

A new need (an alert channel, a link, a colour) is a new key with its default in `_default.conf`: no job changes.

**Rejected:** every file in job-runner's repo (2026-10-10 to 10-12: a project's knowledge in another repo, an edit of job-runner per new job, which a project's session may not make); the library sending the file at each check (more library code, a send per check; the user chose `install.sh`, 2026-10-12); each `install.sh` copying or linking by itself (every project would know job-runner's folders and decide link or copy; the user kept `put-conf.sh`, 2026-10-12); a copy on the NAS even for a NAS job (two copies of one file; the user: links); links only (a Mac job has nothing on the NAS to link to); `DECOMMISSIONED=1` in job-runner's repo (a project removed deploys nothing more).

job-runner's files: [`dashboard/conf/`](dashboard/conf/); the code: [`dashboard/dashboard.py`](dashboard/dashboard.py) (reading the NAS's own `status/`; tested by [`test/dashboard_test.py`](test/dashboard_test.py); http://babisnas:8097 on the tailnet).

## 12. How the library is built (2026-10-10)

What the code of [`lib.sh`](lib.sh) chose where the design left room; tested by [`test/lib_test.sh`](test/lib_test.sh) (36 PASS) and [`test/examples_test.sh`](test/examples_test.sh) (28 PASS), smoke-tested the same day on the Mac, the NAS and GitHub.

| Piece | How |
|---|---|
| more settings (§4) | `JR_NAS_HOST` (`BabisNAS`), `JR_NAS_SSH` (unset: the Mac `babisnas` of its ~/.ssh/config, without its keys; other machines the Tailscale name `babisnas`), `JR_KNOWN_HOSTS` (`nas_known_hosts`), `JR_GITHUB_URL` (`job-runner-sync`), `JR_DRY_RUN=1` (every decision for real, `jr_execute` writes `SKIP "dry run: …"` instead of working) |
| the env NAS | one `ssh` per operation (`ConnectTimeout=5`, `BatchMode`, a shared connection kept 60 s) running one of the 7 operations of [`ops.sh`](ops.sh) by name (put-status, put-log, put-conf, get-statuses, list-logs, claim, release); no `rsync` (macOS ships 2.6.9). On the NAS itself the env NAS is its own disk: nothing copied. **Every machine reports to the NAS directly** (the user, 2026-10-10: no single point of failure for reporting), each with **job-runner's own SSH key** (`~/.ssh/job-runner` on the Mac, the secret `job-runner-ssh-key` on GCP; public halves in [`deploy/keys/`](deploy/keys/)), outside `~/.ssh/config`; on the NAS, `authorized_keys` forces those keys through [`gate.sh`](gate.sh): only the 7 operations, plain-name arguments (tested by [`test/gate_test.sh`](test/gate_test.sh)). The user's own key keeps its full shell for everything else |
| the env GITHUB | a shallow clone of `job-runner-sync` per job, `~/opt/job-runner/sync/GITHUB/<job>/` (two jobs never share a git index); pull = fetch + reset; the token only in git's own environment, read from `JR_SYNC_TOKEN` or `~/.config/job-runner/job-runner-sync.env`, removed from the work's environment |
| reachable or not | found at the first operation of the check, then remembered for the rest of it (one timeout at most per env) |
| claims | `claims/<job>/owner` = `machine until pid`, made by `mkdir`; here, held while its pid lives; elsewhere, until it expires. On the NAS, its own lock and the env NAS's claim are the same folder: a Mac's claim there also stops the NAS |
| a fresh machine | an empty status file is restored from the sync env at load (GCP, which keeps nothing); a `RUNNING` in a restored file is closed as never finished |
| the work | runs from the job's folder, `PATH` with Homebrew and `~/.local/bin`, `LANG` set (S3); a timeout sets `JR_RC=124` |

**Minimized on 2026-10-10** (the user: "minimize the code", "do not change any behavior", "still understandable"): five attempts in parallel (`simplification_1/` … `_5/`, not in git), measured by `tools/token_cost.py` (2 × the logic words of `examples/` + the logic words of `lib.sh`; comments and visible text not counted). Since 2026-10-13: [`tools/token_cost.sh`](tools/token_cost.sh), the counter of skill `code-minimization` (about-me): code tokens, not words (spacing changes nothing, the code inside a string counts), and every file job-runner ships (`ops.sh`, `gate.sh`, `install.sh`, the dashboard…), not only `lib.sh`. Today: 10959 (shared 9221 + 2 × 869 for the entrypoints and their settings); the 2026-10-10 change measured this way: 7294 → 5114 (`lib.sh` and `examples/` only). Kept: attempt 2's library (one runner `_jr_in` for LOCAL, the NAS and GitHub; one claim script for all three; the pull by `tar`; one reader of each check's last line) with attempt 5's helpers and entrypoints (`jr_skip`, `jr_skip_if`, `jr_summary_grep`, `jr_age`, `jr_claim` skipping by itself; `jr_read_status` and `jr_day_start` gone). Cost 3494 → 2198; the same 36 + 28 tests, and 84 scenarios compared with the version before (statuses, texts, files): identical. Known differences, none visible in a status: a GitHub claim is given back with up to 5 tries 1–3 s apart (was 3 tries); a GitHub operation fetches first, except a status write, which pushes first as before.

**`dashboard.py` minimized on 2026-10-14** (the user: "minimize dashboard.py with the new skill", "make sure you didn't remove any features"): 8 attempts in parallel (skill `code-minimization`), the base attempt's code hidden in split strings undone. Code tokens 4789 → 4011 (−16 %), code lines 264 → 230, comment lines 11 → 17. Checked: its test 18/18; the same page, settings, HTTP answers and git commands as before on 81 generated worlds and on a copy of the NAS's real data (25 jobs); the page's HTML/CSS/JS unchanged; Python 3.11.2 on the NAS. No feature cut; the cuts measured (the GitHub backup, the live durations, the strip, dark mode…) are proposals only.

## 13. The NAS: jobs back after a restart, its healthchecks.io check, its weekly backup (2026-11-18)

**The problem** (measured 2026-11-17 on `babisnas`, UGOS Pro): at boot the user's job manager (`systemd --user`, linger) starts ~6 s before UGOS attaches `/home` (`user@1000` 10:21:21, `home.mount` 10:21:27), finds no unit file and starts no job; nothing retries. Docker starts after the disks (10:21:34). The user chose option A (data-reorganisation, `work/plan_nas_workstation_2026-11-17.md` §12).

```
boot ─► systemd --user (no home yet: 0 jobs) ─► UGOS mounts /home ─► Docker ─► job-runner-boot-kick
                                                                                  │ waits: ~/.config/systemd/user and /run/user/<uid>/bus
                                                                                  │ daemon-reload, start default.target + timers.target (dbus-send)
                                                                                  │   └─ default.target starts home-mode: the home back to 700
                                                                                  ▼ sleeps
every 10 min: canaries/run.sh ─► the canaries ─► (NAS) home-mode ─► GET the ping URL of healthchecks.io's check "babisnas" ─► no ping for 30 min: email
```

| Piece | How |
|---|---|
| **boot kick** | [`boot-kick/`](boot-kick/): an alpine image with `dbus-send` (~9 MB), container `job-runner-boot-kick`, `restart: always`, as the user's uid, no network, read-only, no capabilities; it sees only the homes' folder and `/run/user`, read-only and `rslave` (a mount made after it started shows up). Not ready after 600 s: exit 1, Docker starts it again. A Docker restart kicks again: harmless. Deployed by `install.sh` on the NAS only; its log: `docker logs job-runner-boot-kick` |
| **the home's mode** (added 2026-11-18, after the restart test E2r) | UGOS sets the whole home tree (`/home/enrices`, a bind of `/volume2/@home/enrices`) back to 777 at each boot and marks it with its own ACL (`+` in `ls`), under which new files come out 777 whatever the umask (seen 10:47:15 on every entry, before Docker started at 10:47:23; again with UGOS 1.20 and 1.21, ~249,000 entries). [`boot-kick/home-mode.sh`](boot-kick/home-mode.sh) puts the home back to 700, gives `go-rwx` to every entry with group or other write (chmod also drops the ACL mark; files the umask 0022 makes, 644 and 755, are left alone), takes x off the unit files, and writes one journal line (`home …: was 777, now 700; N entries … (repaired)`, or `home …: 700, nothing group/world-writable`). Security only: after a reset every file is left 700, the exec bits UGOS added included. **The exec bits are restored by the skill nas-restart (my-setup), from a snapshot of the home's modes taken before a planned restart** (Jean, 2026-11-24: no scheduled job for this; the security part stays here because reboots are not always planned). A boot-time version (a file kept x only with `#!`, an ELF header or git's 100755) lived here from f518138 to its revert, the same day. Nothing writable (every 10-min run): one `find`, 0.6 s for 346,000 entries (2026-11-24). Tested without a reboot by [`test/home_mode_test.sh`](test/home_mode_test.sh) (a fake HOME set to 777). Run by `com.jeanlescut.job-runner.home-mode.service`, a oneshot `WantedBy=default.target` (so the kick starts it right after the boot; `journalctl --user -u com.jeanlescut.job-runner.home-mode`), and by `canaries/run.sh` on the NAS every 10 min, for a reset after that. Not in the kick: its container sees the home read-only, with no capability, on purpose. Installed by `install.sh` on the NAS only |
| **healthchecks.io ping** | [`canaries/run.sh`](canaries/run.sh), after starting the canaries: a GET of the URL in `~/.config/job-runner/healthchecks_<machine, lower case>.url` (mode 600, made by the user; the tasks service's pattern: success pings only, no `/fail`); no file: one line in the journal, nothing else. The NAS's check `babisnas`: period 10 min, grace 20 min. Since 2026-11-18 the NAS also withholds the ping while the Drive is not mounted at `~/gdrive` (my-setup's module `gdrive_mount`, data-reorganisation task G2): its canary `canaries.gdrive` (the NAS only) shows `FAILURE` and why on the dashboard |
| **the weekly backup** (added 2026-11-18, data-reorganisation task B3) | the job `job-runner.backup`, [`backup/backup.sh`](backup/backup.sh) (its requirements in its header), deployed to `~/opt/job-runner/backup.sh` by `install.sh` on the NAS only, with its trigger `com.jeanlescut.job-runner.backup` (a timer, Sundays 02:00 UTC, `Persistent=true`) and its dashboard settings [`backup/backup.conf`](backup/backup.conf) (red after 8 days, or after 1 failure). One check: the key file (mode 600, else `FAILURE`) · the store on the portable disk, `/mnt/@usb/*/restic` (none, or two not pinned: `FAILURE`; a pin: the store's restic id in `~/.config/job-runner/backup_store.id`) · the encrypted folder locked (no `/volume1/private/.unlocked`): `SKIP`, nothing read, no ping · `restic backup /volume1/private` (since 2026-11-18, data-reorganisation task E6; `/volume3/data` before, tag `volume3-data`), tag `private`, without `#recycle`, `@eaDir`, the sign `.unlocked` and the restore tests' `restore_test_*`; one file system. The first snapshot of the new path read every file once (no parent: restic picks one by host and path) but stored almost nothing (same content, deduplicated); later runs read only the changes · `restic check` reading 1/52 of the data (group (ISO week % 52) + 1) · the disk's free space: below 100 GB or 10 % → `FAILURE "LOW SPACE …"`. **No retention** while there is room: every snapshot kept. **When LOW SPACE shows**, the retention to apply (by hand, then in the job): `restic forget --keep-weekly 12 --keep-monthly 24 --prune` (12 weeks, then 2 years of months). Its own healthchecks.io check **`babisnas-backup`: Period 7 days, Grace 14 hours** (a check sends `/start` first, and a big week may run up to its 12 h timeout); URL in `~/.config/job-runner/healthchecks_babisnas-backup.url` (the user's, mode 600); `/start`, then success or `/fail` with the summary; a failure before the work (no key, no store) sends `/fail` too; no file: one line "no ping". `Kat/` is data only: an output line naming a path under it is hidden, and file names in `restic check`'s errors. A job with no project of its own: it lives here, beside the NAS's other pieces, until the user gives it one |
| **the encrypted folder** (built 2026-11-18, data-reorganisation's E4 and E6: `~/data/private` → `/volume1/private`, the link made by my-setup's `dev_layout`; the backup above is its first user) | a job that needs it checks first that it is unlocked (`[ -f /volume1/private/.unlocked ]`); locked → `jr_skip "~/data/private locked: unlock it in UGOS"`, and its own healthchecks.io check emails; unlocked → the next check goes on by itself. Data-reorganisation's plan §12 holds the test |

**Rejected:** every job in Docker (option B: every project's installer rewritten); a system boot service (needs root; UGOS rewrites its system files at updates); `systemctl` in a Debian image (~100 MB for one call); binding `~/.config/systemd/user` itself (missing at boot, Docker would create it as root).

## Acceptance

- A smoke test: each status (written and by code), the timeout, a crash, the claims (each env), the lid, each helper; the sync env and a report env made unreachable (a wrong URL, a blocked SSH port).
- The canaries quiet for a few days.
- The quota poll ticking every minute on 2 machines: the Mac polls about every 2 min while you work, the NAS almost never while the Mac is awake.

## Open points

None in the design; the questions still open are in [`CONSIDERATIONS.md`](CONSIDERATIONS.md). (The SSH copy per check: answered by the shared connection, §12.)

## Superseded decisions

- 2026-10-09: a separate runner and marker lines → the entrypoint, the library, `jr_execute`, codes 0 / 10 / 11–14 (§1, §2); the codes dropped on 2026-10-10.
- 2026-10-10: `jr_skip` and ready-made rules came back as `jr_skip`, `jr_skip_if` (the user: "Forget about any helper I rejected before. I want to minimize the code"), §12.
- 2026-10-09: ready-made rules, `--anywhere`, `jr_use_job_sync`, `jr_alert_after_min` → `jr_read_*`, `jr_write_status`, `jr_resolve_envs` (§4, §7), alerts on the monitoring side (§6).
- 2026-10-09: statuses through git first → every check to the hub; GitHub only as a store a job reads or writes (§6, §7).
- 2026-10-09: reads merged from every reachable store → one store to read (`JR_READ_FROM`), made safe by the catching-up state (§7), the user's call.
- 2026-10-10: `jr_execute` writing no status, "working now", RUNNING as the claim → `jr_execute` writes RUNNING and the result, one status per check, claims as optional locks per store (§2, §7), the user's call.
- 2026-10-10: decide, then claim, then a new pull compared with the first → claim (and pull), then decide (§7), the user's OK on TODO #1.
- 2026-10-10: the sync env checked at load (abort) and read over the network per call → `jr_pull` once, reads of the local copy, claims and writes in real time, a new pull after a claim (§7), the user's design.
- 2026-10-10: an order of fallback sync envs, the heartbeat, the catching-up state → one `JR_SYNC_ENV`, the check aborting when it cannot reach it (§7), the user's call.
- 2026-10-10: `jr_resolve_envs`, a queue, `state/` + `hub/` + one shared file per job → `JR_SYNC_ENVS` / `JR_REPORT_ENVS` resolved at load, the whole file copied, `status/<job>/<machine>.tsv` in every env (§6, §7), the user's call.
- 2026-10-09: a framework of job-file options → this design (§1).
