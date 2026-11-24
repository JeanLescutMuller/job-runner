#!/bin/bash
# job-runner's implementation cost, by the counter of skill code-minimization (~/opt/my-setup/skills/code-minimization/).
# Shared (x1): every file job-runner ships, i.e. its tracked code but its tests, canaries (its own test jobs) and tools/.
# Client (x2, planned: twice as many jobs): every job's entrypoint in its own project (any .sh under ~/dev/*/*/ sourcing
# the library) and the dashboard settings beside it (<entrypoint>.conf).
# Usage: bash tools/token_cost.sh [-v]   (-v: one row per file)
cd "$(dirname "$0")/.." || exit 1
l_ep=$(grep -rlF --include='*.sh' --exclude-dir=.git '. ~/opt/job-runner/lib.sh' ~/dev/*/*/ | grep -v "^$HOME/dev/infra/job-runner/")
exec python3 ~/opt/my-setup/skills/code-minimization/count_cost.py "$@" \
  --shared $(git ls-files -- '*.sh' '*.py' '*.conf' ':!:test/' ':!:canaries/' ':!:tools/' ':!:dashboard/conf/canaries*') \
  --client $l_ep $(for f in $l_ep; do ls "${f%.sh}.conf" 2>/dev/null; done)
