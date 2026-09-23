[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
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

    # Parse and validate the manifest before touching any managed target.
    . (Join-Path $repoRoot 'scripts/modules/Utils.ps1')
    $manifest = Read-DotfilesManifest -RepositoryRoot $repoRoot
    $manifest | Add-Member -NotePropertyName RepositoryRoot -NotePropertyValue $repoRoot -Force
    [void](Get-DotfilesSelectedEntries -Manifest $manifest)

    $backupDirectory = Join-Path $repoRoot 'backups'
    [void](New-Item -ItemType Directory -Path $backupDirectory -Force -ErrorAction Stop)

    # Probe the exact symbolic-link operation in an isolated temporary folder.
    $probeDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("dotfiles-link-probe-{0}" -f [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $probeDirectory -ErrorAction Stop)
    $probeSource = Join-Path $probeDirectory 'source.txt'
    $probeLink = Join-Path $probeDirectory 'link.txt'
    try {
        [System.IO.File]::WriteAllText($probeSource, 'probe')
        [void](New-Item -ItemType SymbolicLink -Path $probeLink -Value $probeSource -ErrorAction Stop)
    }
    catch {
        throw "Symbolic link creation is unavailable. Enable Windows Developer Mode or run with elevated permissions. $($_.Exception.Message)"
    }
    finally {
        if (Test-Path -LiteralPath $probeLink) { Remove-Item -LiteralPath $probeLink -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $probeSource) { Remove-Item -LiteralPath $probeSource -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $probeDirectory) { Remove-Item -LiteralPath $probeDirectory -Force -ErrorAction SilentlyContinue }
    }

    $powerShellExecutable = Join-Path $PSHOME 'pwsh.exe'
    & $powerShellExecutable -NoLogo -NoProfile -File $cliPath apply
    if ($LASTEXITCODE -ne 0) { throw "Dotfiles apply failed with exit code $LASTEXITCODE." }
    & $powerShellExecutable -NoLogo -NoProfile -File $cliPath status
    if ($LASTEXITCODE -ne 0) { throw "Dotfiles status failed with exit code $LASTEXITCODE." }
}
catch {
    Write-Host ("ERROR: {0}" -f $_.Exception.Message) -ForegroundColor Red
    exit 1
}
