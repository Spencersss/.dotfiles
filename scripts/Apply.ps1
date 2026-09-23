function Invoke-DotfilesApplyEntry {
    param([Parameter(Mandatory)] [object] $Entry, [Parameter(Mandatory)] [string] $RepositoryRoot)

    if (-not (Test-Path -LiteralPath $Entry.Source -PathType Leaf)) {
        throw "Source file does not exist:`n$($Entry.Source)"
    }

    $existing = Get-DotfilesItem -Path $Entry.Target
    if ($Entry.Mode -eq 'symlink' -and $null -ne $existing -and (Test-DotfilesSymbolicLink -Item $existing)) {
        $actualTarget = Resolve-DotfilesLinkTarget -Item $existing
        if (Test-DotfilesSamePath -First $actualTarget -Second $Entry.Source) {
            Write-DotfilesEntryResult -Name $Entry.Name -State 'CURRENT' -Detail 'already linked to repository'
            return
        }
    }
    elseif ($Entry.Mode -eq 'copy' -and $null -ne $existing -and -not (Test-DotfilesSymbolicLink -Item $existing) -and
        -not $existing.PSIsContainer -and (Test-DotfilesCopyMatches -Entry $Entry)) {
        Write-DotfilesEntryResult -Name $Entry.Name -State 'CURRENT' -Detail 'copy matches repository'
        return
    }

    $parent = Split-Path -Parent $Entry.Target
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop)
    }
    if ($Entry.Mode -eq 'symlink') {
        # Check permission before backing up or removing an existing user file.
        Assert-DotfilesSymbolicLinkCapability -Directory $parent
    }

    $copyContent = $null
    if ($Entry.Mode -eq 'copy' -and @($Entry.PreserveKeys).Count -gt 0) {
        if ($null -ne $existing -and $existing.PSIsContainer) { throw "Target is a directory; refusing to replace it: $($Entry.Target)" }
        $existingPath = if ($null -ne $existing) { $Entry.Target } else { $null }
        $copyContent = Get-DotfilesJsonApplyContent -Source $Entry.Source -Target $existingPath -PreserveKeys @($Entry.PreserveKeys)
    }

    if ($null -ne $existing) {
        if ($existing.PSIsContainer) { throw "Target is a directory; refusing to replace it: $($Entry.Target)" }
        $backup = New-DotfilesBackup -RepositoryRoot $RepositoryRoot -Target $Entry.Target -ExistingItem $existing
        Write-Host "  Backup verified: $backup"
        if ((Test-DotfilesSymbolicLink -Item $existing) -or $Entry.Mode -eq 'symlink') {
            Remove-DotfilesFileOrLink -Path $Entry.Target
        }
    }

    if ($Entry.Mode -eq 'symlink') {
        try {
            [void](New-Item -ItemType SymbolicLink -Path $Entry.Target -Value $Entry.Source -ErrorAction Stop)
        }
        catch {
            throw "Unable to create symbolic link '$($Entry.Target)' -> '$($Entry.Source)'. Windows Developer Mode or elevated permissions may be required. $($_.Exception.Message)"
        }
        $created = Get-DotfilesItem -Path $Entry.Target
        if ($null -eq $created -or -not (Test-DotfilesSymbolicLink -Item $created) -or
            -not (Test-DotfilesSamePath -First (Resolve-DotfilesLinkTarget -Item $created) -Second $Entry.Source)) {
            throw "Symbolic link verification failed for '$($Entry.Target)'."
        }
        Write-DotfilesEntryResult -Name $Entry.Name -State 'APPLIED' -Detail 'symbolic link created'
        return
    }

    if (@($Entry.PreserveKeys).Count -gt 0) {
        [System.IO.File]::WriteAllText($Entry.Target, [string]$copyContent, [System.Text.UTF8Encoding]::new($false))
    }
    else {
        [System.IO.File]::Copy($Entry.Source, $Entry.Target, $true)
    }
    if (-not (Test-DotfilesCopyMatches -Entry $Entry)) {
        throw "Copy verification failed for '$($Entry.Target)'."
    }
    Write-DotfilesEntryResult -Name $Entry.Name -State 'APPLIED' -Detail 'file copied'
}

function Invoke-DotfilesApply {
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Entries, [Parameter(Mandatory)] [string] $RepositoryRoot)

    $failed = 0
    foreach ($entry in $Entries) {
        try { Invoke-DotfilesApplyEntry -Entry $entry -RepositoryRoot $RepositoryRoot }
        catch {
            $failed++
            Write-DotfilesEntryResult -Name $entry.Name -State 'ERROR' -Detail $_.Exception.Message
        }
    }
    if ($failed -gt 0) { throw "$failed entry(s) failed to apply." }
}
