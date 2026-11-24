#!/usr/bin/env python3
"""The work of canaries.audit, on the NAS (the hub): checks the canaries' promises in every machine's statuses (~/opt/job-runner/status/),
the last 24 h, after data/audit.ack (an epoch). Prints "AUDIT N problems" then one line each; exit 1 if any."""
import collections, os, time
from pathlib import Path

ROOT = Path(os.environ.get("JR_ROOT", Path.home() / "opt/job-runner"))
now = int(time.time())
f_ack = Path("data/audit.ack")
since = max(now - 86400, int(f_ack.read_text().strip() or 0) if f_ack.exists() else 0)
l_problems = []

def checks(job):
    """→ [(machine, check)], by start: check = {start, run (the RUNNING line's ts, or None), end (its last line's ts), status, text}"""
    l = []
    for f in sorted((ROOT / "status" / f"canaries.{job}").glob("*.tsv")):
        d = {}
        for line in f.read_text(errors="replace").splitlines():
            p = line.split("\t")
            if len(p) != 4 or not p[1].isdigit():
                continue
            c = d.setdefault(p[0], {"start": int(p[0].split(".")[0] or 0), "run": None})
            c.update(end=int(p[1]), status=p[2], text=p[3])
            if p[2] == "RUNNING" and c["run"] is None:
                c["run"] = int(p[1])
        l += [(f.stem, c) for c in d.values() if c["end"] >= since]
    return sorted(l, key=lambda mc: mc[1]["start"])

def problem(job, m, c, what):
    l_problems.append(f"{job} {m} {time.strftime('%a %H:%M', time.gmtime(c['start']))}: {what}")

def executions(job):
    return [(m, c) for m, c in checks(job) if c["run"] is not None]

def no_overlap(job, across):
    # Executions never at the same time: on one machine, or (a shared job) on any two machines
    l = executions(job)
    for i, (m, c) in enumerate(l):
        for m2, c2 in l[i + 1:]:
            if (across or m2 == m) and c2["run"] < c["end"]:
                problem(job, m2, c2, f"executed while {m}'s execution was running")

def one_success_per(job, seconds, across):
    d_last = {}
    for m, c in checks(job):
        k = "all" if across else m
        if c["status"] == "SUCCESS":
            if k in d_last and c["end"] - d_last[k] < seconds:
                problem(job, m, c, f"a second Success within {seconds // 60} min")
            d_last[k] = c["end"]

for job in ("shared-nas", "shared-github"):
    no_overlap(job, across=True)
    one_success_per(job, 3600, across=True)
    for m, c in checks(job):   # a "WAIT … all" stops every machine that pulls it until it ends
        w = c["text"].split()
        if c["status"] == "WAIT" and len(w) > 1 and w[0].isdigit() and w[1] == "all":
            for m2, c2 in executions(job):
                if m2 != m and c["end"] < c2["run"] < c["end"] + int(w[0]):
                    problem(job, m2, c2, f"executed during {m}'s WAIT for all machines")
for job in ("daily", "chaos", "timeout", "crash", "long", "hours", "env", "output"):
    no_overlap(job, across=False)
for m, c in checks("daily"):
    if c["status"] == "SUCCESS" and sum(1 for m2, c2 in checks("daily") if m2 == m and c2["status"] == "SUCCESS"
                                        and c2["end"] // 86400 == c["end"] // 86400) > 1:
        problem("daily", m, c, "a second Success the same UTC day")
h = (13, 14, 11, 11, 13, 10, 13)
for m, c in executions("hours"):
    t = time.gmtime(c["run"])
    if t.tm_hour < h[t.tm_wday]:
        problem("hours", m, c, f"executed before {h[t.tm_wday]}:00 UTC")
for job in ("env", "output"):
    for m, c in checks(job):
        if c["status"] == "FAILURE":
            problem(job, m, c, c["text"])
for m, c in checks("timeout"):
    if "LEAK" in c["text"]:
        problem("timeout", m, c, c["text"])
for m, c in executions("sync-down"):
    problem("sync-down", m, c, "executed although its sync env cannot be reached")
for job in ("daily", "chaos", "timeout", "crash", "long", "hours", "env", "output", "shared-nas", "shared-github"):
    d_by_m = collections.defaultdict(list)
    for m, c in checks(job):
        d_by_m[m].append(c)
    for m, l in d_by_m.items():   # a RUNNING not closed although a later check of that machine ran
        for c in l[:-1]:
            if c["status"] == "RUNNING":
                problem(job, m, c, "still RUNNING after a later check: never closed")

print(f"AUDIT {len(l_problems)} problems in the last 24 h" + (" (after the ack)" if since > now - 86400 else ""))
print("\n".join(l_problems))
raise SystemExit(1 if l_problems else 0)
