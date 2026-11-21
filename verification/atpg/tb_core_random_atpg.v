// SPDX-License-Identifier: Apache-2.0
// SMVDU TITAN-X — Core-Level Random ATPG Verification Testbench
// Instantiates canonical rv_core_top, executes dynamically synthesized random binaries,
// and extracts full architectural commit traces and register state for differential co-simulation.

`timescale 1ns/1ps
`include "params.vh"
`include "isa_pkg.vh"

module tb_core_random_atpg;

    localparam BASE  = 64'h0000_0000_8000_0000;
    localparam DBASE = 64'h0000_0000_8000_0000;
    localparam IMEM_WORDS = 16384; // 64 KB code space (32-bit words)
    localparam DMEM_WORDS = 8192;  // 64 KB data space (64-bit words)

    reg clk;
    reg rst_n;

    // Clock: 100 MHz (10ns period)
    initial clk = 0;
    always #5 clk = ~clk;

    // Core AXI Interfaces
    wire        imem_arvalid, imem_arready;
    wire [39:0] imem_araddr;
    wire [7:0]  imem_arlen;
    wire [2:0]  imem_arsize;
    wire [1:0]  imem_arburst;
    wire        imem_rvalid, imem_rready;
    wire [63:0] imem_rdata;
    wire        imem_rlast;
    wire [1:0]  imem_rresp;

    wire        dmem_awvalid, dmem_awready;
    wire [39:0] dmem_awaddr;
    wire [7:0]  dmem_awlen;
    wire [2:0]  dmem_awsize;
    wire [1:0]  dmem_awburst;
    wire        dmem_wvalid, dmem_wready;
    wire [63:0] dmem_wdata;
    wire [7:0]  dmem_wstrb;
    wire        dmem_wlast;
    wire        dmem_bvalid, dmem_bready;
    wire [1:0]  dmem_bresp;

    wire        dmem_arvalid, dmem_arready;
    wire [39:0] dmem_araddr;
    wire [7:0]  dmem_arlen;
    wire [2:0]  dmem_arsize;
    wire [1:0]  dmem_arburst;
    wire        dmem_arlock;
    wire        dmem_rvalid, dmem_rready;
    wire [63:0] dmem_rdata;
    wire        dmem_rlast;
    wire [1:0]  dmem_rresp;

    wire        ptw_arvalid, ptw_arready;
    wire [39:0] ptw_araddr;
    wire        ptw_rvalid, ptw_rready;
    wire [63:0] ptw_rdata;
    wire [1:0]  ptw_rresp;

    // ------------------------------------------------------------
    // DUT: rv_core_top with RESET_PC = 0x8000_0000
    // ------------------------------------------------------------
    rv_core_top #(
        .HART_ID(0),
        .RESET_PC(BASE),
        .ENABLE_L1_CACHE(0)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .irq_m_ext(1'b0),
        .irq_m_timer(1'b0),
        .irq_m_soft(1'b0),

        .imem_arvalid(imem_arvalid),
        .imem_arready(imem_arready),
        .imem_araddr(imem_araddr),
        .imem_arlen(imem_arlen),
        .imem_arsize(imem_arsize),
        .imem_arburst(imem_arburst),
        .imem_rvalid(imem_rvalid),
        .imem_rready(imem_rready),
        .imem_rdata(imem_rdata),
        .imem_rlast(imem_rlast),
        .imem_rresp(imem_rresp),

        .dmem_awvalid(dmem_awvalid),
        .dmem_awready(dmem_awready),
        .dmem_awaddr(dmem_awaddr),
        .dmem_awlen(dmem_awlen),
        .dmem_awsize(dmem_awsize),
        .dmem_awburst(dmem_awburst),
        .dmem_wvalid(dmem_wvalid),
        .dmem_wready(dmem_wready),
        .dmem_wdata(dmem_wdata),
        .dmem_wstrb(dmem_wstrb),
        .dmem_wlast(dmem_wlast),
        .dmem_bvalid(dmem_bvalid),
        .dmem_bready(dmem_bready),
        .dmem_bresp(dmem_bresp),

        .dmem_arvalid(dmem_arvalid),
        .dmem_arready(dmem_arready),
        .dmem_araddr(dmem_araddr),
        .dmem_arlen(dmem_arlen),
        .dmem_arsize(dmem_arsize),
        .dmem_arburst(dmem_arburst),
        .dmem_arlock(dmem_arlock),
        .dmem_rvalid(dmem_rvalid),
        .dmem_rready(dmem_rready),
        .dmem_rdata(dmem_rdata),
        .dmem_rlast(dmem_rlast),
        .dmem_rresp(dmem_rresp),

        .ptw_arvalid(ptw_arvalid),
        .ptw_arready(ptw_arready),
        .ptw_araddr(ptw_araddr),
        .ptw_rvalid(ptw_rvalid),
        .ptw_rready(ptw_rready),
        .ptw_rdata(ptw_rdata),
        .ptw_rresp(ptw_rresp),

        .snoop_valid(1'b0),
        .snoop_addr(40'h0),
        .snoop_type(2'b00),
        .snoop_ack(),
        .snoop_data_valid(),
        .snoop_data(),

        .halt_req(1'b0),
        .resume_req(1'b0),
        .hart_halted(),
        .hart_running()
    );

    assign ptw_arready = 1'b1;
    assign ptw_rvalid  = 1'b0;
    assign ptw_rdata   = 64'h0;
    assign ptw_rresp   = 2'b00;

    // ------------------------------------------------------------
    // Instruction Memory AXI-Lite Slave
    // ------------------------------------------------------------
    localparam IS_AR = 1'b0, IS_R = 1'b1;
    reg        is_state;
    reg [63:0] is_addr;
    reg [31:0] imem [0:IMEM_WORDS-1];

    assign imem_arready = (is_state == IS_AR) && rst_n;
    wire [63:0] is_word_ix = (is_addr - BASE) >> 2;
    wire        is_oob = (is_addr < BASE) || (is_word_ix >= IMEM_WORDS);
    wire [31:0] is_word = is_oob ? 32'h00000013 : imem[is_word_ix[13:0]];

    assign imem_rdata  = {32'h0, is_word};
    assign imem_rvalid = (is_state == IS_R) && rst_n;
    assign imem_rlast  = 1'b1;
    assign imem_rresp  = is_oob ? 2'b10 : 2'b00;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            is_state <= IS_AR;
            is_addr  <= 64'h0;
        end else begin
            case (is_state)
                IS_AR: if (imem_arvalid && imem_arready) begin
                    is_addr  <= {24'h0, imem_araddr};
                    is_state <= IS_R;
                end
                IS_R: if (imem_rvalid && imem_rready) begin
                    is_state <= IS_AR;
                end
            endcase
        end
    end

    // ------------------------------------------------------------
    // Data Memory AXI-Lite Slave
    // ------------------------------------------------------------
    reg [63:0] dmem [0:DMEM_WORDS-1];
    reg        ds_aw_pend, ds_w_pend, ds_bvalid;
    reg [39:0] ds_aw_addr;
    reg [63:0] ds_w_data;
    reg [7:0]  ds_w_strb;

    assign dmem_awready = !ds_aw_pend;
    assign dmem_wready  = !ds_w_pend;
    assign dmem_bvalid  = ds_bvalid && rst_n;
    assign dmem_bresp   = 2'b00;

    wire [63:0] ds_word_ix = ({24'h0, ds_aw_addr} - DBASE) >> 3;
    wire        ds_oob = (ds_aw_addr < DBASE) || (ds_word_ix >= DMEM_WORDS);

    localparam DS_AR = 1'b0, DS_R = 1'b1;
    reg        ds_rstate;
    reg [39:0] ds_ar_addr;
    assign dmem_arready = (ds_rstate == DS_AR) && rst_n;
    wire [63:0] ds_r_ix = ({24'h0, ds_ar_addr} - DBASE) >> 3;
    wire        ds_r_oob = (ds_ar_addr < DBASE) || (ds_r_ix >= DMEM_WORDS);
    wire [63:0] ds_r_word = ds_r_oob ? 64'h0 : dmem[ds_r_ix[12:0]];
    assign dmem_rvalid = (ds_rstate == DS_R) && rst_n;
    assign dmem_rdata  = ds_r_word;
    assign dmem_rlast  = 1'b1;
    assign dmem_rresp  = ds_r_oob ? 2'b10 : 2'b00;

    integer b;
    reg [63:0] wtmp;
    reg test_completed = 0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ds_aw_pend <= 0; ds_w_pend <= 0; ds_bvalid <= 0;
            ds_aw_addr <= 40'h0; ds_w_data <= 64'h0; ds_w_strb <= 8'h0;
            ds_rstate <= DS_AR; ds_ar_addr <= 40'h0;
        end else begin
            if (!ds_aw_pend && dmem_awvalid && dmem_awready) begin
                ds_aw_addr <= dmem_awaddr;
                ds_aw_pend <= 1'b1;
            end
            if (!ds_w_pend && dmem_wvalid && dmem_wready) begin
                ds_w_data <= dmem_wdata;
                ds_w_strb <= dmem_wstrb;
                ds_w_pend <= 1'b1;
            end
            if (ds_aw_pend && ds_w_pend && !ds_bvalid) begin
                if (!ds_oob) begin
                    wtmp = dmem[ds_word_ix[12:0]];
                    for (b = 0; b < 8; b = b + 1)
                        if (ds_w_strb[b])
                            wtmp[b*8 +: 8] = ds_w_data[b*8 +: 8];
                    dmem[ds_word_ix[12:0]] <= wtmp;

                    // Watch for signature token written anywhere
                    if (ds_w_data == 64'hCAFEBABE_DEADBEEF) begin
                        test_completed <= 1'b1;
                    end
                end
                ds_aw_pend <= 1'b0;
                ds_w_pend  <= 1'b0;
                ds_bvalid  <= 1'b1;
            end
            if (ds_bvalid && dmem_bready)
                ds_bvalid <= 1'b0;
            case (ds_rstate)
                DS_AR: if (dmem_arvalid && dmem_arready) begin
                    ds_ar_addr <= dmem_araddr;
                    ds_rstate  <= DS_R;
                end
                DS_R: if (dmem_rvalid && dmem_rready) begin
                    ds_rstate <= DS_AR;
                end
            endcase
        end
    end

    // ------------------------------------------------------------
    // Architectural Shadow Register File & Retire Monitor
    // ------------------------------------------------------------
    reg [63:0] shadow_rf [0:31];
    integer retire_cnt = 0;
    integer cycle_cnt = 0;
    integer dump_file;
    integer trace_file;
    integer r_idx;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            retire_cnt <= 0;
            for (r_idx = 0; r_idx < 32; r_idx = r_idx + 1)
                shadow_rf[r_idx] <= 64'h0;
        end else begin
            cycle_cnt <= cycle_cnt + 1;
            if (uut.wb_we && (uut.wb_rd != 5'h0)) begin
                shadow_rf[uut.wb_rd] <= uut.wb_data;
                retire_cnt <= retire_cnt + 1;
                if (trace_file) begin
                    $fdisplay(trace_file, "RETIRE: #%0d pc=0x%016h x%0d=0x%016h", 
                             retire_cnt, uut.ex_pc, uut.wb_rd, uut.wb_data);
                end
            end
        end
    end


    // ------------------------------------------------------------
    // Simulation Control & Dumping
    // ------------------------------------------------------------
    initial begin
        $display("==================================================================");
        $display("  SMVDU TITAN-X: Core Random ATPG Architectural Verification");
        $display("==================================================================");

        // Preload memories from hex
        for (r_idx = 0; r_idx < IMEM_WORDS; r_idx = r_idx + 1) imem[r_idx] = 32'h00000013;
        for (r_idx = 0; r_idx < DMEM_WORDS; r_idx = r_idx + 1) dmem[r_idx] = 64'h0;

        $readmemh("tools/atpg/atpg_imem.hex", imem);
        $readmemh("tools/atpg/atpg_dmem.hex", dmem);
        trace_file = $fopen("tools/atpg/rtl_commit.log", "w");

        rst_n = 0;
        repeat (20) @(posedge clk);
        rst_n = 1;
        $display("[RTL ATPG] Core released from reset at 0x%016h...", BASE);

        // Watchdog & Completion Loop
        while (!test_completed && cycle_cnt < 250000) begin
            @(posedge clk);
        end

        if (test_completed) begin
            repeat (25) @(posedge clk); // Allow pipeline to drain
            $display("\n[RTL ATPG SUCCESS] Program completed in %0d cycles (Retire count: %0d)!",
                     cycle_cnt, retire_cnt);

            // Write architectural dump to file
            dump_file = $fopen("tools/atpg/rtl_dump.txt", "w");
            if (dump_file) begin
                $fdisplay(dump_file, "# TITAN-X RTL ARCHITECTURAL DUMP");
                $fdisplay(dump_file, "CYCLES: %0d", cycle_cnt);
                $fdisplay(dump_file, "RETIRES: %0d", retire_cnt);
                for (r_idx = 1; r_idx < 32; r_idx = r_idx + 1) begin
                    $fdisplay(dump_file, "REG x%0d: 0x%016h", r_idx, shadow_rf[r_idx]);
                end
                // Dump all modified/non-zero data memory words
                $fdisplay(dump_file, "# MEMORY SIGNATURE");
                for (r_idx = 0; r_idx < DMEM_WORDS; r_idx = r_idx + 1) begin
                    if (dmem[r_idx] != 64'h0) begin
                        $fdisplay(dump_file, "MEM[0x%08h]: 0x%016h", (r_idx * 8) + 32'h80000000, dmem[r_idx]);
                    end
                end
                $fclose(dump_file);
                $display("[RTL ATPG] Architectural dump successfully written to tools/atpg/rtl_dump.txt");
            end else begin
                $display("[RTL ATPG ERROR] Failed to create rtl_dump.txt!");
            end
        end else begin
            $display("\n[RTL ATPG TIMEOUT] Execution exceeded 250,000 cycles without completion signature!");
            $display("  Last EX PC: 0x%016h, Retired: %0d", uut.ex_pc, retire_cnt);
        end

        if (trace_file) $fclose(trace_file);
        $finish;
    end

endmodule
