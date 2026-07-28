<#
.SYNOPSIS
    Lists or modifies the deletion time of files in the Windows Recycle Bin.

.DESCRIPTION
    Searches all partitions for $RECYCLE.BIN folders, recursively finds $I* metadata files,
    and matches them against a search string (filename or full original path). Matching is
    case-insensitive, normalizes slashes and whitespace, and supports wildcards (*, ?).

    Modes:
    - Modify (default): updates the internal FILETIME (deletion time) in matching $I* files
      to the UTC equivalent of NewDeletionTime, and sets LastWriteTime and CreationTime on
      the $I* file to NewDeletionTime (local). By default also updates the paired $R* file
      timestamps (LastAccessTime, LastWriteTime, CreationTime). Use -SkipRFileUpdate to
      leave $R* files unchanged. Use -Backup to copy original $I* bytes before writing.
    - -WhatIf: dry-run; reports what would change without writing files or creating backups.
    - -List: reports matching entries (current deletion time, paths) without writing.

    Incomplete NewDeletionTime values (e.g. date only) have missing time components randomly
    generated down to milliseconds. Run as administrator to access the Recycle Bin.

.PARAMETER SearchString
    Filename or full original path to match in the Recycle Bin.
    Case-insensitive; normalizes "/" and "\"; supports * and ?.
    Examples: "example.txt", "*.txt", "C:\Users\*\Documents\*.txt".

.PARAMETER NewDeletionTime
    New deletion time as local time (required for Modify / -WhatIf; not used with -List).
    Examples: "YYYY-MM-DD HH:MM:SS", "MM/DD/YYYY HH:MM", "YYYY-MM-DD".
    Internal FILETIME is stored as UTC; filesystem timestamps use local time.
    Missing time components are randomly generated unless -Silent suppresses related errors.

.PARAMETER List
    List matching Recycle Bin entries only. Does not modify files. NewDeletionTime is not required.

.PARAMETER Silent
    Suppresses warnings, errors, and the result table.

.PARAMETER SkipRFileUpdate
    Do not update timestamps on the paired $R* content file. By default $R* is updated.

.PARAMETER Backup
    Before modifying an $I* file, copy its original bytes under BackupPath.

.PARAMETER BackupPath
    Root directory for $I* backups. Default: .\RecycleBinBackups\<yyyyMMdd-HHmmss>\
    under the current location. Files are stored as drive\SID\$I* name under that root.

.EXAMPLE
    .\ModifyRecycleBin.ps1 -SearchString "example.txt" -NewDeletionTime "2025-09-03 17:00:00"
    Modifies matching $I* (and paired $R*) deletion-related timestamps.

.EXAMPLE
    .\ModifyRecycleBin.ps1 -SearchString "*.txt" -NewDeletionTime "2025-09-03 17:00:00" -WhatIf
    Dry-run: shows what would be modified without writing.

.EXAMPLE
    .\ModifyRecycleBin.ps1 -SearchString "*.txt" -List
    Lists matching deleted files and their current deletion times.

.EXAMPLE
    .\ModifyRecycleBin.ps1 -SearchString "report.docx" -NewDeletionTime "2025-09-03 17:00:00" -Backup
    Backs up original $I* bytes, then modifies $I* and paired $R*.

.EXAMPLE
    .\ModifyRecycleBin.ps1 -SearchString "notes.txt" -NewDeletionTime "2025-09-03 17:00:00" -SkipRFileUpdate
    Updates $I* only; leaves the paired $R* file timestamps unchanged.

.EXAMPLE
    .\ModifyRecycleBin.ps1 -SearchString "C:/Users/*/Documents/*.txt" -NewDeletionTime "2025-09-03 17:00" -Backup -BackupPath "D:\Backups\RB"
    Path wildcard match; backs up original $I* bytes under D:\Backups\RB\<yyyyMMdd-HHmmss>\.

.EXAMPLE
    .\ModifyRecycleBin.ps1 -SearchString "*.txt" -NewDeletionTime "2025-09-03" -Silent
    Modifies all matching .txt entries with randomized missing time parts, with no console output.

.NOTES
    Version: 1.1.0
    Author: Recycle Bin Modifier Developer
    Requires: Administrative privileges to access $RECYCLE.BIN.
    -WhatIf is provided by SupportsShouldProcess (dry-run; no writes, no backups written).
    -List and -WhatIf never modify Recycle Bin files.
    $I* and $R* share the same suffix in the same SID folder (e.g. $Iabc -> $Rabc).
    Search is case-insensitive with path normalization and wildcards (*, ?).
    Access errors are handled so other drives can still be searched.
#>

[CmdletBinding(DefaultParameterSetName = 'Modify', SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Modify')]
    [Parameter(Mandatory = $true, ParameterSetName = 'List')]
    [string]$SearchString,

    [Parameter(Mandatory = $true, ParameterSetName = 'Modify')]
    [string]$NewDeletionTime,

    [Parameter(Mandatory = $true, ParameterSetName = 'List')]
    [switch]$List,

    [Parameter(Mandatory = $false)]
    [switch]$Silent,

    [Parameter(Mandatory = $false, ParameterSetName = 'Modify')]
    [switch]$SkipRFileUpdate,

    [Parameter(Mandatory = $false, ParameterSetName = 'Modify')]
    [switch]$Backup,

    [Parameter(Mandatory = $false, ParameterSetName = 'Modify')]
    [string]$BackupPath
)

function Get-PairedRFilePath {
    param([string]$IFilePath)
    $dir = Split-Path -Parent $IFilePath
    $name = Split-Path -Leaf $IFilePath
    if ($name -like '$I*') {
        $rName = '$R' + $name.Substring(2)
        return (Join-Path $dir $rName)
    }
    return $null
}

function Get-BackupTargetPath {
    param(
        [string]$IFilePath,
        [string]$SessionBackupRoot
    )
    # Prefer path under $RECYCLE.BIN (drive\SID\$I*)
    $marker = '$RECYCLE.BIN'
    $idx = $IFilePath.IndexOf($marker, [System.StringComparison]::OrdinalIgnoreCase)
    if ($idx -ge 0) {
        $relative = $IFilePath.Substring($idx + $marker.Length).TrimStart('\', '/')
        $driveLetter = $IFilePath.Substring(0, 1)
        return (Join-Path $SessionBackupRoot (Join-Path $driveLetter $relative))
    }
    $safeName = ($IFilePath -replace '[:\\\/]', '_')
    return (Join-Path $SessionBackupRoot $safeName)
}

function New-ResultObject {
    param(
        [string]$RecycleFile,
        [string]$OriginalPath,
        [string]$RFile,
        [string]$Status,
        $CurrentDeletionTime,
        $NewDeletionTime,
        [string]$BackupFilePath
    )
    return [PSCustomObject]@{
        RecycleFile         = $RecycleFile
        OriginalPath        = $OriginalPath
        RFile               = $RFile
        Status              = $Status
        CurrentDeletionTime = $CurrentDeletionTime
        NewDeletionTime     = $NewDeletionTime
        BackupPath          = $BackupFilePath
    }
}

try {
    $isListMode = $PSCmdlet.ParameterSetName -eq 'List'
    $parsedDateTime = $null
    $newFileTime = [long]0
    $sessionBackupRoot = $null

    if (-not $isListMode) {
        try {
            $parsedDateTime = [datetime]::Parse($NewDeletionTime)
        } catch {
            if (-not $Silent) {
                Write-Error "Invalid date format for NewDeletionTime: '$NewDeletionTime'. Please use a valid date format (e.g., '2025-09-03 17:00:00')."
            }
            exit 1
        }

        # Check if time components are missing and randomly generate them
        $timePart = $NewDeletionTime -replace '.*\s+', ''
        if ($timePart.Length -lt 12) {
            $random = New-Object System.Random
            $hours = if ($parsedDateTime.Hour -eq 0 -and -not $timePart) { $random.Next(0, 24) } else { $parsedDateTime.Hour }
            $minutes = if ($parsedDateTime.Minute -eq 0 -and -not ($timePart -match ':\d{1,2}')) { $random.Next(0, 60) } else { $parsedDateTime.Minute }
            $seconds = if ($parsedDateTime.Second -eq 0 -and -not ($timePart -match ':\d{1,2}:\d{1,2}')) { $random.Next(0, 60) } else { $parsedDateTime.Second }
            $milliseconds = if ($parsedDateTime.Second -eq 0) { $random.Next(0, 1000) } else { $parsedDateTime.Millisecond }
            $parsedDateTime = New-Object DateTime($parsedDateTime.Year, $parsedDateTime.Month, $parsedDateTime.Day, $hours, $minutes, $seconds, $milliseconds)
        }

        $newFileTime = $parsedDateTime.ToFileTime()

        if ($Backup) {
            $root = if ($BackupPath) { $BackupPath } else { Join-Path (Get-Location) 'RecycleBinBackups' }
            $sessionBackupRoot = Join-Path $root (Get-Date -Format 'yyyyMMdd-HHmmss')
        }
    }

    function Invoke-RecycleInfoFile {
        param(
            [string]$FilePath,
            [string]$TargetSearchString,
            [long]$NewFileTimeValue,
            [datetime]$NewDateTime,
            [bool]$ListOnly,
            [bool]$DoBackup,
            [string]$BackupRoot,
            [bool]$UpdateRFile
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

        # File path (index 28 until 00 00, UTF-16LE)
        $pathBytes = New-Object System.Collections.Generic.List[byte]
        $i = 28
        while ($i -lt ($bytes.Length - 1) -and -not ($bytes[$i] -eq 0x00 -and $bytes[$i + 1] -eq 0x00)) {
            [void]$pathBytes.Add($bytes[$i])
            [void]$pathBytes.Add($bytes[$i + 1])
            $i += 2
        }
        if ($i -ge $bytes.Length - 1 -or -not ($bytes[$i] -eq 0x00 -and $bytes[$i + 1] -eq 0x00)) {
            if (-not $Silent) { Write-Warning "Invalid path format in file: $FilePath" }
            return $null
        }

        $originalPath = [System.Text.Encoding]::Unicode.GetString($pathBytes.ToArray()).TrimEnd("`0").Trim()

        $normalizedOriginalPath = $originalPath -replace '/', '\' -replace '\s+', ' '
        $normalizedTargetSearchString = $TargetSearchString -replace '/', '\' -replace '\s+', ' '

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

        $currentFileTimeValue = [BitConverter]::ToInt64($bytes, 16)
        $currentDeletionTime = $null
        try {
            $currentDeletionTime = [DateTime]::FromFileTime($currentFileTimeValue)
        } catch {
            $currentDeletionTime = $null
        }

        $rFilePath = Get-PairedRFilePath -IFilePath $FilePath
        $rFileDisplay = if ($rFilePath -and (Test-Path -LiteralPath $rFilePath)) { $rFilePath } else { '' }

        if ($ListOnly) {
            return (New-ResultObject -RecycleFile $FilePath -OriginalPath $originalPath -RFile $rFileDisplay `
                -Status 'Listed' -CurrentDeletionTime $currentDeletionTime -NewDeletionTime $null -BackupFilePath '')
        }

        $backupTarget = ''
        if ($DoBackup -and $BackupRoot) {
            $backupTarget = Get-BackupTargetPath -IFilePath $FilePath -SessionBackupRoot $BackupRoot
        }

        $rNote = if ($UpdateRFile) { 'and R*' } else { 'I* only' }
        if (-not $PSCmdlet.ShouldProcess($FilePath, "Set deletion time to $NewDateTime ($rNote)")) {
            return (New-ResultObject -RecycleFile $FilePath -OriginalPath $originalPath -RFile $rFileDisplay `
                -Status 'WouldModify' -CurrentDeletionTime $currentDeletionTime -NewDeletionTime $NewDateTime `
                -BackupFilePath $(if ($DoBackup) { $backupTarget } else { '' }))
        }

        if ($DoBackup) {
            try {
                $backupDir = Split-Path -Parent $backupTarget
                if (-not (Test-Path -LiteralPath $backupDir)) {
                    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
                }
                [System.IO.File]::WriteAllBytes($backupTarget, $bytes)
            } catch {
                if (-not $Silent) { Write-Warning "Backup failed for $FilePath. Error: $_. Skipping modify." }
                return (New-ResultObject -RecycleFile $FilePath -OriginalPath $originalPath -RFile $rFileDisplay `
                    -Status "Backup failed: $_" -CurrentDeletionTime $currentDeletionTime -NewDeletionTime $NewDateTime `
                    -BackupFilePath $backupTarget)
            }
        }

        $newTimeBytes = [BitConverter]::GetBytes($NewFileTimeValue)
        for ($j = 0; $j -lt 8; $j++) {
            $bytes[16 + $j] = $newTimeBytes[$j]
        }

        try {
            [System.IO.File]::WriteAllBytes($FilePath, $bytes)
            [System.IO.File]::SetLastWriteTime($FilePath, $NewDateTime)
            [System.IO.File]::SetCreationTime($FilePath, $NewDateTime)
        } catch {
            if (-not $Silent) { Write-Warning "Failed to modify file or update timestamps: $FilePath. Error: $_" }
            return (New-ResultObject -RecycleFile $FilePath -OriginalPath $originalPath -RFile $rFileDisplay `
                -Status "Failed to modify: $_" -CurrentDeletionTime $currentDeletionTime -NewDeletionTime $NewDateTime `
                -BackupFilePath $(if ($DoBackup) { $backupTarget } else { '' }))
        }

        $status = 'Modified'
        if ($UpdateRFile) {
            if ($rFilePath -and (Test-Path -LiteralPath $rFilePath)) {
                try {
                    [System.IO.File]::SetLastAccessTime($rFilePath, $NewDateTime)
                    [System.IO.File]::SetLastWriteTime($rFilePath, $NewDateTime)
                    [System.IO.File]::SetCreationTime($rFilePath, $NewDateTime)
                } catch {
                    if (-not $Silent) { Write-Warning "Failed to update paired R* file: $rFilePath. Error: $_" }
                    $status = "Modified (R* update failed: $_)"
                }
            } else {
                if (-not $Silent) { Write-Warning "Paired R* file not found for: $FilePath" }
                $status = 'Modified (R* missing)'
                $rFileDisplay = ''
            }
        }

        return (New-ResultObject -RecycleFile $FilePath -OriginalPath $originalPath -RFile $rFileDisplay `
            -Status $status -CurrentDeletionTime $currentDeletionTime -NewDeletionTime $NewDateTime `
            -BackupFilePath $(if ($DoBackup) { $backupTarget } else { '' }))
    }

    $results = @()
    $drives = Get-PSDrive -PSProvider FileSystem

    foreach ($drive in $drives) {
        $recycleBin = Join-Path $drive.Root '$RECYCLE.BIN'
        if (Test-Path $recycleBin) {
            try {
                $files = Get-ChildItem -Path $recycleBin -Recurse -Filter '$I*' -Force -File -ErrorAction SilentlyContinue
                foreach ($file in $files) {
                    $processed = Invoke-RecycleInfoFile `
                        -FilePath $file.FullName `
                        -TargetSearchString $SearchString `
                        -NewFileTimeValue $newFileTime `
                        -NewDateTime $(if ($parsedDateTime) { $parsedDateTime } else { [datetime]::MinValue }) `
                        -ListOnly $isListMode `
                        -DoBackup ([bool]$Backup) `
                        -BackupRoot $sessionBackupRoot `
                        -UpdateRFile (-not $SkipRFileUpdate)
                    if ($processed) {
                        $results += $processed
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
