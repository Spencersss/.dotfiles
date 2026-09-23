function Invoke-DotfilesCapture {
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Entries)

    $failed = 0
    foreach ($entry in $Entries) {
        try {
            if ($entry.Mode -eq 'symlink') {
                Write-DotfilesEntryResult -Name $entry.Name -State 'CURRENT' -Detail 'managed through repository symlink; nothing to capture'
                continue
            }

            $targetItem = Get-DotfilesItem -Path $entry.Target
            if ($null -ne $targetItem -and (Test-DotfilesSymbolicLink -Item $targetItem)) {
                throw 'capture source is a symbolic link; copy mode expects a regular target file.'
            }
            if ($null -eq $targetItem -or -not (Test-Path -LiteralPath $entry.Target -PathType Leaf)) {
                throw "Target file does not exist: $($entry.Target)"
            }

            $preserveKeys = @($entry.PreserveKeys)
            $sourceContainsLocalKeys = $false
            if ($preserveKeys.Count -gt 0 -and (Test-Path -LiteralPath $entry.Source -PathType Leaf)) {
                $sourceObject = Read-DotfilesJsonObject -Path $entry.Source
                foreach ($name in $preserveKeys) {
                    if ($null -ne (Find-DotfilesJsonKey -Object $sourceObject -Name $name)) { $sourceContainsLocalKeys = $true; break }
                }
            }
            if (-not $sourceContainsLocalKeys -and (Test-DotfilesCopyMatches -Entry $entry)) {
                Write-DotfilesEntryResult -Name $entry.Name -State 'CURRENT' -Detail 'target already matches repository-managed content'
                continue
            }

            $sourceParent = Split-Path -Parent $entry.Source
            if (-not (Test-Path -LiteralPath $sourceParent -PathType Container)) {
                [void](New-Item -ItemType Directory -Path $sourceParent -Force -ErrorAction Stop)
            }
            if ($preserveKeys.Count -gt 0) {
                $captureContent = Get-DotfilesJsonCaptureContent -Target $entry.Target -PreserveKeys $preserveKeys
                [System.IO.File]::WriteAllText($entry.Source, [string]$captureContent, [System.Text.UTF8Encoding]::new($false))
            }
            else {
                [System.IO.File]::Copy($entry.Target, $entry.Source, $true)
            }
            if (-not (Test-DotfilesCopyMatches -Entry $entry)) {
                throw "Capture verification failed for '$($entry.Source)'."
            }
            Write-DotfilesEntryResult -Name $entry.Name -State 'CAPTURED' -Detail 'target copied into repository'
        }
        catch {
            $failed++
            Write-DotfilesEntryResult -Name $entry.Name -State 'ERROR' -Detail $_.Exception.Message
        }
    }
    if ($failed -gt 0) { throw "$failed entry(s) failed to capture." }
}
