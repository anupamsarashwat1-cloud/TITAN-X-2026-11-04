# SMVDU TITAN-X Multi-Core RISC-V SoC

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![Branch](https://img.shields.io/badge/branch-repository%2Fmigration--2026--11--04-orange.svg)](https://github.com/anupamsarashwat1-cloud/TITAN-X-2026-11-04)
[![Architecture](https://img.shields.io/badge/Architecture-RV64GC_Heterogeneous_5--Hart-darkgreen.svg)](Design%20Files%20of%20TITAN%20X/ARCHITECTURE.md)

---

## 1. Project Overview
**SMVDU TITAN-X** is an open-source, production-grade 64-bit multi-core heterogeneous System-on-Chip (SoC) implementing the RISC-V RV64GC instruction set architecture. Designed by Shri Mata Vaishno Devi University (SMVDU), the platform targets high-reliability edge compute, secure embedded processing, automotive control, and high-throughput computer vision.

This repository (`TITAN-X-2026-11-04`) represents the official, canonical, remediated, and evidence-verified release of the complete TITAN-X SoC ecosystem, migrated with strict cryptographic provenance from `TITAN-X-2026-11-03` and `TITAN-X-All-Modules-27-Oct-2026`.

---

## 2. Architecture Summary
- **Processor Cluster**:
  - $4\times$ Application Cores: In-order 5-stage RV64IMAFD pipeline (`rv_fetch`, `rv_decode`, `rv_execute`, `rv_mem`, `rv_writeback`).
  - $1\times$ Service Monitor Core: RV64IMAC real-time deterministic monitoring core (`rv_monitor_core`).
  - Caches: $32\text{ KB}$ L1 I-Cache and $32\text{ KB}$ L1 D-Cache with SECDED ECC per application core.
- **Coherent Memory Hierarchy**:
  - L2 Cache Subsystem: 16-way set-associative shared cache with 8-beat burst refill/writeback engine (`l2_cache_top`).
  - Snoop Directory: MESI-protocol multi-core coherence directory with dirty-owner intervention datapath (`l2_snoop_filter`).
  - DDR4 Memory Controller: High-throughput memory scheduler and DFI PHY interface (`ddr_ctrl_top`).
- **Interconnect Fabric**:
  - Central AXI4 Crossbar: 10 Master ports, 8 Slave targets (`axi4_crossbar`).
  - Quality-of-Service & MPU: Hardware interconnect QoS arbitration and domain isolation (`qos_controller`, `interconnect_mpu`).
- **Hardware Root-of-Trust & Security**:
  - Secure Boot Engine (`secure_boot`): Enforces NIST FIPS 180-4 SHA-256 integrity and NIST FIPS 186-4 ECDSA P-256 authentication against hardware immutable trust anchors before core reset release.
  - Crypto Accelerators: Hardware SHA-256 (`sha256_engine`), ECDSA P-256 (`ecdsa_engine`), AES-128/256 (`aes_engine`), TRNG, and DRBG.
- **Storage, Video & Industrial Peripherals**:
  - MIPI CSI-2 4-lane receiver, ISP pipeline, VDMA, and HDMI transmitter.
  - USB 2.0 OTG, SD/MMC host controller, and QSPI flash controller.
  - 5x UART 16550, SPI, I2C, 2x CAN 2.0B/FD, GPIO, Watchdog, RTC, PLIC (186 sources), CLINT.

For complete structural diagrams and subsystem details, see [ARCHITECTURE.md](Design%20Files%20of%20TITAN%20X/ARCHITECTURE.md).

---

## 3. Repository Structure
```text
TITAN-X-2026-11-04/
├── README.md                           # Master project documentation
├── PROJECT_STATUS.md                   # Live engineering progress and qualification status
├── CHANGELOG.md                        # Version release history
├── CONTRIBUTING.md                     # Engineering guidelines and rules of engagement
├── LICENSE                             # Apache 2.0 legal license
│
├── Design Files of TITAN X/            # Canonical design hierarchy
│   ├── ARCHITECTURE.md                 # Complete SoC architecture specification
│   ├── MODULE_INVENTORY.md             # Hardware module inventory & port maps
│   ├── DEPENDENCY_MAP.md               # Hierarchy and sub-module dependency trees
│   ├── backend/                        # RV64 pipeline stages, caches, MMU, PLIC, CLINT, Debug
│   ├── frontend/                       # Fetch, decode, branch prediction (BPU), L1 I-Cache
│   ├── common/                         # Clock/reset synchronizers, FIFOs, standard cell stubs
│   ├── interconnect/                   # AXI4 crossbar, AHB/APB bridges, MPU, QoS
│   ├── memory/                         # L2 cache top/ctrl, snoop filter, DDR4 controller
│   ├── peripherals/                    # UART, SPI, I2C, CAN, GPIO, Watchdog, Ethernet, PCIe
│   ├── security/                       # Secure boot engine, ECDSA P-256, DRBG, eNVM controller
│   ├── storage/                        # USB OTG, SD/MMC, QSPI controllers
│   ├── video/                          # MIPI CSI-2, ISP, VDMA, HDMI
│   ├── top/                            # SoC top-level integration (titan_x_top), AXI ROM
│   ├── firmware/                       # Bootloader assembly, C runtime, linker scripts
│   ├── includes/                       # Global parameter headers (params.vh, isa_pkg.vh)
│   └── bfm/                            # Bus Functional Models
│
├── verification/                       # Full verification environment
│   ├── unit_tests/                     # Python cocotb / directed unit tests
│   ├── integration/                    # Multi-subsystem integration testbenches
│   ├── formal/                         # SVA formal property specifications and proof scripts
│   ├── uvm_env/                        # SystemVerilog UVM verification environment
│   ├── coverage/                       # Code and functional coverage instrumentation
│   ├── performance/                    # Benchmark workloads and memory latency suites
│   └── waves/                          # GTKWave golden waveform captures (.png, .gtkw)
│
├── scripts/                            # Automation toolflow scripts
│   ├── run_regress.py                  # Master truthful regression runner
│   ├── verilator_lint.sh               # Verilator lint validation suite
│   ├── run_formal.py                   # Formal verification runner
│   ├── run_synth.py                    # Yosys synthesis automation
│   └── run_mutations.py                # Mutation fault injection harness
│
├── docs/                               # Engineering documentation & qualification reports
│   └── qualification/                  # Forensic audits, lint reports, connectivity matrices
│
├── migration/                          # Migration provenance & integrity logs
│   ├── manifests/                      # SOURCE_FILE_MANIFEST.csv, SOURCE_MODULE_INVENTORY.csv
│   ├── reports/                        # SOURCE_REPOSITORY_INVENTORY.md, comparison reports
│   └── checksums/                      # SHA-256 cryptographic verification evidence
│
├── archive/                            # Preserved historical artifacts
│   ├── artifacts/                      # Historical qualification logs
│   └── planning/                       # Historical engineering logs
│
└── .github/
    └── workflows/                      # Continuous integration workflows
```

---

## 4. Main Design Entry Point
The top-level SoC wrapper module is:
- **Module**: `titan_x_top`
- **File**: [`Design Files of TITAN X/top/titan_x_top/titan_x_top.v`](Design%20Files%20of%20TITAN%20X/top/titan_x_top/titan_x_top.v)
- **Primary Core**: [`Design Files of TITAN X/backend/rv_core_top/rv_core_top.v`](Design%20Files%20of%20TITAN%20X/backend/rv_core_top/rv_core_top.v)
- **Filelist**: [`soc_filelist.f`](soc_filelist.f)

---

## 5. Tool Requirements
- **Simulation**: Icarus Verilog (`iverilog`) $\ge$ v12.0 or Verilator $\ge$ v5.020
- **Waveform Inspection**: GTKWave $\ge$ v3.3.100
- **Linting**: Verilator $\ge$ v5.020 (`verilator --lint-only`)
- **Synthesis**: Yosys Open SYnthesis Suite $\ge$ v0.33
- **Automation Runtime**: Python $\ge$ 3.10 with standard library

---

## 6. Build, Simulation & Verification Instructions

### 6.1 Compiling and Simulating Top-Level SoC
```bash
# Compile top-level SoC with Icarus Verilog
iverilog -g2012 -f soc_filelist.f -s tb_titan_x_top -o sim_top

# Run simulation
vvp sim_top
```

### 6.2 Running Master Regression Suite
```bash
# Execute truthful regression across all 116+ testbenches
python3 scripts/run_regress.py -j 4
```

### 6.3 Static Linting with Verilator
```bash
# Run lint check across all synthesizable RTL
bash scripts/verilator_lint.sh
```

### 6.4 Synthesis Smoke Check with Yosys
```bash
# Run synthesis check on the RV64 core
yosys -s synth_rv_core.tcl

# Run synthesis check on the top-level SoC
yosys -s synth_titan_x.tcl
```

---

## 7. Current Project Status
Migration is actively maintained on branch `repository/migration-2026-11-04`.
See [PROJECT_STATUS.md](PROJECT_STATUS.md) for live audit, defect remediation, and verification status.
