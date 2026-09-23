function Get-DotfilesBackupRelativePath {
    param([Parameter(Mandatory)] [string] $Target)
    $fullTarget = [System.IO.Path]::GetFullPath($Target)
    $profile = [Environment]::GetEnvironmentVariable('USERPROFILE')
    if (-not [string]::IsNullOrWhiteSpace($profile)) {
        $fullProfile = [System.IO.Path]::GetFullPath($profile).TrimEnd('\', '/')
        if ($fullTarget.StartsWith($fullProfile + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $fullTarget.Substring($fullProfile.Length + 1)
        }
    }
    # Keep the drive or UNC namespace so equal paths on different volumes cannot collide.
    if ($fullTarget -match '^([A-Za-z]):[\\/](.*)$') {
        return Join-Path $Matches[1] $Matches[2]
    }
    if ($fullTarget.StartsWith('\\')) {
        return Join-Path 'UNC' ($fullTarget.TrimStart('\\') -replace '[\\/]', [System.IO.Path]::DirectorySeparatorChar)
    }
    return $fullTarget.TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
}

function New-DotfilesBackup {
    param(
        [Parameter(Mandatory)] [string] $RepositoryRoot,
        [Parameter(Mandatory)] [string] $Target,
        [Parameter(Mandatory)] [System.IO.FileSystemInfo] $ExistingItem
    )

    $machine = $env:COMPUTERNAME
    if ([string]::IsNullOrWhiteSpace($machine)) { $machine = 'UNKNOWN-MACHINE' }
    $machine = $machine -replace '[^A-Za-z0-9._-]', '_'
    $backupRoot = Join-Path $RepositoryRoot 'backups'
    $machineRoot = Join-Path $backupRoot $machine
    [void](New-Item -ItemType Directory -Path $machineRoot -Force -ErrorAction Stop)

    $stamp = Get-Date -Format 'yyyy-MM-dd_HHmmssfff'
    $runDirectory = Join-Path $machineRoot $stamp
    $suffix = 0
    while (Test-Path -LiteralPath $runDirectory) {
        $suffix++
        $runDirectory = Join-Path $machineRoot ("{0}_{1:D2}" -f $stamp, $suffix)
    }
    [void](New-Item -ItemType Directory -Path $runDirectory -ErrorAction Stop)

    $relativePath = Get-DotfilesBackupRelativePath -Target $Target
    $backupPath = Join-Path $runDirectory $relativePath
    $backupParent = Split-Path -Parent $backupPath
    [void](New-Item -ItemType Directory -Path $backupParent -Force -ErrorAction Stop)

    $isLink = Test-DotfilesSymbolicLink -Item $ExistingItem
    $linkTarget = if ($isLink) { Resolve-DotfilesLinkTarget -Item $ExistingItem } else { $null }
    $targetExists = Test-Path -LiteralPath $Target -PathType Leaf
    $backupMetadata = [ordered]@{
        originalPath = $Target
        backedUpAt   = (Get-Date).ToString('o')
        symbolicLink = $isLink
    } | ConvertTo-Json -Depth 4
    $backupMetadataPath = "$backupPath.dotfiles-backup.json"
    [System.IO.File]::WriteAllText($backupMetadataPath, $backupMetadata, [System.Text.UTF8Encoding]::new($false))
    if ($targetExists) {
        # File.Copy follows a link and preserves its data as a standalone file.
        [System.IO.File]::Copy($Target, $backupPath, $false)
        $originalHash = (Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash
        $backupHash = (Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash
        if ($originalHash -ne $backupHash) { throw "Backup verification failed for '$Target'. Original left unchanged." }
    }
    if ($isLink) {
        $metadataPath = "$backupPath.dotfiles-link.json"
        $metadata = [ordered]@{
            originalPath = $Target
            linkType     = $ExistingItem.LinkType
            linkTarget   = $linkTarget
            broken       = -not $targetExists
        } | ConvertTo-Json -Depth 4
        [System.IO.File]::WriteAllText($metadataPath, $metadata, [System.Text.UTF8Encoding]::new($false))
    }

    if ($targetExists -and -not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
        throw "Backup verification failed for '$Target': backup file was not created. Original left unchanged."
    }
    if (-not $targetExists -and -not $isLink) {
        throw "Unable to safely back up target '$Target'. It is not a readable file or symbolic link."
    }
    return $backupPath
}
