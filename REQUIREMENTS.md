# Requirements

What the user wants from this tool, from the user's point of view only: the benefit, never the mechanism. How it is built is in [DESIGN.md](DESIGN.md). Words as defined in the vocabulary table of [AGENTS.md](AGENTS.md).

## Goal

In the user's words (2026-10-09): "It's not really about a multi-host orchestrator. It's about a wrapper of scheduled jobs, that provides: a library of useful functions (to do a lot of things, including multi-machine orchestration, among other things: basically functions to help you choose when to skip); a standardization of return codes and summaries; a centralization of those return codes and summaries + a nice dashboard to monitor those. Eventually, I would like to have any scheduled jobs using this project."

Several machines is one thing a job may need, not the tool's nature; and the job decides when to work, with ready-made help, instead of describing its rules to a framework.

## Primary requirements

### Any job can use it

| # | Requirement |
|---|---|
| R1 | **Every scheduled job.** Any job, in any language, on any of my machines, including a job that runs on one machine only. |
| R2 | **Little to adopt.** A job that already decides for itself only reports how it went, in the standard way. A job that does not gets ready-made helpers. Nothing new to learn beyond a short list of helpers. |
| R3 | **The job decides.** Whether to work now is the job's own decision, which can be as simple or as particular as it needs (e.g. "poll if my last reading is older than 2 minutes while a status line is on screen"). |

### Help to decide when to skip (the library)

| # | Requirement |
|---|---|
| R4 | **Already done.** A job can ask whether it already succeeded in its period, on this machine or on any machine. Periods as "the last X hours" or the UTC day or week. |
| R5 | **Retry spacing and a limit on failures.** A job can ask when it last failed and how many times in its period. "Not now" results do not count as failures. |
| R6 | **Conditions.** A job can ask about common conditions: internet, lid closed, on battery. |
| R7 | **Once across machines.** A job owned by several machines can make sure it works only once per period, whichever machine, never at the same time on two machines; failures count across machines; a machine that is down is replaced by another. No one machine being down stops it. |

### Standard results

| # | Requirement |
|---|---|
| R8 | **The job says how it went:** success, failure, skipped (with why), or "not now" (try again after a while, which the job may give, on this machine only or on every machine that shares its statuses). |
| R9 | **A summary line** of each check, shown next to its result (e.g. "4 applications sent", "reading still fresh"). |
| R10 | **Timeout.** A job still working after a given time is stopped, together with everything it started: nothing is left running behind it. |
| R11 | **No overlap, when the job asks.** A job can make sure it never starts while its previous one is still going, on this machine or on any machine; some jobs want overlapping runs, so it is the job's choice (2026-10-10). |
| R12 | **Laptop in a bag.** Lid closed and on battery: nothing is started at all. |

### Seeing what happened

| # | Requirement |
|---|---|
| R13 | **Everything is recorded:** every check and its result; every execution's start, end, duration and full output. |
| R14 | **Logs never fill the disk**, yet the recent failures and successes always stay readable. |
| R15 | **Phone dashboard, live**, from anywhere: every job on every machine, whether it is working right now, its last success, failure and Skip with why, its summary line, its recent history, and each machine's last known state. Privacy: an execution's full output leaves its machine only when it failed. |
| R16 | **Nothing lost offline.** Losing internet never stops a machine's jobs; what happened offline reaches the dashboard later. |
| R17 | **Cheap when nothing happens.** A job checking every minute and skipping most of the time costs almost nothing and floods nothing. |
| R18 | **Data for alerting:** everything an alerting tool needs can be read (failures, a machine gone silent, a job with no success for too long). |

### Where it runs

| # | Requirement |
|---|---|
| R19 | The MacBook (macOS), the VM (Debian) and GCP (which keeps nothing between runs). |

## Secondary requirements (nice to have, later)

| # | Requirement |
|---|---|
| S1 | **Alerts**, later: maybe here, maybe a separate project reading R18's data (2026-10-09: "potentially alerts later"). |
| S2 | **Backups stay tested.** For a job owned by several machines, I learn within a week when a backup machine can no longer do it. |
| S3 | **A job behaves as when I run it by hand** (finds its tools, prints accents correctly); secrets never appear in a log or on the dashboard. |
| S4 | **Every existing job runs here.** |

## Out of scope

| Item | Why |
|---|---|
| Pause / resume a job | Not needed: I can remove its trigger. |
| Jobs that exclude each other | Avoided when scheduling them (e.g. one Chrome profile per job) (2026-10-09). |
| Changing an existing job without my OK | Jobs move one by one, each with my explicit OK: they run in production. |

## Decided questions

| # | Question | Decision |
|---|---|---|
| Q1 | Does a "not now" result count as a failure? | No (R5), 2026-10-07 |
| Q2 | Full output on the dashboard? | Only for failures (R15), 2026-10-07 |
| Q3 | Failures of a job owned by several machines: per machine or across? | Across (R7), 2026-10-08 |
| Q4 | "Not now": for this machine or for all? | The job says, each time (R8), 2026-10-08; "all" reaches the machines that pull the env it is written to (2026-10-10) |
| Q5 | May deciding depend on one particular machine being up? | No (R7), 2026-10-08 |
| Q6 | Time zone? | UTC everywhere, 2026-10-08 |
| Q7 | Is several machines the tool's nature? | No: one of its helpers (R7), 2026-10-09 |
| Q8 | A framework the job describes itself to, or a library the job calls? | A library; the job decides (R2, R3), 2026-10-09 |
| Q9 | The project's name? | `job-runner`, 2026-10-09 |
