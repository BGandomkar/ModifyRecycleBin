# Getting started

1. Clone or download this repository.
2. Open an **elevated** PowerShell window (Run as administrator).
3. Change to the project folder.
4. List matches first (safe):

```powershell
.\ModifyRecycleBin.ps1 -SearchString "*.txt" -List
```

5. Preview a change with dry-run:

```powershell
.\ModifyRecycleBin.ps1 -SearchString "example.txt" -NewDeletionTime "2025-09-03 17:00:00" -WhatIf
```

6. Apply when the preview looks correct:

```powershell
.\ModifyRecycleBin.ps1 -SearchString "example.txt" -NewDeletionTime "2025-09-03 17:00:00" -Backup
```

See [usage.md](usage.md) for all parameters.
