function Get-DotfilesEntryStatus {
    param([Parameter(Mandatory)] [object] $Entry)

    if (-not (Test-Path -LiteralPath $Entry.Source -PathType Leaf)) {
        return [pscustomobject]@{ State = 'ERROR'; Detail = "source missing: $($Entry.Source)" }
    }
    $item = Get-DotfilesItem -Path $Entry.Target
    if ($null -eq $item) { return [pscustomobject]@{ State = 'MISSING'; Detail = $Entry.Target } }
    if ($item.PSIsContainer) { return [pscustomobject]@{ State = 'UNMANAGED'; Detail = 'target is a directory' } }

    $isLink = Test-DotfilesSymbolicLink -Item $item
    if ($Entry.Mode -eq 'symlink') {
        if (-not $isLink) { return [pscustomobject]@{ State = 'UNMANAGED'; Detail = 'target exists but is not a symbolic link' } }
        $linkTarget = Resolve-DotfilesLinkTarget -Item $item
        if (-not (Test-Path -LiteralPath $Entry.Target -PathType Leaf)) {
            return [pscustomobject]@{ State = 'BROKEN LINK'; Detail = "points to $linkTarget" }
        }
        if (-not (Test-DotfilesSamePath -First $linkTarget -Second $Entry.Source)) {
            return [pscustomobject]@{ State = 'WRONG LINK'; Detail = "points to $linkTarget" }
        }
        return [pscustomobject]@{ State = 'CURRENT'; Detail = 'linked to repository' }
    }

    if ($isLink) { return [pscustomobject]@{ State = 'UNMANAGED'; Detail = 'copy mode expects a regular file' } }
    if (Test-DotfilesCopyMatches -Entry $Entry) {
        $detail = if (@($Entry.PreserveKeys).Count -gt 0) { 'managed JSON settings match; local keys preserved' } else { 'copy matches repository' }
        return [pscustomobject]@{ State = 'CURRENT'; Detail = $detail }
    }
    return [pscustomobject]@{ State = 'DIFFERENT'; Detail = 'target content differs from repository' }
}

function Invoke-DotfilesStatus {
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Entries)

    Write-Host 'Dotfiles Status'
    Write-Host ('-' * 48)
    $results = @()
    foreach ($entry in $Entries) {
        try { $result = Get-DotfilesEntryStatus -Entry $entry }
        catch { $result = [pscustomobject]@{ State = 'ERROR'; Detail = $_.Exception.Message } }
        $results += [pscustomobject]@{ Name = $entry.Name; State = $result.State; Detail = $result.Detail }
        Write-Host ("{0}`n  {1} — {2}" -f ($entry.Name.Substring(0, 1).ToUpperInvariant() + $entry.Name.Substring(1)), $result.State, $result.Detail)
    }

    $current = @($results | Where-Object State -eq 'CURRENT').Count
    $missing = @($results | Where-Object State -eq 'MISSING').Count
    $errors = @($results | Where-Object State -eq 'ERROR').Count
    $conflicts = $results.Count - $current - $missing - $errors
    Write-Host ('-' * 48)
    Write-Host ("{0} managed | {1} current | {2} missing | {3} conflicts | {4} errors" -f $results.Count, $current, $missing, $conflicts, $errors)
    if ($errors -gt 0 -or $conflicts -gt 0 -or $missing -gt 0) { throw 'One or more managed entries need attention.' }
}
