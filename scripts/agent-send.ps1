<#
.SYNOPSIS
    Send a message to an agent's inbox
.DESCRIPTION
    Writes a JSON message to .agent-comms/inbox/<agent>/<task_id>_<timestamp>.json
.PARAMETER To
    Target agent (pm, sa, fe, be, devops, testing, reviewer, ai)
.PARAMETER TaskId
    Task identifier (e.g., FEAT-001)
.PARAMETER Type
    Message type: DELEGATE, REVIEW_REQUEST, FEEDBACK, COMPLETE
.PARAMETER Payload
    JSON string or path to JSON file with message payload
.PARAMETER From
    Sender agent (default: pm)
.EXAMPLE
    .\agent-send.ps1 -To sa -TaskId FEAT-001 -Type DELEGATE -Payload '{"spec_path":"SPEC.md","deliverable":"DESIGN.md"}'
    .\agent-send.ps1 -To reviewer -TaskId FEAT-001 -Type REVIEW_REQUEST -Payload '{"deliverable":"frontend","files":["src/components/Button.tsx"]}'
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("pm","sa","fe","be","devops","testing","reviewer","ai")]
    [string]$To,

    [Parameter(Mandatory=$true)]
    [string]$TaskId,

    [Parameter(Mandatory=$true)]
    [ValidateSet("DELEGATE","REVIEW_REQUEST","FEEDBACK","COMPLETE")]
    [string]$Type,

    [Parameter(Mandatory=$true)]
    [string]$Payload,

    [string]$From = "pm"
)

# Resolve project root (where this script lives)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ProjectRoot = Split-Path -Parent $ScriptDir
$InboxDir = Join-Path $ProjectRoot ".agent-comms\inbox\$To"

if (-not (Test-Path $InboxDir)) {
    New-Item -ItemType Directory -Path $InboxDir -Force | Out-Null
}

# Parse payload (could be JSON string or file path)
if (Test-Path $Payload) {
    $PayloadObj = Get-Content $Payload -Raw | ConvertFrom-Json
} else {
    try {
        $PayloadObj = $Payload | ConvertFrom-Json
    } catch {
        Write-Error "Payload must be valid JSON or path to JSON file"
        exit 1
    }
}

# Build message
$Message = @{
    task_id   = $TaskId
    from      = $From
    to        = $To
    type      = $Type
    payload   = $PayloadObj
    iteration = 1
    timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
}

# Write message file
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$FileName = "${TaskId}_${Timestamp}.json"
$FilePath = Join-Path $InboxDir $FileName

$Message | ConvertTo-Json -Depth 10 | Set-Content -Path $FilePath -Encoding UTF8

Write-Host "[Sent $Type to $To for $TaskId -> $FilePath]"