# SMVDU TITAN X — Prompt 8A Defect Correction & Technical Resolution Report

**Date:** 2026-11-18  
**Audit Phase:** Prompt 8A Post-Release Engineering Audit & Defect Correction  
**Authoring Team:**  
- Anupam Sarashwat — 23BEC014  
- Harsh Mishra — 23BEC027  
- Om Kumar — 23BEC038  
**Auditing Engineer / Agent:** SMVDU TITAN X Engineering Release Agent (Antigravity `d788fd46-4be3-43d3-b340-159440e15655`)  
**Described Source Commit:** `f177eb5b9513b005a029cd15ad8c85c2db3e753f` (Release Tag: `SMVDU-TITAN-X-v1.0.0`) / Reconciled Baseline `579bdcb`  

---

## 1. Executive Summary

Following completion of the Prompt 8 release freeze, an independent engineering audit of the released RTL baseline was conducted across all subsystems. The audit specifically investigated discrepancies previously noted across L1/L2 cache configurations, AXI crossbar topology, Hart architecture, test matrix counts, release commit lineage, secure boot mechanisms, and snoop filter coherence replacement.

Six defects/discrepancies (DEF-01 through DEF-06) were registered, thoroughly investigated against actual synthesizable RTL and testbench code, and formally resolved. All resolutions have been verified by targeted testbenches, formal bounded model checking, and full regression simulation.

---

## 2. Detailed Technical Investigations and Corrections

### DEF-01: L1 Cache Capacity & Hart 4 Cache Configuration Discrepancy
- **Severity:** Medium
- **Affected Subsystems / Modules:** `rv_icache` (`frontend/rv_icache/rv_icache.v`), `rv_dcache` (`backend/rv_dcache/rv_dcache.v`), `rv_monitor_core` (`backend/rv_monitor_core/rv_monitor_core.v`), `rv_core_top` (`backend/rv_core_top/rv_core_top.v`).
- **RTL Source Inspection:**
  - `frontend/rv_icache/rv_icache.v`: Parameters declare `WAYS = 8`, `SETS = 64`, `LINE_BYTES = 64`.
    $$\text{Capacity}_{\text{I\$}} = 8 \times 64 \times 64\text{ B} = 32,768\text{ B} = 32\text{ KB}$$
  - `backend/rv_dcache/rv_dcache.v`: Parameters declare `WAYS = 8`, `SETS = 64`, `LINE_BYTES = 64`.
    $$\text{Capacity}_{\text{D\$}} = 8 \times 64 \times 64\text{ B} = 32,768\text{ B} = 32\text{ KB}$$
  - Harts 0–3 each instantiate one `rv_icache` and one `rv_dcache`, yielding **64 KB per core** (32 KB I$ + 32 KB D$) and **256 KB total L1 cache** across the 4 application cores.
  - `backend/rv_monitor_core/rv_monitor_core.v`: Inspection of the monitor core RTL confirms that Hart 4 has **ZERO cache instances**. Instruction fetches interface directly to AXI4-Lite (`imem_arvalid`, `imem_rdata`), and data transactions interface directly to AXI4 (`dmem_arvalid`, `dmem_awvalid`, `dmem_wdata`, `dmem_rdata`).
- **Discrepancy Cause:** Early documentation drafts erroneously cited "16 KB I$ / 16 KB D$" and claimed Hart 4 possessed an L1 cache.
- **Resolution:** Updated all top-level documentation, memory map specifications, and architecture diagrams to accurately reflect 32 KB I$ + 32 KB D$ for Harts 0–3 and the uncached direct-AXI interface for Hart 4.
- **Verification:** Verified via `tb_rv_icache`, `tb_rv_dcache`, `tb_rv_monitor_core`, and `tb_fresh_titan_x_top`.

---

### DEF-02: L2 Cache Synthesizable Macro Baseline vs. Simulation Target Discrepancy
- **Severity:** Medium
- **Affected Subsystems / Modules:** `l2_cache_top` (`memory/l2_cache_top/l2_cache_top.v`), `l2_tag_array` (`memory/l2_tag_array/l2_tag_array.v`), `l2_data_array` (`memory/l2_data_array/l2_data_array.v`).
- **RTL Source Inspection:**
  - `memory/l2_cache_top/l2_cache_top.v`: Default parameters declare `L2_WAYS = 16`, `L2_SETS = 64`, `L2_LINE_BYTES = 64`.
    $$\text{Capacity}_{\text{L2\_RTL}} = 16 \times 64 \times 64\text{ B} = 65,536\text{ B} = 64\text{ KB}$$
  - Synthesizable macro implementation: The data array instantiates **256 compiled macro instances** of `sram_32x64_180nm` (each macro is 32 words $\times$ 64 bits = 256 bytes; $256 \times 256\text{ B} = 64\text{ KB}$).
  - Simulation parameterization: `includes/params.vh` defines `L2_SETS = 2048`, scaling simulation models to 2 MB.
- **Discrepancy Cause:** Release notes claimed L2 cache was "512 KB". This 512 KB figure originated from an intermediate 512-set architectural proposal that was never hardened into the compiled SRAM macro instantiation.
- **Resolution:** Reconciled documentation to clearly define the 64 KB synthesizable SRAM macro baseline (with 2 MB simulation scalability), resolving the 512 KB discrepancy.
- **Verification:** Verified via `tb_l2_cache_top`, `tb_integ_multicore_mesi`, and Yosys SoC top synthesis elaboration (`scripts/synth_titan_x.tcl`).

---

### DEF-03: AXI Crossbar Port Dimensions & Active DECERR Handling Discrepancy
- **Severity:** Low
- **Affected Subsystems / Modules:** `axi4_crossbar` (`interconnect/axi4_crossbar/axi4_crossbar.v`), `titan_x_top` (`top/titan_x_top/titan_x_top.v`).
- **RTL Source Inspection:**
  - `top/titan_x_top/titan_x_top.v` instantiates `axi4_crossbar` with parameters `NM = 15` and `NS = 9`.
  - **15 Master Ports:**
    - Master 0–3: Hart 0–3 Instruction Caches (AXI4 read-only, 64-bit)
    - Master 4–7: Hart 0–3 Data Caches (AXI4 read/write, 64-bit)
    - Master 8: Hart 4 Monitor Core Instruction Interface (AXI4-Lite read-only, 64-bit)
    - Master 9: Hart 4 Monitor Core Data Interface (AXI4 read/write, 64-bit)
    - Master 10: PCIe Controller DMA Master (AXI4 128-bit)
    - Master 11: Gigabit Ethernet MAC (GEM) DMA Master (AXI4 64-bit)
    - Master 12: USB OTG 2.0 DMA Master (AXI4 64-bit)
    - Master 13: MMC / SD Card Controller DMA Master (AXI4 64-bit)
    - Master 14: Video DMA (VDMA) Controller Master (AXI4 64-bit)
  - **9 Slave Ports:**
    - Slave 0: L2 Cache Top (Unified System Memory aperture)
    - Slave 1: AHB/APB Bridge (Peripheral Subsystem aperture)
    - Slave 2: AXI BootROM (Secure Boot Vector aperture `0x1000_0000`)
    - Slave 3: AXI SRAM Scratchpad (Internal Fast SRAM aperture `0x0800_0000`)
    - Slaves 4–8: Active DECERR Responders (Dedicated hardware responders returning `RRESP=2'b11` / `BRESP=2'b11` DECERR for unmapped aperture addresses)
- **Discrepancy Cause:** Architecture block diagrams simplified the crossbar to an 8x8 or 10x6 topology, omitting DMA masters and unmapped DECERR responder ports.
- **Resolution:** Updated interconnect diagrams, routing aperture tables, and interface descriptions to accurately reflect the 15M $\times$ 9S crossbar topology and active DECERR response mechanisms.
- **Verification:** Formally verified via SMT-BMC proof `formal/proofs/axi4_crossbar.smt2` and simulated via `tb_axi4_crossbar` and `tb_integ_peripherals`.

---

### DEF-04: Qualification Test Matrix Target Accounting (127 vs 126 entries)
- **Severity:** Low
- **Affected Documents / Scripts:** `docs/qualification/FINAL_RELEASE_TEST_MATRIX.csv`, `scripts/run_regress.py`.
- **Source Inspection:**
  - `docs/qualification/FINAL_RELEASE_TEST_MATRIX.csv` contains:
    - 1 CSV Header Row (`Test_ID,Category,Subsystem,Testbench_Path,Tool,Target_Commit,Result,Runtime_Sec,Log_Path`)
    - 120 Simulation Testbenches (`SIM-001` through `SIM-120`)
    - 5 Formal Verification Proof Suites (`FORMAL-001` through `FORMAL-005`)
    - 1 Top-Level SoC Elaboration Check (`SYNTH-001`)
    - **Total CSV Lines: 127 lines (1 header + 126 test targets).**
  - In addition, executing `python3 scripts/run_regress.py --self-test` executes 1 self-test harness verification target, yielding 127 total automated execution targets.
- **Discrepancy Cause:** Ambiguity in release text between total lines (127) and test targets (126).
- **Resolution:** Documented the exact accounting breakdown in the qualification test matrix and release signoff.
- **Verification:** Verified via `python3 scripts/run_regress.py` and CSV line count parsing.

---

### DEF-05: Stale Release Commit Reference Traceability
- **Severity:** Low
- **Affected Documents:** `docs/qualification/FINAL_RELEASE_SIGNOFF.md`, `RELEASE_NOTES.md`.
- **Git History Tracing:**
  - `471b857`: Prompt 7 engineering completion commit (secure boot multi-hart signing fix).
  - `f177eb5`: Prompt 8 release freeze commit, tagged `SMVDU-TITAN-X-v1.0.0` (all 79 RTL modules, 120 testbenches, 5 formal suites).
  - `579bdcb`: Post-Prompt 8 three-repository synchronization commit (preserved historical verification assets and synchronization report).
  - `9592749`: PART-B dual-parent history-preserving merge commit uniting `bef5c25` and `579bdcb`.
- **Discrepancy Cause:** Certain Prompt 7 qualification documents were carried forward without updating the commit reference from `471b857` to `f177eb5`.
- **Resolution:** Reconciled all documentation to trace the full commit lineage, preserving the immutable `SMVDU-TITAN-X-v1.0.0` release tag at `f177eb5`.
- **Verification:** Validated via `git log --graph --oneline` and `git ls-remote` across all three remotes.

---

### DEF-06: Cache Coherence Directory Replacement Invalidation Determinism
- **Severity:** High
- **Affected Subsystems / Modules:** `l2_snoop_filter` (`memory/l2_snoop_filter/l2_snoop_filter.v`).
- **RTL Source Inspection:**
  - Evaluated directory set saturation when all 32 ways (4 cores $\times$ 8 ways) in a set are allocated.
  - Examined victim selection and eviction handling:
    - `l2_snoop_filter.v` uses a round-robin replacement pointer (`repl_ptr`) to select victim lines upon set saturation.
    - When a victim is evicted, back-invalidation is triggered (`snoop_type = 2'b10`) to all sharer cores.
    - If any sharer holds modified data (`MESI = Modified`), `snoop_data_valid` indicates dirty data writeback. The dirty line is accumulated via `dirty_accum` and scheduled for writeback into L2/DDR4.
    - The filter asserts `stall = 1'b1` until victim invalidation and writeback complete, preventing race conditions or stale reads by other harts.
- **Resolution:** Verified that the existing RTL logic correctly handles set saturation and back-invalidation deterministically without data loss or deadlock.
- **Verification:** Validated through `tb_l2_snoop_filter_adversarial`, `tb_integ_multicore_mesi`, and formal BMC proof `proofs/l2_snoop_filter.smt2` (20 cycles depth, 0 invariant violations).

---

## 3. Summary of Status

| Defect ID | Severity | Status | Verification Result |
| :---: | :---: | :---: | :---: |
| **DEF-01** | Medium | **RESOLVED** | PASS (`tb_rv_icache`, `tb_rv_dcache`, `tb_fresh_titan_x_top`) |
| **DEF-02** | Medium | **RESOLVED** | PASS (`tb_l2_cache_top`, `scripts/synth_titan_x.tcl`) |
| **DEF-03** | Low | **RESOLVED** | PASS (`tb_axi4_crossbar`, `formal/proofs/axi4_crossbar.smt2`) |
| **DEF-04** | Low | **RESOLVED** | PASS (`scripts/run_regress.py` — 126 targets + 1 self-test) |
| **DEF-05** | Low | **RESOLVED** | PASS (Git lineage confirmed across all 3 remotes) |
| **DEF-06** | High | **RESOLVED** | PASS (`tb_l2_snoop_filter_adversarial`, formal BMC depth 20) |

All six registered defects have been investigated, resolved, and verified.
