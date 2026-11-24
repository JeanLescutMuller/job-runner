# Drill

A protocol to prove job-runner in real conditions before a real job moves to it (TODO `B4`): the canaries ([`../canaries/`](../canaries/), every 10 min on the Mac and the VM) while the VM cannot be reached from the Mac for 20 min (two of its rounds). The VM itself is not stopped (it runs other services): while the file `~/opt/job-runner/canaries/data/drill-vm-down` exists on the Mac, the Mac's canary tick ([`../canaries/run.sh`](../canaries/run.sh)) points the canaries at a host that does not exist (`JR_VM_HOST=vm-down.invalid`): the same failure for the library as a VM down or a network cut, for the canaries only. Report: [`../tools/report.sh`](../tools/report.sh) `[HOURS] canaries`.

| # | What (how long) | Expected (pass) |
|---|---|---|
| 0 | Baseline: two ticks | every canary as [`../canaries/`](../canaries/) says; `canaries.audit` 0 problems |
| 1 | `touch ~/opt/job-runner/canaries/data/drill-nas-down` on the Mac (20 min), then `rm` | the Mac: `canaries.shared-nas` skips "cannot sync: NAS unreachable"; its LOCAL canaries go on; `shared-github` goes on (it needs GitHub, not the NAS); the NAS: `shared-vm` goes on alone. After: at the Mac's next check, its whole status files reach the NAS (no line missing for the 20 min) and its failed logs of the 20 min too; audit 0 problems |

## Results
- 2026-10-10 13:51–14:11 UTC, step 1 passed. During the 20 min the VM got nothing new from the Mac's canaries (its last line 13:49); the VM's `shared-vm` went on alone (Success 14:05); the Mac's `shared-github` went on through GitHub. At 14:22, one Mac round after: all 11 of the Mac's canary status files on the VM identical to the Mac's (every line of the 20 min caught up); failed logs all on the VM but one of `canaries.crash`, whose checks after the drill killed themselves on purpose (a killed check sends nothing): the next normal check sends it. The audit (all machines, 24 h): 0 problems.
