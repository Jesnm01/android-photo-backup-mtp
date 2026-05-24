# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project follows Semantic Versioning.

## [1.0.0] - 2026-05-24
### Added
- Initial public release of the Android photo backup script over USB/MTP.
- Incremental copy behavior with duplicate detection to avoid recopying.
- Folder structure preservation from source device.
- Exclusion rules for unwanted paths such as Android cache folders and WhatsApp.
- Multi-destination backup support.
- Per-run logs with final summary and benchmark metrics.
- Automatic separation by source device name under each destination root.
- Interactive and automatic modes (`-Auto`, `-DeviceIndex`, `-StorageIndex`, `-NoPause`).

