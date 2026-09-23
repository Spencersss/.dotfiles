Set-StrictMode -Version Latest

function Get-DotfilesRepositoryRoot {
    # Utils.ps1 lives in scripts/modules; derive the root from this file, not the
    # caller's working directory, so commands work from any location.
    $root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    return $root.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
}

function Assert-DotfilesPowerShellVersion {
    if ($PSVersionTable.PSVersion -lt [version]'7.2') {
        throw 'Dotfiles requires PowerShell 7.2 or newer. Run it with pwsh; install.ps1 can prepare its YAML dependency.'
    }
}

function Import-DotfilesYamlModule {
    if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
        throw "The required 'powershell-yaml' module is missing. Run .\install.ps1 to install it for the current user."
    }

    Import-Module powershell-yaml -ErrorAction Stop
    if (-not (Get-Command ConvertFrom-Yaml -ErrorAction SilentlyContinue)) {
        throw "The installed 'powershell-yaml' module does not provide ConvertFrom-Yaml. Reinstall it with .\install.ps1."
    }
}

function Get-ObjectProperty {
    param(
        [Parameter(Mandatory)] [object] $InputObject,
        [Parameter(Mandatory)] [string] $Name,
        [object] $Default = $null
    )

    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in $InputObject.Keys) {
            if ([string]::Equals([string]$key, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $InputObject[$key]
            }
        }
    }

    $property = $InputObject.PSObject.Properties | Where-Object {
        [string]::Equals($_.Name, $Name, [System.StringComparison]::OrdinalIgnoreCase)
    } | Select-Object -First 1
    if ($null -ne $property) { return $property.Value }
    return $Default
}

function Read-DotfilesManifest {
    param([Parameter(Mandatory)] [string] $RepositoryRoot)

    Assert-DotfilesPowerShellVersion
    Import-DotfilesYamlModule
    $manifestPath = Join-Path $RepositoryRoot 'dotfiles.yaml'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Manifest file does not exist: $manifestPath"
    }

    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop | ConvertFrom-Yaml -Ordered -ErrorAction Stop
    }
    catch {
        throw "Unable to parse manifest '$manifestPath': $($_.Exception.Message)"
    }

    $version = Get-ObjectProperty -InputObject $manifest -Name 'version'
    if ($version -ne 1) { throw "Unsupported dotfiles manifest version '$version'. This manager supports version 1." }
    $entries = Get-ObjectProperty -InputObject $manifest -Name 'entries'
    if ($null -eq $entries -or $entries -isnot [System.Collections.IDictionary]) {
        throw "Manifest '$manifestPath' must contain an 'entries' mapping."
    }

    return [pscustomobject]@{
        Path      = $manifestPath
        Variables = Get-ObjectProperty -InputObject $manifest -Name 'variables' -Default ([ordered]@{})
        Entries   = $entries
    }
}

function Resolve-DotfilesVariables {
    param(
        [Parameter(Mandatory)] [string] $Value,
        [Parameter(Mandatory)] [object] $Variables
    )

    $resolved = $Value
    for ($pass = 0; $pass -lt 32; $pass++) {
        $matches = [regex]::Matches($resolved, '(\$\{([A-Za-z_][A-Za-z0-9_]*)\}|%([A-Za-z_][A-Za-z0-9_]*)%)')
        if ($matches.Count -eq 0) { return $resolved }

        # Resolve every token against manifest variables first, then environment.
        # Repeat so custom values can themselves refer to either kind of value.
        foreach ($match in $matches) {
            $name = if ($match.Groups[2].Success) { $match.Groups[2].Value } else { $match.Groups[3].Value }
            $replacement = $null
            $found = $false
            if ($Variables -is [System.Collections.IDictionary]) {
                foreach ($key in $Variables.Keys) {
                    if ([string]::Equals([string]$key, $name, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $replacement = [string]$Variables[$key]
                        $found = $true
                        break
                    }
                }
            }
            if (-not $found) {
                $replacement = [Environment]::GetEnvironmentVariable($name)
                $found = $null -ne $replacement
            }
            if (-not $found) { throw "Unable to resolve manifest variable: $($match.Value)" }

            $resolved = $resolved.Replace($match.Value, [string]$replacement)
        }
    }

    throw "Manifest variable expansion exceeded 32 passes while resolving '$Value'. Check for circular variable references."
}

function Get-DotfilesEntryPath {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [ValidateSet('Source', 'Target')] [string] $Kind,
        [Parameter(Mandatory)] [string] $RepositoryRoot,
        [Parameter(Mandatory)] [object] $Variables
    )

    $expanded = Resolve-DotfilesVariables -Value $Path -Variables $Variables
    $expanded = $expanded.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    if ($Kind -eq 'Source' -and -not [System.IO.Path]::IsPathRooted($expanded)) {
        $expanded = Join-Path $RepositoryRoot $expanded
    }
    return [System.IO.Path]::GetFullPath($expanded)
}

function Get-DotfilesSelectedEntries {
    param(
        [Parameter(Mandatory)] [object] $Manifest,
        [string] $Selector
    )

    $selected = @()
    foreach ($name in $Manifest.Entries.Keys) {
        $raw = $Manifest.Entries[$name]
        if ($null -eq $raw) { throw "Manifest entry '$name' must be a mapping." }
        $enabled = Get-ObjectProperty -InputObject $raw -Name 'enabled' -Default $true
        if (-not [bool]$enabled) { continue }
        $machines = Get-ObjectProperty -InputObject $raw -Name 'machines'
        if ($null -ne $machines -and @($machines).Count -gt 0 -and @($machines) -notcontains $env:COMPUTERNAME) { continue }
        if (-not [string]::IsNullOrWhiteSpace($Selector) -and
            -not [string]::Equals([string]$name, $Selector, [System.StringComparison]::OrdinalIgnoreCase) -and
            -not $Selector.StartsWith(([string]$name + '/'), [System.StringComparison]::OrdinalIgnoreCase)) { continue }

        $source = Get-ObjectProperty -InputObject $raw -Name 'source'
        $target = Get-ObjectProperty -InputObject $raw -Name 'target'
        $mode = ([string](Get-ObjectProperty -InputObject $raw -Name 'mode')).ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($source)) { throw "Manifest entry '$name' is missing 'source'." }
        if ([string]::IsNullOrWhiteSpace($target)) { throw "Manifest entry '$name' is missing 'target'." }

        $resolvedSource = Get-DotfilesEntryPath -Path ([string]$source) -Kind Source -RepositoryRoot $Manifest.RepositoryRoot -Variables $Manifest.Variables
        $resolvedTarget = Get-DotfilesEntryPath -Path ([string]$target) -Kind Target -RepositoryRoot $Manifest.RepositoryRoot -Variables $Manifest.Variables
        if ($mode -eq 'directory') {
            $fileMode = ([string](Get-ObjectProperty -InputObject $raw -Name 'file_mode' -Default 'symlink')).ToLowerInvariant()
            if ($fileMode -notin @('symlink', 'copy')) { throw "Manifest entry '$name' uses unsupported file_mode '$fileMode'." }
            if (-not (Test-Path -LiteralPath $resolvedSource -PathType Container)) { throw "Directory source does not exist: $resolvedSource" }
            $files = @(Get-ChildItem -LiteralPath $resolvedSource -File -Recurse -Force | Where-Object { $_.Name -ne '.gitkeep' })
            foreach ($file in $files) {
                $relative = [System.IO.Path]::GetRelativePath($resolvedSource, $file.FullName)
                $childTarget = Join-Path $resolvedTarget $relative
                if ([string]::Equals($Selector, [string]$name, [System.StringComparison]::OrdinalIgnoreCase) -or
                    [string]::Equals($Selector, ("{0}/{1}" -f $name, $relative.Replace('\','/')), [System.StringComparison]::OrdinalIgnoreCase) -or
                    [string]::IsNullOrWhiteSpace($Selector)) {
                    if (Test-DotfilesSamePath -First $file.FullName -Second $childTarget) { throw "Manifest entry '$name' resolves source and target to the same path: $childTarget" }
                    $selected += [pscustomobject]@{ Name = ("{0}/{1}" -f $name, $relative.Replace('\','/')); Source = $file.FullName; Target = $childTarget; Mode = $fileMode; Groups = @(Get-ObjectProperty -InputObject $raw -Name 'groups') }
                }
            }
            continue
        }

        if ($mode -notin @('symlink', 'copy')) { throw "Manifest entry '$name' uses unsupported mode '$mode'. Supported modes are symlink, copy, and directory." }
        if (Test-DotfilesSamePath -First $resolvedSource -Second $resolvedTarget) { throw "Manifest entry '$name' resolves source and target to the same path: $resolvedSource" }
        $selected += [pscustomobject]@{ Name = [string]$name; Source = $resolvedSource; Target = $resolvedTarget; Mode = $mode; Groups = @(Get-ObjectProperty -InputObject $raw -Name 'groups') }
    }

    if (-not [string]::IsNullOrWhiteSpace($Selector) -and $selected.Count -eq 0) {
        $known = @($Manifest.Entries.Keys | Sort-Object) -join ', '
        throw "No enabled entry named '$Selector' applies to this machine. Available entries: $known"
    }
    return $selected
}
function Get-DotfilesItem {
    param([Parameter(Mandatory)] [string] $Path)
    # Get-Item, unlike Test-Path, can return dangling symlink entries on PowerShell 7.
    return Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
}

function Test-DotfilesSymbolicLink {
    param([Parameter(Mandatory)] [System.IO.FileSystemInfo] $Item)
    return ($null -ne $Item.LinkType -and $Item.LinkType -eq 'SymbolicLink')
}

function Resolve-DotfilesLinkTarget {
    param([Parameter(Mandatory)] [System.IO.FileSystemInfo] $Item)
    $linkTarget = [string]$Item.LinkTarget
    if ([string]::IsNullOrWhiteSpace($linkTarget)) { return $null }
    if (-not [System.IO.Path]::IsPathRooted($linkTarget)) {
        $linkTarget = Join-Path $Item.DirectoryName $linkTarget
    }
    return [System.IO.Path]::GetFullPath($linkTarget)
}

function Test-DotfilesSamePath {
    param([string] $First, [string] $Second)
    if ($null -eq $First -or $null -eq $Second) { return $false }
    return [string]::Equals(
        [System.IO.Path]::GetFullPath($First).TrimEnd('\', '/'),
        [System.IO.Path]::GetFullPath($Second).TrimEnd('\', '/'),
        [System.StringComparison]::OrdinalIgnoreCase
    )
}

function Test-DotfilesSameFile {
    param([Parameter(Mandatory)] [string] $First, [Parameter(Mandatory)] [string] $Second)
    if (-not (Test-Path -LiteralPath $First -PathType Leaf) -or -not (Test-Path -LiteralPath $Second -PathType Leaf)) { return $false }
    $left = Get-Item -LiteralPath $First -Force -ErrorAction Stop
    $right = Get-Item -LiteralPath $Second -Force -ErrorAction Stop
    if ($left.Length -ne $right.Length) { return $false }
    return (Get-FileHash -LiteralPath $First -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $Second -Algorithm SHA256).Hash
}

function Remove-DotfilesFileOrLink {
    param([Parameter(Mandatory)] [string] $Path)
    $item = Get-DotfilesItem -Path $Path
    if ($null -eq $item) { return }
    if ($item.PSIsContainer) { throw "Target is a directory; refusing to replace or recursively remove it: $Path" }
    Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($null -ne (Get-DotfilesItem -Path $Path)) { throw "Unable to remove the backed-up target: $Path" }
}

function Assert-DotfilesSymbolicLinkCapability {
    param([Parameter(Mandatory)] [string] $Directory)

    $id = [guid]::NewGuid().ToString('N')
    $source = Join-Path $Directory ".dotfiles-probe-$id.source"
    $link = Join-Path $Directory ".dotfiles-probe-$id.link"
    try {
        [System.IO.File]::WriteAllText($source, 'dotfiles symbolic link capability probe')
        [void](New-Item -ItemType SymbolicLink -Path $link -Value $source -ErrorAction Stop)
    }
    catch {
        throw "Unable to create symbolic links in '$Directory'. Windows Developer Mode or elevated permissions may be required. $($_.Exception.Message)"
    }
    finally {
        if (Test-Path -LiteralPath $link) { Remove-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $source) { Remove-Item -LiteralPath $source -Force -ErrorAction SilentlyContinue }
    }
}
function Write-DotfilesEntryResult {
    param([string] $Name, [string] $State, [string] $Detail = '')
    $label = $Name.Substring(0, 1).ToUpperInvariant() + $Name.Substring(1)
    if ([string]::IsNullOrWhiteSpace($Detail)) { Write-Host ("{0}: {1}" -f $label, $State) }
    else { Write-Host ("{0}: {1} — {2}" -f $label, $State, $Detail) }
}
