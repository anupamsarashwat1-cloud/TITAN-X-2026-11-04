# SMVDU TITAN-X — Engineering Defect Register & Root-Cause Analysis

## Overview
This Defect Register tracks all verified architectural, cryptographic, memory, and integration defects identified during the independent engineering audit of the SMVDU TITAN-X SoC. Every defect adheres to the strict remediation loop: **Inspection -> Reproduction -> Root Cause Analysis -> Minimal Fix -> Independent Review -> Regression Verification -> Commit**.

---

## Defect Summary Table

| Defect ID | Subsystem | Module | Severity | Classification | Status |
|:---:|:---|:---|:---:|:---:|:---:|
| **DEF-01** | Security / RoT | `security/secure_boot/secure_boot.v` | **CRITICAL** | Security Trust Model | **CLOSED (VERIFIED)** |
| **DEF-02** | Security / Crypto | `peripherals/sha256_engine/sha256_engine.v` | **HIGH** | Functional / FIPS 180-4 | **CLOSED (VERIFIED)** |
| **DEF-03** | Security / Memory | `top/titan_x_top/titan_x_top.v` | **MEDIUM** | System Integration | **CLOSED (VERIFIED)** |
| **DEF-04** | Memory Subsystem | `memory/l2_cache_top/l2_cache_top.v` | **MEDIUM** | Architecture & Docs | **CLOSED (VERIFIED)** |
| **DEF-05** | Memory / Coherence | `top/titan_x_top/titan_x_top.v` | **HIGH** | Coherence Data Integrity | **CLOSED (VERIFIED)** |

---

## Detailed Defect Records

### DEF-01: Insecure Root-of-Trust Public Key Ingestion in Secure Boot
- **Defect ID**: `DEF-01`
- **Subsystem**: Security & Root-of-Trust
- **Module**: `Design Files of TITAN X/security/secure_boot/secure_boot.v`
- **Severity**: **CRITICAL**
- **Classification**: Security Architecture / Cryptographic Trust Anchor
- **Evidence**:
  - `secure_boot.v` lines 193–212:
    ```verilog
    } else if (word_addr == 17'd2) begin
        pubkey_id <= envm_rdata;
        if (envm_rdata != AUTH_PUBKEY) begin
            auth_fail <= 1'b1;
            state <= S_HALT;
        end
    } else if (word_addr >= 17'd11 && word_addr <= 17'd18) begin
        pubkey_qx[word_addr - 17'd11] <= envm_rdata;
    } else if (word_addr >= 17'd19 && word_addr <= 17'd26) begin
        pubkey_qy[word_addr - 17'd19] <= envm_rdata;
    ```
  - `secure_boot.v` lines 321–326:
    Loads `pubkey_qx` and `pubkey_qy` directly into `ecdsa_engine` from the image stream.
- **Root Cause**:
  The public key coordinates were read from the untrusted memory image being verified, relying solely on an unauthenticated 32-bit `pubkey_id` (`0xCAFEF00D`). A key identifier is not a cryptographic trust anchor.
- **Impact**:
  An adversary can forge an image with an arbitrary self-generated P-256 public key, sign it with their own private key, set the key ID to `0xCAFEF00D`, and achieve full authentication, causing `boot_pass` to assert and executing malicious code.
- **Reproduction**:
  Construct an image signed with an untrusted private key with attacker $Q_x, Q_y$ in the header and key ID `0xCAFEF00D`. The baseline DUT accepts this image and asserts `boot_pass = 1`.
- **Proposed Technical Fix**:
  1. Store the authorized Root-of-Trust public key coordinates (`ROT_PUBKEY_QX`, `ROT_PUBKEY_QY`) as immutable hardware parameters/constants in `secure_boot.v`.
  2. Load the ECDSA verification engine strictly with the immutable hardware Root-of-Trust public key coordinates, and assert authentication failure (`auth_fail <= 1'b1`) if image-supplied coordinates do not match the immutable trust anchor.
- **Implemented Fix**:
  - Embedded immutable 256-bit parameters `ROT_PUBKEY_QX` and `ROT_PUBKEY_QY` in `Design Files of TITAN X/security/secure_boot/secure_boot.v`.
  - Added strict hardware RoT match checks in `S_READ_HEADER`: any mismatched public key asserts `auth_fail <= 1'b1; state <= S_HALT;`.
  - Configured `S_LOAD_ECDSA_SETUP` to load `rot_qx_word(...)` and `rot_qy_word(...)` directly into `ecdsa_engine`.
- **Verification Proof**:
  - `tb_secure_boot.v` Scenario 6: Adversarial public key replacement attack (keeping `pubkey_id == 0xCAFEF00D` but replacing $Q_x$) correctly rejected with `boot_pass=0, boot_fail=1`.
  - `tb_secure_boot_crypto.v` Scenario 6: Adversarial key replacement strictly rejected.
  - Regression status: **PASS (100%)**.
- **Status**: **CLOSED (VERIFIED)**

---

### DEF-02: SHA-256 Engine Single-Block Limitation & Lack of Accumulator Init Control
- **Defect ID**: `DEF-02`
- **Subsystem**: Peripherals / Security
- **Module**: `Design Files of TITAN X/peripherals/sha256_engine/sha256_engine.v`
- **Severity**: **HIGH**
- **Classification**: Functional Correctness / FIPS 180-4 Compliance
- **Evidence**:
  - `sha256_engine.v` lines 86–87:
    `hash[0..7]` initialized to `H0..H7` only on asynchronous reset `rst_n`.
  - Lines 144–157:
    APB interface only exposes `msg_block[0:15]` (512 bits) and `start` bit. No control bit to reset `hash[0:7]` to standard IV for consecutive independent messages.
  - `secure_boot.v` lines 65, 78, 235:
    `reg [4:0] payload_idx` wrapped at 32 words, preventing hashing of images exceeding 16 words.
- **Root Cause**:
  Engine was designed as a single 512-bit block compression primitive without independent message initialization or multi-block digest accumulation control.
- **Impact**:
  Inability to hash variable-length multi-block messages in accordance with NIST FIPS 180-4.
- **Implemented Fix**:
  1. Added `init_hash` accumulator control in `sha256_engine.v` at APB address `0x60` bit 1 (`pwdata[1]`), executed cleanly upon `start && !active` to initialize `hash[0..7]` to `H0..H7` for message block 0 and accumulate subsequent blocks.
  2. Expanded `secure_boot.v` `payload_idx` to `[15:0]`, added `block_word_idx [3:0]` and `first_block` state tracking to stream multi-block images into `sha256_engine` with `pwdata = 32'h3` on block 0 and `32'h1` on subsequent blocks.
- **Verification Proof**:
  - `tb_sha256_engine.v`: Verified single-block and multi-block hash generation.
  - `tb_secure_boot.v` & `tb_secure_boot_crypto.v`: Full FIPS 180-4 hash and FIPS 186-4 ECDSA verification pass.
- **Status**: **CLOSED (VERIFIED)**

---

### DEF-03: Hardcoded eNVM Array Bypassing Actual eNVM Controller
- **Defect ID**: `DEF-03`
- **Subsystem**: Top-Level Integration
- **Module**: `Design Files of TITAN X/top/titan_x_top/titan_x_top.v`
- **Severity**: **MEDIUM**
- **Classification**: System Integration / Architecture
- **Evidence**:
  - `titan_x_top.v` lines 944–960:
    `assign envm_rdata = (envm_addr < 17'd59) ? envm_image[envm_addr] : 32'h0;`
    `envm_ctrl u_envm` had `s_arvalid(1'b0)` and floating macro interfaces.
- **Root Cause**:
  Temporary bringup shortcut that left the physical `envm_ctrl` disconnected from the secure boot controller.
- **Impact**:
  The system booted from a hardcoded array in RTL rather than connecting the eNVM controller macro.
- **Implemented Fix**:
  - Routed the physical macro interface between `envm_ctrl` and the simulation eNVM macro storage array (`envm_ctrl_macro_addr`, `envm_ctrl_macro_ce_n`, `envm_ctrl_macro_rdata`).
- **Verification Proof**:
  - `tb_titan_x_top.v` and `tb_integ_security_chain.v` pass cleanly with zero bus faults.
- **Status**: **CLOSED (VERIFIED)**

---

### DEF-04: L2 Cache Geometry & Capacity Documentation Discrepancy
- **Defect ID**: `DEF-04`
- **Subsystem**: Memory Subsystem
- **Module**: `Design Files of TITAN X/memory/l2_cache_top/l2_cache_top.v`
- **Severity**: **MEDIUM**
- **Classification**: Documentation / Parameter Consistency
- **Evidence**:
  - RTL parameters: `SETS = 64`, `WAYS = 16`, `OFF_W = 6` (64B lines).
  - Calculated capacity: $64 \times 16 \times 64 = 65,536\text{ bytes} = 64\text{ KB}$.
  - Documentation claimed: 512 KB in `l2_cache_top.v` comment, 2 MB in `README.md`.
- **Root Cause**:
  Cache parameters were downscaled for fast simulation, but documentation was not updated to reflect the default elaborated size versus scalable production parameters.
- **Impact**:
  Misleading capacity claims violating engineering audit standards.
- **Implemented Fix**:
  - Updated `memory/l2_cache_top/README.md` and `memory/l2_cache_top/l2_cache_top.v` header comments to document the exact parameter formulation:
    $$\text{Capacity} = \text{SETS} \times \text{WAYS} \times \text{LINE\_BYTES}$$
    - Default Elaborated (Fast Simulation): 64 KB (64 sets × 16 ways × 64B lines).
    - Scalable ASIC Configuration: 512 KB (`SETS=512, WAYS=16`) and 2 MB (`SETS=2048, WAYS=16`).
- **Verification Proof**:
  - Parameter qualification and simulation verified in `tb_l2_cache_top.v`.
- **Status**: **CLOSED (VERIFIED)**

---

### DEF-05: Coherence Snoop Data Bitwise-OR Hazard
- **Defect ID**: `DEF-05`
- **Subsystem**: Memory Subsystem / Coherence
- **Module**: `Design Files of TITAN X/top/titan_x_top/titan_x_top.v`
- **Severity**: **HIGH**
- **Classification**: Multi-Core Data Integrity
- **Evidence**:
  - `titan_x_top.v` line 585:
    `.snoop_data(core_snoop_data[0] | core_snoop_data[1] | core_snoop_data[2] | core_snoop_data[3])`
- **Root Cause**:
  Bitwise OR across all four core snoop data buses instead of an owner-selected multiplexer.
- **Impact**:
  If non-responding cores drive non-zero or floating bits on their snoop data buses, the dirty cache line returned to L2 is corrupted.
- **Implemented Fix**:
  - Replaced bitwise OR with priority / valid-gated multiplexer:
    ```verilog
    wire [511:0] l2_snoop_data_mux = l2_snoop_data_valid[0] ? core_snoop_data[0] :
                                     l2_snoop_data_valid[1] ? core_snoop_data[1] :
                                     l2_snoop_data_valid[2] ? core_snoop_data[2] :
                                     l2_snoop_data_valid[3] ? core_snoop_data[3] : 512'h0;
    ```
  - Connected `.snoop_data(l2_snoop_data_mux)` into `u_l2_cache`.
- **Verification Proof**:
  - `tb_integ_multicore_mesi.v` and `tb_multicore_coherence.v` pass cleanly.
- **Status**: **CLOSED (VERIFIED)**
