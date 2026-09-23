# Import the Chocolatey Profile that contains the necessary code to enable
# tab-completions to function for `choco`.
# Be aware that if you are missing these lines from your profile, tab completion
# for `choco` will not function.
# See https://ch0.co/tab-completion for details.
$ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
if (Test-Path($ChocolateyProfile)) {
  Import-Module "$ChocolateyProfile"
}

# Set variables
$PSStyle.FileInfo.Directory = ""
$env:STARSHIP_CONFIG = Join-Path $HOME '.config\starship.toml'
$ENV:STARSHIP_CACHE = "$HOME\AppData\Local\Temp"

$env:Path = [System.Environment]::ExpandEnvironmentVariables(([System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")))

# Function to download YouTube audio as MP3
function ytFunc {
    param(
        [Parameter(Mandatory=$true, Position=0, HelpMessage="YouTube URL to download as MP3")]
        [string]$url
    )
    yt-dlp $url -x --audio-format mp3
}

# Alias for the function
Set-Alias yt2mp3 ytFunc

Invoke-Expression (&starship init powershell)
$jabbaProfile = Join-Path $HOME '.jabba\jabba.ps1'
if (Test-Path -LiteralPath $jabbaProfile -PathType Leaf) { . $jabbaProfile }
