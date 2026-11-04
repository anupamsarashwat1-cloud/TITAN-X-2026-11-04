# Changelog — SMVDU TITAN-X

All notable changes to the SMVDU TITAN-X SoC project will be documented in this file.

## [2026-11-04] — Migration & Qualification Release

### Added
- Created canonical repository `TITAN-X-2026-11-04` with top-level structure and dedicated `Design Files of TITAN X/` directory.
- Comprehensive provenance manifests: `SOURCE_FILE_MANIFEST.csv`, `SOURCE_MODULE_INVENTORY.csv`, `SOURCE_COMPARISON_REPORT.md`, `SOURCE_DEPENDENCY_MAP.md`.
- SHA-256 integrity verification logging in `migration/checksums/MIGRATION_CHECKSUM_VERIFICATION.txt`.
- Architecture specification in `Design Files of TITAN X/ARCHITECTURE.md`.

### Migrated & Preserved
- 100% of original design modules across 13 subsystems: `backend/`, `frontend/`, `common/`, `interconnect/`, `memory/`, `peripherals/`, `security/`, `storage/`, `video/`, `top/`, `includes/`, `bfm/`, `firmware/`.
- All 63 module-specific README documentation files preserved in-place beside corresponding RTL blocks.
- All memory initialization files (`.mem`, `.hex`) and firmware assets.
- Complete verification suite, testbenches, GTKWave waveform captures, formal SVA proofs, and build scripts.
