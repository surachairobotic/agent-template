# OpenCode Agent Team

> A multi-agent development team that runs inside OpenCode. A Python **orchestrator** activates each role's agent according to a task DAG. Every role owns a `state.json` and reports progress with status flags.

## Quick Start

```powershell
# 1. Copy template to your project
cp -r D:\agent-template\* .\my-project\
cd .\my-project\

# 2. Bootstrap (creates project.md, git, etc.)
.\scripts\agent-bootstrap.ps1

# 3. Define the feature DAG in orchestrator.json (SPEC/DESIGN/tasks)
#    Then run the orchestrator (it activates agents on a timer):
python orchestrator.py
#   or a single scheduling pass then exit:
python orchestrator.py --once
```

## Architecture

```
                 orchestrator.py  (Python timer loop + thread pool)
                          |
          reads/writes .agent-comms/state/<role>.json  (per-role tasks + flags)
                          |
        spawns opencode run --agent <role>  (up to MAX_CONCURRENCY in parallel)
                          |
        +---------+--------+--------+---------+----------+----------+
        |         |        |        |         |          |          |
       pm        sa       fe       be     devops    testing      reviewer   (ai)
        |         |        |        |         |          |          |
     SPEC.md  DESIGN.md  UI    APIs/DB   Docker/CI   tests     REVIEW.md
                          |
                    STATUS.md  (human-readable progress board, regenerated every tick)
```

- **Each role has its own `state.json`** with that role's tasks and a status flag.
- **Status vocabulary:** `pending` · `ready` · `processing` · `done` · `blocker` · `revision`.
- A task becomes `ready` (actionable) only when all its `depends_on` are `done`.
- The orchestrator auto-detects `done` when the task's `deliverable` file exists on disk.
- **PM additionally writes `STATUS.md`** for human viewing.

## Agent Roles

| Agent | Role | Activated when |
|-------|------|----------------|
| **PM** | Project Manager / Planner | First - writes SPEC.md + STATUS.md |
| **SA** | System Analyst / Architect | After SPEC.md ready |
| **FE** | Frontend Engineer | After DESIGN.md ready |
| **BE** | Backend Engineer | After DESIGN.md ready |
| **DevOps** | Infrastructure / CI/CD | After DESIGN.md ready |
| **Testing** | QA / Test Engineer | After DESIGN.md ready |
| **AI** | ML Engineer (CV, NLP, etc.) | If AI tasks in DAG |
| **Reviewer** | Code Reviewer / Validator | After specialists complete |

All agents are `mode: primary` so the orchestrator can run them directly with
`opencode run --agent <role> --auto -m opencode/nemotron-3-ultra-free`.

## How an agent works (state-driven)

When the orchestrator activates a role, that agent:
1. Reads `.agent-comms/state/<role>.json`.
2. For each task whose `status` is `pending`/`ready` and whose `depends_on` are all `done`:
   a. Sets `status` = `processing`, `updated_at` = now. Saves the JSON.
   b. Does the work described in `details` (reads SPEC.md / DESIGN.md / project.md).
   c. On success sets `status` = `done` with a short `notes` summary, or `blocker` if stuck.
3. Exits when no actionable task remains. PM also writes `STATUS.md`.

If an agent is interrupted mid-`processing`, the orchestrator re-activates the
role on the next tick (resume) instead of leaving it stuck.

## The DAG (`orchestrator.json`)

Tasks are defined in `orchestrator.json` at the project root:

```json
{
  "feature": "Kiosk Feature",
  "tasks": [
    {"id":"T01","owner":"pm","title":"SPEC.md","status":"pending","depends_on":[],
     "deliverable":"SPEC.md","details":"Write SPEC.md ..."},
    {"id":"T02","owner":"sa","title":"DESIGN.md","status":"pending","depends_on":["T01"],
     "deliverable":"DESIGN.md","details":"Write DESIGN.md from SPEC.md ..."}
  ]
}
```

The orchestrator loads this on start and seeds each role's `state.json`
(preserving any status/notes already on disk).

## Tuning (`orchestrator.py` constants)

| Constant | Default | Meaning |
|----------|---------|---------|
| `POLL_INTERVAL` | `5` | Seconds between scheduler ticks |
| `MAX_CONCURRENCY` | `2` | Max simultaneous opencode agent processes |
| `STALE_TIMEOUT` | `600` | Seconds before a stuck `processing` task is marked `blocker` |
| `MODEL` | `opencode/nemotron-3-ultra-free` | Model forced on every spawned agent |

## Communication

State lives in `.agent-comms/state/<role>.json` (machine-readable, one per role).
For humans, the orchestrator regenerates `STATUS.md` every tick:

```
# Agent Status
Updated: 2026-07-14T20:31:05
| ID | Task | Owner | Status | Deliverable | Notes |
|----|------|-------|--------|-------------|-------|
| T01 | SPEC.md | pm | done | SPEC.md | |
| T02 | DESIGN.md | sa | done | DESIGN.md | |
...
```

> Legacy `.agent-comms/inbox`/`outbox` JSON messaging and the `agent-send.ps1` /
> `agent-receive.ps1` / `agent-status.ps1` helpers are retained for reference but
> are not used by the orchestrator.

## Bootstrap (First Run in New Project)

PM (when activated with no `project.md`) asks:
1. Project name, description, type
2. Language, framework, build tool, package manager
3. Lint / Format / Typecheck / Test / Build commands
4. Code conventions (naming, imports, components, state, API style)
5. Git conventions (commit style, branch strategy, hooks)
6. Validation: local commands + Docker (optional)
7. Review: max iterations, human approval required?
8. Active specialists (SA always, others optional)
9. AI config (if AI active): framework, task types, GPU, serving
10. Deployment target, environments, IaC tool
11. Analyze existing codebase? (infers conventions)

## Feature Work

```powershell
python orchestrator.py
# Orchestrator: seeds state.json -> activates pm (SPEC.md)
#   -> activates sa (DESIGN.md) -> activates fe/be/devops/testing in parallel
#   -> activates reviewer (REVIEW.md) -> exits when all done/blocker
# Watch progress in STATUS.md.
```

## Commands Reference

| Script / Command | Purpose |
|------------------|---------|
| `python orchestrator.py` | Run the agent orchestrator (timer loop) |
| `python orchestrator.py --once` | Single scheduling pass, then wait for agents and exit |
| `orchestrator.json` | Task DAG consumed by the orchestrator |
| `agent-bootstrap.ps1` | Initialize a new project from this template |
| `agent-send.ps1` / `agent-receive.ps1` / `agent-status.ps1` | Legacy inbox helpers (reference only) |

## Customization

- Edit `.opencode/agents/*.md` to change agent prompts.
- Edit `orchestrator.json` to change the task DAG.
- Edit `orchestrator.py` constants to tune concurrency / timing / model.
- Add new specialists by creating `.opencode/agents/<name>.md` (set `mode: primary`)
  and adding tasks owned by that role to `orchestrator.json`.

## Requirements

- OpenCode CLI (on PATH, e.g. `opencode.cmd`)
- Python 3.10+
- Git
- Project-specific tools (Node, Python, Docker, etc. per project.md)
