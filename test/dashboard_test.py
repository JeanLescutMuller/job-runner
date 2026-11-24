#!/usr/bin/env python3
"""Tests dashboard/dashboard.py on a fake ~/opt/job-runner. Usage: python3 test/dashboard_test.py > log 2>&1 (PASS/FAIL lines)"""
import importlib.util, os, pathlib, sys, tempfile, threading, time, urllib.request, urllib.error

root = pathlib.Path(tempfile.mkdtemp()); os.environ["JR_ROOT"] = str(root)
spec = importlib.util.spec_from_file_location("dashboard", pathlib.Path(__file__).parent.parent / "dashboard/dashboard.py")
D = importlib.util.module_from_spec(spec); spec.loader.exec_module(D)
now = int(time.time()); P = F = 0

def ok(name, got, want=True):
    global P, F
    if got == want: P += 1; print("PASS", name)
    else: F += 1; print(f"FAIL {name}: got {got!r}, want {want!r}")

def status(job, machine, *l_lines):
    # Each line: (seconds ago the check started, seconds ago written, STATUS, text); pid 1 for all
    f = root / "status" / job / f"{machine}.tsv"; f.parent.mkdir(parents=True, exist_ok=True)
    with f.open("a") as w:
        for start, ts, st, text in l_lines: w.write(f"{now - start}.1\t{now - ts}\t{st}\t{text}\n")

def conf(name, text):
    f = root / "dashboard/conf" / f"{name}.conf"; f.parent.mkdir(parents=True, exist_ok=True); f.write_text(text)

def card(html, job):
    # The job's card, up to the next one
    i = html.index(f'id="j-{job}"'); j = html.find('<details class="card"', i + 1)
    return html[i:j if j > 0 else len(html)]

conf("_default", "RED_AFTER_MIN=1560\nRED_AFTER_FAILURES=3\nSILENT_AFTER_MIN=1560\nSILENT_AFTER_MIN@mac=2880   # the Mac sleeps\n"
     "TITLE=\nGROUP=\nORDER=50\nHISTORY=20\nFOLD=SKIP\nDECOMMISSIONED=0\nALERT=minor-within_a_day\n"
     "ALERT_WHY_COST=while red it does nothing\nALERT_WHY_BY=a red job misses a run a day\n")
status("good", "mac", (600, 590, "RUNNING", ""), (600, 500, "SUCCESS", "3 sent"))
status("late", "vm", (100000, 99990, "SUCCESS", "old"), (60, 50, "SKIP", "too early"))
status("broken", "vm", *[(t, t - 10, "FAILURE", f"exit 1: boom {t}") for t in (3000, 2000, 1000)])
(root / "logs/broken/vm").mkdir(parents=True); (root / "logs/broken/vm" / f"{now - 1000}.1.log").write_text("boom\n")
status("busy", "vm", (300, 290, "RUNNING", ""))
status("waits", "mac", (600, 500, "SUCCESS", ""), (120, 110, "WAIT", "3600 all 429 Retry-After"))
status("asleep", "gcp", (200000, 199990, "SUCCESS", ""))
conf("asleep", "RED_AFTER_MIN=0\n")
status("skippy", "mac", (900, 890, "SUCCESS", ""), *[(t, t - 1, "SKIP", "quota fresh enough") for t in (500, 400, 300, 200, 100)])
conf("skippy", "TITLE=Skippy the job\nGROUP=tracker\n")
f = root / "conf/skippy.conf"; f.parent.mkdir(); f.write_text("TITLE=Skippy from its project\n")   # sent by put-conf.sh
(root / "conf/gone.conf").symlink_to(root / "nowhere/gone.conf")   # its project uninstalled
status("old", "mac", (900000, 899990, "FAILURE", "exit 1"))
conf("old", "DECOMMISSIONED=1\n")
conf("bad", "NOPE=1\nORDER=x\n")
g = root / "sync/dashboard/status/good/cloud.tsv"; g.parent.mkdir(parents=True); g.write_text(f"{now - 300}.1\t{now - 200}\tSUCCESS\tfrom GitHub\n")
g2 = root / "sync/dashboard/status/good/mac.tsv"; g2.write_text(f"{now - 300}.1\t{now - 200}\tFAILURE\tstale copy\n")
h = D.page()

ok("1 a success: green, its summary", "Success" in card(h, "good") and "3 sent" in card(h, "good") and "var(--ok)" in card(h, "good"))
ok("2 no success for RED_AFTER_MIN: red", "no Success for" in card(h, "late") and "var(--bad)" in card(h, "late"))
ok("3 3 failures in a row: red, with the log link", "3 Failures in a row" in card(h, "broken") and f'log/broken/vm/{now - 1000}.1' in card(h, "broken"))
ok("4 running", "running, started" in card(h, "busy"))
ok("5 a pending WAIT", "waiting until" in card(h, "waits"))
ok("6 silent: the machine and its mark", "silent for" in card(h, "asleep") and 'title="gcp">gcp</span><span class="bad">' in h and "gcp: silent for" in card(h, "asleep"))
ok("7 RED_AFTER_MIN=0 in a job's file: never red for that", "var(--bad)" not in card(h, "asleep"))
ok("8b a link to a missing file: shown, the page still works", "settings: conf/gone.conf: links to a missing file" in h)
ok("8 a settings mistake shown, file and line", "settings: dashboard/conf/bad.conf:1: NOPE=1" in h and "settings: dashboard/conf/bad.conf:2: ORDER=x" in h)
ok("9 KEY@machine: the Mac sleeps 2 days before silent", D.setting(D.read_conf()[0], "x", "SILENT_AFTER_MIN", "mac") == 2880
   and D.setting(D.read_conf()[0], "x", "SILENT_AFTER_MIN", "vm") == 1560)
ok("10 decommissioned: folded at the bottom, not to look at", h.index("Decommissioned · 1") < h.index('id="j-old"'))
ok("11 FOLD: 5 SKIPs in a row are one history row", "SKIP ×5" in card(h, "skippy"))
ok("12 TITLE and GROUP; conf/ beats dashboard/conf/ key by key", "Skippy from its project" in card(h, "skippy") and "<h4>tracker</h4>" in h)
ok("13 to look at: late, broken, the silent gcp", "3 to look at" in h)

ok("17 a machine only on GitHub (cloud) is shown; the VM's own file wins", "from GitHub" in card(h, "good") and "stale copy" not in card(h, "good"))

srv = D.http.server.ThreadingHTTPServer(("127.0.0.1", 0), D.Handler); threading.Thread(target=srv.serve_forever, daemon=True).start()
url = f"http://127.0.0.1:{srv.server_port}"
def get(path):
    try: return urllib.request.urlopen(url + path).read().decode()
    except urllib.error.HTTPError as err: return err.code
ok("14 the page over HTTP", "<title>Jobs</title>" in get("/"))
ok("15 a failed log over HTTP", get(f"/log/broken/vm/{now - 1000}.1"), "boom\n")
ok("16 no path outside logs/", get("/log/../status/x"), 404)
# A red job → one task through `task` (~/dev/agents/tasks, D19); back from red → completed
fake = root / "fake-task"; calls = root / "task-calls.txt"
fake.write_text(f'#!/bin/bash\necho "$*" >> {calls}\n'); fake.chmod(0o755); os.environ["JR_TASK"] = str(fake)
beat = root / "heartbeats/job-runner.dashboard"; os.environ["JR_HEARTBEAT"] = str(beat)
D.alert_red(once=True); l_calls = calls.read_text().splitlines()
ok("21 a pass that ended well touches the heartbeat (U17 Q8: tasks' alerting watches it)", beat.exists() and time.time() - beat.stat().st_mtime < 60)
ok("18 one task per red job, minor-within_a_day by default", sorted(c.rsplit(" Job ", 1)[1] for c in l_calls), ["broken is red", "late is red"])
ok("18b cost_if_undone and complete_by from ALERT, each with its why", all(
    " --cost_if_undone minor --why_cost_if_undone while red " in c and " --complete_by within_a_day --why_complete_by a red " in c
    and " --done_when " in c for c in l_calls))
ok("18c the agent works in ~/dev/<category>/<repo>; the canaries in job-runner", (all(" --runs_with_context ~/dev/broken " in c or
    " --runs_with_context ~/dev/late " in c for c in l_calls), D.folder("canaries.audit")), (True, "~/dev/infra/job-runner" if (pathlib.Path.home() / "dev/infra/job-runner").is_dir() else "~/dev/job-runner"))
D.alert_red(once=True)
ok("19 still red: no new alert", len(calls.read_text().splitlines()), 2)
status("broken", "vm", (50, 40, "SUCCESS", "fixed"))
D.alert_red(once=True)
ok("20 back from red: completed", calls.read_text().splitlines()[-1],
   "complete --project Personal --section Projects - IT --subsection broken Job broken is red")
print(f"== {P} PASS, {F} FAIL")
