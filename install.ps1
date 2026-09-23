[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion -lt [version]'7.2') {
    throw "PowerShell 7.2 or newer is required. Run this script with pwsh."
}
& (Join-Path $PSScriptRoot 'scripts/Bootstrap.ps1')
exit $LASTEXITCODE