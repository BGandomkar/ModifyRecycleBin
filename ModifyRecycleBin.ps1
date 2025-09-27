<#
.SYNOPSIS
    Modifies the deletion time of files in the Windows Recycle Bin based on a search string with wildcard support.

.DESCRIPTION
    This script searches all partitions for $RECYCLE.BIN folders, recursively finds $I* files,
    and looks for matches based on the provided search string (either full original path or just filename).
    The search is case-insensitive, normalizes paths (slashes and whitespace), and supports wildcards (*, ?).
    For matching files, it updates the FILETIME (deletion time) within the $I* file to the UTC equivalent
    of the provided NewDeletionTime and sets the file's LastWriteTime and CreationTime to the NewDeletionTime
    in local time. If the provided NewDeletionTime is incomplete (e.g., date only or missing minutes/seconds),
    missing time components are randomly generated down to milliseconds. Results and errors are displayed unless
    the -Silent switch is used, which suppresses all output. When a user deletes a file, the LastWriteTime and
    CreationTime of the corresponding $I* file in the Recycle Bin are set to the same value as the LastAccessTime
    of the associated $R* file, and this script mirrors that behavior by updating both the internal FILETIME (in UTC)
    and the file system properties (in local time). Run as administrator to access the Recycle Bin.

.PARAMETER SearchString
    The filename or full original path of the deleted file to search for in the Recycle Bin.
    The search is case-insensitive, normalizes slashes (e.g., "/" or "\") and whitespace, and supports
    wildcards (* for any characters, ? for a single character).
    Examples: "example.txt", "*.txt", "C:\Users\*\Documents\*.txt".

.PARAMETER NewDeletionTime
    The new deletion time to set for matching files, in a valid local time date format (e.g., "2025-09-03 17:00:00").
    Supports formats like "YYYY-MM-DD HH:MM:SS", "MM/DD/YYYY HH:MM", or "YYYY-MM-DD". The input is interpreted
    as local time; the internal FILETIME in the $I* file is set to the UTC equivalent, while the file's
    LastWriteTime and CreationTime are set to the local time. If time components are missing (e.g., date only
    or hour only), they are randomly generated down to milliseconds. Invalid formats will trigger an error
    unless -Silent is specified.

.PARAMETER Silent
    Suppresses all output, including errors (e.g., invalid date format, file access issues) and the result table.
    Use this switch for quiet operation.

.EXAMPLE
    .\ModifyRecycleBin.ps1 -SearchString "example.txt" -NewDeletionTime "2025-09-03 17:00:00"
    Searches for a deleted file named "example.txt" (case-insensitive) and sets its internal FILETIME to
    the UTC equivalent of September 3, 2025, 5:00 PM local time, and its LastWriteTime and CreationTime
    to 5:00 PM local time. Displays results or a "no matches" message.

.EXAMPLE
    .\ModifyRecycleBin.ps1 -SearchString "*.txt" -NewDeletionTime "2025-09-03" -Silent
    Searches for all .txt files (case-insensitive), sets their internal FILETIME to the UTC equivalent
    of 2025-09-03 with random hours, minutes, seconds, and milliseconds (e.g., 2025-09-03 14:27:19.583 UTC),
    and their LastWriteTime and CreationTime to the same local time, running silently.

.EXAMPLE
    .\ModifyRecycleBin.ps1 -SearchString "C:/Users/*/Documents/*.txt" -NewDeletionTime "2025-09-03 17:00"
    Searches for all .txt files in any user's Documents folder (case-insensitive, normalizes slashes), sets their
    internal FILETIME to the UTC equivalent of 2025-09-03 17:00 with random minutes, seconds, and milliseconds
    (e.g., 2025-09-03 17:42:09.127 UTC), and their LastWriteTime and CreationTime to the local time equivalent.

.EXAMPLE
    .\ModifyRecycleBin.ps1 -SearchString "File?.txt" -NewDeletionTime "2025-09-03 17:5:30"
    Searches for files like "File1.txt" or "File2.txt" and sets their internal FILETIME to the UTC
    equivalent of 2025-09-03 17:05:30 local time, and their LastWriteTime and CreationTime to 17:05:30 local time.

.EXAMPLE
    .\ModifyRecycleBin.ps1 -SearchString "File.txt" -NewDeletionTime "invalid-date" -Silent
    Attempts to parse an invalid date, but with -Silent, exits without displaying the error.

.NOTES
    Version: 1.0.7.6
    Author: Recycle Bin Modifier Developer
    Requires: Administrative privileges to access $RECYCLE.BIN.
    Date formats must be valid (e.g., "2025-09-03 17:00:00"). Invalid formats are suppressed with -Silent.
    Incomplete time inputs (e.g., date only, missing seconds, or single-digit minutes/seconds) will have
    missing components randomly generated. The NewDeletionTime is interpreted as local time; the internal
    FILETIME is set to UTC, while LastWriteTime and CreationTime are set to local time.
    Search is case-insensitive, normalizes paths, and supports wildcards (*, ?) for flexible matching.
    Access errors (e.g., denied access to Recycle Bin subfolders) are handled gracefully to continue searching other drives.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$SearchString,
    [Parameter(Mandatory=$true)]
    [string]$NewDeletionTime,
    [Parameter(Mandatory=$false)]
    [switch]$Silent
)

try {
    # Validate and convert NewDeletionTime to datetime (local time)
    $parsedDateTime = $null
    try {
        $parsedDateTime = [datetime]::Parse($NewDeletionTime)
    } catch {
        if (-not $Silent) {
            Write-Error "Invalid date format for NewDeletionTime: '$NewDeletionTime'. Please use a valid date format (e.g., '2025-09-03 17:00:00')."
        }
        exit
    }

    # Check if time components are missing and randomly generate them
    $timePart = $NewDeletionTime -replace '.*\s+', ''
    if ($timePart.Length -lt 12) {
        # Generate random time components
        $random = New-Object System.Random
        $hours = if ($parsedDateTime.Hour -eq 0 -and -not $timePart) { $random.Next(0, 24) } else { $parsedDateTime.Hour }
        $minutes = if ($parsedDateTime.Minute -eq 0 -and -not ($timePart -match ':\d{1,2}')) { $random.Next(0, 60) } else { $parsedDateTime.Minute }
        $seconds = if ($parsedDateTime.Second -eq 0 -and -not ($timePart -match ':\d{1,2}:\d{1,2}')) { $random.Next(0, 60) } else { $parsedDateTime.Second }
        $milliseconds = if ($parsedDateTime.Second -eq 0) { $random.Next(0, 1000) } else { $parsedDateTime.Millisecond }
        # Reconstruct datetime with random components (local time)
        $parsedDateTime = New-Object DateTime($parsedDateTime.Year, $parsedDateTime.Month, $parsedDateTime.Day, $hours, $minutes, $seconds, $milliseconds)
    }

    function ParseAndModifyRecycleFile {
        param(
            [string]$FilePath,
            [string]$TargetSearchString,
            [long]$NewFileTimeValue,
            [datetime]$NewDateTime
        )

        try {
            $bytes = [System.IO.File]::ReadAllBytes($FilePath)
        } catch {
            if (-not $Silent) { Write-Warning "Failed to read file: $FilePath. Error: $_" }
            return $null
        }

        if ($bytes.Length -lt 30) {
            if (-not $Silent) { Write-Warning "File too small or corrupted: $FilePath" }
            return $null
        }

        # Extract OriginalPath for matching
        # Next 4 bytes (indices 24–27): PathLength
        $nextFourBytes = $bytes[24..27]
        $pathLength = [BitConverter]::ToInt32($nextFourBytes, 0)

        # File path (index 28 until 00 00, UTF-16LE)
        $pathBytes = @()
        $i = 28
        while ($i -lt ($bytes.Length - 1) -and -not ($bytes[$i] -eq 0x00 -and $bytes[$i + 1] -eq 0x00)) {
            $pathBytes += $bytes[$i]
            $pathBytes += $bytes[$i + 1]
            $i += 2
        }
        if ($i -ge $bytes.Length - 1 -or -not ($bytes[$i] -eq 0x00 -and $bytes[$i + 1] -eq 0x00)) {
            if (-not $Silent) { Write-Warning "Invalid path format in file: $FilePath" }
            return $null
        }

        $originalPath = [System.Text.Encoding]::Unicode.GetString($pathBytes).TrimEnd("`0").Trim()

        # Normalize paths: convert slashes to backslashes, trim whitespace
        $normalizedOriginalPath = $originalPath -replace '/', '\' -replace '\s+', ' '
        $normalizedTargetSearchString = $TargetSearchString -replace '/', '\' -replace '\s+', ' '

        # Determine match type
        $isFullPathMatch = $normalizedTargetSearchString.Contains('\')
        $match = $false
        if ($isFullPathMatch) {
            if ($normalizedOriginalPath -like $normalizedTargetSearchString) {
                $match = $true
            }
        } else {
            $fileName = [System.IO.Path]::GetFileName($normalizedOriginalPath)
            if ($fileName -like $normalizedTargetSearchString) {
                $match = $true
            }
        }

        if (-not $match) {
            return $null
        }

        # Modify FILETIME (bytes 16-23) with UTC time
        $newTimeBytes = [BitConverter]::GetBytes($NewFileTimeValue)
        for ($j = 0; $j -lt 8; $j++) {
            $bytes[16 + $j] = $newTimeBytes[$j]
        }

        # Write back to file and update LastWriteTime and CreationTime with local time
        try {
            [System.IO.File]::WriteAllBytes($FilePath, $bytes)
            [System.IO.File]::SetLastWriteTime($FilePath, $NewDateTime)
            [System.IO.File]::SetCreationTime($FilePath, $NewDateTime)
            return [PSCustomObject]@{
                RecycleFile = $FilePath
                OriginalPath = $originalPath
                Status = "Modified"
                NewDeletionTime = $NewDateTime
            }
        } catch {
            if (-not $Silent) { Write-Warning "Failed to modify file or update timestamps: $FilePath. Error: $_" }
            return [PSCustomObject]@{
                RecycleFile = $FilePath
                OriginalPath = $originalPath
                Status = "Failed to modify: $_"
                NewDeletionTime = $NewDateTime
            }
        }
    }

    $results = @()
    $newFileTime = $parsedDateTime.ToFileTime()

    $drives = Get-PSDrive -PSProvider FileSystem

    foreach ($drive in $drives) {
        $recycleBin = Join-Path $drive.Root '$RECYCLE.BIN'
        if (Test-Path $recycleBin) {
            try {
                $files = Get-ChildItem -Path $recycleBin -Recurse -Filter '$I*' -Force -File -ErrorAction SilentlyContinue
                foreach ($file in $files) {
                    $modified = ParseAndModifyRecycleFile -FilePath $file.FullName -TargetSearchString $SearchString -NewFileTimeValue $newFileTime -NewDateTime $parsedDateTime
                    if ($modified) {
                        $results += $modified
                    }
                }
            } catch {
                if (-not $Silent) { Write-Warning "Error accessing $recycleBin. Error: $_" }
            }
        }
    }

    if (-not $Silent) {
        if ($results.Count -eq 0) {
            Write-Output "No matching deleted files found for '$SearchString'."
        } else {
            $results | Format-Table -AutoSize
        }
    }
} catch {
    if (-not $Silent) {
        Write-Error $_.Exception.Message
    }
}