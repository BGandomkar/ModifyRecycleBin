# Changelog

All notable changes to this project are documented in this file.

## [1.1.0] - 2026-07-28

### Added

- `-WhatIf` dry-run via `SupportsShouldProcess` (no writes, no backups created).
- `-List` mode to report matching Recycle Bin entries without modifying them.
- Default update of paired `$R*` file timestamps; opt out with `-SkipRFileUpdate`.
- Optional `-Backup` / `-BackupPath` to copy original `$I*` bytes before modify.
- Lean documentation under `docs/`, plus root `CONTRIBUTING.md`.

### Changed

- Comment-based help rewritten for v1.1.0.
- Result table includes `RFile`, `CurrentDeletionTime`, `NewDeletionTime`, and `BackupPath`.

## [1.0.7.6] - prior

- Initial documented release: search `$I*` files and set deletion FILETIME plus `$I*` filesystem timestamps.
