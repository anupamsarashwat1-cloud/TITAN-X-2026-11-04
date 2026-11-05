// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — AXI On-Chip Scratchpad SRAM Self-Checking Testbench
`timescale 1ns/1ps

module tb_axi_sram();

    parameter AW = 40;
    parameter DW = 64;
    parameter IDW = 4;
    parameter DEPTH = 8192;

    reg             clk;
    reg             rst_n;

    // AW Channel
    reg             s_awvalid;
    wire            s_awready;
    reg  [AW-1:0]   s_awaddr;
    reg  [IDW-1:0]  s_awid;

    // W Channel
    reg             s_wvalid;
    wire            s_wready;
    reg  [DW-1:0]   s_wdata;
    reg  [DW/8-1:0] s_wstrb;
    reg             s_wlast;

    // B Channel
    wire            s_bvalid;
    reg             s_bready;
    wire [1:0]      s_bresp;
    wire [IDW-1:0]  s_bid;

    // AR Channel
    reg             s_arvalid;
    wire            s_arready;
    reg  [AW-1:0]   s_araddr;
    reg  [IDW-1:0]  s_arid;

    // R Channel
    wire            s_rvalid;
    reg             s_rready;
    wire [DW-1:0]   s_rdata;
    wire [1:0]      s_rresp;
    wire            s_rlast;
    wire [IDW-1:0]  s_rid;

    integer pass_count = 0;
    integer fail_count = 0;

    // DUT Instantiation
    axi_sram #(
        .DEPTH(DEPTH),
        .AW(AW),
        .DW(DW),
        .IDW(IDW)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .s_awvalid(s_awvalid),
        .s_awready(s_awready),
        .s_awaddr(s_awaddr),
        .s_awid(s_awid),
        .s_wvalid(s_wvalid),
        .s_wready(s_wready),
        .s_wdata(s_wdata),
        .s_wstrb(s_wstrb),
        .s_wlast(s_wlast),
        .s_bvalid(s_bvalid),
        .s_bready(s_bready),
        .s_bresp(s_bresp),
        .s_bid(s_bid),
        .s_arvalid(s_arvalid),
        .s_arready(s_arready),
        .s_araddr(s_araddr),
        .s_arid(s_arid),
        .s_rvalid(s_rvalid),
        .s_rready(s_rready),
        .s_rdata(s_rdata),
        .s_rresp(s_rresp),
        .s_rlast(s_rlast),
        .s_rid(s_rid)
    );

    always #5.0 clk = ~clk;

    task check(input [255:0] test_name, input condition);
        begin
            if (condition) begin
                $display("PASS [%0t] %0s", $time, test_name);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL [%0t] %0s", $time, test_name);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Write transaction task
    task axi_write(
        input [AW-1:0] addr,
        input [DW-1:0] data,
        input [DW/8-1:0] strb,
        input [IDW-1:0] id
    );
        begin
            @(posedge clk);
            s_awaddr  <= addr;
            s_awid    <= id;
            s_awvalid <= 1'b1;
            s_wdata   <= data;
            s_wstrb   <= strb;
            s_wlast   <= 1'b1;
            s_wvalid  <= 1'b1;
            s_bready  <= 1'b1;

            while (!(s_awready && s_awvalid)) @(posedge clk);
            @(posedge clk);
            s_awvalid <= 1'b0;
            s_wvalid  <= 1'b0;
            s_wlast   <= 1'b0;

            while (!s_bvalid) @(posedge clk);
            @(posedge clk);
            s_bready <= 1'b0;
        end
    endtask

    // Read transaction task
    task axi_read(
        input  [AW-1:0]  addr,
        input  [IDW-1:0] id,
        output [DW-1:0]  data,
        output [1:0]     resp,
        output [IDW-1:0] rid
    );
        begin
            @(posedge clk);
            s_araddr  <= addr;
            s_arid    <= id;
            s_arvalid <= 1'b1;
            s_rready  <= 1'b1;

            while (!(s_arready && s_arvalid)) @(posedge clk);
            @(posedge clk);
            s_arvalid <= 1'b0;

            while (!s_rvalid) @(posedge clk);
            data = s_rdata;
            resp = s_rresp;
            rid  = s_rid;
            @(posedge clk);
            s_rready <= 1'b0;
        end
    endtask

    reg [DW-1:0] rd_data;
    reg [1:0]    rd_resp;
    reg [IDW-1:0] rd_id_val;

    initial begin
        clk = 0;
        rst_n = 0;
        s_awvalid = 0; s_awaddr = 0; s_awid = 0;
        s_wvalid = 0; s_wdata = 0; s_wstrb = 0; s_wlast = 0;
        s_bready = 0;
        s_arvalid = 0; s_araddr = 0; s_arid = 0;
        s_rready = 0;

        #25;
        rst_n = 1;
        #15;

        // Test 1: Reset state
        check("TEST 1: Reset asserts ready signals", (s_awready == 1'b1) && (s_wready == 1'b1) && (s_arready == 1'b1));
        check("TEST 2: Reset holds valids low", (s_bvalid == 1'b0) && (s_rvalid == 1'b0));

        // Test 2: Write 64-bit word to address 0x0000_1000
        axi_write(40'h00_0000_1000, 64'h0123_4567_89AB_CDEF, 8'hFF, 4'h3);
        check("TEST 3: Write response OKAY", (uut.s_bresp == 2'b00));
        check("TEST 4: Write response ID matches", (uut.s_bid == 4'h3));

        // Test 3: Read 64-bit word from address 0x0000_1000
        axi_read(40'h00_0000_1000, 4'h5, rd_data, rd_resp, rd_id_val);
        check("TEST 5: Read data matches written value", (rd_data == 64'h0123_4567_89AB_CDEF));
        check("TEST 6: Read response OKAY", (rd_resp == 2'b00));
        check("TEST 7: Read ID forwarded correctly", (rd_id_val == 4'h5));

        // Test 4: Byte-strobed write
        // Write only bytes [3:0] (0xA5A5A5A5) at 0x0000_1008
        axi_write(40'h00_0000_1008, 64'hFFFF_FFFF_A5A5_A5A5, 8'h0F, 4'h1);
        axi_read(40'h00_0000_1008, 4'h1, rd_data, rd_resp, rd_id_val);
        check("TEST 8: Byte-strobed write verified (upper 32 zero, lower 32 A5)", 
              (rd_data == 64'h0000_0000_A5A5_A5A5));

        // Test 5: Back-to-back write and read at address 0x0000_3FF8
        axi_write(40'h00_0000_3FF8, 64'hCAFE_BABE_DEAD_BEEF, 8'hFF, 4'h7);
        axi_read(40'h00_0000_3FF8, 4'h7, rd_data, rd_resp, rd_id_val);
        check("TEST 9: High address boundary read matches", (rd_data == 64'hCAFE_BABE_DEAD_BEEF));

        #20;
        $display("\n==============================");
        if (fail_count == 0 && pass_count >= 9) begin
            $display("AXI_SRAM VERDICT: PASS — All %0d tests green", pass_count);
        end else begin
            $display("AXI_SRAM VERDICT: FAIL — %0d failed, %0d passed", fail_count, pass_count);
        end
        $display("==============================\n");
        $finish;
    end

endmodule
