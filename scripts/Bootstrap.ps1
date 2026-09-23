[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$cliPath = Join-Path $repoRoot 'scripts/dotfiles.ps1'

try {
    if ($PSVersionTable.PSVersion -lt [version]'7.2') {
        throw "PowerShell 7.2 or newer is required. Current version: $($PSVersionTable.PSVersion). Install PowerShell 7 and rerun with pwsh."
    }
    if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
        Write-Host "Installing required 'powershell-yaml' module for the current user..."
        Install-Module -Name powershell-yaml -Scope CurrentUser -Repository PSGallery -Force -AllowClobber -ErrorAction Stop
    }
    Import-Module powershell-yaml -ErrorAction Stop
    if (-not (Get-Command ConvertFrom-Yaml -ErrorAction SilentlyContinue)) {
        throw "The installed 'powershell-yaml' module does not provide ConvertFrom-Yaml."
    }

    . (Join-Path $PSScriptRoot 'Utils.ps1')
    . (Join-Path $PSScriptRoot 'Backup.ps1')
    $manifest = Read-DotfilesManifest -RepositoryRoot $repoRoot
    $manifest | Add-Member -NotePropertyName RepositoryRoot -NotePropertyValue $repoRoot -Force
    [void](Get-DotfilesSelectedEntries -Manifest $manifest)
    [void](New-Item -ItemType Directory -Path (Join-Path $repoRoot 'backups') -Force -ErrorAction Stop)

    $pwsh = Join-Path $PSHOME 'pwsh.exe'
    & $pwsh -NoLogo -NoProfile -File $cliPath apply
    if ($LASTEXITCODE -ne 0) { throw "Dotfiles apply reported entries needing attention (exit code $LASTEXITCODE)." }
    & $pwsh -NoLogo -NoProfile -File $cliPath status
    if ($LASTEXITCODE -ne 0) { throw "Dotfiles status reported entries needing attention (exit code $LASTEXITCODE)." }
}
catch {
    Write-Host ("ERROR: {0}" -f $_.Exception.Message) -ForegroundColor Red
    exit 1
}