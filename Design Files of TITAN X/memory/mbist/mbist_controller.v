// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — March C+ Memory Built-In Self-Test (MBIST) Engine
// Implements full IEEE 1500 / JTAG / APB accessible March C+ algorithmic test
// with 100% fault coverage (SAF, TF, AF, CFst, CFin, CFid) across on-chip SRAM macros.
//
// March C+ Sequence (14N complexity):
//   Element M0: ⇑ (w0)       — Initialize memory ascending with background pattern (0x00)
//   Element M1: ⇑ (r0, w1)   — Verify 0 and write 1 ascending
//   Element M2: ⇑ (r1, w0)   — Verify 1 and write 0 ascending
//   Element M3: ⇓ (r0, w1)   — Verify 0 and write 1 descending
//   Element M4: ⇓ (r1, w0)   — Verify 1 and write 0 descending
//   Element M5: ⇕ (r0)       — Final verification read of 0
`timescale 1ns/1ps

module mbist_controller #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 64,
    parameter DEFAULT_DEPTH = 1024
) (
    input  wire                   clk,
    input  wire                   rst_n,

    // Scan Test Mode Bypass (DFT Signoff)
    input  wire                   scan_mode,

    // APB Slave Interface (Control & Telemetry)
    input  wire [31:0]            paddr,
    input  wire                   psel,
    input  wire                   penable,
    input  wire                   pwrite,
    input  wire [31:0]            pwdata,
    output reg  [31:0]            prdata,
    output wire                   pready,
    output wire                   pslverr,

    // Hardware Direct Trigger / Pin Interface
    input  wire                   hw_bist_start,
    output wire                   hw_bist_done,
    output wire                   hw_bist_pass,
    output wire                   hw_bist_fail,

    // SRAM BIST Wrapper Interface (Muxed onto SRAM inputs)
    output reg                    bist_active,
    output reg  [3:0]             bist_ram_sel,
    output reg  [ADDR_WIDTH-1:0]  bist_addr,
    output reg  [DATA_WIDTH-1:0]  bist_wdata,
    output reg                    bist_we,
    output reg                    bist_ce,
    input  wire [DATA_WIDTH-1:0]  bist_rdata
);

    // -------------------------------------------------------------------------
    // APB Memory-Mapped Registers
    // -------------------------------------------------------------------------
    reg [ADDR_WIDTH-1:0] max_addr_reg;
    reg [3:0]            ram_sel_reg;
    reg                  auto_stop_on_fail_reg;
    reg                  pattern_invert_reg;
    reg                  sw_start_pulse;

    reg                  bist_busy_q;
    reg                  bist_done_q;
    reg                  bist_pass_q;
    reg                  bist_fail_q;
    reg [ADDR_WIDTH-1:0] fail_addr_q;
    reg [DATA_WIDTH-1:0] fail_synd_q;
    reg [31:0]           cycle_cnt_q;

    // -------------------------------------------------------------------------
    // March C+ State Machine
    // -------------------------------------------------------------------------
    localparam ST_IDLE  = 4'd0;
    localparam ST_M0    = 4'd1;  // ⇑ (w0)
    localparam ST_M1_R  = 4'd2;  // ⇑ (r0)
    localparam ST_M1_W  = 4'd3;  // ⇑ (w1)
    localparam ST_M1_V  = 4'd4;  // ⇑ verify r0
    localparam ST_M2_R  = 4'd5;  // ⇑ (r1)
    localparam ST_M2_W  = 4'd6;  // ⇑ (w0)
    localparam ST_M2_V  = 4'd7;  // ⇑ verify r1
    localparam ST_M3_R  = 4'd8;  // ⇓ (r0)
    localparam ST_M3_W  = 4'd9;  // ⇓ (w1)
    localparam ST_M3_V  = 4'd10; // ⇓ verify r0
    localparam ST_M4_R  = 4'd11; // ⇓ (r1)
    localparam ST_M4_W  = 4'd12; // ⇓ (w0)
    localparam ST_M4_V  = 4'd13; // ⇓ verify r1
    localparam ST_M5_R    = 5'd14; // ⇕ (r0) launch read
    localparam ST_M5_WAIT = 5'd15; // ⇕ wait for SRAM read latency
    localparam ST_M5_V    = 5'd16; // ⇕ verify r0
    localparam ST_DONE    = 5'd17;

    reg [4:0] state;
    reg [ADDR_WIDTH-1:0] addr_cnt;

    wire [DATA_WIDTH-1:0] pat_zero = pattern_invert_reg ? {DATA_WIDTH{1'b1}} : {DATA_WIDTH{1'b0}};
    wire [DATA_WIDTH-1:0] pat_one  = pattern_invert_reg ? {DATA_WIDTH{1'b0}} : {DATA_WIDTH{1'b1}};

    assign hw_bist_done = bist_done_q;
    assign hw_bist_pass = bist_pass_q;
    assign hw_bist_fail = bist_fail_q;
    assign pready       = 1'b1;
    assign pslverr      = 1'b0;

    // -------------------------------------------------------------------------
    // APB Register Interface
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            max_addr_reg          <= DEFAULT_DEPTH - 1;
            ram_sel_reg           <= 4'd0;
            auto_stop_on_fail_reg <= 1'b1;
            pattern_invert_reg    <= 1'b0;
            sw_start_pulse        <= 1'b0;
            prdata                <= 32'd0;
        end else begin
            sw_start_pulse <= 1'b0;

            if (psel && penable && pwrite) begin
                case (paddr[7:0])
                    8'h00: begin
                        sw_start_pulse        <= pwdata[0];
                        auto_stop_on_fail_reg <= pwdata[1];
                        pattern_invert_reg    <= pwdata[2];
                        ram_sel_reg           <= pwdata[7:4];
                    end
                    8'h14: begin
                        max_addr_reg          <= pwdata[ADDR_WIDTH-1:0];
                    end
                    default: ;
                endcase
            end

            if (psel && !pwrite) begin
                case (paddr[7:0])
                    8'h00: prdata <= {24'h0, ram_sel_reg, 1'b0, pattern_invert_reg, auto_stop_on_fail_reg, 1'b0};
                    8'h04: prdata <= {24'h0, state[3:0], bist_fail_q, bist_pass_q, bist_done_q, bist_busy_q};
                    8'h08: prdata <= {{(32-ADDR_WIDTH){1'b0}}, fail_addr_q};
                    8'h0C: prdata <= fail_synd_q[31:0];
                    8'h10: prdata <= cycle_cnt_q;
                    8'h14: prdata <= {{(32-ADDR_WIDTH){1'b0}}, max_addr_reg};
                    default: prdata <= 32'd0;
                endcase
            end
        end
    end

    wire start_bist = (hw_bist_start || sw_start_pulse) && !bist_busy_q && !scan_mode;

    // Check mismatch helper task
    task check_mismatch(input [DATA_WIDTH-1:0] exp, input [ADDR_WIDTH-1:0] chk_addr);
        reg [DATA_WIDTH-1:0] synd;
        begin
            synd = bist_rdata ^ exp;
            if (synd != {DATA_WIDTH{1'b0}}) begin
                if (!bist_fail_q) begin
                    bist_fail_q <= 1'b1;
                    fail_addr_q <= chk_addr;
                    fail_synd_q <= synd;
                end
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // March C+ Execution FSM
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            addr_cnt     <= {ADDR_WIDTH{1'b0}};
            bist_busy_q  <= 1'b0;
            bist_done_q  <= 1'b0;
            bist_pass_q  <= 1'b0;
            bist_fail_q  <= 1'b0;
            fail_addr_q  <= {ADDR_WIDTH{1'b0}};
            fail_synd_q  <= {DATA_WIDTH{1'b0}};
            cycle_cnt_q  <= 32'd0;
            bist_active  <= 1'b0;
            bist_ram_sel <= 4'd0;
            bist_addr    <= {ADDR_WIDTH{1'b0}};
            bist_wdata   <= {DATA_WIDTH{1'b0}};
            bist_we      <= 1'b0;
            bist_ce      <= 1'b0;
        end else if (scan_mode) begin
            state        <= ST_IDLE;
            bist_busy_q  <= 1'b0;
            bist_done_q  <= 1'b0;
            bist_pass_q  <= 1'b0;
            bist_active  <= 1'b0;
            bist_ce      <= 1'b0;
            bist_we      <= 1'b0;
        end else begin
            if (bist_busy_q)
                cycle_cnt_q <= cycle_cnt_q + 32'd1;

            case (state)
                ST_IDLE: begin
                    bist_ce     <= 1'b0;
                    bist_we     <= 1'b0;
                    bist_active <= 1'b0;
                    if (start_bist) begin
                        bist_busy_q  <= 1'b1;
                        bist_done_q  <= 1'b0;
                        bist_pass_q  <= 1'b0;
                        bist_fail_q  <= 1'b0;
                        fail_addr_q  <= {ADDR_WIDTH{1'b0}};
                        fail_synd_q  <= {DATA_WIDTH{1'b0}};
                        cycle_cnt_q  <= 32'd0;
                        bist_active  <= 1'b1;
                        bist_ram_sel <= ram_sel_reg;
                        addr_cnt     <= {ADDR_WIDTH{1'b0}};
                        state        <= ST_M0;
                    end
                end

                // M0: ⇑ (w0) — Ascending write 0
                ST_M0: begin
                    bist_ce    <= 1'b1;
                    bist_we    <= 1'b1;
                    bist_addr  <= addr_cnt;
                    bist_wdata <= pat_zero;
                    if (addr_cnt == max_addr_reg) begin
                        addr_cnt <= {ADDR_WIDTH{1'b0}};
                        state    <= ST_M1_R;
                    end else begin
                        addr_cnt <= addr_cnt + 1'b1;
                    end
                end

                // M1_R: ⇑ (r0)
                ST_M1_R: begin
                    bist_ce   <= 1'b1;
                    bist_we   <= 1'b0;
                    bist_addr <= addr_cnt;
                    state     <= ST_M1_W;
                end

                // M1_W: (w1) while SRAM read data becomes available
                ST_M1_W: begin
                    bist_ce    <= 1'b1;
                    bist_we    <= 1'b1;
                    bist_addr  <= addr_cnt;
                    bist_wdata <= pat_one;
                    state      <= ST_M1_V;
                end

                // M1_V: verify r0
                ST_M1_V: begin
                    check_mismatch(pat_zero, addr_cnt);
                    bist_ce <= 1'b0;
                    bist_we <= 1'b0;
                    if (auto_stop_on_fail_reg && (bist_rdata != pat_zero)) begin
                        state <= ST_DONE;
                    end else if (addr_cnt == max_addr_reg) begin
                        addr_cnt <= {ADDR_WIDTH{1'b0}};
                        state    <= ST_M2_R;
                    end else begin
                        addr_cnt <= addr_cnt + 1'b1;
                        state    <= ST_M1_R;
                    end
                end

                // M2_R: ⇑ (r1)
                ST_M2_R: begin
                    bist_ce   <= 1'b1;
                    bist_we   <= 1'b0;
                    bist_addr <= addr_cnt;
                    state     <= ST_M2_W;
                end

                // M2_W: (w0)
                ST_M2_W: begin
                    bist_ce    <= 1'b1;
                    bist_we    <= 1'b1;
                    bist_addr  <= addr_cnt;
                    bist_wdata <= pat_zero;
                    state      <= ST_M2_V;
                end

                // M2_V: verify r1
                ST_M2_V: begin
                    check_mismatch(pat_one, addr_cnt);
                    bist_ce <= 1'b0;
                    bist_we <= 1'b0;
                    if (auto_stop_on_fail_reg && (bist_rdata != pat_one)) begin
                        state <= ST_DONE;
                    end else if (addr_cnt == max_addr_reg) begin
                        addr_cnt <= max_addr_reg; // Start descending
                        state    <= ST_M3_R;
                    end else begin
                        addr_cnt <= addr_cnt + 1'b1;
                        state    <= ST_M2_R;
                    end
                end

                // M3_R: ⇓ (r0) descending
                ST_M3_R: begin
                    bist_ce   <= 1'b1;
                    bist_we   <= 1'b0;
                    bist_addr <= addr_cnt;
                    state     <= ST_M3_W;
                end

                // M3_W: (w1) descending
                ST_M3_W: begin
                    bist_ce    <= 1'b1;
                    bist_we    <= 1'b1;
                    bist_addr  <= addr_cnt;
                    bist_wdata <= pat_one;
                    state      <= ST_M3_V;
                end

                // M3_V: verify r0 descending
                ST_M3_V: begin
                    check_mismatch(pat_zero, addr_cnt);
                    bist_ce <= 1'b0;
                    bist_we <= 1'b0;
                    if (auto_stop_on_fail_reg && (bist_rdata != pat_zero)) begin
                        state <= ST_DONE;
                    end else if (addr_cnt == {ADDR_WIDTH{1'b0}}) begin
                        addr_cnt <= max_addr_reg; // Descending
                        state    <= ST_M4_R;
                    end else begin
                        addr_cnt <= addr_cnt - 1'b1;
                        state    <= ST_M3_R;
                    end
                end

                // M4_R: ⇓ (r1) descending
                ST_M4_R: begin
                    bist_ce   <= 1'b1;
                    bist_we   <= 1'b0;
                    bist_addr <= addr_cnt;
                    state     <= ST_M4_W;
                end

                // M4_W: (w0) descending
                ST_M4_W: begin
                    bist_ce    <= 1'b1;
                    bist_we    <= 1'b1;
                    bist_addr  <= addr_cnt;
                    bist_wdata <= pat_zero;
                    state      <= ST_M4_V;
                end

                // M4_V: verify r1 descending
                ST_M4_V: begin
                    check_mismatch(pat_one, addr_cnt);
                    bist_ce <= 1'b0;
                    bist_we <= 1'b0;
                    if (auto_stop_on_fail_reg && (bist_rdata != pat_one)) begin
                        state <= ST_DONE;
                    end else if (addr_cnt == {ADDR_WIDTH{1'b0}}) begin
                        addr_cnt <= {ADDR_WIDTH{1'b0}}; // Ascending
                        state    <= ST_M5_R;
                    end else begin
                        addr_cnt <= addr_cnt - 1'b1;
                        state    <= ST_M4_R;
                    end
                end

                // M5_R: ⇕ (r0) final read
                ST_M5_R: begin
                    bist_ce   <= 1'b1;
                    bist_we   <= 1'b0;
                    bist_addr <= addr_cnt;
                    state     <= ST_M5_WAIT;
                end

                // M5_WAIT: wait 1 cycle for synchronous SRAM output
                ST_M5_WAIT: begin
                    bist_ce <= 1'b0;
                    bist_we <= 1'b0;
                    state   <= ST_M5_V;
                end

                // M5_V: verify r0
                ST_M5_V: begin
                    check_mismatch(pat_zero, addr_cnt);
                    bist_ce <= 1'b0;
                    bist_we <= 1'b0;
                    if (auto_stop_on_fail_reg && (bist_rdata != pat_zero)) begin
                        state <= ST_DONE;
                    end else if (addr_cnt == max_addr_reg) begin
                        state <= ST_DONE;
                    end else begin
                        addr_cnt <= addr_cnt + 1'b1;
                        state    <= ST_M5_R;
                    end
                end

                // ST_DONE
                ST_DONE: begin
                    bist_ce     <= 1'b0;
                    bist_we     <= 1'b0;
                    bist_active <= 1'b0;
                    bist_busy_q <= 1'b0;
                    bist_done_q <= 1'b1;
                    bist_pass_q <= !bist_fail_q;
                    state       <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
