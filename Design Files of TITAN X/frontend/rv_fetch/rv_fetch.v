// SPDX-License-Identifier: Apache-2.0
// SMVDU-Titan-X SoC — RISC-V Instruction Fetch Stage (RV64I)
//
// Single-outstanding AXI-Lite fetch FSM with redirect-safe teardown:
// on a redirect the unit first drains any orphaned transaction belonging
// to the abandoned stream (an unaccepted AR, or an R beat already owed)
// before issuing the redirected fetch. Without that drain the stale
// instruction would be paired with the NEW pc_out — silent execution of
// the wrong instruction at the wrong architectural address.
`timescale 1ns/1ps
`include "params.vh"

module rv_fetch #(
    parameter RESET_PC     = `RESET_PC,
    parameter ENABLE_DRAIN = 1,
    parameter ENABLE_RVC   = 0
) (
    input  wire        clk,
    input  wire        rst_n,
    // Hazard/control
    input  wire        stall,
    input  wire        flush,
    input  wire        branch_taken,
    input  wire [63:0] branch_target,
    // Instruction memory (AXI-Lite AR/R)
    output reg  [63:0] imem_addr,
    output reg         imem_arvalid,
    input  wire        imem_arready,
    input  wire [31:0] imem_rdata,
    input  wire        imem_rvalid,
    output wire        imem_rready,
    input  wire [1:0]  imem_rresp,
    // To decode stage
    output reg  [63:0] pc_out,
    output reg  [31:0] instr_out,
    output reg         valid_out,
    output reg         fault_out,
    output reg  [63:0] fault_cause_out,
    output reg  [63:0] fault_tval_out
);
    reg [63:0] pc;
    reg [15:0] half_buf;
    reg        half_buf_valid;

    // Fetch FSM
    localparam F_REQ   = 2'd1;
    localparam F_WAIT  = 2'd2;
    localparam F_FLUSH = 2'd3;   // draining an orphaned transaction
    reg [1:0] fstate;
    reg       pending_r;         // AR accepted; matching R beat still owed

    // Ready for the R beat while waiting for data OR while swallowing an
    // orphan after a redirect — and never during a global stall (a
    // compliant slave holds rvalid/rdata stable until we accept).
    assign imem_rready = (fstate == F_WAIT || fstate == F_FLUSH) && !stall;

    wire redirect = flush || branch_taken;

    // Transaction-completion pulses. r_fire doubles as "the R beat is being
    // consumed THIS edge" (rready is high by construction in both wait
    // states), which is what makes the redirect classification below exact.
    wire ar_fire = imem_arvalid && imem_arready;
    wire r_fire  = !stall && imem_rvalid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc              <= RESET_PC;
            imem_addr       <= RESET_PC;
            imem_arvalid    <= 1'b0;
            pc_out          <= 64'h0;
            instr_out       <= 32'h0000_0013; // NOP
            valid_out       <= 1'b0;
            fault_out       <= 1'b0;
            fault_cause_out <= 64'h0;
            fault_tval_out  <= 64'h0;
            fstate          <= F_REQ;
            pending_r       <= 1'b0;
            half_buf        <= 16'h0;
            half_buf_valid  <= 1'b0;
        end else begin
            case (fstate)
                F_REQ: begin
                    if (redirect) begin
                        valid_out       <= 1'b0;
                        fault_out       <= 1'b0;
                        fault_cause_out <= 64'h0;
                        fault_tval_out  <= 64'h0;
                        half_buf_valid  <= 1'b0;
                        pc              <= branch_target;
                        imem_addr       <= ENABLE_RVC ? {branch_target[63:2], 2'b00} : branch_target;
                        imem_arvalid    <= 1'b1;
                        fstate          <= F_WAIT;
                    end else if (!stall) begin
                        valid_out       <= 1'b0;
                        fault_out       <= 1'b0;
                        fault_cause_out <= 64'h0;
                        fault_tval_out  <= 64'h0;
                        if (ENABLE_RVC && half_buf_valid && (half_buf[1:0] != 2'b11)) begin
                            // Fast path: consume the buffered 16-bit compressed instruction directly
                            pc_out          <= pc;
                            instr_out       <= {16'h0000, half_buf};
                            valid_out       <= 1'b1;
                            pc              <= pc + 64'd2;
                            half_buf_valid  <= 1'b0;
                            fstate          <= F_REQ;
                        end else begin
                            imem_addr       <= ENABLE_RVC ? ({pc[63:2], 2'b00} + (half_buf_valid ? 64'd4 : 64'd0)) : pc;
                            imem_arvalid    <= 1'b1;
                            fstate          <= F_WAIT;
                        end
                    end
                end
                F_WAIT: begin
                    // Track AR completion for the outstanding request
                    if (ar_fire) begin
                        imem_arvalid <= 1'b0;
                        pending_r    <= 1'b1;
                    end
                    if (redirect) begin
                        valid_out       <= 1'b0;
                        fault_out       <= 1'b0;
                        fault_cause_out <= 64'h0;
                        fault_tval_out  <= 64'h0;
                        half_buf_valid  <= 1'b0;
                        pc              <= branch_target;
                        if (ENABLE_DRAIN && ((imem_arvalid && !ar_fire) ||
                            ((pending_r || ar_fire) && !r_fire)))
                            fstate <= F_FLUSH;
                        else begin
                            pending_r    <= 1'b0;
                            imem_addr    <= ENABLE_RVC ? {branch_target[63:2], 2'b00} : branch_target;
                            imem_arvalid <= 1'b1;
                            fstate       <= F_WAIT;
                        end
                    end else if (!stall && pending_r && imem_rvalid) begin
                        pc_out <= pc;
                        if (imem_rresp != 2'b00) begin
                            instr_out       <= 32'h0000_0013; // NOP
                            valid_out       <= 1'b1;
                            fault_out       <= 1'b1;
                            fault_cause_out <= 64'd1;         // Instruction access fault
                            fault_tval_out  <= pc;
                            pc              <= pc + 64'd4;
                            half_buf_valid  <= 1'b0;
                            pending_r       <= 1'b0;
                            fstate          <= F_REQ;
                        end else if (ENABLE_RVC && half_buf_valid) begin
                            // Spanning 32-bit instruction: lower half from buffer, upper half from imem_rdata[15:0]
                            instr_out       <= {imem_rdata[15:0], half_buf};
                            valid_out       <= 1'b1;
                            fault_out       <= 1'b0;
                            fault_cause_out <= 64'h0;
                            fault_tval_out  <= 64'h0;
                            pc              <= pc + 64'd4;
                            half_buf        <= imem_rdata[31:16];
                            half_buf_valid  <= 1'b1;
                            pending_r       <= 1'b0;
                            fstate          <= F_REQ;
                        end else if (ENABLE_RVC && (pc[1] == 1'b0)) begin
                            if (imem_rdata[1:0] != 2'b11) begin
                                // 16-bit compressed instruction at word lower half
                                instr_out       <= {16'h0000, imem_rdata[15:0]};
                                valid_out       <= 1'b1;
                                fault_out       <= 1'b0;
                                fault_cause_out <= 64'h0;
                                fault_tval_out  <= 64'h0;
                                pc              <= pc + 64'd2;
                                half_buf        <= imem_rdata[31:16];
                                half_buf_valid  <= 1'b1;
                            end else begin
                                // 32-bit regular instruction
                                instr_out       <= imem_rdata;
                                valid_out       <= 1'b1;
                                fault_out       <= 1'b0;
                                fault_cause_out <= 64'h0;
                                fault_tval_out  <= 64'h0;
                                pc              <= pc + 64'd4;
                                half_buf_valid  <= 1'b0;
                            end
                            pending_r <= 1'b0;
                            fstate    <= F_REQ;
                        end else if (ENABLE_RVC && (pc[1] == 1'b1)) begin
                            // pc[1] == 1'b1: instruction begins at imem_rdata[31:16]
                            if (imem_rdata[17:16] != 2'b11) begin
                                // 16-bit compressed instruction at upper half
                                instr_out       <= {16'h0000, imem_rdata[31:16]};
                                valid_out       <= 1'b1;
                                fault_out       <= 1'b0;
                                fault_cause_out <= 64'h0;
                                fault_tval_out  <= 64'h0;
                                pc              <= pc + 64'd2;
                                half_buf_valid  <= 1'b0;
                                pending_r       <= 1'b0;
                                fstate          <= F_REQ;
                            end else begin
                                // 32-bit uncompressed instruction starting at upper half: buffer and fetch next word
                                half_buf        <= imem_rdata[31:16];
                                half_buf_valid  <= 1'b1;
                                imem_addr       <= {pc[63:2], 2'b00} + 64'd4;
                                imem_arvalid    <= 1'b1;
                                pending_r       <= 1'b0;
                                // Remain in F_WAIT for next word
                            end
                        end else begin
                            // Standard uncompressed fetch (ENABLE_RVC == 0)
                            instr_out       <= imem_rdata;
                            valid_out       <= 1'b1;
                            fault_out       <= 1'b0;
                            fault_cause_out <= 64'h0;
                            fault_tval_out  <= 64'h0;
                            pc              <= pc + 64'd4;
                            half_buf_valid  <= 1'b0;
                            pending_r       <= 1'b0;
                            fstate          <= F_REQ;
                        end
                    end
                end
                F_FLUSH: begin
                    valid_out       <= 1'b0;
                    fault_out       <= 1'b0;
                    fault_cause_out <= 64'h0;
                    fault_tval_out  <= 64'h0;
                    half_buf_valid  <= 1'b0;
                    // Latest target wins if another redirect arrives mid-drain.
                    if (redirect) begin
                        pc <= branch_target;
                        if (!ENABLE_DRAIN) begin
                            imem_addr    <= ENABLE_RVC ? {branch_target[63:2], 2'b00} : branch_target;
                            imem_arvalid <= 1'b1;
                            pending_r    <= 1'b0;
                            fstate       <= F_WAIT;
                        end
                    end
                    if (imem_arvalid) begin
                        // Old request still waiting for its AR handshake:
                        // hold address/arvalid stable until accepted.
                        if (ar_fire) begin
                            imem_arvalid <= 1'b0;
                            pending_r    <= 1'b1;
                        end
                    end else if (pending_r) begin
                        if (r_fire)
                            pending_r <= 1'b0;    // orphan swallowed
                    end else begin
                        imem_addr    <= ENABLE_RVC ? {pc[63:2], 2'b00} : pc;
                        imem_arvalid <= 1'b1;
                        fstate       <= F_WAIT;
                    end
                end
                default: fstate <= F_REQ;
            endcase
`ifndef SYNTHESIS
            if ($time > 0) begin
                // Check if in window
            end
`endif
        end
    end
endmodule
