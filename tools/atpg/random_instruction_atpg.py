#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SMVDU TITAN-X — Constrained Random Instruction ATPG Generator
# Dynamically generates valid, deterministic, baremetal RISC-V RV64IMAC test programs
# targeting deep architectural verification and differential co-simulation against Spike/QEMU.

import argparse
import random
import sys

# RISC-V Registers:
# x0: zero (hardwired 0)
# x1: ra (return address / link register)
# x2: sp (reserved as scratchpad base pointer: scratch_area + 2048)
# x3..x31: general test registers
TEST_REGS = [f"x{i}" for i in range(3, 32)]
RVC_REGS = [f"x{i}" for i in range(8, 16)] # x8-x15 (s0-a5)

CORNER_VALUES = [
    0x0000000000000000,
    0xFFFFFFFFFFFFFFFF,
    0x7FFFFFFFFFFFFFFF,
    0x8000000000000000,
    0x000000007FFFFFFF,
    0xFFFFFFFF80000000,
    0x00000000FFFFFFFF,
    0x5555555555555555,
    0xAAAAAAAAAAAAAAAA,
    0x0000000000000001,
    0x0000000000000002,
    0xFFFFFFFFFFFFFFFE,
    0x000000000000003F,
    0x000000000000001F,
    0x123456789ABCDEF0,
]

ALU_OPS_REG = ["add", "sub", "slt", "sltu", "xor", "or", "and", "sll", "srl", "sra"]
ALU_OPS_IMM = ["addi", "slti", "sltiu", "xori", "ori", "andi", "slli", "srli", "srai"]
ALU_W_OPS_REG = ["addw", "subw", "sllw", "srlw", "sraw"]
ALU_W_OPS_IMM = ["addiw", "slliw", "srliw", "sraiw"]

MEXT_OPS = ["mul", "mulh", "mulhsu", "mulhu", "div", "divu", "rem", "remu", "mulw", "divw", "divuw", "remw", "remuw"]

LOAD_STORE_OPS = [
    ("sd", "ld", 8),
    ("sw", "lw", 4),
    ("sh", "lh", 2),
    ("sb", "lb", 1),
    ("sw", "lwu", 4),
    ("sh", "lhu", 2),
    ("sb", "lbu", 1),
]

BRANCH_OPS = ["beq", "bne", "blt", "bge", "bltu", "bgeu"]

def emit_header():
    lines = [
        "/* ================================================================= */",
        "/* SMVDU TITAN-X Random ATPG Auto-Generated Assembly                 */",
        "/* Target: RV64IMAC Baremetal Signoff Verification                   */",
        "/* ================================================================= */",
        "",
        ".section .text.init, \"ax\"",
        ".globl _start",
        ".type _start, @function",
        "",
        "_start:",
        "    /* Initialize base memory scratchpad pointer: x2 = scratch_area + 2048 */",
        "    la x2, scratch_area",
        "    addi x2, x2, 2047",
        "    addi x2, x2, 1",
        "",
        "    /* Preload corner & diverse values across x3..x31 */",
    ]
    for i, reg in enumerate(TEST_REGS):
        val = CORNER_VALUES[i % len(CORNER_VALUES)]
        lines.append(f"    li {reg}, {hex(val)}")

    lines.extend([
        "",
        "    /* Preload scratchpad memory with deterministic non-zero seed words */",
        "    li x1, 0x0123456789ABCDEF",
    ])
    for offset in range(-512, 512, 64):
        lines.append(f"    sd x1, {offset}(x2)")
        lines.append("    addi x1, x1, 0x111")

    lines.append("\n    /* ---- BEGIN RANDOM ATPG INSTRUCTION STREAM ---- */\n")
    return lines

def generate_random_atpg_stream(num_insns, enable_rvc=True, enable_mext=True):
    lines = []
    prev_rd = "x3"
    prev_prev_rd = "x4"
    branch_label_id = 0

    for idx in range(num_insns):
        # Determine hazard forwarding
        r = random.random()
        if r < 0.35:
            rs1 = prev_rd
            rs2 = random.choice(TEST_REGS)
        elif r < 0.55:
            rs1 = random.choice(TEST_REGS)
            rs2 = prev_rd
        elif r < 0.70:
            rs1 = prev_prev_rd
            rs2 = random.choice(TEST_REGS)
        else:
            rs1 = random.choice(TEST_REGS)
            rs2 = random.choice(TEST_REGS)

        rd = random.choice(TEST_REGS)

        # Instruction category selection
        cat = random.random()
        if cat < 0.30:
            # 64-bit ALU
            if random.random() < 0.5:
                op = random.choice(ALU_OPS_REG)
                lines.append(f"    {op} {rd}, {rs1}, {rs2}")
            else:
                op = random.choice(ALU_OPS_IMM)
                if op in ("slli", "srli", "srai"):
                    shamt = random.randint(0, 63)
                    lines.append(f"    {op} {rd}, {rs1}, {shamt}")
                else:
                    imm = random.randint(-2048, 2047)
                    lines.append(f"    {op} {rd}, {rs1}, {imm}")

        elif cat < 0.50:
            # 32-bit Word Ops (RV64I W-ops)
            if random.random() < 0.5:
                op = random.choice(ALU_W_OPS_REG)
                lines.append(f"    {op} {rd}, {rs1}, {rs2}")
            else:
                op = random.choice(ALU_W_OPS_IMM)
                if op in ("slliw", "srliw", "sraiw"):
                    shamt = random.randint(0, 31)
                    lines.append(f"    {op} {rd}, {rs1}, {shamt}")
                else:
                    imm = random.randint(-2048, 2047)
                    lines.append(f"    {op} {rd}, {rs1}, {imm}")

        elif cat < 0.70 and enable_mext:
            # Multiplier & Divider (M-Extension)
            op = random.choice(MEXT_OPS)
            lines.append(f"    {op} {rd}, {rs1}, {rs2}")

        elif cat < 0.85:
            # Memory Access (Load/Store to safe bounded scratchpad in [-512, 512])
            st_op, ld_op, align = random.choice(LOAD_STORE_OPS)
            offset = random.randrange(-512, 512, align)
            if random.random() < 0.5:
                lines.append(f"    {st_op} {rs1}, {offset}(x2)")
            else:
                lines.append(f"    {ld_op} {rd}, {offset}(x2)")

        elif cat < 0.93 and enable_rvc:
            # Compressed Instructions (RVC)
            c_op = random.choice(["c.add", "c.sub", "c.and", "c.or", "c.xor", "c.mv", "c.addi", "c.addw"])
            rc1 = random.choice(RVC_REGS)
            rc2 = random.choice(RVC_REGS)
            if c_op in ("c.add", "c.sub", "c.and", "c.or", "c.xor", "c.addw"):
                lines.append(f"    {c_op} {rc1}, {rc2}")
                rd = rc1
            elif c_op == "c.mv":
                lines.append(f"    {c_op} {rd}, {rs1}")
            elif c_op == "c.addi":
                c_imm = random.randint(-32, 31)
                if c_imm == 0: c_imm = 1
                lines.append(f"    {c_op} {rc1}, {c_imm}")
                rd = rc1

        else:
            # Forward conditional branch jumping over 1-2 instructions
            b_op = random.choice(BRANCH_OPS)
            lbl = f"fwd_br_{branch_label_id}"
            branch_label_id += 1
            lines.append(f"    {b_op} {rs1}, {rs2}, {lbl}")
            # Target instruction to skip
            dummy_rd = random.choice(TEST_REGS)
            lines.append(f"    addi {dummy_rd}, {dummy_rd}, 1")
            lines.append(f"{lbl}:")

        prev_prev_rd = prev_rd
        prev_rd = rd

    lines.append("\n    /* ---- END RANDOM ATPG INSTRUCTION STREAM ---- */\n")
    return lines

def emit_epilogue():
    lines = [
        "    /* ---- TEST EPILOGUE & SIGNATURE SAVE ---- */",
        "    /* Save all registers x1, x3..x31 to memory dump area: reg_dump_area */",
        "    la x1, reg_dump_area",
        "    sd x2, 16(x1)  /* Record final base pointer */",
    ]
    for i, reg in enumerate(TEST_REGS):
        reg_idx = int(reg[1:])
        offset = reg_idx * 8
        lines.append(f"    sd {reg}, {offset}(x1)")

    lines.extend([
        "",
        "    /* Signal completion to Spike via tohost */",
        "    la x1, tohost",
        "    li x3, 1",
        "    sd x3, 0(x1)",
        "",
        "    /* Write golden signature token CAFEBABE_DEADBEEF to completion_token_addr */",
        "    li x4, 0xCAFEBABE",
        "    slli x4, x4, 32",
        "    li x5, 0xDEADBEEF",
        "    or x4, x4, x5",
        "    la x6, completion_token_addr",
        "    sd x4, 0(x6)",
        "",
        "    /* Spin indefinitely */",
        "1:",
        "    wfi",
        "    j 1b",
        "",
        ".section .tohost, \"aw\", @progbits",
        ".align 6",
        ".globl tohost",
        "tohost:   .dword 0",
        ".globl fromhost",
        "fromhost: .dword 0",
        ""
    ])
    return lines

def main():
    parser = argparse.ArgumentParser(description="Constrained Random Instruction ATPG for TITAN-X")
    parser.add_argument("--seed", type=int, default=42, help="Random seed")
    parser.add_argument("--num-insns", type=int, default=1000, help="Number of random instructions")
    parser.add_argument("--output-asm", type=str, default="tools/atpg/test_atpg.S", help="Output .S file")
    parser.add_argument("--no-rvc", action="store_true", help="Disable RVC instructions")
    parser.add_argument("--no-mext", action="store_true", help="Disable M-extension instructions")

    args = parser.parse_args()
    random.seed(args.seed)

    print(f"[ATPG GEN] Generating {args.num_insns} instructions (Seed={args.seed}, RVC={not args.no_rvc}, M-Ext={not args.no_mext})...")

    asm_lines = []
    asm_lines.extend(emit_header())
    asm_lines.extend(generate_random_atpg_stream(args.num_insns, enable_rvc=(not args.no_rvc), enable_mext=(not args.no_mext)))
    asm_lines.extend(emit_epilogue())

    with open(args.output_asm, "w") as f:
        f.write("\n".join(asm_lines))

    print(f"[ATPG GEN] Successfully emitted {len(asm_lines)} lines of assembly to {args.output_asm}")

if __name__ == "__main__":
    main()
