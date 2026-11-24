# job-runner

Development home: NAS (`~/dev/infra/job-runner` on the NAS, since 2026-11-22; no copy on the Mac: `tm job-runner` opens it). Its Mac part (the library, the canaries): `dev-install job-runner` (my-setup); the NAS: `bash install.sh` here. Why (U19, the user, 2026-11-22): the NAS by default; nothing ties it to the Mac.

**A wrapper for all my scheduled jobs: a library of helpers to decide when to skip, standard result codes and summary lines, and one dashboard for all of them.** Successor of `multi-host-orchestrator` (retired 2026-10-10; its GitHub repo is archived).

## Stage

In production since 2026-10-10: every scheduled job of the Mac, the NAS and GCP runs through this library. Canaries and their audit keep testing it (`canaries/`); the dashboard: http://babisnas:8097.

## Rules

- **Least code wins:** cut before you add. Keep the proven parts (the dashboard, decommissioning, the trigger names, `jr_execute`'s process group and timeout) instead of rewriting them. → [`DESIGN.md`](DESIGN.md) §8
- **The job decides, the library records.** A rule about when to work is code in the entrypoint, using helpers, never an option of the library. Each job uses only the pieces it needs (helpers, claims, `job-runner-sync`): nothing is forced on all. → §1, §5
- **Bash 3.2** (macOS `/bin/bash`) on the machines, needing only `git` and `ssh`; the dashboard alone is Python (standard library, the NAS only).
- **Everything UTC.**
- **Never change another project** (auto-commit, auto-job-apply, agent-tracker, the trading bot, agent-resume…) without the user's explicit OK: they run in production.
- **Secrets:** never print, log or commit a token (the sync token `JR_SYNC_TOKEN`, any project's).
- **Development on the Mac only**; the deployed copy is `~/opt/job-runner/`, written only by `install.sh`.

## Vocabulary

The only words for these concepts, in every file and when talking to the user. A new word is added here first, with the user's agreement. Agreed on 2026-10-10.

| Word | Means | Never say |
|---|---|---|
| **Job** | one thing to run on a schedule, e.g. auto-job-apply; named `<repo>` or `<repo>.<job>` | task |
| **Entrypoint** | a job's own Bash script, `~/opt/<repo>/entrypoint.sh` (or `<job>.sh`), run by its trigger: decides, works, ends with a result | runner, wrapper, job file |
| **Library** | `~/opt/job-runner/lib.sh`, sourced by every entrypoint: the helpers, the statuses, the records | framework |
| **Helper** | a `jr_` function of the library, e.g. `jr_execute`, `jr_write_status`, `jr_claim` | option, rule |
| **Machine** | a place that runs jobs: the MacBook, the NAS, GCP; named by its host name | node |
| **Trigger** | the machine's own scheduler entry that starts the entrypoint: LaunchAgent, systemd timer, Cloud Scheduler; named `com.jeanlescut.<repo>[.<job>]` | |
| **Check** | one start of the entrypoint (by its trigger or by hand): ends in a Success, a Failure, a Skip or an Ask to Wait | run (as a noun) |
| **Skip** | a check where nothing was done, always with its reason: decided by the job (a claim held elsewhere included), or by the library (a pending Ask to Wait) | |
| **Execution** | a check where the job did its work: a Success or a Failure | run (as a noun) |
| **Period** | the span in which a job should succeed once | window |
| **Ask to Wait** | the status `WAIT "SECONDS [all] reason"`: "not now", nothing tried until then on this machine, or with `all` on every machine that pulls it; not a failure | |
| **Summary line** | the text of the last `jr_write_status`, else the entrypoint's last output line; shown next to the result | |
| **Tick** | a trigger every few minutes (the Mac's way: it may sleep at any moment) | |
| **Fixed schedule** | a trigger at given times only, like cron | |
| **Shared job** | a job several machines may do: one success per period, whichever machine | |
| **Claim** | an optional lock taken by `jr_claim`, never a status: a lockfile here (no overlap), an atomic `mkdir` on the NAS, a file on GitHub `main` | |
| **Status** | what a check wrote last: `RUNNING`, `SUCCESS`, `FAILURE`, `SKIP`, `WAIT`; one per check, a line of `status/<job>/<machine>.tsv` | state, result code |
| **job-runner-sync** | the private GitHub repo used as the env `GITHUB` | sync repo |
| **Env** | a place where statuses are kept, each with the same layout `status/<job>/<machine>.tsv`: `LOCAL` (this machine), `NAS`, `GITHUB` (`job-runner-sync`) | store, status store, hub, state |
| **JR_SYNC_ENV** | the one env shared with the other machines: pulled once by `jr_pull` (then read locally), claimed in; default `LOCAL` | sync envs, fallback |
| **JR_REPORT_ENVS** | the envs a check writes its statuses to (plus `JR_SYNC_ENV`); default `LOCAL NAS` | |
| **Silent** | a machine the dashboard has heard of much later than usual: asleep, off or offline | down, dead |
| **Canary** | a fake job testing a promise in real conditions | test job |
| **Decommissioned** | a job that no longer exists, folded at the bottom of the dashboard | retired, inactive |

## Where to look

| | |
|---|---|
| what the user wants | [`REQUIREMENTS.md`](REQUIREMENTS.md) |
| why it is built this way | [`DESIGN.md`](DESIGN.md) |
| what is still unclear | [`CONSIDERATIONS.md`](CONSIDERATIONS.md) |
| every current job's entrypoint (in its own project) | [`doc/examples.md`](doc/examples.md), tested by [`test/examples_test.sh`](test/examples_test.sh) |
| the dashboard and its settings | [`dashboard/dashboard.py`](dashboard/dashboard.py), [`dashboard/conf/`](dashboard/conf/) (defaults, canaries), a job's own in its project, sent by [`put-conf.sh`](put-conf.sh) (DESIGN §11); on the Mac: `ssh babisnas curl -s 127.0.0.1:8097/` |
| the NAS's operations and their gate | [`ops.sh`](ops.sh), [`gate.sh`](gate.sh), [`deploy/keys/`](deploy/keys/) (job-runner's own key per machine), DESIGN §12 |
| the library, its tests, its install | [`lib.sh`](lib.sh), [`test/`](test/) (`bash test/lib_test.sh > log 2>&1`), [`install.sh`](install.sh) / [`uninstall.sh`](uninstall.sh) on each machine (the NAS: from a temporary clone, so push first; the command is in `install.sh`'s header) |
| the NAS's boot kick (its jobs back after a restart) and its healthchecks.io ping | [`boot-kick/`](boot-kick/), [`canaries/run.sh`](canaries/run.sh), DESIGN §13 |
| the NAS's weekly backup of `/volume1/private` (the encrypted folder; `/volume3/data` until 2026-11-18) to the portable disk (restic), the job `job-runner.backup` | [`backup/`](backup/), DESIGN §13 |
| the skill for creating and removing jobs and services | [`skills/jobs-and-services/`](skills/jobs-and-services/SKILL.md), deployed by `install.sh` |
| open work | Todoist (skill `tasks`): its tasks carry `Repo: job-runner`; [`todo.html`](todo.html) shows them |
