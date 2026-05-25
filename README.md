# Mobile Photo Backup (MTP) to PC

PowerShell script to run incremental backups of photos and videos from Android over USB (MTP), preserving folder structure and avoiding common duplicates.

## What This Script Does Well
- Incremental backup: avoids re-copying files when they already exist and match.
- Preserves structure: keeps your organization (`DCIM`, `Pictures`, etc.).
- Filters junk: excludes unwanted paths (`Android`, `WhatsApp`, `.thumbnails`, etc.).
- Multi-destination: copies to multiple drives or paths in one run.
- Device separation: creates a subfolder per source device inside each destination.
- Persistent log: writes progress continuously while running.
- Always-on benchmark: shows and logs `Copied MB`, `Files/min`, and `Approx MB/s`.

## Structure
- `CopiaFotosMovil.ps1`: main script.
- `EJECUTAR_COPIA.ps1`: private launcher with your real destination paths.
- `EJECUTAR_COPIA_EJEMPLO.ps1`: template launcher.
- `LauncherAccesoDirecto.bat`: double-click launcher.
- `Logs/`: created automatically.

## Recommended Usage Flow
1. Connect the phone by USB.
2. Unlock it and select **File transfer (MTP)** mode.
3. Run `LauncherAccesoDirecto.bat` or `EJECUTAR_COPIA.ps1`.
4. In interactive mode, select device/storage and confirm.

## Script Parameters
`CopiaFotosMovil.ps1` supports:
- `-Destinos <string[]>`: destination root paths.
- `-Auto`: skips prompts; selects by index.
- `-DeviceIndex <int>`: device index to use in `-Auto` (1-based).
- `-StorageIndex <int>`: storage index to use in `-Auto` (1-based).
- `-NoPause`: does not wait for Enter at the end.
- `-ShowSkipped`: prints each skipped duplicate file.

The script version is defined in `$SCRIPT_VERSION` inside `CopiaFotosMovil.ps1`, and is printed at startup and logged.

Automatic run example:

```powershell
& "$PSScriptRoot\CopiaFotosMovil.ps1" `
  -Destinos @("C:\BackupPhotos","D:\BackupPhotos") `
  -Auto -DeviceIndex 1 -StorageIndex 1 -NoPause
```

## Duplicates and Conflicts
- Main rule: if a destination file exists with the same relative path/name and same size, it is treated as duplicate.
- If MTP cannot provide reliable size, it falls back to timestamp matching.
- This minimizes native Windows conflict popups during periodic incremental runs.

## Per-Device Separation
Inside each destination root, the script creates a folder with the device name (sanitized for Windows).

Example:
- Destination root: `D:\PhotoBackup`
- Device: `Pixel_8`
- Final path: `D:\PhotoBackup\Pixel_8\DCIM\Camera\...`

## If You Stop Mid-Run
- Already copied files remain in destination.
- Already written log entries remain (line-by-line writes).
- Only the final summary may be missing if the run is interrupted early.

## Useful Internal Config
In the script's `$CONFIG` block:
- `AllowedRootFolders`: source root folders to scan.
- `ExcludePaths`: paths to skip.
- `Extensions`: allowed file extensions.
- `CopyTimeoutSeconds`: per-file timeout.

## Suggested Future Improvements
- `-DryRun` mode (simulate without copying).
- Export run summary as CSV or JSON.
- Automatic retries for transient MTP errors.
- Windows Task Scheduler integration for periodic runs.

## MTP Limitations
- Windows MTP does not always expose metadata consistently.
- Performance depends heavily on cable quality, USB port, and average file size.
- Internal EXIF data is preserved, even if Windows file modification timestamps differ.
