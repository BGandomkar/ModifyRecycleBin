# Usage

```powershell
# Modify (default)
.\ModifyRecycleBin.ps1 -SearchString <string> -NewDeletionTime <string> [-Silent] [-SkipRFileUpdate] [-Backup] [-BackupPath <path>] [-WhatIf]

# List only
.\ModifyRecycleBin.ps1 -SearchString <string> -List [-Silent]
```

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `-SearchString` | Yes | Filename or path pattern (`*`, `?` allowed) |
| `-NewDeletionTime` | Modify / WhatIf | Local time to set as deletion time |
| `-List` | List mode | Report matches only; no writes |
| `-WhatIf` | No | Dry-run; show `WouldModify` without writing |
| `-Silent` | No | Suppress warnings and tables |
| `-SkipRFileUpdate` | No | Do not update paired `$R*` timestamps (default updates `$R*`) |
| `-Backup` | No | Copy original `$I*` bytes before modify |
| `-BackupPath` | No | Backup root; default `.\RecycleBinBackups\<yyyyMMdd-HHmmss>\` |

## Examples

**List**

```powershell
.\ModifyRecycleBin.ps1 -SearchString "*.docx" -List
```

**Dry-run**

```powershell
.\ModifyRecycleBin.ps1 -SearchString "report.pdf" -NewDeletionTime "2025-09-03 17:00:00" -WhatIf
```

**Modify with backup**

```powershell
.\ModifyRecycleBin.ps1 -SearchString "report.pdf" -NewDeletionTime "2025-09-03 17:00:00" -Backup
```

**Modify `$I*` only**

```powershell
.\ModifyRecycleBin.ps1 -SearchString "notes.txt" -NewDeletionTime "2025-09-03 17:00:00" -SkipRFileUpdate
```

**Custom backup root**

```powershell
.\ModifyRecycleBin.ps1 -SearchString "*.txt" -NewDeletionTime "2025-09-03" -Backup -BackupPath "D:\Backups\RB"
```

Incomplete times (e.g. date only) get missing components filled randomly down to milliseconds.
