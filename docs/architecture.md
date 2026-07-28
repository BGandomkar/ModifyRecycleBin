# Architecture

## Recycle Bin layout

Each drive may contain `$RECYCLE.BIN\<user-SID>\` with pairs of files:

- `$I*` — metadata (original path, deletion FILETIME)
- `$R*` — deleted content

Pairing: same directory, same suffix after the `$I` / `$R` prefix (e.g. `$Iabc123` ↔ `$Rabc123`).

## `$I*` binary fields (Vista+)

| Offset | Size | Meaning |
|--------|------|---------|
| 0–7 | 8 | Header / version |
| 8–15 | 8 | File size |
| 16–23 | 8 | Deletion FILETIME (UTC-based Windows FILETIME) |
| 24–27 | 4 | Path length |
| 28+ | var | Original path (UTF-16LE, null-terminated) |

Explorer’s “Date deleted” is driven by this FILETIME and related filesystem times on `$I*` / `$R*`.

## Timestamp model

- Input `NewDeletionTime` is **local time**.
- Bytes 16–23 store `ToFileTime()` (UTC-based FILETIME).
- `$I*` `LastWriteTime` and `CreationTime` are set to the local datetime.
- By default, paired `$R*` gets the same local datetime on `LastAccessTime`, `LastWriteTime`, and `CreationTime` (opt out with `-SkipRFileUpdate`).

## Processing modes

1. Scan filesystem drives for `$RECYCLE.BIN`.
2. Recurse `$I*` files; parse path and FILETIME; match `-SearchString`.
3. Branch:
   - **List** — emit row; no write
   - **WhatIf** — emit `WouldModify`; no write / no backup file
   - **Modify** — optional backup of original `$I*` bytes, patch FILETIME, set `$I*` times, optionally update `$R*`

See the flowchart in the [README](../README.md#how-it-works).
