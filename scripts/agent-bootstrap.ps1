<#
.SYNOPSIS
    Bootstrap a new project with agent team
.DESCRIPTION
    Initializes .opencode/memory/project.md from template, creates git repo, scaffolds base files.
    Run this once per new project, then use `opencode run --agent pm` to start.
.PARAMETER ProjectRoot
    Target project directory (default: current directory)
.PARAMETER Force
    Overwrite existing files
.EXAMPLE
    .\agent-bootstrap.ps1
    .\agent-bootstrap.ps1 -ProjectRoot "D:\my-new-project"
    .\agent-bootstrap.ps1 -Force
#>

param(
    [string]$ProjectRoot = (Get-Location).Path,
    [switch]$Force
)

$TemplateRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Definition)
$ProjectRoot = Resolve-Path $ProjectRoot

Write-Host "Bootstrapping agent team in $ProjectRoot" -ForegroundColor Green

# Create directory structure
$Dirs = @(
    ".opencode\agents",
    ".opencode\memory",
    ".agent-comms\inbox\pm",
    ".agent-comms\inbox\sa",
    ".agent-comms\inbox\fe",
    ".agent-comms\inbox\be",
    ".agent-comms\inbox\devops",
    ".agent-comms\inbox\testing",
    ".agent-comms\inbox\reviewer",
    ".agent-comms\inbox\ai",
    ".agent-comms\outbox",
    ".agent-comms\state",
    "scripts"
)

foreach ($Dir in $Dirs) {
    $Path = Join-Path $ProjectRoot $Dir
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Host "  Created $Dir"
    }
}

# Copy agent YAMLs
$Agents = @("pm","sa","fe","be","devops","testing","reviewer","ai")
foreach ($Agent in $Agents) {
    $Src = Join-Path $TemplateRoot ".opencode\agents\$Agent.md"
    $Dst = Join-Path $ProjectRoot ".opencode\agents\$Agent.md"
    if (Test-Path $Src) {
        if ($Force -or -not (Test-Path $Dst)) {
            Copy-Item $Src $Dst -Force
            Write-Host "  Copied $Agent.md"
        }
    } else {
        Write-Warning "  Template not found: $Src"
    }
}

# Copy memory templates to actual files (if not exist)
$Templates = @{
    "project.md.template"  = "project.md"
    "decisions.md.template" = "decisions.md"
    "tasks.md.template"     = "tasks.md"
    "context.md.template"   = "context.md"
}

foreach ($Key in $Templates.Keys) {
    $Src = Join-Path $TemplateRoot ".opencode\memory\$Key"
    $Dst = Join-Path $ProjectRoot ".opencode\memory\$($Templates[$Key])"
    if (Test-Path $Src) {
        if ($Force -or -not (Test-Path $Dst)) {
            Copy-Item $Src $Dst -Force
            Write-Host "  Created $($Templates[$Key]) from template"
        }
    }
}

# Copy scripts
$Scripts = @("agent-send.ps1","agent-receive.ps1","agent-status.ps1","agent-bootstrap.ps1")
foreach ($Script in $Scripts) {
    $Src = Join-Path $TemplateRoot "scripts\$Script"
    $Dst = Join-Path $ProjectRoot "scripts\$Script"
    if (Test-Path $Src) {
        if ($Force -or -not (Test-Path $Dst)) {
            Copy-Item $Src $Dst -Force
            Write-Host "  Copied $Script"
        }
    }
}

# Copy orchestrator (Python scheduler) + sample DAG
$OrchestratorFiles = @("orchestrator.py", "orchestrator.json")
foreach ($File in $OrchestratorFiles) {
    $Src = Join-Path $TemplateRoot $File
    $Dst = Join-Path $ProjectRoot $File
    if (Test-Path $Src) {
        if ($Force -or -not (Test-Path $Dst)) {
            Copy-Item $Src $Dst -Force
            Write-Host "  Copied $File"
        }
    }
}

# Initialize git if not exists
$GitDir = Join-Path $ProjectRoot ".git"
if (-not (Test-Path $GitDir)) {
    Write-Host "`nInitializing git repository..." -ForegroundColor Cyan
    git init | Out-Null
    Write-Host "  Git initialized"
} else {
    Write-Host "`nGit already initialized" -ForegroundColor Cyan
}

# Create .gitignore if not exists
$Gitignore = Join-Path $ProjectRoot ".gitignore"
$GitignoreLines = @(
    "# Agent system",
    ".agent-comms/",
    "*.log",
    "",
    "# OS",
    ".DS_Store",
    "Thumbs.db",
    "",
    "# IDE",
    ".vscode/",
    ".idea/",
    "*.swp",
    "*.swo",
    "",
    "# Node",
    "node_modules/",
    "dist/",
    "build/",
    "*.tsbuildinfo",
    "",
    "# Python",
    "__pycache__/",
    "*.pyc",
    "*.pyo",
    ".pytest_cache/",
    ".venv/",
    "venv/",
    "*.egg-info/",
    "",
    "# Docker",
    ".docker/",
    "",
    "# Environment",
    ".env",
    ".env.local",
    ".env.*.local",
    "",
    "# IDE / Editor",
    ".cursor/",
    "# .opencode/ (keep agents/ and memory/)"
)

if (-not (Test-Path $Gitignore)) {
    $GitignoreLines -join "`n" | Set-Content -Path $Gitignore -Encoding UTF8
    Write-Host "  Created .gitignore"
}

# Create README-AGENTS.md if not exists
$ReadmeDst = Join-Path $ProjectRoot "README-AGENTS.md"
$ReadmeSrc = Join-Path $TemplateRoot "README-AGENTS.md"
if (Test-Path $ReadmeSrc) {
    if ($Force -or -not (Test-Path $ReadmeDst)) {
        Copy-Item $ReadmeSrc $ReadmeDst -Force
        Write-Host "  Copied README-AGENTS.md"
    }
}

# Initial commit
Write-Host "`nCreating initial commit..." -ForegroundColor Cyan
git add .opencode/ scripts/ .gitignore README-AGENTS.md orchestrator.py orchestrator.json 2>$null
git commit -m "chore: bootstrap agent team" --no-verify 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "  Initial commit created"
} else {
    Write-Host "  No changes to commit (already committed or empty)"
}

Write-Host "`nBootstrap complete!" -ForegroundColor Green
Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "  1. cd $ProjectRoot"
Write-Host "  2. Edit orchestrator.json to define your feature DAG"
Write-Host "  3. python orchestrator.py        # run the agent orchestrator"
Write-Host "     python orchestrator.py --once # single pass"
Write-Host "  4. Watch progress in STATUS.md"
Write-Host ""