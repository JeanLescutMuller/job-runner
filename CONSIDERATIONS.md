# Considerations

Points still unclear for job-runner: to investigate, risks, unknowns. This file states no design choice, on purpose; an answered point is kept and marked with where it was answered. Words as in [`AGENTS.md`](AGENTS.md).

## 1. Exit codes

- **Standard codes.** 0 / 10 / 11–14 proposed by the user on 2026-10-09, dropped on 2026-10-10: only 0 means something to the library, a project's other codes are its own. → answered in [`DESIGN.md`](DESIGN.md) §2.

## 2. The VM and `job-runner-sync`

- **Two places, no majority.** → answered in [`DESIGN.md`](DESIGN.md) §7 (2026-10-10): one sync env per job, pulled once by `jr_pull`; unreachable, the job decides (skip, or go on alone); no fallback.
- **GCP writing to the VM.** → answered in [`DESIGN.md`](DESIGN.md) §12 (2026-10-10): every machine, GCP included, reports to the VM directly with job-runner's own SSH key, which the VM's `gate.sh` lets run only the 7 operations of `ops.sh`; GitHub is never the only way to report (the user: no single point of failure).
- **The dashboard while the VM is down.** It runs on the VM, so it is down too, and `job-runner-sync` holds only the statuses of jobs syncing or reporting there. Enough?
- **One SSH copy per check.** → answered in [`DESIGN.md`](DESIGN.md) §12: one shared connection kept 60 s (ControlMaster), job-runner's own, so a job ticking every minute opens about one connection.

## 3. The job deciding for itself

- **A job run by hand.** The entrypoint run by hand is a check, with its Skips ("already applied today"). Forcing one past its Skips: a `JR_FORCE=1` that makes the Skip helpers answer no?
- **Python jobs.** Bash only for now (the user, 2026-10-09): a Python program is called by its entrypoint and speaks through its exit code.

