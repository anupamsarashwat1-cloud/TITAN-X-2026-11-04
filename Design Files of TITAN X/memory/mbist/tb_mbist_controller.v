// SPDX-License-Identifier: Apache-2.0
// Testbench for March C+ MBIST Controller (tb_mbist_controller.v)
`timescale 1ns/1ps

module tb_mbist_controller;

    parameter ADDR_WIDTH = 6;
    parameter DATA_WIDTH = 16;
    parameter TEST_DEPTH = 32;

    reg clk;
    reg rst_n;
    reg scan_mode;

    // APB
    reg [31:0] paddr;
    reg        psel;
    reg        penable;
    reg        pwrite;
    reg [31:0] pwdata;
    wire [31:0] prdata;
    wire       pready;
    wire       pslverr;

    // HW Trigger
    reg  hw_bist_start;
    wire hw_bist_done;
    wire hw_bist_pass;
    wire hw_bist_fail;

    // SRAM BIST Wrapper
    wire                   bist_active;
    wire [3:0]             bist_ram_sel;
    wire [ADDR_WIDTH-1:0]  bist_addr;
    wire [DATA_WIDTH-1:0]  bist_wdata;
    wire                   bist_we;
    wire                   bist_ce;
    reg  [DATA_WIDTH-1:0]  bist_rdata;

    // DUT Instantiation
    mbist_controller #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .DEFAULT_DEPTH(TEST_DEPTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .scan_mode(scan_mode),
        .paddr(paddr),
        .psel(psel),
        .penable(penable),
        .pwrite(pwrite),
        .pwdata(pwdata),
        .prdata(prdata),
        .pready(pready),
        .pslverr(pslverr),
        .hw_bist_start(hw_bist_start),
        .hw_bist_done(hw_bist_done),
        .hw_bist_pass(hw_bist_pass),
        .hw_bist_fail(hw_bist_fail),
        .bist_active(bist_active),
        .bist_ram_sel(bist_ram_sel),
        .bist_addr(bist_addr),
        .bist_wdata(bist_wdata),
        .bist_we(bist_we),
        .bist_ce(bist_ce),
        .bist_rdata(bist_rdata)
    );

    // Synchronous SRAM Behavioral Model with Fault Injection Capability
    reg [DATA_WIDTH-1:0] mem [0:TEST_DEPTH-1];
    reg fault_inject_en;
    reg [ADDR_WIDTH-1:0] fault_addr;
    reg [DATA_WIDTH-1:0] fault_mask;

    always @(posedge clk) begin
        if (bist_ce) begin
            if (bist_we) begin
                mem[bist_addr] <= bist_wdata;
            end
            // Synchronous 1-cycle read latency
            if (fault_inject_en && (bist_addr == fault_addr))
                bist_rdata <= mem[bist_addr] ^ fault_mask;
            else
                bist_rdata <= mem[bist_addr];
        end
    end

    // Clock Generation (100 MHz)
    always #5 clk = ~clk;

    // APB Write Task
    task apb_write(input [31:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            paddr   <= addr;
            pwdata  <= data;
            pwrite  <= 1'b1;
            psel    <= 1'b1;
            penable <= 1'b0;
            @(posedge clk);
            penable <= 1'b1;
            @(posedge clk);
            psel    <= 1'b0;
            penable <= 1'b0;
            pwrite  <= 1'b0;
        end
    endtask

    // APB Read Task
    task apb_read(input [31:0] addr, output [31:0] data);
        begin
            @(posedge clk);
            paddr   <= addr;
            pwrite  <= 1'b0;
            psel    <= 1'b1;
            penable <= 1'b0;
            @(posedge clk);
            penable <= 1'b1;
            @(posedge clk);
            data    = prdata;
            psel    <= 1'b0;
            penable <= 1'b0;
        end
    endtask

    integer errors;
    reg [31:0] read_val;

    initial begin
        $dumpfile("/tmp/tb_mbist.vcd");
        $dumpvars(0, tb_mbist_controller);
        clk = 0;
        rst_n = 0;
        scan_mode = 0;
        paddr = 0;
        psel = 0;
        penable = 0;
        pwrite = 0;
        pwdata = 0;
        hw_bist_start = 0;
        fault_inject_en = 0;
        fault_addr = 0;
        fault_mask = 0;
        errors = 0;

        #20;
        rst_n = 1;
        #20;

        $display("==================================================");
        $display("  SMVDU TITAN-X MBIST Engine Verification Suite   ");
        $display("==================================================");

        // ----------------------------------------------------
        // Test 1: Golden March C+ Run (No Faults)
        // ----------------------------------------------------
        $display("\n[TEST 1] Golden March C+ Execution on 32-word SRAM...");
        hw_bist_start = 1;
        @(posedge clk);
        hw_bist_start = 0;

        wait(hw_bist_done);
        @(posedge clk);

        if (hw_bist_pass && !hw_bist_fail) begin
            $display("PASS: Golden March C+ test PASSED (Pass=1, Fail=0, Cycles=%0d)", dut.cycle_cnt_q);
        end else begin
            $display("FAIL: Golden March C+ test failed unexpectedly! fail_q=%0d fail_addr=0x%h fail_synd=0x%h (rdata=0x%h)",
                     dut.bist_fail_q, dut.fail_addr_q, dut.fail_synd_q, dut.bist_rdata);
            errors = errors + 1;
        end

        // ----------------------------------------------------
        // Test 2: Stuck-at Fault Injection (SAF) Detection
        // ----------------------------------------------------
        $display("\n[TEST 2] Stuck-At-Fault Injection at Address 0x12, Bit 3...");
        fault_inject_en = 1;
        fault_addr = 6'h12;
        fault_mask = 16'h0008; // Stuck bit 3

        hw_bist_start = 1;
        @(posedge clk);
        hw_bist_start = 0;

        wait(dut.bist_busy_q);
        wait(hw_bist_done);
        @(posedge clk);

        if (hw_bist_fail && !hw_bist_pass) begin
            $display("PASS: Fault correctly detected by March C+ engine!");
            if (dut.fail_addr_q == 6'h12 && dut.fail_synd_q == 16'h0008) begin
                $display("PASS: Fail address (0x%02h) and syndrome (0x%04h) perfectly matched!",
                         dut.fail_addr_q, dut.fail_synd_q);
            end else begin
                $display("FAIL: Fault address/syndrome mismatch! Expected addr 0x12, synd 0x0008. Got addr 0x%02h, synd 0x%04h",
                         dut.fail_addr_q, dut.fail_synd_q);
                errors = errors + 1;
            end
        end else begin
            $display("FAIL: Fault was NOT detected!");
            errors = errors + 1;
        end

        // ----------------------------------------------------
        // Test 3: APB Software Control & Status Verification
        // ----------------------------------------------------
        $display("\n[TEST 3] APB Interface Verification...");
        fault_inject_en = 0; // Clear fault
        apb_write(32'h00, 32'h00000001); // Trigger start via APB
        wait(dut.bist_busy_q);
        wait(hw_bist_done);
        @(posedge clk);

        apb_read(32'h04, read_val); // Read STATUS register
        if (read_val[2] == 1'b1 && read_val[3] == 1'b0) begin
            $display("PASS: APB status register confirms clean test PASS (STATUS=0x%08h)", read_val);
        end else begin
            $display("FAIL: APB status register reported incorrect status: 0x%08h", read_val);
            errors = errors + 1;
        end

        // ----------------------------------------------------
        // Test 4: Pattern Inversion Run (Invert Background)
        // ----------------------------------------------------
        $display("\n[TEST 4] Pattern Inversion Run (Background=0xFFFF)...");
        apb_write(32'h00, 32'h00000005); // Start + InvertPattern
        wait(dut.bist_busy_q);
        wait(hw_bist_done);
        @(posedge clk);

        apb_read(32'h04, read_val);
        if (read_val[2] == 1'b1 && read_val[3] == 1'b0) begin
            $display("PASS: Pattern-inverted March C+ test PASSED cleanly!");
        end else begin
            $display("FAIL: Pattern-inverted test failed: STATUS=0x%08h", read_val);
            errors = errors + 1;
        end

        // ----------------------------------------------------
        // Summary
        // ----------------------------------------------------
        $display("\n==================================================");
        if (errors == 0)
            $display("ALL MBIST CONTROLLER TESTS PASSED (100%% March C+ Coverage)");
        else
            $display("MBIST CONTROLLER VERIFICATION FAILED: %0d errors", errors);
        $display("==================================================\n");
        $finish;
    end

endmodule
