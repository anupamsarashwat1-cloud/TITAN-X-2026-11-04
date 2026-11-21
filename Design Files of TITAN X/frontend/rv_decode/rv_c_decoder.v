// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — RISC-V Compressed Instruction Decompressor (RV64C)
// Combinational decompression of 16-bit compressed instructions into
// canonical 32-bit RV64I/D opcodes per RISC-V Privileged & Unprivileged ISA v2.2.
`timescale 1ns/1ps

module rv_c_decoder (
    input  wire [15:0] c_instr,
    output reg  [31:0] instr32,
    output reg         illegal
);

    wire [1:0] op2    = c_instr[1:0];
    wire [2:0] funct3 = c_instr[15:13];

    // Standard register indices
    wire [4:0] rd_std  = c_instr[11:7];
    wire [4:0] rs1_std = c_instr[11:7];
    wire [4:0] rs2_std = c_instr[6:2];

    // Compressed "prime" register indices (x8 - x15)
    wire [4:0] rd_p  = {2'b01, c_instr[4:2]};
    wire [4:0] rs1_p = {2'b01, c_instr[9:7]};
    wire [4:0] rs2_p = {2'b01, c_instr[4:2]};

    // Immediates
    // Quadrant 0
    wire [9:0] nzuimm_addi4spn = {c_instr[10:7], c_instr[12:11], c_instr[5], c_instr[6], 2'b00};
    wire [7:0] uimm_fld        = {c_instr[6:5], c_instr[12:10], 3'b000};
    wire [6:0] uimm_lw         = {c_instr[5], c_instr[12:10], c_instr[6], 2'b00};
    wire [7:0] uimm_ld         = {c_instr[6:5], c_instr[12:10], 3'b000};
    wire [7:0] uimm_fsd        = {c_instr[6:5], c_instr[12:10], 3'b000};
    wire [6:0] uimm_sw         = {c_instr[5], c_instr[12:10], c_instr[6], 2'b00};
    wire [7:0] uimm_sd         = {c_instr[6:5], c_instr[12:10], 3'b000};

    // Quadrant 1
    wire [11:0] imm_addi  = {{6{c_instr[12]}}, c_instr[12], c_instr[6:2]};
    wire [11:0] imm_addiw = {{6{c_instr[12]}}, c_instr[12], c_instr[6:2]};
    wire [11:0] imm_li    = {{6{c_instr[12]}}, c_instr[12], c_instr[6:2]};
    wire [11:0] imm_16sp  = {{2{c_instr[12]}}, c_instr[12], c_instr[4:3], c_instr[5], c_instr[2], c_instr[6], 4'b0000};
    wire [19:0] imm_lui   = {{14{c_instr[12]}}, c_instr[12], c_instr[6:2]};
    wire [5:0]  shamt_sr  = {c_instr[12], c_instr[6:2]};
    wire [11:0] imm_andi  = {{6{c_instr[12]}}, c_instr[12], c_instr[6:2]};
    wire [20:0] imm_j     = {{9{c_instr[12]}}, c_instr[12], c_instr[8], c_instr[10:9], c_instr[6], c_instr[7], c_instr[2], c_instr[11], c_instr[5:3], 1'b0};
    wire [12:0] imm_b     = {{4{c_instr[12]}}, c_instr[12], c_instr[6:5], c_instr[2], c_instr[11:10], c_instr[4:3], 1'b0};

    // Quadrant 2
    wire [5:0] shamt_slli = {c_instr[12], c_instr[6:2]};
    wire [8:0] uimm_fldsp = {c_instr[4:2], c_instr[12], c_instr[6:5], 3'b000};
    wire [7:0] uimm_lwsp  = {c_instr[3:2], c_instr[12], c_instr[6:4], 2'b00};
    wire [8:0] uimm_ldsp  = {c_instr[4:2], c_instr[12], c_instr[6:5], 3'b000};
    wire [8:0] uimm_fsdsp = {c_instr[9:7], c_instr[12:10], 3'b000};
    wire [7:0] uimm_swsp  = {c_instr[8:7], c_instr[12:9], 2'b00};
    wire [8:0] uimm_sdsp  = {c_instr[9:7], c_instr[12:10], 3'b000};

    always @(*) begin
        instr32 = 32'h0000_0000; // default 0 (illegal/bubble)
        illegal = 1'b0;

        case (op2)
            // ────────────────────────────────────────────────────────
            // Quadrant 0: Load/Store and Stack Ops
            // ────────────────────────────────────────────────────────
            2'b00: begin
                case (funct3)
                    3'b000: begin // C.ADDI4SPN
                        if (nzuimm_addi4spn == 10'd0)
                            illegal = 1'b1;
                        else
                            instr32 = {2'b00, nzuimm_addi4spn, 5'd2, 3'b000, rd_p, 7'b0010011}; // addi rd', x2, nzuimm
                    end
                    3'b001: begin // C.FLD (RV64D)
                        instr32 = {4'b0000, uimm_fld, rs1_p, 3'b011, rd_p, 7'b0000111}; // fld rd', uimm(rs1')
                    end
                    3'b010: begin // C.LW
                        instr32 = {5'b00000, uimm_lw, rs1_p, 3'b010, rd_p, 7'b0000011}; // lw rd', uimm(rs1')
                    end
                    3'b011: begin // C.LD (RV64)
                        instr32 = {4'b0000, uimm_ld, rs1_p, 3'b011, rd_p, 7'b0000011}; // ld rd', uimm(rs1')
                    end
                    3'b101: begin // C.FSD (RV64D)
                        instr32 = {4'b0000, uimm_fsd[7:5], rs2_p, rs1_p, 3'b011, uimm_fsd[4:0], 7'b0100111}; // fsd rs2', uimm(rs1')
                    end
                    3'b110: begin // C.SW
                        instr32 = {5'b00000, uimm_sw[6:5], rs2_p, rs1_p, 3'b010, uimm_sw[4:0], 7'b0100011}; // sw rs2', uimm(rs1')
                    end
                    3'b111: begin // C.SD (RV64)
                        instr32 = {4'b0000, uimm_sd[7:5], rs2_p, rs1_p, 3'b011, uimm_sd[4:0], 7'b0100011}; // sd rs2', uimm(rs1')
                    end
                    default: illegal = 1'b1;
                endcase
            end

            // ────────────────────────────────────────────────────────
            // Quadrant 1: ALU, Branches, Jumps
            // ────────────────────────────────────────────────────────
            2'b01: begin
                case (funct3)
                    3'b000: begin // C.NOP / C.ADDI
                        instr32 = {imm_addi, rd_std, 3'b000, rd_std, 7'b0010011}; // addi rd, rd, imm
                    end
                    3'b001: begin // C.ADDIW (RV64)
                        if (rd_std == 5'd0)
                            illegal = 1'b1;
                        else
                            instr32 = {imm_addiw, rd_std, 3'b000, rd_std, 7'b0011011}; // addiw rd, rd, imm
                    end
                    3'b010: begin // C.LI
                        instr32 = {imm_li, 5'd0, 3'b000, rd_std, 7'b0010011}; // addi rd, x0, imm
                    end
                    3'b011: begin
                        if (rd_std == 5'd2) begin // C.ADDI16SP
                            if (imm_16sp == 12'd0)
                                illegal = 1'b1;
                            else
                                instr32 = {imm_16sp, 5'd2, 3'b000, 5'd2, 7'b0010011}; // addi x2, x2, imm
                        end else if (rd_std != 5'd0) begin // C.LUI
                            if (imm_lui == 20'd0)
                                illegal = 1'b1;
                            else
                                instr32 = {imm_lui, rd_std, 7'b0110111}; // lui rd, imm
                        end else begin
                            illegal = 1'b1;
                        end
                    end
                    3'b100: begin
                        case (c_instr[11:10])
                            2'b00: begin // C.SRLI
                                instr32 = {6'b000000, shamt_sr, rs1_p, 3'b101, rs1_p, 7'b0010011}; // srli rd', rd', shamt
                            end
                            2'b01: begin // C.SRAI
                                instr32 = {6'b010000, shamt_sr, rs1_p, 3'b101, rs1_p, 7'b0010011}; // srai rd', rd', shamt
                            end
                            2'b10: begin // C.ANDI
                                instr32 = {imm_andi, rs1_p, 3'b111, rs1_p, 7'b0010011}; // andi rd', rd', imm
                            end
                            2'b11: begin
                                if (c_instr[12] == 1'b0) begin
                                    case (c_instr[6:5])
                                        2'b00: instr32 = {7'b0100000, rs2_p, rs1_p, 3'b000, rs1_p, 7'b0110011}; // sub rd', rd', rs2'
                                        2'b01: instr32 = {7'b0000000, rs2_p, rs1_p, 3'b100, rs1_p, 7'b0110011}; // xor rd', rd', rs2'
                                        2'b10: instr32 = {7'b0000000, rs2_p, rs1_p, 3'b110, rs1_p, 7'b0110011}; // or  rd', rd', rs2'
                                        2'b11: instr32 = {7'b0000000, rs2_p, rs1_p, 3'b111, rs1_p, 7'b0110011}; // and rd', rd', rs2'
                                    endcase
                                end else begin // c_instr[12] == 1'b1
                                    case (c_instr[6:5])
                                        2'b00: instr32 = {7'b0100000, rs2_p, rs1_p, 3'b000, rs1_p, 7'b0111011}; // subw rd', rd', rs2'
                                        2'b01: instr32 = {7'b0000000, rs2_p, rs1_p, 3'b000, rs1_p, 7'b0111011}; // addw rd', rd', rs2'
                                        default: illegal = 1'b1;
                                    endcase
                                end
                            end
                        endcase
                    end
                    3'b101: begin // C.J
                        instr32 = {imm_j[20], imm_j[10:1], imm_j[11], imm_j[19:12], 5'd0, 7'b1101111}; // jal x0, imm
                    end
                    3'b110: begin // C.BEQZ
                        instr32 = {imm_b[12], imm_b[10:5], 5'd0, rs1_p, 3'b000, imm_b[4:1], imm_b[11], 7'b1100011}; // beq rs1', x0, imm
                    end
                    3'b111: begin // C.BNEZ
                        instr32 = {imm_b[12], imm_b[10:5], 5'd0, rs1_p, 3'b001, imm_b[4:1], imm_b[11], 7'b1100011}; // bne rs1', x0, imm
                    end
                endcase
            end

            // ────────────────────────────────────────────────────────
            // Quadrant 2: Stack Load/Store, Shifts, and Indirect Jumps
            // ────────────────────────────────────────────────────────
            2'b10: begin
                case (funct3)
                    3'b000: begin // C.SLLI
                        instr32 = {6'b000000, shamt_slli, rd_std, 3'b001, rd_std, 7'b0010011}; // slli rd, rd, shamt
                    end
                    3'b011: begin // C.LDSP (RV64)
                        if (rd_std == 5'd0)
                            illegal = 1'b1;
                        else
                            instr32 = {3'b000, uimm_ldsp, 5'd2, 3'b011, rd_std, 7'b0000011}; // ld rd, uimm(x2)
                    end
                    3'b001: begin // C.FLDSP (RV64D)
                        instr32 = {3'b000, uimm_fldsp, 5'd2, 3'b011, rd_std, 7'b0000111}; // fld rd, uimm(x2)
                    end
                    3'b010: begin // C.LWSP
                        if (rd_std == 5'd0)
                            illegal = 1'b1;
                        else
                            instr32 = {4'b0000, uimm_lwsp, 5'd2, 3'b010, rd_std, 7'b0000011}; // lw rd, uimm(x2)
                    end
                    3'b100: begin
                        if (c_instr[12] == 1'b0) begin
                            if (rs2_std == 5'd0) begin // C.JR
                                if (rs1_std == 5'd0)
                                    illegal = 1'b1;
                                else
                                    instr32 = {12'h0, rs1_std, 3'b000, 5'd0, 7'b1100111}; // jalr x0, 0(rs1)
                            end else begin // C.MV
                                instr32 = {7'b0000000, rs2_std, 5'd0, 3'b000, rd_std, 7'b0110011}; // add rd, x0, rs2
                            end
                        end else begin // c_instr[12] == 1'b1
                            if (rs2_std == 5'd0) begin
                                if (rd_std == 5'd0) begin // C.EBREAK
                                    instr32 = 32'h0010_0073; // ebreak
                                end else begin // C.JALR
                                    instr32 = {12'h0, rs1_std, 3'b000, 5'd1, 7'b1100111}; // jalr x1, 0(rs1)
                                end
                            end else begin // C.ADD
                                instr32 = {7'b0000000, rs2_std, rd_std, 3'b000, rd_std, 7'b0110011}; // add rd, rd, rs2
                            end
                        end
                    end
                    3'b101: begin // C.FSDSP (RV64D)
                        instr32 = {3'b000, uimm_fsdsp[8:5], rs2_std, 5'd2, 3'b011, uimm_fsdsp[4:0], 7'b0100111}; // fsd rs2, uimm(x2)
                    end
                    3'b110: begin // C.SWSP
                        instr32 = {4'b0000, uimm_swsp[7:5], rs2_std, 5'd2, 3'b010, uimm_swsp[4:0], 7'b0100011}; // sw rs2, uimm(x2)
                    end
                    3'b111: begin // C.SDSP (RV64)
                        instr32 = {3'b000, uimm_sdsp[8:5], rs2_std, 5'd2, 3'b011, uimm_sdsp[4:0], 7'b0100011}; // sd rs2, uimm(x2)
                    end
                endcase
            end

            // ────────────────────────────────────────────────────────
            // Quadrant 3: 32-bit standard instruction (pass-through / not handled here)
            // ────────────────────────────────────────────────────────
            2'b11: begin
                illegal = 1'b0;
                instr32 = 32'h0000_0013;
            end
        endcase
    end

endmodule
