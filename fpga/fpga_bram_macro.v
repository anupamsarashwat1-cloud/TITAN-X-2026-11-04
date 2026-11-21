// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — Synthesizable FPGA BRAM Replacement Macros
// Target: Xilinx Vivado (Artix-7, Kintex-7, Zynq, UltraScale+)
// Drop-in pin-compatible replacements for ASIC foundry hard macros
`timescale 1ns/1ps

// ============================================================
// 1. 32x64 BRAM Macro (Drop-in for sram_32x64_180nm)
// Used in L1/L2 Cache tag & status arrays
// ============================================================
module fpga_sram_32x64 (
    input  wire        clk0,
    input  wire        csb0,    // active-low chip select
    input  wire        web0,    // active-low write enable
    input  wire [3:0]  wmask0,  // active-high byte mask
    input  wire [5:0]  addr0,   // 6-bit address (64 locations)
    input  wire [31:0] din0,    // write data
    output reg  [31:0] dout0    // read data
);
    (* ram_style = "block" *) reg [31:0] mem [0:63];

    integer i;
    initial begin
        for (i = 0; i < 64; i = i + 1)
            mem[i] = 32'h0;
    end

    always @(posedge clk0) begin
        if (!csb0) begin
            if (!web0) begin
                if (wmask0[0]) mem[addr0][7:0]   <= din0[7:0];
                if (wmask0[1]) mem[addr0][15:8]  <= din0[15:8];
                if (wmask0[2]) mem[addr0][23:16] <= din0[23:16];
                if (wmask0[3]) mem[addr0][31:24] <= din0[31:24];
            end
            dout0 <= mem[addr0];
        end
    end
endmodule

// ============================================================
// 2. 512KB SRAM Macro (Drop-in for sram_512kx8_180nm)
// Used in On-Chip SRAM / Boot SRAM
// Inferred as Block RAM / UltraRAM in Vivado
// ============================================================
module fpga_sram_512kx8 (
    input  wire         CLK,    // Clock
    input  wire         CEN,    // Chip Enable (Active Low)
    input  wire         WEN,    // Write Enable (Active Low)
    input  wire [18:0]  A,      // Address (19 bits = 512K)
    input  wire [7:0]   D,      // Data In
    output reg  [7:0]   Q       // Data Out
);
    (* ram_style = "block" *) reg [7:0] mem [0:524287];

    always @(posedge CLK) begin
        if (!CEN) begin
            if (!WEN) begin
                mem[A] <= D;
                Q      <= D;
            end else begin
                Q      <= mem[A];
            end
        end
    end
endmodule

// ============================================================
// 3. Dual-Port True Block RAM (Generic Parametric Model)
// ============================================================
module fpga_bram_true_dp #(
    parameter DATA_WIDTH = 64,
    parameter ADDR_WIDTH = 12,
    parameter DEPTH      = 4096
) (
    // Port A
    input  wire                  clka,
    input  wire                  ena,
    input  wire [DATA_WIDTH/8-1:0] wea,
    input  wire [ADDR_WIDTH-1:0] addra,
    input  wire [DATA_WIDTH-1:0] dina,
    output reg  [DATA_WIDTH-1:0] douta,

    // Port B
    input  wire                  clkb,
    input  wire                  enb,
    input  wire [DATA_WIDTH/8-1:0] web,
    input  wire [ADDR_WIDTH-1:0] addrb,
    input  wire [DATA_WIDTH-1:0] dinb,
    output reg  [DATA_WIDTH-1:0] doutb
);
    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] ram [0:DEPTH-1];

    genvar ga;
    generate
        for (ga = 0; ga < DATA_WIDTH/8; ga = ga + 1) begin : gen_byte_wr_a
            always @(posedge clka) begin
                if (ena && wea[ga])
                    ram[addra][ga*8 +: 8] <= dina[ga*8 +: 8];
            end
        end
    endgenerate

    always @(posedge clka) begin
        if (ena)
            douta <= ram[addra];
    end

    genvar gb;
    generate
        for (gb = 0; gb < DATA_WIDTH/8; gb = gb + 1) begin : gen_byte_wr_b
            always @(posedge clkb) begin
                if (enb && web[gb])
                    ram[addrb][gb*8 +: 8] <= dinb[gb*8 +: 8];
            end
        end
    endgenerate

    always @(posedge clkb) begin
        if (enb)
            doutb <= ram[addrb];
    end
endmodule
