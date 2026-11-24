#!/bin/sh
# The VM's gate for the job-runner keys: ~/.ssh/authorized_keys runs it as their forced command
# (command="/home/enrices/opt/job-runner/gate.sh",restrict), so whatever a job-runner key asks for, only an operation of
# ops.sh runs, every argument a plain name (letters, digits, . _ -; not . or ..). Anything else is refused. Written by
# install.sh on the VM, with the keys in deploy/keys/.
set -f; set -- $SSH_ORIGINAL_COMMAND
case $1 in put-status | put-log | put-conf | get-statuses | list-logs | claim | release) ;; *) echo "job-runner gate: refused: $1" >&2; exit 2 ;; esac
for a; do case $a in '' | . | .. | *[!A-Za-z0-9._-]*) echo "job-runner gate: refused argument" >&2; exit 2 ;; esac; done
cd ~/opt/job-runner && exec sh ops.sh "$@"
