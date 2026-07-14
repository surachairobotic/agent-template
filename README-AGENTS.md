# OpenCode Agent Team

> A multi-agent development team that runs inside OpenCode. PM orchestrates, specialists implement, reviewer validates.

## Quick Start

```powershell
# 1. Copy template to your project
cp -r D:\agent-template\* .\my-project\
cd .\my-project\

# 2. Bootstrap (creates project.md, git, etc.)
.\scripts\agent-bootstrap.ps1

# 3. Start PM agent
opencode run --agent pm
```

## Agent Roles

| Agent | Role | When Active |
|-------|------|-------------|
| **PM** | Project Manager / Orchestrator | Always - main interface |
| **SA** | System Analyst / Architect | After SPEC approved |
| **FE** | Frontend Engineer | After DESIGN ready |
| **BE** | Backend Engineer | After DESIGN ready |
| **DevOps** | Infrastructure / CI/CD | After DESIGN ready |
| **Testing** | QA / Test Engineer | After DESIGN ready |
| **AI** | ML Engineer (CV, NLP, etc.) | If AI tasks in project |
| **Reviewer** | Code Reviewer / Validator | After specialists complete |

## Workflow

```
You <-> PM: Chat, clarify, approve SPEC
         |
         v
      SPEC.md (you approve)
         |
         v
      PM delegates:
      SA -> DESIGN.md
      FE/BE/DevOps/Testing/AI -> parallel implementation
         |
         v
      Reviewer validates (lint, typecheck, test, build + LLM review)
         |
         v
      PASS -> PM presents to you
      FAIL -> Specialist revises (max 3x)
         |
         v
      You accept / request changes -> loop
```

## Memory System (`.opencode/memory/`)

| File | Purpose | Updated By |
|------|---------|------------|
| `project.md` | Stack, conventions, validation rules, active specialists | PM (bootstrap), all agents |
| `decisions.md` | Architecture Decision Records (ADR) | PM, SA |
| `tasks.md` | Task tracking table | PM, all agents |
| `context.md` | Current feature context | PM, all agents |

## Communication (`.agent-comms/`)

```
inbox/pm/       <- Messages for PM
inbox/sa/       <- Messages for SA
inbox/fe/       <- Messages for FE
inbox/be/       <- Messages for BE
inbox/devops/   <- Messages for DevOps
inbox/testing/  <- Messages for Testing
inbox/reviewer/ <- Messages for Reviewer
inbox/ai/       <- Messages for AI
outbox/         <- Completed work notifications
```

Messages are JSON files. Use helper scripts:
```powershell
# Send task to agent
.\scripts\agent-send.ps1 -To fe -TaskId FEAT-001 -Type DELEGATE -Payload '{"spec_path":"SPEC.md","design_path":"DESIGN.md"}'

# Read agent inbox
.\scripts\agent-receive.ps1 -Agent fe

# Show task status
.\scripts\agent-status.ps1
```

## Bootstrap (First Run in New Project)

PM will ask:
1. Project name, description, type
2. Language, framework, build tool, package manager
3. Lint / Format / Typecheck / Test / Build commands
4. Code conventions (naming, imports, components, state, API style)
5. Git conventions (commit style, branch strategy, hooks)
6. Validation: local commands + Docker (optional)
7. Review: max iterations, human approval required?
8. Active specialists (SA always, others optional)
8. AI config (if AI active): framework, task types, GPU, serving
9. Deployment target, environments, IaC tool
10. Analyze existing codebase? (infers conventions)

## Feature Work

```powershell
opencode run --agent pm
# You: "Add user authentication with JWT"
# PM: asks clarifying questions -> writes SPEC.md
# You: "APPROVE"
# PM: delegates -> specialists work -> reviewer validates -> PM presents
# You: "looks good" or "change X"
```

## Commands Reference

| Script | Purpose |
|--------|---------|
| `agent-bootstrap.ps1` | Initialize project from template |
| `agent-send.ps1` | Send message to agent inbox |
| `agent-receive.ps1` | Read/clear agent inbox |
| `agent-status.ps1` | Show task status from tasks.md |

## Customization

- Edit `.opencode/agents/*.md` to change agent prompts
- Edit `.opencode/memory/project.md` to update conventions
- Add new specialists by creating `.opencode/agents/<name>.md` and adding to `project.md` specialists list

## Requirements

- OpenCode CLI
- Git
- PowerShell 5.1+ (Windows) / PowerShell 7+ (cross-platform)
- Project-specific tools (Node, Python, Docker, etc. per project.md)