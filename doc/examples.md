# Entrypoints: every current job

Every job running today, written for job-runner as designed in [`../DESIGN.md`](../DESIGN.md). **The entrypoints live in their projects only** (no copies here since 2026-10-12): each opens with the job's requirements, then the code that meets them. Words as in [`../AGENTS.md`](../AGENTS.md).

**Tested** by [`../test/examples_test.sh`](../test/examples_test.sh): it runs each project's real entrypoint (from `~/dev/<category>/<repo>/`), deployed in a fake `~/opt/<repo>/` as its trigger would run it, against the library ([`../lib.sh`](../lib.sh); the NAS faked as a folder, GitHub as a local bare repo), the work replaced by a stub, under `/bin/bash` 3.2. It checks the decisions (skips, waits, claims held, the status each check ends with), not the real work. Verified 2026-11-09: 39 PASS.

## The files

| Job | Entrypoint, in its project | Machines | Trigger | Sync env (`JR_SYNC_ENV`) | Claim | Shows |
|---|---|---|---|---|---|---|
| `jobs.auto-job-apply` | `~/dev/professional/jobs/applying/auto-job-apply/entrypoint.sh` | Mac | 3600 s | `LOCAL` | lockfile | once a day, 3 tries, the work's exit codes, a wait |
| `auto-commit` | `~/dev/infra/auto-commit/src/entrypoint.sh` | Mac, NAS, GCP, once for all | Mac 600 s; NAS a time per weekday; GCP 12:00 | `GITHUB` | lockfile, GitHub | a claim, a rule per machine |
| `trading-bot.daily-global-scraping` | `~/dev/professional/trading-bot/dev/1_global_scraping/deployment/daily-global-scraping.sh` | NAS | `*:0/20` | `LOCAL` | lockfile | a project with several jobs; a check of the work's last line |
| `trading-bot.cpl_monitoring` | `~/dev/professional/trading-bot/dev/4_copy_trading/deployment/cpl_monitoring.sh` | NAS | every minute | `LOCAL` | no | the summary taken from the output (`jr_summary_grep`) |
| `trading-bot.cpl_monitoring_pack` | `~/dev/professional/trading-bot/dev/4_copy_trading/deployment/cpl_monitoring_pack.sh` | NAS | hourly at :15 | `LOCAL` | no | once a day, hourly tries |
| `agent-tracker.claude-quota` | `~/dev/agents/agent-tracker/jobs/claude-quota.sh` | Mac, NAS, the Mac preferred | 60 s | `LOCAL`; the NAS's reading taken by the poller (`--peer`) | no (harmless) | local checks first, a wait on this machine only |
| `agent-tracker.codex-quota` | `~/dev/agents/agent-tracker/jobs/codex-quota.sh` | Mac | 60 s | `LOCAL` | no (harmless) | the work decides itself, with code 10 |
| `agent-tracker.codex-plan-history` | `~/dev/agents/agent-tracker/jobs/codex-plan-history.sh` | Mac | 3600 s | `LOCAL` | no | once a day, retry after 1 h |
| `agent-tracker.aggregates` | `~/dev/agents/agent-tracker/jobs/aggregates.sh` | Mac, NAS, each for itself | 300 s | `LOCAL` | lockfile | a rule per machine (the Mac sends, the NAS does not) |
| `marketplace-seller` | `~/dev/personal/marketplace-seller/src/entrypoint.sh` | Mac | 1800 s | `LOCAL` | lockfile | at most 3 failures a day (`jr_skip_if FAILURE day`); one exit code of the work (13) a skip, not a try; nothing to sell (`state/to_sell.txt` empty): exits before the library, nothing recorded |
| `job-runner.backup` | `~/dev/infra/job-runner/backup/backup.sh` | NAS | `Sun *-*-* 02:00:00 UTC`, Persistent | `LOCAL` | lockfile | a check that fails before working (no disk: `FAILURE`, no ping); its own healthchecks.io pings; the work in the same file (`backup.sh work`) |

Decommissioned: `auto-apply` (renamed `job-applications.auto-apply`), `job-applications.auto-apply` (renamed `job-applications.auto-job-apply` on 2026-10-17), `job-applications.auto-job-apply` (the repo renamed `jobs` on 2026-11-12: `jobs.auto-job-apply`), `agent-usage-tracker.transcripts` (replaced by `aggregates`), `agent-usage-tracker.push` (`aggregates` sends the slots), `agent-resume` (2026-11-20: its index is refreshed at search time, other machines searched over ssh: no job left), `agent-session-manager` and `agent-usage-tracker.claude-quota`, `.codex-quota`, `.codex-plan-history`, `.aggregates` (the repos renamed agent-resume and agent-tracker on 2026-11-07: the same jobs under the new names). A job's dashboard settings: an optional `<job>.conf` beside its entrypoint (DESIGN §11).

The job's name comes from where its file is: `~/opt/<repo>/entrypoint.sh` is `<repo>`, `~/opt/<repo>/<job>.sh` is `<repo>.<job>` (the same as its trigger's `com.jeanlescut.<repo>[.<job>]`). agent-tracker's OpenTelemetry receiver is not a job: a service, always running, it stays a plain LaunchAgent / systemd unit.

## claude-quota, a job deciding for itself

```
                status line on screen here (heartbeat < 90 s)    idle
the Mac  polls if   the quota is older than 110 s                  older than 300 s
the NAS   polls if   the quota is older than 170 s                  older than 360 s   ◄── the Mac's readings land here
```

A 429 waits on its own machine only: the endpoint counts per login token. Two polls at once remain possible (the NAS watched, the Mac idle), and harmless.
