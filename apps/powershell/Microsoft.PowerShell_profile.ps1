# Import Chocolatey's helper module when Chocolatey is installed.
# This enables tab completion for choco commands.
$ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
if (Test-Path -LiteralPath $ChocolateyProfile) {
    Import-Module $ChocolateyProfile
}

# Configure the PowerShell 7 prompt and shell environment.
$PSStyle.FileInfo.Directory = ""
$env:STARSHIP_CONFIG = Join-Path $HOME '.config\starship.toml'
$env:STARSHIP_CACHE = Join-Path $HOME 'AppData\Local\Temp'

# Refresh PATH from the machine and user environment variables.
$machinePath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
$userPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
$env:Path = [System.Environment]::ExpandEnvironmentVariables("$machinePath;$userPath")

# Run the repository's dotfiles manager from any working directory.
function dots {
    if ([string]::IsNullOrWhiteSpace($env:DOTFILES_REPO_ROOT)) {
        throw 'Dotfiles repository path is not configured. Run .\install.ps1 from the repository, then open a new PowerShell session.'
    }

    $dotfilesCommand = Join-Path $env:DOTFILES_REPO_ROOT 'scripts\dotfiles.ps1'
    if (-not (Test-Path -LiteralPath $dotfilesCommand -PathType Leaf)) {
        throw "Dotfiles manager not found at '$dotfilesCommand'. Rerun .\install.ps1 from the repository."
    }

    # The CLI uses exit codes, so run it as a child process to keep the interactive shell open.
    $pwsh = Join-Path $PSHOME 'pwsh.exe'
    & $pwsh -NoLogo -NoProfile -File $dotfilesCommand @args
}

# Download YouTube audio and convert it to MP3.
function ytFunc {
    param(
        [Parameter(Mandatory = $true, Position = 0, HelpMessage = 'YouTube URL to download as MP3')]
        [string]$url
    )

    yt-dlp $url -x --audio-format mp3
}

# Keep the shorter alias for the audio download helper.
Set-Alias yt2mp3 ytFunc

# Initialize the PowerShell 7 prompt.
Invoke-Expression (& starship init powershell)

# Load Jabba's environment when it is installed.
$jabbaProfile = Join-Path $HOME '.jabba\jabba.ps1'
if (Test-Path -LiteralPath $jabbaProfile -PathType Leaf) {
    . $jabbaProfile
}
