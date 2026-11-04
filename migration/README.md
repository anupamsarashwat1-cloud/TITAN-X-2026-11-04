# SMVDU TITAN-X — Repository Migration Suite & Audit Records

## Overview
This directory contains the complete provenance, audit trails, source inventories, and cryptographic checksum verifications for the migration of the SMVDU TITAN-X SoC project into the canonical repository `TITAN-X-2026-11-04`.

- **Primary Migration Source**: `https://github.com/anupamsarashwat1-cloud/TITAN-X-2026-11-03.git` (Commit: `a71bf8b548004bb11e29cef8de882a8614341437`)
- **Secondary Historical Reference**: `https://github.com/anupamsarashwat1-cloud/TITAN-X-All-Modules-27-Oct-2026.git` (Commit: `44ab348d6d4ae015bb7d825c00a60429f52f3549`)
- **Target Repository**: `https://github.com/anupamsarashwat1-cloud/TITAN-X-2026-11-04.git`
- **Active Migration Branch**: `repository/migration-2026-11-04`

## Directory Structure
- `manifests/`:
  - `SOURCE_FILE_MANIFEST.csv`: Comprehensive row-by-row accounting of all 832 source files, including SHA-256 hashes, classifications, target destinations, and dispositions.
  - `SOURCE_MODULE_INVENTORY.csv`: Exhaustive hardware module inventory detailing module declarations, parent files, include dependencies, memory images, and sub-module instantiations.
- `reports/`:
  - `SOURCE_REPOSITORY_INVENTORY.md`: Summary breakdown of source repositories and directory structures.
  - `SOURCE_COMPARISON_REPORT.md`: Detailed diff analysis between `27-Oct-2026` and `2026-11-03`.
  - `SOURCE_DEPENDENCY_MAP.md`: Top-level system hierarchy diagram and module dependency trees.
  - `SOURCE_DIRECTORY_TREE.txt`: Complete source filesystem tree listing.
- `checksums/`:
  - `MIGRATION_CHECKSUM_VERIFICATION.txt`: Evidence log verifying that 100% of migrated files matched their source SHA-256 hashes with zero discrepancies.
