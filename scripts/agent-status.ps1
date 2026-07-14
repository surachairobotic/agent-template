<#
.SYNOPSIS
    Show task status from tasks.md
.DESCRIPTION
    Parses .opencode/memory/tasks.md and displays a formatted status table.
.PARAMETER ProjectRoot
    Path to project root (default: script parent)
.EXAMPLE
    .\agent-status.ps1
    .\agent-status.ps1 -ProjectRoot "D:\my-project"
#>

param(
    [string]$ProjectRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Definition))
)

$TasksFile = Join-Path $ProjectRoot ".opencode\memory\tasks.md"

if (-not (Test-Path $TasksFile)) {
    Write-Host "[tasks.md not found at $TasksFile]" -ForegroundColor Yellow
    Write-Host "Run agent-bootstrap.ps1 first or create manually" -ForegroundColor Yellow
    exit 0
}

$Content = Get-Content $TasksFile -Raw

# Find the table (lines with | ID |)
$Lines = $Content -split "`n"
$InTable = $false
$Headers = @()
$Rows = @()

foreach ($Line in $Lines) {
    if ($Line -match '^\|') {
        if (-not $InTable) {
            # Check if header row
            if ($Line -match '\|\s*ID\s*\|') {
                $InTable = $true
                $Headers = $Line.Split('|') | Where-Object { $_ -ne '' } | ForEach-Object { $_.Trim() }
            }
        } else {
            # Data row
            if ($Line -notmatch '\|\s*-+\s*\|') {
                $Row = $Line.Split('|') | Where-Object { $_ -ne '' } | ForEach-Object { $_.Trim() }
                if ($Row.Count -ge $Headers.Count) {
                    $Rows += $Row
                }
            }
        }
    }
}

if (-not $Rows) {
    Write-Host "[No tasks found in tasks.md]"
    exit 0
}

# Color mapping
$StatusColors = @{
    "PLANNED"      = "Cyan"
    "IN_PROGRESS"  = "Yellow"
    "REVIEW"       = "Magenta"
    "DONE"         = "Green"
    "BLOCKED"      = "Red"
    "SKIPPED"      = "Gray"
}

# Print table
Write-Host "`n[Task Status ($($Rows.Count) tasks)]`n" -ForegroundColor Green

# Calculate column widths
$ColWidths = @{}
for ($i=0; $i -lt $Headers.Count; $i++) {
    $Max = $Headers[$i].Length
    foreach ($Row in $Rows) {
        if ($i -lt $Row.Count) { $Max = [Math]::Max($Max, $Row[$i].Length) }
    }
    $ColWidths[$i] = $Max + 2
}

# Header
$HeaderLine = ""
for ($i=0; $i -lt $Headers.Count; $i++) {
    $HeaderLine += $Headers[$i].PadRight($ColWidths[$i])
}
Write-Host $HeaderLine -ForegroundColor White -BackgroundColor DarkGray

# Separator
$SepLine = ""
for ($i=0; $i -lt $Headers.Count; $i++) {
    $SepLine += ("-" * $ColWidths[$i])
}
Write-Host $SepLine -ForegroundColor DarkGray

# Rows
foreach ($Row in $Rows) {
    $Line = ""
    for ($i=0; $i -lt $Headers.Count; $i++) {
        $Val = if ($i -lt $Row.Count) { $Row[$i] } else { "" }
        $Color = "White"
        if ($i -eq 3) {
            if ($StatusColors.ContainsKey($Val)) {
                $Color = $StatusColors[$Val]
            }
        }
        $Line += $Val.PadRight($ColWidths[$i])
    }
    Write-Host $Line -ForegroundColor $Color
}

Write-Host ""