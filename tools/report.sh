#!/bin/bash
# Run by hand from ~/dev/infra/job-runner: every job's statuses as the NAS holds them (every machine's), one line per (job, machine):
# its checks in the last N hours by status, then its last check. Usage: tools/report.sh [HOURS=24] [JOB_PREFIX]
# Output: tools/logs/report.log (also printed)
mkdir -p "$(dirname "$0")/logs"; L=$(dirname "$0")/logs/report.log
ssh babisnas "cd ~/opt/job-runner/status && for f in ${2:-}*/*.tsv; do awk -F'\t' -v job=\${f%/*} -v m=\$(basename \$f .tsv) -v t=\$((\$(date +%s) - ${1:-24} * 3600)) '
  { last[\$1] = \$3; text[\$1] = \$4; ts[\$1] = \$2; if (!(\$1 in seen)) { seen[\$1] = 1; order[++n] = \$1 } }
  END { for (i = 1; i <= n; i++) if (ts[order[i]] >= t) c[last[order[i]]]++
        s = \"\"; for (k in c) s = s k \"=\" c[k] \" \"
        k = order[n]; printf \"%-32s %-24s %-40s last %s %s: %s\n\", job, m, s, strftime(\"%H:%M\", ts[k], 1), last[k], substr(text[k], 1, 70) }' \$f; done; ls ~/opt/job-runner/canaries/data/audit.ack 2>/dev/null" 2>/dev/null | tee "$L"
