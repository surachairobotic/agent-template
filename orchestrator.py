#!/usr/bin/env python3
"""
Agent Orchestrator
==================
Timer-driven controller that activates opencode agents according to a task DAG.

Design
------
- Each role owns its own state file: `.agent-comms/state/<role>.json`
  containing that role's tasks and their status flags.
- Status vocabulary: pending | ready | processing | done | blocker | revision
- A Python timer loop (POLL_INTERVAL) evaluates which roles are "ready"
  (all dependencies done) and spawns them via `opencode run --agent <role>`,
  up to MAX_CONCURRENCY parallel processes.
- When activated, an agent reads its own state file, sets `processing`,
  does the work, then sets `done` (or `blocker`), writing a `notes` summary.
- PM additionally writes STATUS.md for human viewing.
- The orchestrator regenerates STATUS.md every tick so a human can watch progress.

Run
---
    python orchestrator.py            # normal run
    python orchestrator.py --once     # single scheduling pass then exit
    Ctrl-C                            # graceful stop

Config
------
Task DAG is loaded from `orchestrator.json` in the project root on first run.
If absent, an embedded default DAG is used.
"""
import json
import time
import subprocess
import threading
import datetime
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent
STATE_DIR = ROOT / ".agent-comms" / "state"
STATUS_MD = ROOT / "STATUS.md"

POLL_INTERVAL = 5          # seconds between scheduler ticks
MAX_CONCURRENCY = 2        # max simultaneous opencode agent processes
STALE_TIMEOUT = 600        # seconds before a stuck 'processing' task -> 'blocker'

ROLES = ["pm", "sa", "fe", "be", "devops", "testing", "reviewer", "ai"]

LOCK = threading.Lock()
running = {}               # role -> threading.Thread


def now_iso():
    return datetime.datetime.now().isoformat(timespec="seconds")


# ---------------------------------------------------------------------------
# State I/O
# ---------------------------------------------------------------------------
def load_role(role):
    p = STATE_DIR / f"{role}.json"
    if p.exists():
        try:
            return json.loads(p.read_text(encoding="utf-8"))
        except Exception:
            return {"role": role, "tasks": []}
    return {"role": role, "tasks": []}


def save_role(role, data):
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    (STATE_DIR / f"{role}.json").write_text(
        json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8"
    )


def all_tasks():
    """Merge every role's tasks into a dict keyed by task id."""
    tasks = {}
    for role in ROLES:
        for t in load_role(role).get("tasks", []):
            tasks[t["id"]] = t
    return tasks


def persist_tasks(tasks):
    """Write an in-memory task dict back to per-role state files (no disk re-read)."""
    by_role = {r: {"role": r, "tasks": []} for r in ROLES}
    for t in tasks.values():
        owner = t.get("owner")
        if owner in by_role:
            by_role[owner]["tasks"].append(t)
    for r, d in by_role.items():
        if d["tasks"]:
            save_role(r, d)


def deliverable_exists(task):
    d = task.get("deliverable")
    if not d:
        return False
    return (ROOT / d).exists()


# ---------------------------------------------------------------------------
# DAG / init
# ---------------------------------------------------------------------------
def default_dag():
    """Fallback DAG if orchestrator.json is missing."""
    return {
        "feature": "Default Feature",
        "tasks": [
            {"id": "T01", "owner": "pm", "title": "SPEC.md",
             "status": "pending", "depends_on": [], "deliverable": "SPEC.md",
             "details": "Create SPEC.md with goals, scope, acceptance criteria."},
            {"id": "T02", "owner": "sa", "title": "DESIGN.md",
             "status": "pending", "depends_on": ["T01"], "deliverable": "DESIGN.md",
             "details": "Write DESIGN.md from SPEC.md."},
        ],
    }


def init_state_from_config():
    cfg_path = ROOT / "orchestrator.json"
    data = (
        json.loads(cfg_path.read_text(encoding="utf-8"))
        if cfg_path.exists()
        else default_dag()
    )

    by_role = {r: {"role": r, "tasks": []} for r in ROLES}
    for t in data.get("tasks", []):
        owner = t.get("owner")
        if owner in by_role:
            by_role[owner]["tasks"].append(t)

    for role, d in by_role.items():
        if not d["tasks"]:
            continue
        existing = load_role(role)
        emap = {t["id"]: t for t in existing.get("tasks", [])}
        for t in d["tasks"]:
            # preserve any status/notes already on disk
            if t["id"] in emap:
                t["status"] = emap[t["id"]].get("status", t.get("status", "pending"))
                t["notes"] = emap[t["id"]].get("notes", "")
            t.setdefault("status", "pending")
            t.setdefault("notes", "")
        save_role(role, d)

    # auto-detect 'done' when the deliverable file already exists
    tasks = all_tasks()
    for t in tasks.values():
        if t.get("status") != "done" and deliverable_exists(t):
            t["status"] = "done"
            t["notes"] = (t.get("notes") or "") + " [auto-detected: deliverable exists]"
    persist_tasks(tasks)


# ---------------------------------------------------------------------------
# Scheduling helpers
# ---------------------------------------------------------------------------
def deps_done(task, tasks):
    for d in task.get("depends_on", []):
        t = tasks.get(d)
        if not t or t.get("status") != "done":
            return False
    return True


def ready_roles(tasks):
    """Roles that have at least one actionable task.

    A task is actionable when its deps are all done and its status is
    pending / ready, OR processing while that role's agent is NOT currently
    running (a crashed/interrupted run we should resume).
    """
    running_roles = set(running.keys())
    out = []
    for role in ROLES:
        for t in load_role(role).get("tasks", []):
            st = t.get("status")
            if st == "processing":
                actionable = role not in running_roles
            else:
                actionable = st in ("pending", "ready")
            if actionable and deps_done(t, tasks):
                out.append(role)
                break
    return out


def detect_stale(tasks):
    """Mark 'processing' tasks whose agent is no longer running as 'blocker'."""
    changed = False
    with LOCK:
        running_roles = set(running.keys())
    for tid, t in tasks.items():
        if t.get("status") == "processing" and t.get("owner") not in running_roles:
            upd = t.get("updated_at")
            try:
                ts = datetime.datetime.fromisoformat(upd) if upd else None
            except Exception:
                ts = None
            if ts is None or (now_iso_utc()- ts).total_seconds() > STALE_TIMEOUT:
                t["status"] = "blocker"
                t["notes"] = (t.get("notes") or "") + " [stale: agent did not report completion]"
                changed = True
    return changed


def now_iso_utc():
    return datetime.datetime.now()


# ---------------------------------------------------------------------------
# Agent activation
# ---------------------------------------------------------------------------
def build_message(role):
    return (
        f"You are activated by the orchestrator. "
        f"Read .agent-comms/state/{role}.json. "
        f"Process every task whose status is 'pending' or 'ready' AND whose depends_on "
        f"are all marked 'done'. For each such task: set status='processing' (save the JSON), "
        f"do the work described in its 'details' (read SPEC.md and DESIGN.md as needed, "
        f"follow your system instructions), then set status='done' with a short 'notes' "
        f"summary, or 'blocker' if you cannot proceed. Always save the JSON after each "
        f"status change and update 'updated_at'. When no actionable task remains, finish."
    )


MODEL = "opencode/nemotron-3-ultra-free"


def find_opencode():
    """Locate the opencode executable (it ships as a .cmd/.ps1 shim on Windows)."""
    import shutil
    for cand in ("opencode.cmd", "opencode.exe", "opencode"):
        p = shutil.which(cand)
        if p:
            return p
    # fallback: common install location
    guess = pathlib.Path.home() / "AppData/Local/hermes/node/opencode.cmd"
    if guess.exists():
        return str(guess)
    raise RuntimeError("opencode executable not found on PATH")


def spawn_agent(role):
    msg = build_message(role)
    return subprocess.Popen(
        [find_opencode(), "run", "--agent", role, "--auto", "-m", MODEL, msg],
        cwd=str(ROOT),
    )


def role_worker(role):
    try:
        proc = spawn_agent(role)
        proc.wait()
    finally:
        with LOCK:
            running.pop(role, None)


# ---------------------------------------------------------------------------
# Human-readable status
# ---------------------------------------------------------------------------
def generate_status_md():
    tasks = all_tasks()
    lines = [
        "# Agent Status",
        "",
        f"Updated: {now_iso()}",
        "",
        "| ID | Task | Owner | Status | Deliverable | Notes |",
        "|----|------|-------|--------|-------------|-------|",
    ]
    for tid, t in sorted(tasks.items()):
        note = (t.get("notes") or "").replace("\n", " ").strip()
        if len(note) > 60:
            note = note[:57] + "..."
        lines.append(
            f"| {tid} | {t.get('title','')} | {t.get('owner','')} | "
            f"{t.get('status','')} | {t.get('deliverable','')} | {note} |"
        )
    STATUS_MD.write_text("\n".join(lines) + "\n", encoding="utf-8")


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
def main():
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    init_state_from_config()
    generate_status_md()

    print(f"[orchestrator] started | poll={POLL_INTERVAL}s max_concurrency={MAX_CONCURRENCY}")
    print(f"[orchestrator] state dir: {STATE_DIR}")

    once = "--once" in sys.argv
    scheduled_once = False

    try:
        while True:
            with LOCK:
                running_roles = set(running.keys())

            if running_roles:
                # wait for in-flight agents, then re-evaluate
                time.sleep(POLL_INTERVAL)
                continue

            # nothing running -> decide whether to exit (--once mode)
            if once and scheduled_once:
                break

            tasks = all_tasks()

            # auto-detect done via deliverable existence
            changed = False
            for t in tasks.values():
                if t.get("status") not in ("done", "blocker") and deliverable_exists(t):
                    t["status"] = "done"
                    t["notes"] = (t.get("notes") or "") + " [auto-detected: deliverable exists]"
                    changed = True
            if changed:
                persist_tasks(tasks)

            if detect_stale(tasks):
                persist_tasks(tasks)

            ready = ready_roles(tasks)

            for role in ready[:MAX_CONCURRENCY]:
                print(f"[orchestrator] -> activating {role}")
                th = threading.Thread(target=role_worker, args=(role,), daemon=True)
                with LOCK:
                    running[role] = th
                th.start()

            generate_status_md()
            scheduled_once = True

            if tasks and all(
                t.get("status") in ("done", "blocker") for t in tasks.values()
            ):
                print("[orchestrator] all tasks done or blocked. Exiting.")
                break

            if once:
                # let the batch we just launched finish, then exit
                time.sleep(POLL_INTERVAL)
                continue

            time.sleep(POLL_INTERVAL)
    except KeyboardInterrupt:
        print("\n[orchestrator] interrupted by user")
    finally:
        generate_status_md()
        print("[orchestrator] final STATUS.md written")


if __name__ == "__main__":
    main()
