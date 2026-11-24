#!/bin/bash
# canaries.output (R9, R13): a big, odd output (20 000 lines, a 200 kB line, invalid UTF-8, NUL, HTML): its summary shown escaped
. ~/opt/job-runner/lib.sh
jr_skip_if SUCCESS 21600 "succeeded in the last 6 h"
jr_execute 1 python3 work/output.py
jr_summary_grep '^SUMMARY'
