[CmdletBinding()]
param(
    # Run this switch from an elevated PowerShell to install Chocolatey only.
    [switch]$ChocolateyOnly
)

$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-CommandAvailable {
    param([Parameter(Mandatory)][string]$Name)

    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Refresh-ProcessEnvironment {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machinePath;$userPath;$env:Path"

    $machineChocolateyInstall = [Environment]::GetEnvironmentVariable('ChocolateyInstall', 'Machine')
    $userChocolateyInstall = [Environment]::GetEnvironmentVariable('ChocolateyInstall', 'User')
    if ($machineChocolateyInstall) {
        $env:ChocolateyInstall = $machineChocolateyInstall
    }
    elseif ($userChocolateyInstall) {
        $env:ChocolateyInstall = $userChocolateyInstall
    }
}

function Install-Chocolatey {
    if (Test-CommandAvailable -Name 'choco') {
        Write-Host 'Chocolatey is already installed.'
        return
    }

    if (-not (Test-IsAdministrator)) {
        throw 'Chocolatey needs an elevated PowerShell. Reopen PowerShell as Administrator and run: .\scripts\Install-Dependencies.ps1 -ChocolateyOnly'
    }

    if (Test-CommandAvailable -Name 'winget') {
        Write-Host 'Installing Chocolatey with WinGet...'
        & winget install --id Chocolatey.Chocolatey --exact --source winget --accept-source-agreements --accept-package-agreements --scope machine --silent --disable-interactivity
        if ($LASTEXITCODE -eq 0) {
            Refresh-ProcessEnvironment
            if (Test-CommandAvailable -Name 'choco') {
                Write-Host 'Chocolatey installed with WinGet.'
                return
            }

            throw 'WinGet installed Chocolatey, but choco is not visible in this shell. Open a new elevated PowerShell and check again before rerunning installation.'
        }
        else {
            Write-Warning "WinGet could not install Chocolatey (exit code $LASTEXITCODE). Falling back to Chocolatey's official installer."
        }
    }
    else {
        Write-Warning 'WinGet is unavailable. Falling back to Chocolatey official installer.'
    }

    Write-Host 'Installing Chocolatey from its official bootstrap script...'
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
    $installerUrl = 'https://community.chocolatey.org/install.ps1'
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString($installerUrl))
    Refresh-ProcessEnvironment

    if (-not (Test-CommandAvailable -Name 'choco')) {
        throw 'Chocolatey setup finished, but choco.exe is not available in this session. Open a new elevated PowerShell and retry.'
    }

    Write-Host 'Chocolatey installed.'
}

# Chocolatey is machine-wide and needs elevation. Scoop installs per-user, so
# keep the two setup steps in separate shells instead of running Scoop as admin.
if ($ChocolateyOnly) {
    Install-Chocolatey
    return
}

if (Test-IsAdministrator) {
    if (-not (Test-CommandAvailable -Name 'choco')) {
        Install-Chocolatey
    }

    Write-Host ''
    Write-Host 'Chocolatey is ready. Close this elevated shell, open a regular PowerShell, and rerun this script to install Scoop and profile tools.'
    return
}

# Install Chocolatey separately from an elevated shell when it is not present.
if (Test-CommandAvailable -Name 'choco') {
    Write-Host 'Chocolatey is already installed.'
}
else {
    Write-Warning 'Chocolatey is not installed. Run this script with -ChocolateyOnly from an elevated PowerShell, then rerun it here.'
}

# Scoop is not available in the current WinGet source, so use its official
# per-user bootstrap from a regular, non-elevated PowerShell.
if (-not (Test-CommandAvailable -Name 'scoop')) {
    $currentUserPolicy = Get-ExecutionPolicy -Scope CurrentUser
    if ($currentUserPolicy -notin @('RemoteSigned', 'Unrestricted', 'Bypass')) {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    }

    Write-Host 'Installing Scoop for the current user...'
    Invoke-RestMethod -Uri 'https://get.scoop.sh' | Invoke-Expression
    Refresh-ProcessEnvironment
}

if (-not (Test-CommandAvailable -Name 'scoop')) {
    throw 'Scoop installation did not add scoop to PATH. Open a new regular PowerShell and rerun this script.'
}

# Scoop's shims are used only as a fallback when WinGet cannot install a tool.
$scoopRoot = if ($env:SCOOP) { $env:SCOOP } else { Join-Path $HOME 'scoop' }
$scoopShims = Join-Path $scoopRoot 'shims'
if ((Test-Path -LiteralPath $scoopShims) -and ($env:Path -notlike "*$scoopShims*")) {
    $env:Path = "$scoopShims;$env:Path"
}

# Each package has an exact WinGet ID and a Scoop fallback. ffmpeg supplies
# ffmpeg.exe and ffprobe.exe for yt-dlp's MP3 extraction helper.
$packages = @(
    [pscustomobject]@{
        Name = 'yt-dlp'
        WingetId = 'yt-dlp.yt-dlp'
        ScoopName = 'yt-dlp'
        Commands = @('yt-dlp')
    }
    [pscustomobject]@{
        Name = 'ffmpeg'
        WingetId = 'Gyan.FFmpeg.Shared'
        ScoopName = 'ffmpeg'
        Commands = @('ffmpeg', 'ffprobe')
    }
    [pscustomobject]@{
        Name = 'Starship'
        WingetId = 'Starship.Starship'
        ScoopName = 'starship'
        Commands = @('starship')
    }
)

foreach ($package in $packages) {
    $missingCommands = @(
        $package.Commands | Where-Object { -not (Test-CommandAvailable -Name $_) }
    )

    if ($missingCommands.Count -eq 0) {
        Write-Host "$($package.Name) is already available."
        continue
    }

    $installedWithWinget = $false
    if (Test-CommandAvailable -Name 'winget') {
        Write-Host "Installing $($package.Name) with WinGet ($($package.WingetId))..."
        & winget install --id $package.WingetId --exact --source winget --accept-source-agreements --accept-package-agreements --scope user --silent --disable-interactivity
        if ($LASTEXITCODE -eq 0) {
            Refresh-ProcessEnvironment
            $missingCommands = @(
                $package.Commands | Where-Object { -not (Test-CommandAvailable -Name $_) }
            )
            if ($missingCommands.Count -eq 0) {
                Write-Host "$($package.Name) installed with WinGet."
                $installedWithWinget = $true
            }
            else {
                Write-Warning "$($package.Name) installed with WinGet, but its command is not visible in this shell yet. Open a new PowerShell window before using it."
                $installedWithWinget = $true
            }
        }
        else {
            Write-Warning "WinGet could not install $($package.Name) (exit code $LASTEXITCODE). Trying Scoop."
        }
    }
    else {
        Write-Warning 'WinGet is unavailable. Using Scoop for this tool.'
    }

    if (-not $installedWithWinget) {
        Write-Host "Installing $($package.Name) with Scoop..."
        & scoop install $package.ScoopName
        if ($LASTEXITCODE -ne 0) {
            throw "Scoop failed to install $($package.Name) (exit code $LASTEXITCODE)."
        }
        Refresh-ProcessEnvironment
    }
}

Write-Host ''
Write-Host 'PowerShell profile dependencies are ready.'
