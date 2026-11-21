// SPDX-License-Identifier: Apache-2.0
// SMVDU TITAN-X — Structural Datapath Random ATPG Testbench
// High-density pseudo-random and corner-case verification across
// 64-bit ALU, Multiplier, Divider, Barrel Shifter, and RVC Decompressor.

`timescale 1ns/1ps
`include "params.vh"
`include "isa_pkg.vh"

module tb_datapath_random_atpg;

    reg clk;
    reg rst_n;

    // Clock generation: 100 MHz (10ns period)
    initial clk = 0;
    always #5 clk = ~clk;

    // ------------------------------------------------------------
    // LFSR 64-bit Pseudo-Random Generator
    // ------------------------------------------------------------
    reg [63:0] lfsr1, lfsr2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr1 <= 64'hACE1_2026_DEAD_BEEF;
            lfsr2 <= 64'h1357_9BDF_CAFE_BABE;
        end else begin
            // Polynomial: x^64 + x^63 + x^61 + x^60 + 1
            lfsr1 <= {lfsr1[62:0], lfsr1[63] ^ lfsr1[62] ^ lfsr1[60] ^ lfsr1[59]};
            lfsr2 <= {lfsr2[62:0], lfsr2[63] ^ lfsr2[62] ^ lfsr2[60] ^ lfsr2[59] ^ lfsr1[0]};
        end
    end

    // Corner case injection array
    reg [63:0] corner_cases [0:15];
    initial begin
        corner_cases[0]  = 64'h0000_0000_0000_0000; // 0
        corner_cases[1]  = 64'hFFFF_FFFF_FFFF_FFFF; // -1
        corner_cases[2]  = 64'h7FFF_FFFF_FFFF_FFFF; // Max pos signed 64
        corner_cases[3]  = 64'h8000_0000_0000_0000; // Min neg signed 64
        corner_cases[4]  = 64'h0000_0000_7FFF_FFFF; // Max pos signed 32
        corner_cases[5]  = 64'hFFFF_FFFF_8000_0000; // Min neg signed 32
        corner_cases[6]  = 64'h0000_0000_FFFF_FFFF; // Unsigned 32-bit max
        corner_cases[7]  = 64'h5555_5555_5555_5555; // Alternating 0101
        corner_cases[8]  = 64'hAAAA_AAAA_AAAA_AAAA; // Alternating 1010
        corner_cases[9]  = 64'h0000_0000_0000_0001; // +1
        corner_cases[10] = 64'h0000_0000_0000_0002; // +2
        corner_cases[11] = 64'hFFFF_FFFF_FFFF_FFFE; // -2
        corner_cases[12] = 64'h0000_0000_0000_003F; // 63 (max shift 64)
        corner_cases[13] = 64'h0000_0000_0000_001F; // 31 (max shift 32)
        corner_cases[14] = 64'h0000_0000_0000_0040; // 64 (overflow shift)
        corner_cases[15] = 64'h1234_5678_9ABC_DEF0; // Arbitrary pattern
    end

    // ------------------------------------------------------------
    // Execution Unit DUT
    // ------------------------------------------------------------
    reg  [63:0] dut_pc_in;
    reg  [63:0] dut_rs1, dut_rs2, dut_imm;
    reg  [4:0]  dut_rd;
    reg  [4:0]  dut_rs1a, dut_rs2a;
    reg  [2:0]  dut_f3;
    reg  [6:0]  dut_f7;
    reg  [6:0]  dut_opcode;
    reg  [4:0]  dut_alu_op;
    reg         dut_mem_read, dut_mem_write, dut_reg_write;
    reg         dut_branch, dut_jal, dut_jalr;
    reg         dut_is_amo;
    reg  [4:0]  dut_amo_f5;
    reg         dut_is_csr;
    reg  [1:0]  dut_csr_op;
    reg         dut_is_ecall, dut_is_ebreak, dut_is_mret, dut_is_sret;
    reg         dut_illegal, dut_valid_in;

    wire [63:0] dut_alu_res;
    wire        dut_mul_div_stall;
    wire        dut_branch_taken;
    wire [63:0] dut_branch_target;
    wire        dut_valid_out;

    rv_execute dut_ex (
        .clk(clk),
        .rst_n(rst_n),
        .stall(1'b0),
        .flush(1'b0),
        .pc_in(dut_pc_in),
        .rs1_data(dut_rs1),
        .rs2_data(dut_rs2),
        .imm(dut_imm),
        .rd_in(dut_rd),
        .rs1_addr(dut_rs1a),
        .rs2_addr(dut_rs2a),
        .funct3(dut_f3),
        .funct7(dut_f7),
        .opcode(dut_opcode),
        .alu_op(dut_alu_op),
        .mem_read(dut_mem_read),
        .mem_write(dut_mem_write),
        .reg_write(dut_reg_write),
        .branch(dut_branch),
        .jal(dut_jal),
        .jalr(dut_jalr),
        .is_amo(dut_is_amo),
        .amo_funct5(dut_amo_f5),
        .is_csr(dut_is_csr),
        .csr_op(dut_csr_op),
        .is_ecall(dut_is_ecall),
        .is_ebreak(dut_is_ebreak),
        .is_mret(dut_is_mret),
        .is_sret(dut_is_sret),
        .illegal_in(dut_illegal),
        .instr_in(32'h00000013),
        .fe_fault_in(1'b0),
        .fe_fault_cause_in(64'h0),
        .fe_fault_tval_in(64'h0),
        .mem_fault_in(1'b0),
        .mem_fault_cause_in(64'h0),
        .mem_fault_tval_in(64'h0),
        .mem_fault_pc_in(64'h0),
        .irq_m_ext(1'b0),
        .irq_m_timer(1'b0),
        .irq_m_soft(1'b0),
        .valid_in(dut_valid_in),
        .fwd_mem_data(64'h0),
        .fwd_mem_valid(1'b0),
        .fwd_mem_rd(5'h0),
        .fwd_wb_data(64'h0),
        .fwd_wb_valid(1'b0),
        .fwd_wb_rd(5'h0),
        .fpu_result(64'h0),
        .fpu_valid(1'b0),
        .fpu_done(1'b0),
        .fpu_fflags(5'h0),
        .frm_out(),
        .fp_stall(),
        .sfence_vma_pulse(),
        .sfence_asid_en(),
        .sfence_va_en(),
        .sfence_va_val(),
        .sfence_asid_val(),
        .pc_out(),
        .alu_result(dut_alu_res),
        .rs2_out(),
        .rd_out(),
        .funct3_out(),
        .opcode_out(),
        .mem_read_out(),
        .mem_write_out(),
        .reg_write_out(),
        .is_amo_out(),
        .amo_funct5_out(),
        .valid_out(dut_valid_out),
        .mul_div_stall(dut_mul_div_stall),
        .branch_taken(dut_branch_taken),
        .branch_target(dut_branch_target),
        .trap_taken(),
        .trap_pc_out(),
        .trap_cause_out(),
        .trap_tval_out()
    );

    // ------------------------------------------------------------
    // RVC Decompressor DUT
    // ------------------------------------------------------------
    reg  [15:0] rvc_in;
    wire [31:0] rvc_decomp_instr;
    wire        rvc_decomp_illegal;

    rv_c_decoder dut_rvc (
        .c_instr(rvc_in),
        .instr32(rvc_decomp_instr),
        .illegal(rvc_decomp_illegal)
    );

    // ------------------------------------------------------------
    // Independent Golden Verification Models
    // ------------------------------------------------------------
    function [63:0] golden_alu(
        input [4:0]  op,
        input [63:0] a,
        input [63:0] b,
        input        is_w
    );
        reg signed [63:0] sa, sb;
        reg signed [63:0] sra_val;
        reg [63:0] res;
        reg [5:0] shamt;
        begin
            sa = a;
            sb = b;
            shamt = is_w ? {1'b0, b[4:0]} : b[5:0];
            sra_val = is_w ? {{32{a[31]}}, a[31:0]} : a;
            case (op)
                `ALU_ADD:  res = a + b;
                `ALU_SUB:  res = a - b;
                `ALU_SLT:  res = (sa < sb) ? 64'd1 : 64'd0;
                `ALU_SLTU: res = (a < b) ? 64'd1 : 64'd0;
                `ALU_XOR:  res = a ^ b;
                `ALU_OR:   res = a | b;
                `ALU_AND:  res = a & b;
                `ALU_SLL:  res = (is_w ? {32'b0, a[31:0]} : a) << shamt;
                `ALU_SRL:  res = (is_w ? {32'b0, a[31:0]} : a) >> shamt;
                `ALU_SRA:  res = sra_val >>> shamt;
                `ALU_LUI:  res = b;
                default:   res = a + b;
            endcase
            if (is_w) begin
                res = {{32{res[31]}}, res[31:0]};
            end
            golden_alu = res;
        end
    endfunction

    function [63:0] golden_mext(
        input [4:0]  op,
        input [63:0] a,
        input [63:0] b,
        input        is_w
    );
        reg signed [63:0] sa, sb;
        reg signed [127:0] p_ss;
        reg [127:0] p_su, p_uu;
        reg [63:0] eff_a, eff_b;
        reg [63:0] res;
        begin
            eff_a = is_w ? ((op == `ALU_DIVU || op == `ALU_REMU) ? {32'h0, a[31:0]} : {{32{a[31]}}, a[31:0]}) : a;
            eff_b = is_w ? ((op == `ALU_DIVU || op == `ALU_REMU) ? {32'h0, b[31:0]} : {{32{b[31]}}, b[31:0]}) : b;
            sa = eff_a;
            sb = eff_b;
            p_ss = sa * sb;
            p_su = sa * $signed({1'b0, eff_b});
            p_uu = eff_a * eff_b;
            case (op)
                `ALU_MUL:    res = p_ss[63:0];
                `ALU_MULH:   res = p_ss[127:64];
                `ALU_MULHSU: res = p_su[127:64];
                `ALU_MULHU:  res = p_uu[127:64];
                `ALU_DIV: begin
                    if (eff_b == 64'd0) res = 64'hFFFF_FFFF_FFFF_FFFF;
                    else if (is_w && eff_a[31:0] == 32'h8000_0000 && eff_b == 64'hFFFF_FFFF_FFFF_FFFF) res = {{32{1'b1}}, 32'h8000_0000};
                    else if (!is_w && eff_a == 64'h8000_0000_0000_0000 && eff_b == 64'hFFFF_FFFF_FFFF_FFFF) res = 64'h8000_0000_0000_0000;
                    else res = sa / sb;
                end
                `ALU_DIVU: begin
                    if (eff_b == 64'd0) res = 64'hFFFF_FFFF_FFFF_FFFF;
                    else res = eff_a / eff_b;
                end
                `ALU_REM: begin
                    if (eff_b == 64'd0) res = eff_a;
                    else if (is_w && eff_a[31:0] == 32'h8000_0000 && eff_b == 64'hFFFF_FFFF_FFFF_FFFF) res = 64'd0;
                    else if (!is_w && eff_a == 64'h8000_0000_0000_0000 && eff_b == 64'hFFFF_FFFF_FFFF_FFFF) res = 64'd0;
                    else res = sa % sb;
                end
                `ALU_REMU: begin
                    if (eff_b == 64'd0) res = eff_a;
                    else res = eff_a % eff_b;
                end
                default: res = 64'd0;
            endcase
            if (is_w) begin
                res = {{32{res[31]}}, res[31:0]};
            end
            golden_mext = res;
        end
    endfunction

    // ------------------------------------------------------------
    // Test Control & Stimulus
    // ------------------------------------------------------------
    integer i;
    integer errors = 0;
    integer pass_count = 0;
    reg [63:0] opA, opB, expected;
    reg [4:0]  alu_sel;
    reg        is_w;

    initial begin
        $display("==================================================================");
        $display("  SMVDU TITAN-X: Structural Datapath Random ATPG Testbench");
        $display("  Target: 125,536 Random, Corner-Case & Exhaustive Vectors");
        $display("==================================================================\n");

        rst_n = 0;
        dut_pc_in = 64'h8000_0000;
        dut_rd = 5'd1;
        dut_rs1a = 5'd0;
        dut_rs2a = 5'd0;
        dut_f3 = 3'b000;
        dut_f7 = 7'b0000000;
        dut_opcode = `OP_REG;
        dut_mem_read = 0;
        dut_mem_write = 0;
        dut_reg_write = 1;
        dut_branch = 0;
        dut_jal = 0;
        dut_jalr = 0;
        dut_is_amo = 0;
        dut_amo_f5 = 0;
        dut_is_csr = 0;
        dut_csr_op = 0;
        dut_is_ecall = 0;
        dut_is_ebreak = 0;
        dut_is_mret = 0;
        dut_is_sret = 0;
        dut_illegal = 0;
        dut_valid_in = 0;
        dut_imm = 64'h0;

        repeat (10) @(posedge clk);
        rst_n = 1;
        repeat (10) @(posedge clk);

        // --------------------------------------------------------
        // SECTION 1: 50,000 Vector Random ALU & Logic ATPG
        // --------------------------------------------------------
        $display("[ATPG PHASE 1] Starting 50,000-Vector Random & Corner ALU/Logic Sweep...");
        for (i = 0; i < 50000; i = i + 1) begin
            // Select ALU operation
            case (i % 10)
                0: alu_sel = `ALU_ADD;
                1: alu_sel = `ALU_SUB;
                2: alu_sel = `ALU_SLT;
                3: alu_sel = `ALU_SLTU;
                4: alu_sel = `ALU_XOR;
                5: alu_sel = `ALU_OR;
                6: alu_sel = `ALU_AND;
                7: alu_sel = `ALU_SLL;
                8: alu_sel = `ALU_SRL;
                9: alu_sel = `ALU_SRA;
            endcase

            // Only ADD, SUB, SLL, SRL, SRA exist in 32-bit W-form in RV64I
            if (alu_sel == `ALU_ADD || alu_sel == `ALU_SUB || 
                alu_sel == `ALU_SLL || alu_sel == `ALU_SRL || alu_sel == `ALU_SRA) begin
                is_w = (i % 2 == 1);
            end else begin
                is_w = 1'b0;
            end

            // Mix LFSR with corner cases (every 10th vector uses an extreme corner)
            if (i % 10 == 0) begin
                opA = corner_cases[lfsr1[3:0]];
                opB = corner_cases[lfsr2[3:0]];
            end else begin
                opA = lfsr1;
                opB = lfsr2;
            end

            // Drive on negedge clk so rv_execute captures on posedge clk
            @(negedge clk);
            dut_alu_op   = alu_sel;
            dut_opcode   = is_w ? `OP_REG64 : `OP_REG;
            dut_rs1      = opA;
            dut_rs2      = opB;
            dut_valid_in = 1'b1;

            @(posedge clk);
            #1; // Output register updated on this edge
            expected = golden_alu(alu_sel, opA, opB, is_w);

            if (dut_alu_res !== expected) begin
                $display("[ATPG FAIL #%0d] Op=%0d is_w=%0d A=0x%016h B=0x%016h GOT=0x%016h EXP=0x%016h",
                         i, alu_sel, is_w, opA, opB, dut_alu_res, expected);
                errors = errors + 1;
            end else begin
                pass_count = pass_count + 1;
            end

            if ((i + 1) % 10000 == 0) begin
                $display("[ATPG PROGRESS] Completed %0d ALU vectors (Pass=%0d, Errors=%0d)...", 
                         i + 1, pass_count, errors);
            end
        end

        // Pipeline drain between Phase 1 and Phase 2
        @(negedge clk);
        dut_valid_in = 1'b0;
        dut_alu_op   = `ALU_ADD;
        repeat (5) @(posedge clk);

        // --------------------------------------------------------
        // SECTION 2: 10,000 Vector Random Multiplier & Divider ATPG
        // --------------------------------------------------------
        $display("\n[ATPG PHASE 2] Starting 10,000-Vector M-Extension (MUL/DIV/REM) ATPG...");
        for (i = 0; i < 10000; i = i + 1) begin
            // Stimulate operands
            if (i % 8 == 0) begin
                opA = corner_cases[lfsr1[3:0]];
                opB = corner_cases[lfsr2[3:0]];
            end else begin
                opA = lfsr1;
                opB = lfsr2;
            end

            // Cycle through MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU
            case (i % 8)
                0: begin dut_alu_op = `ALU_MUL;    dut_f3 = `F3_MUL;    end
                1: begin dut_alu_op = `ALU_MULH;   dut_f3 = `F3_MULH;   end
                2: begin dut_alu_op = `ALU_MULHSU; dut_f3 = `F3_MULHSU; end
                3: begin dut_alu_op = `ALU_MULHU;  dut_f3 = `F3_MULHU;  end
                4: begin dut_alu_op = `ALU_DIV;    dut_f3 = `F3_DIV;    end
                5: begin dut_alu_op = `ALU_DIVU;   dut_f3 = `F3_DIVU;   end
                6: begin dut_alu_op = `ALU_REM;    dut_f3 = `F3_REM;    end
                7: begin dut_alu_op = `ALU_REMU;   dut_f3 = `F3_REMU;   end
            endcase

            is_w = (i % 4 == 3) && (dut_alu_op == `ALU_MUL || dut_alu_op == `ALU_DIV || 
                                    dut_alu_op == `ALU_DIVU || dut_alu_op == `ALU_REM || dut_alu_op == `ALU_REMU);
            dut_opcode = is_w ? `OP_REG64 : `OP_REG;
            dut_f7 = `F7_MEXT;

            // Drive inputs
            @(negedge clk);
            dut_rs1 = opA;
            dut_rs2 = opB;
            dut_valid_in = 1'b1;

            // Wait for completion (when dut_valid_out becomes 1)
            @(posedge clk);
            while (!dut_valid_out) @(posedge clk);
            #1;

            expected = golden_mext(dut_alu_op, opA, opB, is_w);

            if (dut_alu_res !== expected) begin
                $display("[ATPG M-EXT FAIL #%0d] Op=%0d is_w=%0d A=0x%016h B=0x%016h GOT=0x%016h EXP=0x%016h",
                         i, dut_alu_op, is_w, opA, opB, dut_alu_res, expected);
                errors = errors + 1;
            end else begin
                pass_count = pass_count + 1;
            end

            // Deassert valid and let pipeline drain
            @(negedge clk);
            dut_valid_in = 1'b0;
            dut_alu_op = `ALU_ADD;
            dut_opcode = `OP_REG;
            @(posedge clk);
            while (dut_mul_div_stall || dut_ex.mx_fin) @(posedge clk);

            if ((i + 1) % 2000 == 0) begin
                $display("[ATPG PROGRESS] Completed %0d M-Extension vectors (Pass=%0d, Errors=%0d)...",
                         i + 1, pass_count, errors);
            end
        end

        // --------------------------------------------------------
        // SECTION 3: 65,536 Vector Exhaustive RVC Decompressor Sweep
        // --------------------------------------------------------
        $display("\n[ATPG PHASE 3] Starting 65,536-Vector Exhaustive RVC Decompressor Sweep (0x0000..0xFFFF)...");
        for (i = 0; i < 65536; i = i + 1) begin
            rvc_in = i[15:0];
            #1;

            // Decompressor must never produce X state
            if (^rvc_decomp_instr === 1'bx || rvc_decomp_illegal === 1'bx) begin
                $display("[ATPG RVC FAIL #%0d] Decompressor X on input 0x%04h: instr=0x%08h, illegal=%0b",
                         i, rvc_in, rvc_decomp_instr, rvc_decomp_illegal);
                errors = errors + 1;
            end else begin
                pass_count = pass_count + 1;
            end

            if ((i + 1) % 15000 == 0) begin
                $display("[ATPG PROGRESS] Completed %0d RVC vectors (Pass=%0d, Errors=%0d)...",
                         i + 1, pass_count, errors);
            end
        end

        // --------------------------------------------------------
        // ATPG Signoff Report
        // --------------------------------------------------------
        $display("\n==================================================================");
        $display("  STRUCTURAL DATAPATH RANDOM ATPG RESULTS");
        $display("==================================================================");
        $display("  Total Vectors Executed : %0d", 50000 + 10000 + 65536);
        $display("  Total Vectors Passed   : %0d", pass_count);
        $display("  Total Failures         : %0d", errors);
        if (errors == 0) begin
            $display("  VERDICT: PASS — 125,536 RANDOM ATPG VECTORS 100%% VERIFIED");
            $display("  REGRESS_RESULT: PASS");
        end else begin
            $display("  VERDICT: FAIL — %0d ANOMALIES DETECTED", errors);
            $display("  REGRESS_RESULT: FAIL");
        end
        $display("==================================================================\n");

        $finish;
    end

endmodule
