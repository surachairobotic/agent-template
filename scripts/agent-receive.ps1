<#
.SYNOPSIS
    Read and clear messages from an agent's inbox
.DESCRIPTION
    Reads all JSON messages from .agent-comms/inbox/<agent>/, outputs them, and optionally clears them.
.PARAMETER Agent
    Agent name (pm, sa, fe, be, devops, testing, reviewer, ai)
.PARAMETER Clear
    If set, deletes messages after reading
.PARAMETER TaskId
    Optional filter by task ID prefix
.EXAMPLE
    .\agent-receive.ps1 -Agent fe
    .\agent-receive.ps1 -Agent sa -Clear
    .\agent-receive.ps1 -Agent pm -TaskId FEAT-001
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("pm","sa","fe","be","devops","testing","reviewer","ai")]
    [string]$Agent,

    [switch]$Clear,

    [string]$TaskId
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ProjectRoot = Split-Path -Parent $ScriptDir
$InboxDir = Join-Path $ProjectRoot ".agent-comms\inbox\$Agent"

if (-not (Test-Path $InboxDir)) {
    Write-Host "[No messages for $Agent]"
    exit 0
}

$Files = Get-ChildItem -Path $InboxDir -Filter "*.json" | Sort-Object LastWriteTime

if ($TaskId) {
    $Files = $Files | Where-Object { $_.Name.StartsWith($TaskId) }
}

if (-not $Files) {
    $Msg = "[No messages for $Agent]"
    if ($TaskId) { $Msg += " (task: $TaskId)" }
    Write-Host $Msg
    exit 0
}

$Messages = @()
foreach ($File in $Files) {
    $Content = Get-Content $File.FullName -Raw
    try {
        $Msg = $Content | ConvertFrom-Json
        $Msg | Add-Member -MemberType NoteProperty -Name "_file" -Value $File.Name -Force
        $Messages += $Msg
    } catch {
        Write-Warning "Failed to parse $($File.Name): $_"
    }
}

# Output as JSON array
$Messages | ConvertTo-Json -Depth 10

if ($Clear) {
    foreach ($File in $Files) {
        Remove-Item $File.FullName -Force
    }
    Write-Host "[Cleared $($Files.Count) message(s) from $Agent inbox]" -ForegroundColor Yellow
}