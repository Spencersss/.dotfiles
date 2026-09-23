[CmdletBinding()]
param(
    [Parameter(Position = 0)] [string] $Command,
    [Parameter(Position = 1)] [string] $Selector,
    [switch] $DebugMode
)

$ErrorActionPreference = 'Stop'
$moduleRoot = Join-Path $PSScriptRoot 'modules'
. (Join-Path $moduleRoot 'Utils.ps1')
. (Join-Path $moduleRoot 'Apply.ps1')
. (Join-Path $moduleRoot 'Status.ps1')
. (Join-Path $moduleRoot 'Capture.ps1')

try {
    Assert-DotfilesPowerShellVersion
    $repoRoot = Get-DotfilesRepositoryRoot
    if ([string]::IsNullOrWhiteSpace($Command)) {
        throw 'Usage: .\scripts\dotfiles.ps1 <apply|status|capture> [entry-name]'
    }

    $normalizedCommand = $Command.ToLowerInvariant()
    if ($normalizedCommand -notin @('apply', 'status', 'capture')) {
        throw "Unknown command '$Command'. Supported commands: apply, status, capture."
    }
    $manifest = Read-DotfilesManifest -RepositoryRoot $repoRoot
    $manifest | Add-Member -NotePropertyName RepositoryRoot -NotePropertyValue $repoRoot -Force
    $entries = @(Get-DotfilesSelectedEntries -Manifest $manifest -Selector $Selector)

    switch ($normalizedCommand) {
        'apply'   { Invoke-DotfilesApply -Entries $entries -RepositoryRoot $repoRoot }
        'status'  { Invoke-DotfilesStatus -Entries $entries }
        'capture' { Invoke-DotfilesCapture -Entries $entries }
    }
}
catch {
    if ($DebugMode) { Write-Error $_ }
    else { Write-Host ("ERROR: {0}" -f $_.Exception.Message) -ForegroundColor Red }
    exit 1
}
