# SMVDU TITAN-X — Complete Source Repository Inventory

## 1. Source Identification & Commit Integrity
- **Primary Source Repository**: `https://github.com/anupamsarashwat1-cloud/TITAN-X-2026-11-03.git`
  - Canonical Commit SHA: `a71bf8b548004bb11e29cef8de882a8614341437`
  - Tracked Files: `832`
- **Secondary Historical Repository**: `https://github.com/anupamsarashwat1-cloud/TITAN-X-All-Modules-27-Oct-2026.git`
  - Canonical Commit SHA: `20703fef5e6934f40fe71ddbf090d241aead954a`
  - Tracked Files: `825`

## 2. Directory Breakdown (Primary Source)
| Subsystem / Directory | File Count | Primary Contents |
|---|---|---|
| `backend/` | 133 | RV64 Core stages, Regfile, CSR, MMU, TLB, PTW, PMP, D-Cache, PLIC, CLINT, Debug |
| `frontend/` | 24 | Fetch stage, Decode, Branch Prediction Unit (BPU), L1 I-Cache |
| `common/` | 24 | CDC synchronizers, Reset synchronizers, Sync/Async FIFOs, Standard cell buffers |
| `interconnect/` | 41 | AXI4 10x8 Crossbar, Burst-to-Lite shims, AHB/APB bridges, Interconnect MPU, QoS |
| `memory/` | 48 | L2 Cache top & controller, Snoop filter, Tag/Data arrays, DDR4 scheduler & PHY |
| `peripherals/` | 71 | UART 16550, SPI, I2C, CAN, GPIO, Watchdog, RTC, TRNG, AES, SHA-256, Ethernet, PCIe |
| `security/` | 21 | Secure boot Root-of-Trust, ECDSA P-256 engine, DRBG, eNVM controller |
| `storage/` | 15 | USB 2.0 OTG, SD/MMC controller, QSPI flash controller |
| `video/` | 20 | MIPI CSI-2 receiver, ISP pipeline, VDMA, HDMI controller |
| `top/` | 14 | SoC top wrapper (`titan_x_top`), AXI ROM, boot firmware memory images |
| `verification/` | 65 | Coverage models, SVA formal proofs, performance suite, UVM testbench, unit tests |
| `verification_waves/` | 23 | GTKWave golden waveform captures and visual verification evidence |
| `docs/` | 91 | Architecture specifications, qualification audits, reports, signoff manifests |
| `scripts/` | 39 | Regression runner (`run_regress.py`), Verilator lint, formal verification scripts |
| `artifacts/` | 117 | Historical qualification test logs and regression execution outputs |
| `.planning/` | 16 | Engineering milestones, defect logs, roadmap traces |
| Root files (`.`) | 20 | Filelists (`soc_filelist.f`, `verilator_files.f`), top level README, configs |

## 3. Discovered Hardware Modules Summary
- Total Verilog Hardware Modules Discovered: **205**
- Full SoC Top-Level Module: `titan_x_top` (`top/titan_x_top/titan_x_top.v`)
- Core Subsystem Module: `rv_core_top` (`backend/rv_core_top/rv_core_top.v`)
- All discovered modules, headers, memory images, and documentation have been cataloged in `SOURCE_MODULE_INVENTORY.csv` and `SOURCE_FILE_MANIFEST.csv`.
