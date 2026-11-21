// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — RV Fetch Stage with RVC Unit Test
`timescale 1ns/1ps

module tb_rv_fetch_rvc();
    reg        clk, rst_n, stall, flush, branch_taken;
    reg [63:0] branch_target;

    wire [63:0] imem_addr;
    wire        imem_arvalid;
    reg         imem_arready;
    reg [31:0]  imem_rdata;
    reg         imem_rvalid;
    reg [1:0]   imem_rresp;

    wire [63:0] pc_out;
    wire [31:0] instr_out;
    wire        valid_out;

    integer error_count = 0;
    integer instr_count = 0;
    reg [63:0] cap_pc [0:7];
    reg [31:0] cap_instr [0:7];

    rv_fetch #(.RESET_PC(64'h0000_8000_0000), .ENABLE_RVC(1)) uut (
        .clk(clk), .rst_n(rst_n), .stall(stall), .flush(flush),
        .branch_taken(branch_taken), .branch_target(branch_target),
        .imem_addr(imem_addr), .imem_arvalid(imem_arvalid),
        .imem_arready(imem_arready), .imem_rdata(imem_rdata),
        .imem_rvalid(imem_rvalid), .imem_rresp(imem_rresp),
        .pc_out(pc_out), .instr_out(instr_out), .valid_out(valid_out),
        .fault_out(), .fault_cause_out(), .fault_tval_out()
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // Watchdog
    initial begin
        #10000;
        $display("[WATCHDOG TIMEOUT] Simulation hung!");
        $finish;
    end

    // Instruction capture
    always @(posedge clk) begin
        if (rst_n && valid_out) begin
            cap_pc[instr_count] <= pc_out;
            cap_instr[instr_count] <= instr_out;
            instr_count <= instr_count + 1;
            $display("[T=%0t] CAPTURED: pc=0x%016X instr=0x%08X (count=%0d)",
                     $time, pc_out, instr_out, instr_count + 1);
        end
    end

    // Simple autonomous memory slave
    reg [31:0] mem_rom [0:15];
    initial begin
        mem_rom[0] = 32'h4581_0501; // 0x8000_0000: c.nop (0x0501) + c.li a1, 0 (0x4581)
        mem_rom[1] = 32'h0040_0093; // 0x8000_0004: addi x1, x0, 4 (32-bit standard)
        mem_rom[2] = 32'h0000_0013; // 0x8000_0008: nop
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            imem_arready <= 1'b1;
            imem_rvalid  <= 1'b0;
            imem_rdata   <= 32'h0;
            imem_rresp   <= 2'b00;
        end else begin
            if (imem_arvalid && imem_arready) begin
                imem_rvalid <= 1'b1;
                imem_rdata  <= mem_rom[(imem_addr - 64'h8000_0000) >> 2];
                imem_rresp  <= 2'b00;
            end else begin
                imem_rvalid <= 1'b0;
            end
        end
    end

    initial begin
        rst_n = 0; stall = 0; flush = 0; branch_taken = 0; branch_target = 0;
        repeat(5) @(posedge clk);
        rst_n = 1;

        // Wait until 3 instructions are fetched
        wait(instr_count >= 3);
        repeat(2) @(posedge clk);

        // Verify instr 0: compressed nop at 0x8000_0000
        if (cap_pc[0] !== 64'h8000_0000 || cap_instr[0] !== 32'h0000_0501) begin
            $display("FAIL: Instr 0 got pc=0x%08X instr=0x%08X", cap_pc[0], cap_instr[0]);
            error_count = error_count + 1;
        end else begin
            $display("PASS: Instr 0 pc=0x%08X instr=0x%08X", cap_pc[0], cap_instr[0]);
        end

        // Verify instr 1: compressed li at 0x8000_0002
        if (cap_pc[1] !== 64'h8000_0002 || cap_instr[1] !== 32'h0000_4581) begin
            $display("FAIL: Instr 1 got pc=0x%08X instr=0x%08X", cap_pc[1], cap_instr[1]);
            error_count = error_count + 1;
        end else begin
            $display("PASS: Instr 1 pc=0x%08X instr=0x%08X", cap_pc[1], cap_instr[1]);
        end

        // Verify instr 2: 32-bit standard at 0x8000_0004
        if (cap_pc[2] !== 64'h8000_0004 || cap_instr[2] !== 32'h0040_0093) begin
            $display("FAIL: Instr 2 got pc=0x%08X instr=0x%08X", cap_pc[2], cap_instr[2]);
            error_count = error_count + 1;
        end else begin
            $display("PASS: Instr 2 pc=0x%08X instr=0x%08X", cap_pc[2], cap_instr[2]);
        end

        if (error_count == 0)
            $display("\n=== ALL RVC FETCH TESTS PASSED 100% ===");
        else
            $display("\n=== FAILED with %0d errors ===", error_count);
        $finish;
    end
endmodule
