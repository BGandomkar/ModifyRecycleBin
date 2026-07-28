# Installation

## Requirements

- Windows 10 or later
- PowerShell 5.1 or later
- Administrator privileges to read/write `$RECYCLE.BIN`

## Setup

No install step is required. Copy or clone the repo and run `ModifyRecycleBin.ps1` from an elevated session.

If script execution is restricted:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Then:

```powershell
cd path\to\ModifyRecycleBin
.\ModifyRecycleBin.ps1 -SearchString "*.txt" -List
```
