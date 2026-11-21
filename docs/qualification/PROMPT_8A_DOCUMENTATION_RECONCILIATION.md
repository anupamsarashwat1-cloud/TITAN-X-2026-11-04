# SMVDU TITAN X — Prompt 8A Documentation Reconciliation Report

**Audit Date:** 2026-11-18  
**Phase:** Prompt 8A Post-Release Engineering Audit & Documentation Reconciliation  
**Authoring Team:**  
- Anupam Sarashwat — 23BEC014  
- Harsh Mishra — 23BEC027  
- Om Kumar — 23BEC038  
**Auditing Agent:** SMVDU TITAN X Engineering Release Agent (Antigravity `d788fd46-4be3-43d3-b340-159440e15655`)  
**Described Source Commit:** `f177eb5b9513b005a029cd15ad8c85c2db3e753f` (Release Tag: `SMVDU-TITAN-X-v1.0.0`) / Reconciled Baseline `579bdcb`  

---

## 1. Scope & Objective

This report documents the systematic reconciliation between actual synthesizable RTL source code, parameter instantiations, hardware interconnect topologies, and all published documentation across the SMVDU TITAN X project repository.

Every parameter, capacity, port dimension, bus width, and test target in this document is derived directly from RTL source inspection and executed tool artifacts.

---

## 2. Reconciled Architectural Discrepancies (Items A–H)

### Item A: L1 Cache Architecture & Geometry Reconciliation
- **Previous Erroneous Claims:** Early documentation drafts reported L1 cache size as "16 KB I$ / 16 KB D$ per core" and suggested Hart 4 (monitor core) had an L1 cache.
- **RTL Source Ground Truth:**
  - `frontend/rv_icache/rv_icache.v`: Parameters declare `WAYS = 8`, `SETS = 64`, `LINE_BYTES = 64`. Geometry: 8 ways $\times$ 64 sets $\times$ 64 bytes = **32 KB I\$**.
  - `backend/rv_dcache/rv_dcache.v`: Parameters declare `WAYS = 8`, `SETS = 64`, `LINE_BYTES = 64`. Geometry: 8 ways $\times$ 64 sets $\times$ 64 bytes = **32 KB D\$**.
  - Per Application Hart (Harts 0–3): **64 KB L1 cache per core** (32 KB I$ + 32 KB D$). Total L1 capacity across Harts 0–3 = **256 KB**.
  - Monitor Core (Hart 4): Direct inspection of `backend/rv_monitor_core/rv_monitor_core.v` confirms that Hart 4 is strictly **UNCACHED**. It has 0 cache instances, interfacing directly to AXI4-Lite for instruction fetch (`imem_arvalid`, `imem_rdata`) and AXI4 for data memory (`dmem_arvalid`, `dmem_awvalid`, `dmem_wdata`, `dmem_rdata`).
- **Reconciliation Actions:** Updated `README.md`, `RELEASE_NOTES.md`, `MODULE_INVENTORY.md`, and `TITAN_X_ARCHITECTURE_BASELINE.md` to reflect 32 KB I$ + 32 KB D$ per application core (Harts 0–3) and uncached direct-AXI operation for Hart 4.

---

### Item B: L2 Cache Synthesizable Macro Baseline vs. Simulation Scalability
- **Previous Erroneous Claims:** Release notes claimed L2 cache was "512 KB".
- **RTL Source Ground Truth:**
  - `memory/l2_cache_top/l2_cache_top.v`: Default parameters declare `L2_WAYS = 16`, `L2_SETS = 64`, `L2_LINE_BYTES = 64`.
    $$\text{Synthesizable Baseline Capacity} = 16 \times 64 \times 64\text{ B} = 65,536\text{ B} = 64\text{ KB}$$
  - The physical data array instantiates **256 macro instances** of `sram_32x64_180nm` (each macro is 32 words $\times$ 64 bits = 256 bytes; $256 \times 256\text{ B} = 64\text{ KB}$).
  - In simulation environments, `includes/params.vh` defines `L2_SETS = 2048`, scaling the simulation memory model to 2 MB ($16 \times 2048 \times 64 = 2\text{ MB}$).
  - The "512 KB" claim was an intermediate 512-set architectural proposal that was never instantiated in compiled macro silicon.
- **Reconciliation Actions:** Explicitly documented the 64 KB synthesizable SRAM macro baseline and parameterizable simulation expansion up to 2 MB in `TITAN_X_ARCHITECTURE_BASELINE.md`, `README.md`, and `RELEASE_NOTES.md`.

---

### Item C: AXI Crossbar Port Dimensions & Active DECERR Responders
- **Previous Discrepancies:** Various diagrams depicted the crossbar as 8x8 or 10x6.
- **RTL Source Ground Truth:**
  - `top/titan_x_top/titan_x_top.v` instantiates `axi4_crossbar` with `NM = 15` and `NS = 9`.
  - **15 Master Ports:**
    - M0–M3: Harts 0–3 I-Cache (AXI4 RO, 64-bit)
    - M4–M7: Harts 0–3 D-Cache (AXI4 RW, 64-bit)
    - M8: Hart 4 Monitor Core Instruction Interface (AXI4-Lite RO, 64-bit)
    - M9: Hart 4 Monitor Core Data Interface (AXI4 RW, 64-bit)
    - M10: PCIe Gen2 Controller Master (AXI4, 128-bit)
    - M11: Gigabit Ethernet MAC (GEM) Master (AXI4, 64-bit)
    - M12: USB OTG 2.0 Master (AXI4, 64-bit)
    - M13: MMC / SD Master (AXI4, 64-bit)
    - M14: Video DMA (VDMA) Master (AXI4, 64-bit)
  - **9 Slave Ports:**
    - S0: L2 Cache Top (`0x8000_0000`–`0x8FFF_FFFF`)
    - S1: AHB/APB Bridge (`0x2000_0000`–`0x2FFF_FFFF`)
    - S2: BootROM Vector (`0x1000_0000`–`0x1000_7FFF`)
    - S3: Fast SRAM Scratchpad (`0x0800_0000`–`0x0800_FFFF`)
    - S4–S8: Internal Hardware Active DECERR Responders (`RRESP=2'b11` / `BRESP=2'b11` DECERR on unmapped aperture accesses)
- **Reconciliation Actions:** Reconciled all interconnect block diagrams, AXI routing tables, and interface descriptions to accurately reflect the 15M $\times$ 9S topology and DECERR handling.

---

### Item D: Multi-Hart Configuration & Reset Gating
- **RTL Source Ground Truth:**
  - Total Harts: **5 Harts** (Hart 0–3: RV64IM_Zicsr Application Cores; Hart 4: RV64IMAC Safety/Monitor Core).
  - Operating Mode: Machine Mode (M-mode) only. All CSR addresses (`mstatus`, `mie`, `mtvec`, `mepc`, `mcause`, `mtval`, `misa`, `mvendorid`, `marchid`, `mimpid`, `mhartid`, `mcycle`, `minstret`) comply with RISC-V Privileged Architecture v1.12.
  - Reset Vector: All 5 harts boot at PC `0x1000_0000`.
  - Reset Gating: All harts are held in hard reset (`core_rst_n = rst_n & boot_pass & wdt_reset_n`) until hardware Root-of-Trust cryptographically verifies the BootROM container.
- **Reconciliation Actions:** Reconciled CPU core subsystem descriptions in `README.md` and `TITAN_X_ARCHITECTURE_BASELINE.md`.

---

### Item E: Qualification Test Matrix Target Inventory Reconciliation
- **Accounting Verification:**
  - `docs/qualification/FINAL_RELEASE_TEST_MATRIX.csv` contains 127 total physical rows:
    - 1 CSV Header Row
    - 120 Simulation Testbenches
    - 5 Formal BMC Proof Suites
    - 1 Top-Level SoC Elaboration Check
    - **Total Test Targets = 126 targets.**
  - Executing `python3 scripts/run_regress.py --self-test` executes 1 test harness validation check, bringing the automated execution targets to **127 targets**.
- **Reconciliation Actions:** Clarified the exact distinction between physical test targets (126) and total validation targets including the harness self-test (127).

---

### Item F: Git Lineage & Release Commit References
- **Lineage Verification:**
  - `471b857`: Prompt 7 engineering completion commit.
  - `f177eb5`: Prompt 8 release freeze commit, tagged `SMVDU-TITAN-X-v1.0.0`.
  - `579bdcb`: Canonical & intermediate three-repository synchronization commit.
  - `9592749`: PART-B dual-parent history-preserving merge commit uniting `bef5c25` and `579bdcb`.
- **Reconciliation Actions:** Updated `FINAL_RELEASE_SIGNOFF.md` and `RELEASE_NOTES.md` to reference the immutable release tag `SMVDU-TITAN-X-v1.0.0` at commit `f177eb5` and subsequent synchronization commits.

---

### Item G: Secure Boot & Cryptographic Chain
- **RTL Source Ground Truth:**
  - `security/secure_boot/secure_boot.v` validates:
    1. Header magic `32'h5449544E` ("TITN")
    2. Anti-rollback image version against hardware OTP eFuses (`efuse_ctrl.v`)
    3. Revocation bitmask against eFuses
    4. Hardware multi-block SHA-256 computation over full payload (words 0 through 42 + code)
    5. Hardware NIST P-256 ECDSA point multiplication and modular arithmetic verification
  - Root-of-Trust holds `boot_pass = 0` and locks the BootROM AXI slave port (`s_arready = 0`) until authentication passes.
- **Reconciliation Actions:** Reconciled security architecture documentation to document the complete hardware cryptographic gating chain.

---

### Item H: Cache Coherence & Snoop Filter Directory Invariants
- **RTL Source Ground Truth:**
  - `memory/l2_snoop_filter/l2_snoop_filter.v` tracks 64 sets $\times$ 32 ways (4 cores $\times$ 8 ways).
  - Directory saturation: Round-robin pointer evicts victim entries. Back-invalidation (`snoop_type = 2'b10`) is asserted to sharers. Dirty cache lines assert `snoop_data_valid` and drain dirty data into L2/DDR4 before eviction completes.
  - Assertions and backpressure prevent race conditions during concurrent multi-core accesses.
- **Reconciliation Actions:** Reconciled memory and coherence architecture documentation.

---

## 3. Reconciled Documentation Inventory

The following project documents have been reviewed and reconciled:

| Document | Path | Reconciled Items |
| :--- | :--- | :--- |
| **Top-Level README** | `README.md` | L1/L2 Cache geometry, 15Mx9S Crossbar, 5-Hart ISA, Commit lineage |
| **Release Notes** | `RELEASE_NOTES.md` | L2 64KB macro vs 2MB sim, L1 32KB+32KB per core, Tag `SMVDU-TITAN-X-v1.0.0` |
| **Final Release Signoff** | `docs/qualification/FINAL_RELEASE_SIGNOFF.md` | Commit lineage (`f177eb5`), 126 test targets + 1 self-test = 127 targets |
| **Qualification Test Matrix** | `docs/qualification/FINAL_RELEASE_TEST_MATRIX.csv` | Header + 126 test targets = 127 lines |
| **Known Limitations** | `docs/qualification/KNOWN_LIMITATIONS.md` | Hart 4 uncached architecture, L2 physical macro baseline |
| **Module Inventory** | `MODULE_INVENTORY.md` | 79 RTL modules verified, 15Mx9S Crossbar, Cache instances |
| **Architecture Baseline** | `TITAN_X_ARCHITECTURE_BASELINE.md` | Full multi-hart, cache hierarchy, and interconnect topology |

All documentation is now fully reconciled with the synthesizable RTL baseline.
