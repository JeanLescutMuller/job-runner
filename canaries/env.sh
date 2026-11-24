#!/bin/bash
# canaries.env (S3): the work's environment as by hand: PATH with ~/.local/bin, UTF-8, its own folder, no job-runner-sync token
# (a fake one is set here), no terminal
export JR_SYNC_TOKEN=canary-fake-token
. ~/opt/job-runner/lib.sh
jr_skip_if SUCCESS 3600 "succeeded in the last hour"
jr_execute 1 work/env.sh
