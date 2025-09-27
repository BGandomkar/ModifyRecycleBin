# ModifyRecycleBin.ps1

## Overview
`ModifyRecycleBin.ps1` is a PowerShell script that modifies the deletion time of files in the Windows Recycle Bin. It searches all partitions for `$RECYCLE.BIN` folders, matches `$I*` files (containing deleted file metadata) against a case-insensitive search string with wildcard support, and updates:
- The internal `FILETIME` (deletion time).
- The `$I*` file’s `LastWriteTime` and `CreationTime`.

All timestamps are set to the provided `NewDeletionTime` in local time, matching the Recycle Bin UI’s "Date Deleted" display. Incomplete time inputs are randomized (e.g., hours, minutes, seconds, milliseconds). Run as Administrator.

## Features
- **Wildcard Search**: Supports `*` (any characters) and `?` (single character), e.g., `*.txt` or `C:\Users\*\*.txt`.
- **Local Time**: `NewDeletionTime` is local time, applied to `FILETIME`, `LastWriteTime`, and `CreationTime`.
- **Error Handling**: Handles access errors gracefully; `-Silent` switch suppresses output.
- **Random Time Generation**: Fills missing time components with random values.

## Requirements
- Windows (tested on Windows 10+)
- PowerShell 5.1+
- Administrative privileges

## Usage
Run in an elevated PowerShell session:
```powershell
.\ModifyRecycleBin.ps1 -SearchString <string> -NewDeletionTime <string> [-Silent]
```
- `-SearchString`: Filename or path to match (supports wildcards).
- `-NewDeletionTime`: Local time (e.g., "2025-09-03 17:00:00"); incomplete times are randomized.
- `-Silent`: Suppresses all output.

## Examples
1. **Modify Specific File**
   ```powershell
   .\ModifyRecycleBin.ps1 -SearchString "example.txt" -NewDeletionTime "2025-09-03 17:00:00"
   ```
   Sets `FILETIME`, `LastWriteTime`, and `CreationTime` to 2025-09-03 17:00:00 local time for `example.txt`.

2. **Modify All .txt Files**
   ```powershell
   .\ModifyRecycleBin.ps1 -SearchString "*.txt" -NewDeletionTime "2025-09-03" -Silent
   ```
   Sets timestamps for all `.txt` files to 2025-09-03 with random time components, silently.

3. **Wildcard Path Search**
   ```powershell
   .\ModifyRecycleBin.ps1 -SearchString "C:\Users\*\Documents\*.txt" -NewDeletionTime "2025-09-03 17:5"
   ```
   Sets timestamps for `.txt` files in Documents folders to 2025-09-03 17:05 with random seconds/milliseconds.

## Notes
- **Date Formats**: Use valid local time formats (e.g., "2025-09-03 17:00", "09/03/2025 17:5"). Incomplete times are randomized.
- **Recycle Bin**: Mirrors behavior where `$I*` file’s `LastWriteTime` and `CreationTime` match `$R*` file’s `LastAccessTime` (local time).
- **Search**: Case-insensitive, normalizes paths (slashes, whitespace).

## Troubleshooting
- **No Matches**: Verify `-SearchString` matches "Original Location" in Recycle Bin.
- **Permissions**: Run as Administrator; check warnings (without `-Silent`).
- **Timestamps**: Use `Get-Item C:\$RECYCLE.BIN\S-1-5-...\I* | Select-Object LastWriteTime, CreationTime` and check Recycle Bin UI.


## Contributing
Submit pull requests or issues for improvements or bugs.
