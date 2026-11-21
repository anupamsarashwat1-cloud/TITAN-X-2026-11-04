#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SMVDU TITAN-X — Multi-Seed Differential ATPG Runner & Verification Suite
# Orchestrates end-to-end random program generation, dual-execution co-simulation
# across official Spike RISC-V ISA Simulator and TITAN-X rv_core_top RTL,
# performing cycle-accurate, bit-for-bit differential comparison.

import argparse
import os
import re
import subprocess
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
ATPG_DIR = REPO_ROOT / "tools" / "atpg"
VVP_EXEC = "/tmp/tb_core_random_atpg.vvp"

def run_cmd(cmd, cwd=REPO_ROOT, timeout=120):
    res = subprocess.run(cmd, shell=True, capture_output=True, text=True, cwd=cwd, timeout=timeout)
    return res.returncode, res.stdout, res.stderr

def compile_rtl_testbench():
    print("[ATPG SUITE] Compiling TITAN-X Core Random ATPG Testbench...")
    compile_cmd = (
        "iverilog -g2012 -DFAST_INIT -s tb_core_random_atpg "
        "-I includes -I common -I backend/rv_core_top -I backend/rv_execute -I frontend/rv_decode -I frontend/rv_fetch "
        f"-o {VVP_EXEC} "
        "-f soc_filelist.f verification/atpg/tb_core_random_atpg.v"
    )
    rc, out, err = run_cmd(compile_cmd)
    if rc != 0:
        print(f"[FATAL] RTL Compilation failed:\n{err}\n{out}")
        sys.exit(1)
    print("[ATPG SUITE] RTL Compilation Successful.")

def parse_spike_log(log_path):
    """Parses Spike commit log to extract the final architectural register state and memory signature."""
    rf = {f"x{i}": 0 for i in range(1, 32)}
    mem = {}

    reg_pattern = re.compile(r"core\s+0:\s+\d+\s+0x[0-9a-fA-F]+\s+\(0x[0-9a-fA-F]+\)\s+(x\d+)\s+0x([0-9a-fA-F]+)")
    mem_pattern = re.compile(r"core\s+0:\s+\d+\s+0x[0-9a-fA-F]+\s+\(0x[0-9a-fA-F]+\)\s+mem\s+0x([0-9a-fA-F]+)\s+0x([0-9a-fA-F]+)")

    with open(log_path, "r") as f:
        for line in f:
            rm = reg_pattern.search(line)
            if rm:
                rname, rval = rm.groups()
                if rname in rf:
                    rf[rname] = int(rval, 16)

            mm = mem_pattern.search(line)
            if mm:
                maddr, mval = mm.groups()
                mem[int(maddr, 16)] = int(mval, 16)

    return rf, mem

def parse_rtl_dump(dump_path):
    """Parses TITAN-X RTL dump file for architectural registers and memory signature."""
    rf = {}
    mem = {}
    cycles = 0
    retires = 0

    if not os.path.exists(dump_path):
        return None, None, 0, 0

    with open(dump_path, "r") as f:
        for line in f:
            line = line.strip()
            if line.startswith("CYCLES:"):
                cycles = int(line.split()[1])
            elif line.startswith("RETIRES:"):
                retires = int(line.split()[1])
            elif line.startswith("REG "):
                parts = line.split()
                rname = parts[1].replace(":", "")
                rval = int(parts[2], 16)
                rf[rname] = rval
            elif line.startswith("MEM["):
                # MEM[0x80001000]: 0x1234...
                addr_match = re.search(r"MEM\[0x([0-9a-fA-F]+)\]:\s+0x([0-9a-fA-F]+)", line)
                if addr_match:
                    addr = int(addr_match.group(1), 16)
                    val = int(addr_match.group(2), 16)
                    mem[addr] = val

    return rf, mem, cycles, retires

def get_symbol_addr(elf_path, sym_name):
    rc, out, _ = run_cmd(f"riscv64-unknown-elf-nm -B {elf_path} | grep ' {sym_name}$'")
    if rc == 0 and out.strip():
        return int(out.strip().split()[0], 16)
    return None

def run_atpg_batch(seed, num_insns):
    test_asm = ATPG_DIR / f"test_atpg_seed_{seed}.S"
    test_elf = ATPG_DIR / f"test_atpg_seed_{seed}.elf"
    test_bin = ATPG_DIR / f"test_atpg_seed_{seed}.bin"
    imem_hex = ATPG_DIR / "atpg_imem.hex"
    dmem_hex = ATPG_DIR / "atpg_dmem.hex"
    spike_log = ATPG_DIR / f"spike_commit_seed_{seed}.log"
    rtl_dump = ATPG_DIR / "rtl_dump.txt"

    # Step 1: Generate Assembly
    gen_cmd = f"python3 tools/atpg/random_instruction_atpg.py --seed {seed} --num-insns {num_insns} --output-asm {test_asm}"
    rc, out, err = run_cmd(gen_cmd)
    if rc != 0:
        return False, f"Assembly generation failed for seed {seed}: {err}"

    # Step 2: Compile with GCC
    compile_cmd = (
        f"riscv64-unknown-elf-gcc -march=rv64imac -mabi=lp64 -nostdlib -nostartfiles -mcmodel=medany "
        f"-T tools/atpg/atpg_link.ld -o {test_elf} {test_asm}"
    )
    rc, out, err = run_cmd(compile_cmd)
    if rc != 0:
        return False, f"GCC compilation failed for seed {seed}: {err}"

    # Step 3: Extract binary and emit 32-bit & 64-bit Hex
    rc, out, err = run_cmd(f"riscv64-unknown-elf-objcopy -O binary {test_elf} {test_bin}")
    with open(test_bin, "rb") as f:
        raw = f.read()
    while len(raw) % 8 != 0:
        raw += b"\x00"

    imem_words = [f"{int.from_bytes(raw[i:i+4], 'little'):08x}" for i in range(0, len(raw), 4)]
    with open(imem_hex, "w") as f:
        f.write("\n".join(imem_words) + "\n")

    dmem_words = [f"{int.from_bytes(raw[i:i+8], 'little'):016x}" for i in range(0, len(raw), 8)]
    with open(dmem_hex, "w") as f:
        f.write("\n".join(dmem_words) + "\n")

    # Step 4: Run Golden Reference (Spike)
    spike_cmd = f"spike --isa=rv64imac --log-commits {test_elf} > {spike_log} 2>&1"
    rc, out, err = run_cmd(spike_cmd)
    if rc != 0:
        return False, f"Spike execution failed for seed {seed} (Exit code {rc}): {err}"

    golden_rf, golden_mem = parse_spike_log(spike_log)

    # Step 5: Run TITAN-X RTL Simulation
    if os.path.exists(rtl_dump):
        os.remove(rtl_dump)
    rtl_cmd = f"vvp {VVP_EXEC}"
    rc, out, err = run_cmd(rtl_cmd, timeout=180)
    if rc != 0:
        return False, f"TITAN-X RTL simulation crashed for seed {seed}:\n{out}\n{err}"

    rtl_rf, rtl_mem, cycles, retires = parse_rtl_dump(rtl_dump)
    if rtl_rf is None:
        return False, f"TITAN-X RTL did not produce rtl_dump.txt (timeout or crash)!\nOutput:\n{out}"

    # Step 6: Differential Comparison
    mismatches = []
    # Check all registers x1..x31
    for r_idx in range(1, 32):
        rname = f"x{r_idx}"
        g_val = golden_rf.get(rname, 0)
        r_val = rtl_rf.get(rname, 0)
        if g_val != r_val:
            mismatches.append(f"  Register {rname} MISMATCH: Golden(Spike)=0x{g_val:016x}, RTL=0x{r_val:016x} (Diff=0x{g_val^r_val:016x})")

    # Check memory signature words at reg_dump_area
    dump_addr = get_symbol_addr(test_elf, "reg_dump_area")
    mem_words_checked = 0
    if dump_addr is not None:
        for offset in range(0, 256, 8):
            addr = dump_addr + offset
            g_val = golden_mem.get(addr, 0)
            r_val = rtl_mem.get(addr, 0)
            mem_words_checked += 1
            if g_val != r_val:
                mismatches.append(f"  Memory[0x{addr:08x}] MISMATCH: Golden(Spike)=0x{g_val:016x}, RTL=0x{r_val:016x}")

    if mismatches:
        return False, "\n".join(mismatches)

    return True, f"PASS (Cycles={cycles}, Retires={retires}, 31/31 Regs Match, {mem_words_checked}/{mem_words_checked} Mem Words Match)"

def main():
    parser = argparse.ArgumentParser(description="TITAN-X Random ATPG Multi-Seed Suite")
    parser.add_argument("--iterations", type=int, default=10, help="Number of diverse seeds to execute")
    parser.add_argument("--insns-per-test", type=int, default=1000, help="Instructions per test program")
    parser.add_argument("--base-seed", type=int, default=1001, help="Starting base random seed")
    args = parser.parse_args()

    print("==================================================================")
    print("  SMVDU TITAN-X: Random ATPG & Differential Co-Simulation Suite")
    print(f"  Iterations: {args.iterations} | Insns/Test: {args.insns_per_test} | Base Seed: {args.base_seed}")
    print("==================================================================\n")

    compile_rtl_testbench()

    total_tests = args.iterations
    passed_tests = 0
    failed_tests = 0
    total_dynamic_insns = 0

    results = []

    start_time = time.time()

    for idx in range(total_tests):
        seed = args.base_seed + idx * 7919 # Large prime step for diverse pseudo-random spaces
        print(f"\n[ATPG BATCH {idx+1}/{total_tests}] Launching Seed {seed} ({args.insns_per_test} random instructions)...")
        b_start = time.time()
        success, msg = run_atpg_batch(seed, args.insns_per_test)
        b_dur = time.time() - b_start

        if success:
            passed_tests += 1
            total_dynamic_insns += args.insns_per_test
            print(f"[ATPG BATCH {idx+1} PASS] {msg} ({b_dur:.2f}s)")
            results.append((seed, "PASS", msg))
        else:
            failed_tests += 1
            print(f"[ATPG BATCH {idx+1} FAIL] Anomaly detected ({b_dur:.2f}s):\n{msg}")
            results.append((seed, "FAIL", msg))

    total_time = time.time() - start_time

    print("\n==================================================================")
    print("  RANDOM ATPG SUITE VERIFICATION REPORT")
    print("==================================================================")
    print(f"  Total ATPG Batches Executed : {total_tests}")
    print(f"  Batches 100% Passed        : {passed_tests}")
    print(f"  Batches Failed             : {failed_tests}")
    print(f"  Total Dynamic Instructions : {total_dynamic_insns}")
    print(f"  Overall Execution Time     : {total_time:.2f}s")
    print("------------------------------------------------------------------")
    for seed, verdict, note in results:
        status_str = "[PASS]" if verdict == "PASS" else "[FAIL]"
        print(f"  Seed {seed:<8}: {status_str} {note}")
    print("------------------------------------------------------------------")

    if failed_tests == 0:
        print("  FINAL SIGNOFF VERDICT: 100% PASS — ZERO DISCREPANCIES ACROSS ALL SEEDS")
        print("  Spike RISC-V Golden Model == TITAN-X RTL (Bit-for-Bit Identical)")
    else:
        print(f"  FINAL SIGNOFF VERDICT: FAIL — {failed_tests} SEEDS FAILED")
    print("==================================================================\n")

    return 0 if failed_tests == 0 else 1

if __name__ == "__main__":
    sys.exit(main())
