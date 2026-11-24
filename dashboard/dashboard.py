#!/usr/bin/env python3
"""dashboard.py: job-runner's phone dashboard, on the NAS only (the env NAS; the VM until 2026-11) (DESIGN.md §11).
Each page load reads, under JR_ROOT (default ~/opt/job-runner):
  status/<job>/<machine>.tsv   every machine's statuses (each check copies its whole file here): check id, ts, status, text
  logs/<job>/<machine>/        the failed checks' logs (sent by each check)
  dashboard/conf/*.conf        job-runner's settings: _default.conf, the canaries'
  conf/*.conf                  each job's settings, sent by its project's install.sh (put-conf.sh); a key here beats the same
                               file's key in dashboard/conf/. Read: _default, then <repo>, then <repo>.<job>; KEY@<machine> for one machine
  sync/dashboard/status/       its own copy of job-runner-sync (the env GITHUB), fetched every 10 min, a backup: the statuses of a machine
                               with no file on the NAS is shown from there (GCP: it reports through GitHub only)
  python3 dashboard.py [PORT]    default 8097, on 127.0.0.1 (published on the tailnet by `tailscale serve`). Everything in UTC.
Every 5 min, a job that turned red is a task through `task` (~/dev/agents/tasks, D19): "Job <job> is red" in Personal › Projects - IT
› <repo>, its ALERT setting as cost_if_undone-complete_by (default minor-within_a_day: a Todoist task, a silent pop-up at 18:00
if still red), justified by ALERT_WHY_COST and ALERT_WHY_BY; back from red, `task complete`. Jobs alerted: dashboard-alerts.txt under JR_ROOT.
Each such pass that ends well touches the heartbeat ~/.local/state/heartbeats/job-runner.dashboard (JR_HEARTBEAT): tasks'
alerting service on this machine adds a task when it grows old (~/dev/agents/tasks conf/alerting.toml [heartbeats]; U17 Q8).
"""
import hashlib, html, http.server, operator, os, re, subprocess, sys, threading, time
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(os.environ.get("JR_ROOT", "~/opt/job-runner")).expanduser()
KEYS = {"RED_AFTER_MIN": int, "RED_AFTER_FAILURES": int, "SILENT_AFTER_MIN": int, "TITLE": str, "GROUP": str, "ORDER": int,
        "HISTORY": int, "FOLD": str, "DECOMMISSIONED": int, "ALERT": str, "ALERT_WHY_COST": str, "ALERT_WHY_BY": str}   # a key missing everywhere: 0 or "" (that feature off)
EXECUTED = ("SUCCESS", "FAILURE")
STRIP = {"SUCCESS": "ok", "FAILURE": "bad", "WAIT": "warn"}   # the statuses on a job's strip, and their colour
URL = os.environ.get("JR_GITHUB_URL", "https://github.com/JeanLescutMuller/job-runner-sync.git")


def fetch_github():
    """Every 10 min: the dashboard's own shallow copy of job-runner-sync, in sync/dashboard (the token given to git only)"""
    f_env, d = Path.home() / ".config/job-runner/job-runner-sync.env", str(ROOT / "sync/dashboard")
    git = ["git", "-c", "credential.helper=", "-c", "credential.helper=!f() { echo username=x-access-token; echo \"password=$JR_SYNC_TOKEN\"; }; f"]
    while True:
        # The token: from the environment, else from the line JR_SYNC_TOKEN=… of the file, else none
        token = os.environ.get("JR_SYNC_TOKEN") or (re.findall(r"(?m)^JR_SYNC_TOKEN=(.*)", f_env.read_text() if f_env.exists() else "") + [""])[0].strip()
        l_cmds = ([["-C", d, "fetch", "-q", "--depth", "1", "origin", "main"], ["-C", d, "reset", "-q", "--hard", "FETCH_HEAD"]]
                  if Path(d, ".git").exists() else [["clone", "-q", "--depth", "1", URL, d]])
        for cmd in l_cmds:
            if subprocess.run(git + cmd, env=dict(os.environ, JR_SYNC_TOKEN=token, GIT_TERMINAL_PROMPT="0"), capture_output=True, timeout=60).returncode:
                break   # unreachable: the last copy stays
        time.sleep(600)   # a backup only: every machine but GCP reports to the NAS directly


def read_conf():
    """→ ({file name without .conf: {KEY or KEY@machine: value}}, [problems: "file:line: text"])"""
    d_conf, l_bad = {}, []
    for f in sorted(ROOT.glob("dashboard/conf/*.conf")) + sorted(ROOT.glob("conf/*.conf")):
        d = d_conf.setdefault(f.stem, {})
        if not f.exists():   # a link to a project no longer installed
            l_bad.append(f"{f.relative_to(ROOT)}: links to a missing file"); continue
        for n, line in enumerate(f.read_text(errors="replace").splitlines(), 1):
            if line := re.sub(r"(^|\s)#.*", "", line).strip():   # a comment: '#' at the start of a word
                try:
                    k, v = map(str.strip, line.split("=", 1))   # no "=": ValueError
                    d[k] = KEYS[k.split("@")[0]](v)   # an unknown key: KeyError; a number that is not one: ValueError
                except (KeyError, ValueError):
                    l_bad.append(f"{f.relative_to(ROOT)}:{n}: {line}")
    return d_conf, l_bad


def setting(d_conf, job, key, machine=None):
    """_default, then the repo's file, then the job's: the last value wins; in each, KEY@machine beats KEY"""
    v = KEYS[key]()
    for name in ("_default", job.split(".")[0], job):
        d = d_conf.get(name, {})
        v = d.get(f"{key}@{machine}", d.get(key, v))
    return v


def read_checks(f):
    """A status file → its checks, oldest first: .id, .m (the machine), .start, .ts, .status, .text, a check's status being its last line"""
    d = {}
    for line in f.read_text(errors="replace").splitlines():
        for i, start, ts, status, text in re.findall(r"^(([^\t.]*)[^\t]*)\t(\d+)\t([^\t]*)\t([^\t]*)$", line):   # a malformed line: none; start: the id up to its first '.'
            d[i] = SimpleNamespace(id=i, m=f.stem, start=int(start or 0), ts=int(ts), status=status, text=text)   # keeps its place in d
    return list(d.values())


def dur(s):
    return "<1 min" if s < 60 else f"{s // 60} min" if s < 3600 else f"{s // 3600} h" if s < 86400 else f"{s // 86400} d"


def hm(t):
    return time.strftime("%a %H:%M", time.gmtime(t))   # UTC


def page(l_red=None):
    """The page; l_red, when given, gets (job, ALERT setting, plain text) for every red job."""
    now, e = time.time(), html.escape
    d_conf, l_bad = read_conf()
    d_jobs = {}   # {job: {machine: its checks}}; a machine the NAS has no file of (GCP): from GitHub
    for f in sorted(ROOT.glob("status/*/*.tsv")) + sorted(ROOT.glob("sync/dashboard/status/*/*.tsv")):
        d_jobs.setdefault(f.parent.name, {}).setdefault(f.stem, read_checks(f))

    def since(t, f="{} ago", warn=0):
        # A duration up to now that the browser keeps counting (dur() in the page's script); red after warn seconds
        s = int(now - t)
        text = "just now" if f == "{} ago" and s < 60 else f.format(dur(s))
        # (red only in the browser: the one call with warn is for now)
        return (f'<span class="ago" data-t="{int(t)}" data-f="{e(f)}"'
                + (f' data-warn="{warn}"' if warn else "") + f'>{e(text)}</span>')

    def host(m, n=None):
        # A machine's name in its colour; n: only its first n letters.
        # Same colour as the user's shell prompt and statusline (infra/my-setup/dotfiles/files/get_host_color.sh): an xterm colour,
        x = [25, 27, 33, 39, 45, 51, 50, 44, 57, 63, 99, 129, 135, 141][int(hashlib.sha256(m.encode()).hexdigest()[:8], 16) % 14]
        # then its red, green and blue: each one of the xterm colour cube's 6 levels (0, 95, 135, 175, 215, 255), in hex
        rgb = "".join(f"{(0, 95, 135, 175, 215, 255)[(x - 16) // k % 6]:02x}" for k in (36, 6, 1))
        return f'<span class="host" style="--h:#{rgb}" title="{e(m)}">{e(m[:n])}</span>'

    def span(colour, x):
        return f'<span class="{colour}">{x}</span>'

    def more(text):
        # " · text", when there is one
        return f" · {e(text)}" if text else ""

    def state(s, l_all, l_last):
        # The whole job in a few words, worst first: (colour, icon, html); s: its settings, l_last: each machine's last check
        l_exec = [c for c in l_all if c.status in EXECUTED]
        ok = {c.status: c for c in l_exec}.get("SUCCESS")   # the last Success, or None
        n_ko = len(l_exec) - (l_exec.index(ok) + 1 if ok else 0)   # Failures in a row: the executions after the last Success
        since_ok = ok.ts if ok else l_all[0].start   # never succeeded: counted from its first check
        l_run = [c for c in l_last if c.status == "RUNNING"]
        # A WAIT's end ("SECONDS [all] reason"), or 0: the latest one
        wait = max([c.ts + int(w) for c in l_last if c.status == "WAIT" for w in re.findall(r"^\d+(?= |$)", c.text)], default=0)
        if s.DECOMMISSIONED:
            return "mut", "·", "decommissioned"
        if s.RED_AFTER_MIN and now - since_ok > s.RED_AFTER_MIN * 60:
            return "bad", "✗", since(since_ok, "no Success for {}")
        if s.RED_AFTER_FAILURES and n_ko >= s.RED_AFTER_FAILURES:
            return "bad", "✗", f"{n_ko} Failures in a row, the last " + since(l_exec[-1].ts)
        if l_run:
            return "run", "▶", "running, started " + since(l_run[0].start)
        if n_ko:
            return "warn", "✗", "Failure " + since(l_exec[-1].ts)
        if wait > now:
            return "warn", "⏸", f"waiting until {hm(wait)}"
        if ok:
            return "ok", "✓", "Success " + since(ok.ts)
        return "mut", "·", "no Success yet"

    # Jobs by GROUP (default: the repo), each group and job by ORDER then name; decommissioned ones folded at the bottom.
    # Machines: when each was last heard of; silent when every job it reports is silent for it
    d_heard, d_silent, d_groups, l_gone, n_bad = {}, {}, {}, [], 0
    for job in sorted(d_jobs, key=lambda job: (setting(d_conf, job, "ORDER"), job)):
        d_m = d_jobs[job]
        if not any(d_m.values()):
            continue
        s = SimpleNamespace(**{k: setting(d_conf, job, k) for k in KEYS})   # the job's settings
        # Its card: two short lines (the job; its state and each machine's); tapped: the strip, each machine, the history
        l_all = sorted(sum(d_m.values(), []), key=operator.attrgetter("start", "ts"))
        colour, icon, text = state(s, l_all, [l[-1] for l in d_m.values() if l])
        n_bad += colour == "bad"   # never a decommissioned job ("mut")
        if colour == "bad" and l_red is not None:
            l_red.append((job, s.ALERT or "minor-within_a_day", html.unescape(re.sub(r"<[^>]+>", "", text)),
                          s.ALERT_WHY_COST, s.ALERT_WHY_BY))
        marks = blocks = ""
        for m, l in d_m.items():
            c = l[-1] if l else None   # its last check
            ok, ko = map({x.status: x for x in l}.get, EXECUTED)   # its last Success, its last Failure, or None
            # This machine wrote no status for this job for SILENT_AFTER_MIN (asleep, off or offline: the dashboard cannot tell)
            limit = setting(d_conf, job, "SILENT_AFTER_MIN", m)
            silent = limit and c and now - c.ts > limit * 60
            # One machine on a job's line: its initial, then its own state for this job
            mk_colour, mk_icon, mk_text = (("mut", "◌", f"silent for {dur(int(now - c.ts))}") if silent
                                           else ("run", "▶", "running") if c and c.status == "RUNNING"
                                           else ("bad", "✗", "last execution failed") if ko and (not ok or l.index(ko) > l.index(ok))
                                           else ("ok", "✓", "last execution succeeded") if ok
                                           else ("mut", "–", "never executed here"))
            marks += f'<span class="mk" title="{e(m)}: {mk_text}">{host(m, 1)}{span(mk_colour, mk_icon)}</span>'
            if not c:
                continue
            d_heard[m] = max(d_heard.get(m, 0), c.ts)
            if not s.DECOMMISSIONED:
                d_silent[m] = d_silent.get(m, True) and silent
            # One machine's facts for this job (the lines that apply): its last check, last Success, last Failure (with its log, when on the NAS)
            log = ko and f"{job}/{m}/{ko.id}"   # the last Failure's log: logs/<job>/<machine>/<check id>.log
            l_out = [f'last check {since(c.ts)}: {e(c.status)}{more(c.text)}',
                     ok and ok is not c and span("ok", "last Success " + since(ok.ts)) + more(ok.text),
                     ko and ko is not c and (not ok or ko.ts > ok.ts)
                     and span("bad", "last Failure " + since(ko.ts)) + " · " + e(ko.text),
                     log and (ROOT / f"logs/{log}.log").is_file() and f'<a href="log/{e(log)}">log of the last Failure</a>']
            blocks += f'<div class="mach"><b>{host(m)}</b>' + "".join(f"<div>{x}</div>" for x in l_out if x) + "</div>"
        strip = "".join(f'<i class="{STRIP[c.status]}" title="{hm(c.ts)} {e(c.m)} {c.status}"></i>'
                        for c in [c for c in l_all if c.status in STRIP][-30:])
        # History, newest first: HISTORY rows; a run of FOLD statuses (e.g. SKIP) is one row with its count
        rows = []   # [its newest check, count, (status, machine)]
        for c in reversed(l_all):
            k = c.status, c.m
            if rows and c.status in s.FOLD.split() and rows[-1][2] == k:
                rows[-1][1] += 1
            elif len(rows) == s.HISTORY:
                break
            else:
                rows.append([c, 1, k])
        table = "".join(f'<tr><td>{hm(c.ts)}</td><td>{host(c.m, 1)}</td><td>{e(c.status)}{f" ×{n}" if n > 1 else ""}'
                        f'{more(c.text)}</td></tr>' for c, n, _ in rows)
        (l_gone if s.DECOMMISSIONED else d_groups.setdefault(s.GROUP or job.split(".")[0], [])).append(
            f'<details class="card" id="j-{e(job)}" style="border-left-color:var(--{colour})">'
            f'<summary>{span(colour + " st", icon)}<b>{e(s.TITLE or job)}</b>{span("sub", span(colour, text) + span("marks", marks))}</summary>'
            f'<div class="strip">{strip}</div>{blocks}<details id="h-{e(job)}"><summary>history</summary><table>{table}</table></details></details>')

    machines = "".join(f'<div class="row">{host(m)}' + (span("bad", since(t, "silent for {}")) if d_silent.get(m) else span("mut", "active · " + since(t)))
                       + "</div>" for m, t in sorted(d_heard.items()))
    n_bad += sum(d_silent.values())
    look = " · " + span("bad", f"{n_bad} to look at") if n_bad else ""
    groups = "".join(f'<div class="sec"><h4>{e(g)}</h4></div>' + "".join(l) for g, l in d_groups.items())
    gone = (f'<details class="group gone" id="g-gone"><summary><h4>Decommissioned · {len(l_gone)}</h4></summary>'
            + "".join(l_gone) + "</details>") if l_gone else ""
    bad = "".join(f'<p class="warn">settings: {e(x)}</p>' for x in l_bad)
    return f"""<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Jobs</title><style>
:root{{--bg:#fff;--fg:#111;--mut:#666;--card:#f4f4f6;--ok:#137333;--bad:#c5221f;--warn:#b06000;--run:#1a56db}}
@media (prefers-color-scheme:dark){{:root{{--bg:#111;--fg:#eee;--mut:#999;--card:#1d1d21;--ok:#5bd17a;--bad:#ff6b6b;--warn:#f0a040;--run:#7aa7ff}}}}
*{{box-sizing:border-box}}body{{background:var(--bg);color:var(--fg);font:15px/1.35 system-ui;margin:0 auto;max-width:720px;padding:10px 12px}}
h3{{margin:4px 0 10px}}h4{{display:inline;margin:0;font-size:15px}}.sec{{margin:14px 0 4px}}p{{margin:4px 0}}
.row{{display:flex;justify-content:space-between;gap:8px;padding:3px 0;font-size:14px;white-space:nowrap}}
.card{{background:var(--card);border-radius:8px;border-left:4px solid var(--mut);padding:7px 10px;margin:6px 0}}
.card>summary,.group>summary{{list-style:none;cursor:pointer}}.card>summary::-webkit-details-marker,.group>summary::-webkit-details-marker{{display:none}}
.group>summary::before{{content:"▸ ";color:var(--mut)}}.group[open]>summary::before{{content:"▾ "}}.group{{margin-top:14px}}
.card>summary{{display:grid;grid-template-columns:1.2em 1fr;row-gap:1px}}.card>summary b{{overflow-wrap:anywhere}}
.sub{{grid-column:2;display:flex;justify-content:space-between;gap:8px;font-size:13px}}.marks{{display:flex;gap:8px;white-space:nowrap}}
.host{{color:var(--h);font-weight:600}}@media not (prefers-color-scheme:dark){{.host{{color:color-mix(in srgb,var(--h) 70%,#000)}}}}
.mach{{margin-top:8px;font-size:14px;overflow-wrap:anywhere}}.mach>div{{padding-left:10px}}
.ok{{color:var(--ok)}}.bad{{color:var(--bad)}}.warn{{color:var(--warn)}}.mut{{color:var(--mut)}}.run{{color:var(--run)}}
.strip{{margin:6px 0;line-height:0}}.strip i{{display:inline-block;width:7px;height:14px;margin-right:2px;border-radius:2px;background:currentColor}}
.gone .card{{opacity:.6}}table{{font-size:13px;border-collapse:collapse}}td{{padding:1px 6px 1px 0;vertical-align:top;overflow-wrap:anywhere}}td:first-child{{white-space:nowrap}}a{{color:var(--run)}}
</style></head><body><h3>Jobs · {since(now, "updated {} ago", 180)}{look}</h3>{bad}
<div class="sec"><h4>Machines</h4></div>{machines}
{groups}
{gone}
<script>
// Every 30 s (and when the tab comes back) the page fetches itself and swaps its content: on failure the old content stays and
// "updated … ago" keeps growing, red after 3 min. Every 10 s each duration is recounted from its epoch (data-t), as dur() in Python.
const K = "jr-open";
function dur(s) {{ return s < 60 ? "<1 min" : s < 3600 ? Math.floor(s / 60) + " min" : s < 86400 ? Math.floor(s / 3600) + " h" : Math.floor(s / 86400) + " d"; }}
function tick() {{
  const now = Date.now() / 1000;
  document.querySelectorAll(".ago").forEach(el => {{
    const s = Math.max(0, Math.floor(now - el.dataset.t)), f = el.dataset.f;
    el.textContent = f == "{{}} ago" && s < 60 ? "just now" : f.replace("{{}}", dur(s));
    if (el.dataset.warn) el.classList.toggle("bad", s > +el.dataset.warn);
  }});
}}
function setup() {{  // reopen what was open; remember what gets opened
  let l = [];
  try {{ l = JSON.parse(sessionStorage.getItem(K) || "[]"); }} catch (err) {{}}
  const all = document.querySelectorAll("details[id]");
  all.forEach(d => {{
    d.open = l.includes(d.id);
    d.addEventListener("toggle", () => {{ try {{ sessionStorage.setItem(K, JSON.stringify([...all].filter(x => x.open).map(x => x.id))); }} catch (err) {{}} }});
  }});
  tick();
}}
async function reload() {{
  try {{
    const r = await fetch(location.href, {{cache: "no-store"}});
    if (r.ok) {{ document.body.innerHTML = new DOMParser().parseFromString(await r.text(), "text/html").body.innerHTML; setup(); }}
  }} catch (err) {{}}
}}
setup(); setInterval(tick, 10000); setInterval(reload, 30000);
document.addEventListener("visibilitychange", () => {{ if (!document.hidden) {{ tick(); reload(); }} }});
</script></body></html>"""


ALERT_RE = r"(optional|minor|moderate|major|critical)-(within_the_hour|within_a_day|within_a_week|within_a_month|someday)"


def place(job):
    """Where a red job's task goes: its repo's subsection of Personal › Projects - IT (skill tasks)."""
    return ["--project", "Personal", "--section", "Projects - IT", "--subsection", job.split(".")[0]]


def folder(job):
    """The folder an agent works in on a red job's task: ~/dev/<category>/<repo>; the canaries live in job-runner itself."""
    repo = 'job-runner' if job.split(".")[0] == 'canaries' else job.split(".")[0]
    found = sorted((Path.home() / "dev").glob(f"*/{repo}"))   # ~/dev/<category>/<repo>; not cloned here: the flat name
    return f"~/dev/{found[0].parent.name}/{repo}" if found else f"~/dev/{repo}"


def alert_red(once=False):
    """Every 5 min: a job newly red → `task add "Job <job> is red"` in Personal › Projects - IT › <repo> (its ALERT:
    "<cost_if_undone>-<complete_by>", or "off"); a job no longer red → `task complete` (~/dev/agents/tasks, D19). ~/dev/agents/tasks never
    depends on job-runner (no cycle): only this direction."""
    f_state, task = ROOT / "dashboard-alerts.txt", Path(os.environ.get("JR_TASK", Path.home() / ".local/bin/task"))
    beat = Path(os.environ.get("JR_HEARTBEAT", Path.home() / ".local/state/heartbeats/job-runner.dashboard"))
    while True:
        try:
            l_red = []
            page(l_red)
            s_before = set(f_state.read_text().split()) if f_state.exists() else set()
            s_done = set()
            for job, alert, text, why_cost, why_by in l_red:
                if job in s_before or alert == "off" or not re.fullmatch(ALERT_RE, alert):
                    s_done.add(job) if job in s_before else None
                    continue
                cost, by = alert.split("-")
                r = subprocess.run([str(task), "add", *place(job), "--runs_with_context", folder(job),
                                    "--done_when", f"{job} is green again on job-runner's dashboard (this task then completes "
                                    "by itself), or its ALERT is set to off",
                                    "--cost_if_undone", cost, "--why_cost_if_undone", why_cost or "?",
                                    "--complete_by", by, "--why_complete_by", why_by or "?", "--owner", "claude", "--category", "ops",
                                    "--created_by", "job job-runner.dashboard",
                                    "--description", f"{job} on job-runner's dashboard: {text}", f"Job {job} is red"],
                                   capture_output=True, text=True, timeout=90)
                if r.returncode == 0:
                    s_done.add(job)
                else:
                    print(f"alert for {job} failed: {(r.stderr or r.stdout).strip()[:200]}", file=sys.stderr)
            for job in s_before - {l[0] for l in l_red}:
                if subprocess.run([str(task), "complete", *place(job), f"Job {job} is red"], capture_output=True, timeout=90).returncode:
                    s_done.add(job)   # not resolved yet: try again next time
            f_state.write_text("".join(f"{job}\n" for job in sorted(s_done)))
            beat.parent.mkdir(parents=True, exist_ok=True); beat.touch()   # alive: the pass ended well
        except Exception as ex:   # the dashboard must keep serving
            print(f"alert_red: {type(ex).__name__}: {ex}", file=sys.stderr)
        if once:
            return
        time.sleep(300)


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        p = self.path.strip("/")   # "/" or "/log/<job>/<machine>/<check id>", without the slashes around
        m = re.fullmatch(r"log((/[A-Za-z0-9_.-]+){3})", p)   # job, machine and check names allowed in a URL
        body, ctype, code = ((page().encode(), "text/html; charset=utf-8", 200) if not p
                             else (f_log.read_bytes(), "text/plain; charset=utf-8", 200) if m and (f_log := ROOT / f"logs{m[1]}.log").is_file()
                             else (b"not found", "text/plain", 404))
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", len(body))
        self.end_headers()
        self.wfile.write(body)

    log_message = lambda *args: None   # no access log


if __name__ == "__main__":
    threading.Thread(target=fetch_github, daemon=True).start()
    threading.Thread(target=alert_red, daemon=True).start()
    http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1]) if sys.argv[1:] else 8097), Handler).serve_forever()
