# Contributing

## Requirements

- Windows 10+ with PowerShell 5.1+
- Run the script elevated (Administrator) when testing Recycle Bin access

## Guidelines

- Keep the comment-based help block at the top of `ModifyRecycleBin.ps1` in sync with parameters and behavior (`Get-Help .\ModifyRecycleBin.ps1 -Full`).
- Update `CHANGELOG.md` and relevant files under `docs/` when behavior changes.
- Prefer small, focused pull requests with a short description of why the change is needed.

## Pull requests

1. Fork or branch from the default branch.
2. Make your changes and verify List / WhatIf / Modify paths still work.
3. Open a pull request with a clear summary and test notes.
