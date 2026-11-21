// SPDX-License-Identifier: Apache-2.0
// SMVDU-TitanX SoC — RV64IMC Core Top (retirement spine)
//
// Phase 5 rebuild: classic five-stage in-order pipeline assembled from this
// repo's own stage modules:
//
//   rv_fetch -> rv_decode -> rv_execute -> rv_mem -> rv_writeback
//
// with a complete forwarding network (EX pass-through / MEM / WB) back to
// both operand read stations, and the writeback feedback into the register
// file finally live (the old top tied wb_we=0 — nothing ever retired).
//
// Vertical bring-up scope (Step 5.1):
//  - rv_fetch and rv_mem drive the AXI master ports directly with
//    single-beat transactions. icache/dcache/MMU/PMP/FPU/BPU return BEHIND
//    these same ports once the spine is compliance-green; caches must then
//    prove transparent equivalence.
//  - exception is tied 0 and exception_target 0 until the CSR/trap unit
//    provides mtvec.
//  - snoop_* outputs idle until the dcache returns.
`timescale 1ns/1ps
`include "params.vh"
`include "isa_pkg.vh"

module rv_core_top #(
    parameter HART_ID  = 0,
    parameter RESET_PC = `RESET_PC,
    parameter ENABLE_L1_CACHE = 0,
    parameter [63:0] FDT_ADDR = 64'h0000_0000_8002_0000
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        irq_m_ext,   // External IRQ
    input  wire        irq_m_timer, // Timer IRQ
    input  wire        irq_m_soft,  // Software IRQ

    // AXI4 Master: Instruction Fetch (single-beat until icache returns)
    output wire        imem_arvalid,
    input  wire        imem_arready,
    output wire [39:0] imem_araddr,
    output wire [7:0]  imem_arlen,
    output wire [2:0]  imem_arsize,
    output wire [1:0]  imem_arburst,
    input  wire        imem_rvalid,
    output wire        imem_rready,
    input  wire [63:0] imem_rdata,
    input  wire        imem_rlast,
    input  wire [1:0]  imem_rresp,

    // AXI4 Master: Data Access (single-beat until dcache returns)
    output wire        dmem_awvalid,
    input  wire        dmem_awready,
    output wire [39:0] dmem_awaddr,
    output wire [7:0]  dmem_awlen,
    output wire [2:0]  dmem_awsize,
    output wire [1:0]  dmem_awburst,
    output wire        dmem_wvalid,
    input  wire        dmem_wready,
    output wire [63:0] dmem_wdata,
    output wire [7:0]  dmem_wstrb,
    output wire        dmem_wlast,
    input  wire        dmem_bvalid,
    output wire        dmem_bready,
    input  wire [1:0]  dmem_bresp,

    output wire        dmem_arvalid,
    input  wire        dmem_arready,
    output wire [39:0] dmem_araddr,
    output wire [7:0]  dmem_arlen,
    output wire [2:0]  dmem_arsize,
    output wire [1:0]  dmem_arburst,
    output wire        dmem_arlock,
    input  wire        dmem_rvalid,
    output wire        dmem_rready,
    input  wire [63:0] dmem_rdata,
    input  wire        dmem_rlast,
    input  wire [1:0]  dmem_rresp,

    // AXI4 Master: Sv39 Page Table Walker (PTW)
    output wire        ptw_arvalid,
    input  wire        ptw_arready,
    output wire [39:0] ptw_araddr,
    input  wire        ptw_rvalid,
    output wire        ptw_rready,
    input  wire [63:0] ptw_rdata,
    input  wire [1:0]  ptw_rresp,

    // L2 Snoop Port (idle until dcache returns)
    input  wire        snoop_valid,
    input  wire [39:0] snoop_addr,
    input  wire [1:0]  snoop_type,
    output wire        snoop_ack,
    output wire        snoop_data_valid,
    output wire [511:0] snoop_data,

    // Debug control
    input  wire        halt_req,
    input  wire        resume_req,
    output wire        hart_halted,
    output wire        hart_running
);

    // -------------------------------------------------------
    // Pipeline control
    // -------------------------------------------------------
    wire        stall;
    wire        branch_taken;
    wire [63:0] branch_target;
    wire        ex_trap_taken;
    wire [63:0] ex_trap_pc, ex_trap_cause, ex_trap_tval, ex_mtvec, ex_mepc;
    wire        mem_fault;
    wire [63:0] mem_fault_pc, mem_fault_cause, mem_fault_tval;
    wire        exception = ex_trap_taken || mem_fault;

    wire flush_raw = branch_taken || exception;
    // Manual buffering of the decode-side flush (high-fanout net)
    wire flush_de_1, flush_de_4;
    BUFX4 u_buf_flush1 ( .A(flush_raw), .Y(flush_de_1) );
    BUFX4 u_buf_flush4 ( .A(flush_raw), .Y(flush_de_4) );

    // -------------------------------------------------------
    // Fetch Stage & L1 I-Cache Datapath
    // -------------------------------------------------------
    wire [63:0] fe_pc, fe_imem_addr;
    wire [31:0] fe_instr;
    wire        fe_valid;
    wire        fe_rready;
    wire        fe_fault;
    wire [63:0] fe_fault_cause, fe_fault_tval;

    wire        fe_imem_arvalid;
    wire        fe_imem_arready;
    wire [31:0] fe_imem_rdata;
    wire        fe_imem_rvalid;
    wire [1:0]  fe_imem_rresp;

    rv_fetch #(
        .RESET_PC     (RESET_PC),
        .ENABLE_RVC   (1),
        .ENABLE_DRAIN (!ENABLE_L1_CACHE)
    ) u_fetch (
        .clk             (clk),
        .rst_n           (rst_n),
        .stall           (stall),
        .flush           (exception),          // branches redirect via branch_taken
        .branch_taken    (branch_taken),
        .branch_target   (branch_target),
        .imem_addr       (fe_imem_addr),
        .imem_arvalid    (fe_imem_arvalid),
        .imem_arready    (fe_imem_arready),
        .imem_rdata      (fe_imem_rdata),
        .imem_rvalid     (fe_imem_rvalid),
        .imem_rready     (fe_rready),
        .imem_rresp      (fe_imem_rresp),
        .pc_out          (fe_pc),
        .instr_out       (fe_instr),
        .valid_out       (fe_valid),
        .fault_out       (fe_fault),
        .fault_cause_out (fe_fault_cause),
        .fault_tval_out  (fe_fault_tval)
    );

    // Instantiate I-side MMU
    wire [39:0] fe_pa;
    wire        fe_trans_valid, fe_trans_busy;
    wire        fe_mmu_page_fault;
    wire [63:0] fe_mmu_fault_va;
    wire        ptw_imem_arvalid, ptw_imem_arready;
    wire [39:0] ptw_imem_araddr;
    wire        ptw_imem_rvalid,  ptw_imem_rready;
    wire [63:0] ptw_imem_rdata;
    wire [1:0]  ptw_imem_rresp;
    
    wire        ex_sfence_vma;
    wire        ex_sfence_asid_en;
    wire        ex_sfence_va_en;
    wire [63:0] ex_sfence_va_val;
    wire [63:0] ex_sfence_asid_val;

    rv_mmu u_mmu_fetch (
        .clk(clk), .rst_n(rst_n),
        .satp(ex_satp), .priv_mode(ex_priv_mode),
        .va_req(fe_imem_addr),
        .req_valid(fe_imem_arvalid),
        .req_r(1'b0), .req_w(1'b0), .req_x(1'b1),
        .pa_out(fe_pa), .trans_valid(fe_trans_valid), .trans_busy(fe_trans_busy),
        .page_fault(fe_mmu_page_fault), .fault_va(fe_mmu_fault_va),
        .ptw_arvalid(ptw_imem_arvalid), .ptw_arready(ptw_imem_arready), .ptw_araddr(ptw_imem_araddr),
        .ptw_rvalid(ptw_imem_rvalid), .ptw_rready(ptw_imem_rready), .ptw_rdata(ptw_imem_rdata),
        .ptw_rresp(ptw_imem_rresp),
        .sfence_vma(ex_sfence_vma), .sfence_asid_en(ex_sfence_asid_en), .sfence_va_en(ex_sfence_va_en), 
        .sfence_va_val(ex_sfence_va_val), .sfence_asid_val(ex_sfence_asid_val)
    );

    // L1 I-Cache & Burst-to-Lite Shim
    wire [31:0] icache_cpu_rdata;
    wire        icache_cpu_valid;
    wire        icache_cpu_stall;

    reg ic_pending_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ic_pending_r <= 1'b0;
        else if (exception || branch_taken)
            ic_pending_r <= 1'b0;
        else if (fe_imem_arvalid && fe_imem_arready)
            ic_pending_r <= 1'b1;
        else if (fe_imem_rvalid && fe_rready)
            ic_pending_r <= 1'b0;
    end

    wire icache_req = (fe_imem_arvalid || ic_pending_r);

    wire        ic_out_arvalid, ic_out_arready;
    wire [39:0] ic_out_araddr;
    wire [7:0]  ic_out_arlen;
    wire [2:0]  ic_out_arsize;
    wire [1:0]  ic_out_arburst;
    wire        ic_out_rvalid, ic_out_rready, ic_out_rlast;
    wire [63:0] ic_out_rdata;
    wire [1:0]  ic_out_rresp;

    generate
        if (ENABLE_L1_CACHE) begin : gen_icache
            wire        ic_b2l_arvalid, ic_b2l_arready;
            wire [39:0] ic_b2l_araddr;
            wire [7:0]  ic_b2l_arlen;
            wire [2:0]  ic_b2l_arsize;
            wire [1:0]  ic_b2l_arburst;
            wire        ic_b2l_rvalid, ic_b2l_rready, ic_b2l_rlast;
            wire [63:0] ic_b2l_rdata;
            wire [1:0]  ic_b2l_rresp;

            rv_icache #(
                .WAYS(`L1I_WAYS),
                .SETS(`L1I_SETS),
                .LINE_BYTES(`L1I_LINE_BYTES),
                .ADDR_W(40),
                .DATA_W(64)
            ) u_icache (
                .clk        (clk),
                .rst_n      (rst_n),
                .cpu_addr   (fe_pa),
                .cpu_req    (icache_req),
                .cpu_rdata  (icache_cpu_rdata),
                .cpu_valid  (icache_cpu_valid),
                .cpu_stall  (icache_cpu_stall),
                .invalidate (1'b0),
                .m_arvalid  (ic_b2l_arvalid),
                .m_arready  (ic_b2l_arready),
                .m_araddr   (ic_b2l_araddr),
                .m_arlen    (ic_b2l_arlen),
                .m_arsize   (ic_b2l_arsize),
                .m_arburst  (ic_b2l_arburst),
                .m_rvalid   (ic_b2l_rvalid),
                .m_rready   (ic_b2l_rready),
                .m_rdata    (ic_b2l_rdata),
                .m_rlast    (ic_b2l_rlast),
                .m_rresp    (ic_b2l_rresp),
                .ecc_1bit   (),
                .ecc_2bit   ()
            );

            axi4_burst_to_lite #(
                .ADDR_W(40),
                .DATA_W(64),
                .MAX_BEATS(8)
            ) u_icache_b2l (
                .clk        (clk),
                .rst_n      (rst_n),
                .s_arvalid  (ic_b2l_arvalid),
                .s_arready  (ic_b2l_arready),
                .s_araddr   (ic_b2l_araddr),
                .s_arlen    (ic_b2l_arlen),
                .s_arsize   (ic_b2l_arsize),
                .s_arburst  (ic_b2l_arburst),
                .s_rvalid   (ic_b2l_rvalid),
                .s_rready   (ic_b2l_rready),
                .s_rdata    (ic_b2l_rdata),
                .s_rlast    (ic_b2l_rlast),
                .s_rresp    (ic_b2l_rresp),
                .s_awvalid  (1'b0),
                .s_awready  (),
                .s_awaddr   (40'h0),
                .s_awlen    (8'h0),
                .s_awsize   (3'h0),
                .s_awburst  (2'h0),
                .s_wvalid   (1'b0),
                .s_wready   (),
                .s_wdata    (64'h0),
                .s_wstrb    (8'h0),
                .s_wlast    (1'b0),
                .s_bvalid   (),
                .s_bready   (1'b1),
                .s_bresp    (),
                .m_arvalid  (ic_out_arvalid),
                .m_arready  (ic_out_arready),
                .m_araddr   (ic_out_araddr),
                .m_arlen    (ic_out_arlen),
                .m_arsize   (ic_out_arsize),
                .m_arburst  (ic_out_arburst),
                .m_rvalid   (ic_out_rvalid),
                .m_rready   (ic_out_rready),
                .m_rdata    (ic_out_rdata),
                .m_rlast    (ic_out_rlast),
                .m_rresp    (ic_out_rresp),
                .m_awvalid  (),
                .m_awready  (1'b0),
                .m_awaddr   (),
                .m_awlen    (),
                .m_awsize   (),
                .m_awburst  (),
                .m_wvalid   (),
                .m_wready   (1'b0),
                .m_wdata    (),
                .m_wstrb    (),
                .m_wlast    (),
                .m_bvalid   (1'b0),
                .m_bready   (),
                .m_bresp    (2'b00)
            );
        end else begin : gen_no_icache
            assign icache_cpu_valid = 1'b0;
            assign icache_cpu_rdata = 32'h0;
            assign icache_cpu_stall = 1'b0;
            assign ic_out_arvalid   = 1'b0;
            assign ic_out_araddr    = 40'h0;
            assign ic_out_arlen     = 8'h0;
            assign ic_out_arsize    = 3'h0;
            assign ic_out_arburst   = 2'h0;
            assign ic_out_rready    = 1'b0;
        end
    endgenerate

    // Mux between I-Cache and Direct Fetch
    assign fe_imem_arready = ENABLE_L1_CACHE ? !icache_cpu_stall : imem_arready;
    assign fe_imem_rvalid  = ENABLE_L1_CACHE ? icache_cpu_valid : imem_rvalid;
    assign fe_imem_rdata   = ENABLE_L1_CACHE ? icache_cpu_rdata : imem_rdata[31:0];
    assign fe_imem_rresp   = ENABLE_L1_CACHE ? 2'b00 : imem_rresp;

    assign imem_arvalid = ENABLE_L1_CACHE ? ic_out_arvalid : fe_imem_arvalid;
    assign imem_araddr  = ENABLE_L1_CACHE ? ic_out_araddr  : fe_pa;
    assign imem_arlen   = ENABLE_L1_CACHE ? ic_out_arlen   : 8'h0;
    assign imem_arsize  = ENABLE_L1_CACHE ? ic_out_arsize  : 3'd2;
    assign imem_arburst = ENABLE_L1_CACHE ? ic_out_arburst : 2'b00;
    assign ic_out_arready = ENABLE_L1_CACHE ? imem_arready : 1'b0;

    assign imem_rready   = ENABLE_L1_CACHE ? ic_out_rready : fe_rready;
    assign ic_out_rvalid = ENABLE_L1_CACHE ? imem_rvalid   : 1'b0;
    assign ic_out_rdata  = ENABLE_L1_CACHE ? imem_rdata    : 64'h0;
    assign ic_out_rlast  = ENABLE_L1_CACHE ? imem_rlast    : 1'b0;
    assign ic_out_rresp  = ENABLE_L1_CACHE ? imem_rresp    : 2'b00;

    // -------------------------------------------------------
    // Decode Stage
    // -------------------------------------------------------
    wire [63:0] de_pc, de_rs1, de_rs2, de_imm;
    wire [31:0] de_instr;
    wire [4:0]  de_rd, de_rs1a, de_rs2a;
    wire [2:0]  de_f3;
    wire [6:0]  de_f7, de_op;
    wire [4:0]  de_aluop;
    wire        de_memr, de_memw, de_regw, de_branch, de_jal, de_jalr, de_valid;
    // SYSTEM controls (Step 5.4)
    wire        de_iscsr;
    wire [1:0]  de_csrop;
    wire        de_ecall, de_ebreak, de_mret, de_sret;
    wire        de_is_amo;
    wire [4:0]  de_amo_funct5;
    wire        de_illegal;
    wire        de_fault;
    wire [63:0] de_fault_cause, de_fault_tval;

    // Writeback feedback into the register file
    wire [63:0] wb_data;
    wire [4:0]  wb_rd;
    wire        wb_we;

    rv_decode #(
        .HART_ID  ({56'h0, HART_ID[7:0]}),
        .FDT_ADDR (FDT_ADDR)
    ) u_decode (
        .clk          (clk),         .rst_n         (rst_n),
        .stall        (stall),
        .flush        (flush_de_1),
        .pc_in        (fe_pc),       .instr_in      (fe_instr),    .valid_in (fe_valid),
        .fault_in     (fe_fault),    .fault_cause_in(fe_fault_cause), .fault_tval_in(fe_fault_tval),
        .wb_rd        (wb_rd),       .wb_data       (wb_data),     .wb_we    (wb_we),
        .pc_out       (de_pc),       .instr_out     (de_instr),    .rs1_data (de_rs1),      .rs2_data (de_rs2),
        .imm          (de_imm),      .rd            (de_rd),
        .rs1_addr     (de_rs1a),     .rs2_addr      (de_rs2a),
        .funct3       (de_f3),       .funct7        (de_f7),       .opcode   (de_op),
        .alu_op       (de_aluop),    .mem_read      (de_memr),     .mem_write(de_memw),
        .reg_write    (de_regw),     .branch        (de_branch),   .jal      (de_jal),
        .jalr         (de_jalr),
        .is_csr       (de_iscsr),    .csr_op        (de_csrop),
        .is_ecall     (de_ecall),    .is_ebreak     (de_ebreak),   .is_mret  (de_mret),
        .is_sret      (de_sret),
        .is_amo       (de_is_amo),   .amo_funct5    (de_amo_funct5),
        .illegal_instr(de_illegal),
        .fault_out    (de_fault),    .fault_cause_out(de_fault_cause), .fault_tval_out(de_fault_tval),
        .valid_out    (de_valid)
    );

    // -------------------------------------------------------
    // Execute Stage
    // -------------------------------------------------------
    wire [63:0] ex_pc, ex_alures, ex_rs2;
    wire [4:0]  ex_rd;
    wire [2:0]  ex_f3;
    wire [6:0]  ex_op;
    wire        ex_memr, ex_memw, ex_regw, ex_valid;
    wire        ex_is_amo;
    wire [4:0]  ex_amo_funct5;
    wire        mul_div_stall;
    wire        stall_ex;

    // Forwarding network
    wire [63:0] fwd_mem_data, fwd_wb_data;
    wire [4:0]  fwd_mem_rd, fwd_wb_rd;
    wire        fwd_mem_valid, fwd_wb_valid;

    rv_execute #(
        .HART_ID(HART_ID)
    ) u_execute (
        .clk          (clk),        .rst_n        (rst_n),
        .stall        (stall_ex),   .flush        (flush_de_4),
        .pc_in        (de_pc),      .rs1_data     (de_rs1),    .rs2_data    (de_rs2),
        .imm          (de_imm),     .rd_in        (de_rd),
        .rs1_addr     (de_rs1a),    .rs2_addr     (de_rs2a),
        .funct3       (de_f3),      .funct7       (de_f7),     .opcode      (de_op),
        .alu_op       (de_aluop),   .mem_read     (de_memr),   .mem_write   (de_memw),
        .reg_write    (de_regw),    .branch       (de_branch), .jal         (de_jal),
        .jalr         (de_jalr),
        .is_amo       (de_is_amo),  .amo_funct5   (de_amo_funct5),
        .is_csr       (de_iscsr),   .csr_op       (de_csrop),
        .is_ecall     (de_ecall),   .is_ebreak    (de_ebreak),
        .is_mret      (de_mret),
        .is_sret      (de_sret),
        .illegal_in   (de_illegal),
        .instr_in     (de_instr),
        .fe_fault_in  (de_fault),
        .fe_fault_cause_in (de_fault_cause),
        .fe_fault_tval_in  (de_fault_tval),
        .mem_fault_in (mem_fault),
        .mem_fault_cause_in(mem_fault_cause),
        .mem_fault_tval_in (mem_fault_tval),
        .mem_fault_pc_in   (mem_fault_pc),
        .irq_m_ext    (irq_m_ext),  .irq_m_timer  (irq_m_timer),
        .irq_m_soft   (irq_m_soft),
        .valid_in     (de_valid),
        .fwd_mem_data (fwd_mem_data), .fwd_mem_valid(fwd_mem_valid), .fwd_mem_rd(fwd_mem_rd),
        .fwd_wb_data  (fwd_wb_data),  .fwd_wb_valid (fwd_wb_valid),  .fwd_wb_rd (fwd_wb_rd),
        .fpu_result   (fpu_res),      .fpu_valid    (fpu_vld),      .fpu_done(fpu_done_sig),
        .fpu_fflags   (fpu_flags),    .frm_out      (frm_from_csr), .fp_stall(fp_stall),
        .sfence_vma_pulse(ex_sfence_vma), .sfence_asid_en(ex_sfence_asid_en),
        .sfence_va_en(ex_sfence_va_en), .sfence_va_val(ex_sfence_va_val),
        .sfence_asid_val(ex_sfence_asid_val),
        .pc_out       (ex_pc),
        .alu_result   (ex_alures),  .rs2_out      (ex_rs2),
        .rd_out       (ex_rd),      .funct3_out   (ex_f3),     .opcode_out  (ex_op),
        .mem_read_out (ex_memr),    .mem_write_out(ex_memw),   .reg_write_out(ex_regw),
        .is_amo_out   (ex_is_amo),  .amo_funct5_out(ex_amo_funct5),
        .valid_out    (ex_valid),
        .mul_div_stall(mul_div_stall),
        .branch_taken (branch_taken), .branch_target(branch_target),
        .trap_taken   (ex_trap_taken),
        .trap_pc_out  (ex_trap_pc),
        .trap_cause_out(ex_trap_cause),
        .trap_tval_out(ex_trap_tval),
        .mtvec_out    (ex_mtvec),
        .mepc_out     (ex_mepc),
        .satp_out     (ex_satp),
        .priv_mode_out(ex_priv_mode),
        .lr_addr      (),           .lr_valid     ()
    );
    
    wire [63:0] ex_satp;
    wire [1:0]  ex_priv_mode;

    // -------------------------------------------------------
    // Memory Stage & L1 D-Cache Datapath
    // -------------------------------------------------------
    wire [63:0] mem_result;
    wire [4:0]  mem_rd;
    wire        mem_regw, mem_valid, mem_stall;

    wire        pipe_dmem_awvalid, pipe_dmem_awready;
    wire [39:0] pipe_dmem_awaddr;
    wire        pipe_dmem_wvalid,  pipe_dmem_wready;
    wire [63:0] pipe_dmem_wdata;
    wire [7:0]  pipe_dmem_wstrb;
    wire        pipe_dmem_bvalid,  pipe_dmem_bready;
    wire [1:0]  pipe_dmem_bresp;
    wire        pipe_dmem_arvalid, pipe_dmem_arready;
    wire [39:0] pipe_dmem_araddr;
    wire        pipe_dmem_rvalid,  pipe_dmem_rready;
    wire [63:0] pipe_dmem_rdata;
    wire [1:0]  pipe_dmem_rresp;

    // Instantiate D-side MMU
    wire [39:0] mem_pa;
    wire        mem_trans_valid, mem_trans_busy;
    wire        mem_mmu_page_fault;
    wire [63:0] mem_mmu_fault_va;
    wire        ptw_dmem_arvalid, ptw_dmem_arready;
    wire [39:0] ptw_dmem_araddr;
    wire        ptw_dmem_rvalid,  ptw_dmem_rready;
    wire [63:0] ptw_dmem_rdata;
    wire [1:0]  ptw_dmem_rresp;
    
    rv_mmu u_mmu_mem (
        .clk(clk), .rst_n(rst_n),
        .satp(ex_satp), .priv_mode(ex_priv_mode),
        .va_req(ex_alures),
        .req_valid(ex_valid && (ex_memr || ex_memw)),
        .req_r(ex_memr), .req_w(ex_memw), .req_x(1'b0),
        .pa_out(mem_pa), .trans_valid(mem_trans_valid), .trans_busy(mem_trans_busy),
        .page_fault(mem_mmu_page_fault), .fault_va(mem_mmu_fault_va),
        .ptw_arvalid(ptw_dmem_arvalid), .ptw_arready(ptw_dmem_arready), .ptw_araddr(ptw_dmem_araddr),
        .ptw_rvalid(ptw_dmem_rvalid), .ptw_rready(ptw_dmem_rready), .ptw_rdata(ptw_dmem_rdata),
        .ptw_rresp(ptw_dmem_rresp),
        .sfence_vma(ex_sfence_vma), .sfence_asid_en(ex_sfence_asid_en), .sfence_va_en(ex_sfence_va_en), 
        .sfence_va_val(ex_sfence_va_val), .sfence_asid_val(ex_sfence_asid_val)
    );

    rv_mem u_mem (
        .clk          (clk),
        .rst_n        (rst_n),
        .flush        (1'b0),
        .alu_result   (ex_alures),
        .phys_addr    (mem_pa),
        .mmu_page_fault(mem_mmu_page_fault),
        .mmu_fault_va (mem_mmu_fault_va),
        .rs2_data     (ex_rs2),
        .rd_in        (ex_rd),
        .funct3       (ex_f3),
        .opcode       (ex_op),
        .mem_read     (ex_memr),
        .mem_write    (ex_memw),
        .reg_write    (ex_regw),
        .is_amo       (ex_is_amo),
        .amo_funct5   (ex_amo_funct5),
        .valid_in     (ex_valid),
        .dmem_awvalid (pipe_dmem_awvalid),  .dmem_awready(pipe_dmem_awready),
        .dmem_awaddr  (pipe_dmem_awaddr),
        .dmem_wvalid  (pipe_dmem_wvalid),   .dmem_wready (pipe_dmem_wready),
        .dmem_wdata   (pipe_dmem_wdata),    .dmem_wstrb  (pipe_dmem_wstrb),
        .dmem_bvalid  (pipe_dmem_bvalid),   .dmem_bready (pipe_dmem_bready),
        .dmem_arvalid (pipe_dmem_arvalid),  .dmem_arready(pipe_dmem_arready),
        .dmem_araddr  (pipe_dmem_araddr),
        .dmem_rvalid  (pipe_dmem_rvalid),   .dmem_rready (pipe_dmem_rready),
        .dmem_rdata   (pipe_dmem_rdata),    .dmem_rresp  (pipe_dmem_rresp),
        .pc_in        (ex_pc),
        .dmem_bresp   (pipe_dmem_bresp),
        .result       (mem_result),
        .rd_out       (mem_rd),
        .reg_write_out(mem_regw),
        .valid_out    (mem_valid),
        .fwd_mem_data (fwd_mem_data),
        .fwd_mem_rd   (fwd_mem_rd),
        .fwd_mem_valid(fwd_mem_valid),
        .mem_fault    (mem_fault),
        .mem_fault_pc (mem_fault_pc),
        .mem_fault_cause(mem_fault_cause),
        .mem_fault_tval (mem_fault_tval),
        .mem_stall    (mem_stall)
    );

    function is_mmio_addr;
        input [39:0] a;
        begin
            is_mmio_addr = (a >= 40'h0_0200_0000 && a < 40'h0_0201_0000) ||
                           (a >= 40'h0_0C00_0000 && a < 40'h0_1000_0000) ||
                           (a >= 40'h0_4000_0000 && a < 40'h0_5000_0000);
        end
    endfunction

    reg [39:0] latched_mem_addr;
    reg        latched_is_mmio;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            latched_mem_addr <= 40'h0;
            latched_is_mmio  <= 1'b0;
        end else if (pipe_dmem_arvalid || pipe_dmem_awvalid) begin
            latched_mem_addr <= pipe_dmem_arvalid ? pipe_dmem_araddr : pipe_dmem_awaddr;
            latched_is_mmio  <= is_mmio_addr(pipe_dmem_arvalid ? pipe_dmem_araddr : pipe_dmem_awaddr);
        end
    end

    // MMIO Detection
    wire [39:0] cur_mem_addr = (pipe_dmem_arvalid || pipe_dmem_awvalid) ?
                               (pipe_dmem_arvalid ? pipe_dmem_araddr : pipe_dmem_awaddr) :
                               latched_mem_addr;
    wire is_mmio = (pipe_dmem_arvalid || pipe_dmem_awvalid) ?
                   is_mmio_addr(pipe_dmem_arvalid ? pipe_dmem_araddr : pipe_dmem_awaddr) :
                   latched_is_mmio;

    // L1 D-Cache & Burst-to-Lite Shim
    wire [63:0] dcache_cpu_rdata;
    wire        dcache_cpu_valid;
    wire        dcache_cpu_stall;

    reg dc_rd_pending, dc_wr_pending;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dc_rd_pending <= 1'b0;
            dc_wr_pending <= 1'b0;
        end else begin
            if (pipe_dmem_arvalid && !is_mmio && !dcache_cpu_valid)
                dc_rd_pending <= 1'b1;
            else if (dcache_cpu_valid && !pipe_dmem_awvalid)
                dc_rd_pending <= 1'b0;

            if (pipe_dmem_awvalid && pipe_dmem_wvalid && !is_mmio && !dcache_cpu_valid)
                dc_wr_pending <= 1'b1;
            else if (dcache_cpu_valid && (pipe_dmem_awvalid || dc_wr_pending))
                dc_wr_pending <= 1'b0;
        end
    end

    wire dcache_req = ENABLE_L1_CACHE && !is_mmio &&
                      (pipe_dmem_arvalid || pipe_dmem_awvalid || dc_rd_pending || dc_wr_pending);
    wire dcache_wr  = (pipe_dmem_awvalid || dc_wr_pending);

    wire        dc_snoop_ack;
    wire        dc_snoop_data_valid;
    wire [511:0] dc_snoop_data;
    wire [1:0]  dc_b2l_rresp;
    wire        dc_out_arvalid, dc_out_arready;
    wire [39:0] dc_out_araddr;
    wire [7:0]  dc_out_arlen;
    wire [2:0]  dc_out_arsize;
    wire [1:0]  dc_out_arburst;
    wire        dc_out_rvalid, dc_out_rready, dc_out_rlast;
    wire [63:0] dc_out_rdata;
    wire [1:0]  dc_out_rresp;
    wire        dc_out_awvalid, dc_out_awready;
    wire [39:0] dc_out_awaddr;
    wire [7:0]  dc_out_awlen;
    wire [2:0]  dc_out_awsize;
    wire [1:0]  dc_out_awburst;
    wire        dc_out_wvalid, dc_out_wready, dc_out_wlast;
    wire [63:0] dc_out_wdata;
    wire [7:0]  dc_out_wstrb;
    wire        dc_out_bvalid, dc_out_bready;
    wire [1:0]  dc_out_bresp;

    generate
        if (ENABLE_L1_CACHE) begin : gen_dcache
            wire        dc_b2l_arvalid, dc_b2l_arready;
            wire [39:0] dc_b2l_araddr;
            wire [7:0]  dc_b2l_arlen;
            wire [2:0]  dc_b2l_arsize;
            wire [1:0]  dc_b2l_arburst;
            wire        dc_b2l_rvalid, dc_b2l_rready, dc_b2l_rlast;
            wire [63:0] dc_b2l_rdata;
            wire        dc_b2l_awvalid, dc_b2l_awready;
            wire [39:0] dc_b2l_awaddr;
            wire [7:0]  dc_b2l_awlen;
            wire [2:0]  dc_b2l_awsize;
            wire [1:0]  dc_b2l_awburst;
            wire        dc_b2l_wvalid, dc_b2l_wready, dc_b2l_wlast;
            wire [63:0] dc_b2l_wdata;
            wire [7:0]  dc_b2l_wstrb;
            wire        dc_b2l_bvalid, dc_b2l_bready;
            wire [1:0]  dc_b2l_bresp;

            rv_dcache #(
                .WAYS(`L1D_WAYS),
                .SETS(`L1D_SETS),
                .LINE_BYTES(`L1D_LINE_BYTES),
                .ADDR_W(40),
                .DATA_W(64)
            ) u_dcache (
                .clk              (clk),
                .rst_n            (rst_n),
                .cpu_addr         (cur_mem_addr),
                .cpu_wdata        (pipe_dmem_wdata),
                .cpu_wstrb        (pipe_dmem_wstrb),
                .cpu_req          (dcache_req),
                .cpu_wr           (dcache_wr),
                .cpu_size         (ex_f3),
                .cpu_rdata        (dcache_cpu_rdata),
                .cpu_valid        (dcache_cpu_valid),
                .cpu_stall        (dcache_cpu_stall),
                .is_lr            (1'b0),
                .is_sc            (1'b0),
                .lr_addr_in       (40'h0),
                .lr_valid_in      (1'b0),
                .sc_success       (),
                .flush_all        (1'b0),
                .flush_addr_en    (1'b0),
                .flush_addr       (40'h0),
                .flush_busy       (),
                .m_arvalid        (dc_b2l_arvalid),
                .m_arready        (dc_b2l_arready),
                .m_araddr         (dc_b2l_araddr),
                .m_arlen          (dc_b2l_arlen),
                .m_arsize         (dc_b2l_arsize),
                .m_arburst        (dc_b2l_arburst),
                .m_arlock         (),
                .m_rvalid         (dc_b2l_rvalid),
                .m_rready         (dc_b2l_rready),
                .m_rdata          (dc_b2l_rdata),
                .m_rlast          (dc_b2l_rlast),
                .m_rresp          (dc_b2l_rresp),
                .m_awvalid        (dc_b2l_awvalid),
                .m_awready        (dc_b2l_awready),
                .m_awaddr         (dc_b2l_awaddr),
                .m_awlen          (dc_b2l_awlen),
                .m_awsize         (dc_b2l_awsize),
                .m_awburst        (dc_b2l_awburst),
                .m_wvalid         (dc_b2l_wvalid),
                .m_wready         (dc_b2l_wready),
                .m_wdata          (dc_b2l_wdata),
                .m_wstrb          (dc_b2l_wstrb),
                .m_wlast          (dc_b2l_wlast),
                .m_bvalid         (dc_b2l_bvalid),
                .m_bready         (dc_b2l_bready),
                .m_bresp          (dc_b2l_bresp),
                .snoop_valid      (snoop_valid),
                .snoop_addr       (snoop_addr),
                .snoop_type       (snoop_type),
                .snoop_ack        (dc_snoop_ack),
                .snoop_data_valid (dc_snoop_data_valid),
                .snoop_data       (dc_snoop_data),
                .ecc_1bit         (),
                .ecc_2bit         ()
            );

            axi4_burst_to_lite #(
                .ADDR_W(40),
                .DATA_W(64),
                .MAX_BEATS(8)
            ) u_dcache_b2l (
                .clk        (clk),
                .rst_n      (rst_n),
                .s_arvalid  (dc_b2l_arvalid),
                .s_arready  (dc_b2l_arready),
                .s_araddr   (dc_b2l_araddr),
                .s_arlen    (dc_b2l_arlen),
                .s_arsize   (dc_b2l_arsize),
                .s_arburst  (dc_b2l_arburst),
                .s_rvalid   (dc_b2l_rvalid),
                .s_rready   (dc_b2l_rready),
                .s_rdata    (dc_b2l_rdata),
                .s_rlast    (dc_b2l_rlast),
                .s_rresp    (dc_b2l_rresp),
                .s_awvalid  (dc_b2l_awvalid),
                .s_awready  (dc_b2l_awready),
                .s_awaddr   (dc_b2l_awaddr),
                .s_awlen    (dc_b2l_awlen),
                .s_awsize   (dc_b2l_awsize),
                .s_awburst  (dc_b2l_awburst),
                .s_wvalid   (dc_b2l_wvalid),
                .s_wready   (dc_b2l_wready),
                .s_wdata    (dc_b2l_wdata),
                .s_wstrb    (dc_b2l_wstrb),
                .s_wlast    (dc_b2l_wlast),
                .s_bvalid   (dc_b2l_bvalid),
                .s_bready   (dc_b2l_bready),
                .s_bresp    (dc_b2l_bresp),
                .m_arvalid  (dc_out_arvalid),
                .m_arready  (dc_out_arready),
                .m_araddr   (dc_out_araddr),
                .m_arlen    (dc_out_arlen),
                .m_arsize   (dc_out_arsize),
                .m_arburst  (dc_out_arburst),
                .m_rvalid   (dc_out_rvalid),
                .m_rready   (dc_out_rready),
                .m_rdata    (dc_out_rdata),
                .m_rlast    (dc_out_rlast),
                .m_rresp    (dc_out_rresp),
                .m_awvalid  (dc_out_awvalid),
                .m_awready  (dc_out_awready),
                .m_awaddr   (dc_out_awaddr),
                .m_awlen    (dc_out_awlen),
                .m_awsize   (dc_out_awsize),
                .m_awburst  (dc_out_awburst),
                .m_wvalid   (dc_out_wvalid),
                .m_wready   (dc_out_wready),
                .m_wdata    (dc_out_wdata),
                .m_wstrb    (dc_out_wstrb),
                .m_wlast    (dc_out_wlast),
                .m_bvalid   (dc_out_bvalid),
                .m_bready   (dc_out_bready),
                .m_bresp    (dc_out_bresp)
            );
        end else begin : gen_no_dcache
            assign dcache_cpu_valid    = 1'b0;
            assign dcache_cpu_rdata    = 64'h0;
            assign dcache_cpu_stall    = 1'b0;
            assign dc_snoop_ack        = 1'b0;
            assign dc_snoop_data_valid = 1'b0;
            assign dc_snoop_data       = 512'h0;
            assign dc_b2l_rresp        = 2'b00;
            assign dc_out_arvalid      = 1'b0;
            assign dc_out_araddr       = 40'h0;
            assign dc_out_arlen        = 8'h0;
            assign dc_out_arsize       = 3'h0;
            assign dc_out_arburst      = 2'h0;
            assign dc_out_rready       = 1'b0;
            assign dc_out_awvalid      = 1'b0;
            assign dc_out_awaddr       = 40'h0;
            assign dc_out_awlen        = 8'h0;
            assign dc_out_awsize       = 3'h0;
            assign dc_out_awburst      = 2'h0;
            assign dc_out_wvalid       = 1'b0;
            assign dc_out_wdata        = 64'h0;
            assign dc_out_wstrb        = 8'h0;
            assign dc_out_bready       = 1'b0;
        end
    endgenerate

    // Mux between D-Cache, MMIO Bypass, and Direct Mode
    assign pipe_dmem_awready = !ENABLE_L1_CACHE ? dmem_awready :
                               is_mmio          ? dmem_awready : dcache_cpu_valid;
    assign pipe_dmem_wready  = !ENABLE_L1_CACHE ? dmem_wready  :
                               is_mmio          ? dmem_wready  : dcache_cpu_valid;
    assign pipe_dmem_bvalid  = !ENABLE_L1_CACHE ? dmem_bvalid  :
                               is_mmio          ? dmem_bvalid  : (dcache_cpu_valid && (pipe_dmem_awvalid || dc_wr_pending));
    assign pipe_dmem_bresp   = !ENABLE_L1_CACHE ? dmem_bresp   :
                               is_mmio          ? dmem_bresp   : 2'b00;

    assign pipe_dmem_arready = !ENABLE_L1_CACHE ? dmem_arready :
                               is_mmio          ? dmem_arready : dcache_cpu_valid;
    assign pipe_dmem_rvalid  = !ENABLE_L1_CACHE ? dmem_rvalid  :
                               is_mmio          ? dmem_rvalid  : (dcache_cpu_valid && !pipe_dmem_awvalid && !dc_wr_pending);
    assign pipe_dmem_rdata   = !ENABLE_L1_CACHE ? dmem_rdata   :
                               is_mmio          ? dmem_rdata   : (dcache_cpu_rdata << {cur_mem_addr[2:0], 3'b000});
    assign pipe_dmem_rresp   = !ENABLE_L1_CACHE ? dmem_rresp   :
                               is_mmio          ? dmem_rresp   : dc_b2l_rresp;

    assign dmem_awvalid = !ENABLE_L1_CACHE ? pipe_dmem_awvalid :
                          is_mmio          ? pipe_dmem_awvalid : dc_out_awvalid;
    assign dmem_awaddr  = !ENABLE_L1_CACHE ? pipe_dmem_awaddr  :
                          is_mmio          ? pipe_dmem_awaddr  : dc_out_awaddr;
    assign dmem_awlen   = !ENABLE_L1_CACHE ? 8'h0 :
                          is_mmio          ? 8'h0 : dc_out_awlen;
    assign dmem_awsize  = !ENABLE_L1_CACHE ? 3'b011 :
                          is_mmio          ? 3'b011 : dc_out_awsize;
    assign dmem_awburst = !ENABLE_L1_CACHE ? 2'b00 :
                          is_mmio          ? 2'b00 : dc_out_awburst;

    assign dmem_wvalid  = !ENABLE_L1_CACHE ? pipe_dmem_wvalid :
                          is_mmio          ? pipe_dmem_wvalid : dc_out_wvalid;
    assign dmem_wdata   = !ENABLE_L1_CACHE ? pipe_dmem_wdata  :
                          is_mmio          ? pipe_dmem_wdata  : dc_out_wdata;
    assign dmem_wstrb   = !ENABLE_L1_CACHE ? pipe_dmem_wstrb  :
                          is_mmio          ? pipe_dmem_wstrb  : dc_out_wstrb;
    assign dmem_wlast   = 1'b1;

    assign dmem_bready  = !ENABLE_L1_CACHE ? pipe_dmem_bready :
                          is_mmio          ? pipe_dmem_bready : dc_out_bready;
    assign dc_out_bvalid = (ENABLE_L1_CACHE && !is_mmio) ? dmem_bvalid : 1'b0;
    assign dc_out_bresp  = dmem_bresp;
    assign dc_out_awready= (ENABLE_L1_CACHE && !is_mmio) ? dmem_awready : 1'b0;
    assign dc_out_wready = (ENABLE_L1_CACHE && !is_mmio) ? dmem_wready  : 1'b0;

    assign dmem_arvalid = !ENABLE_L1_CACHE ? pipe_dmem_arvalid :
                          is_mmio          ? pipe_dmem_arvalid : dc_out_arvalid;
    assign dmem_araddr  = !ENABLE_L1_CACHE ? pipe_dmem_araddr  :
                          is_mmio          ? pipe_dmem_araddr  : dc_out_araddr;
    assign dmem_arlen   = !ENABLE_L1_CACHE ? 8'h0 :
                          is_mmio          ? 8'h0 : dc_out_arlen;
    assign dmem_arsize  = !ENABLE_L1_CACHE ? 3'b011 :
                          is_mmio          ? 3'b011 : dc_out_arsize;
    assign dmem_arburst = !ENABLE_L1_CACHE ? 2'b00 :
                          is_mmio          ? 2'b00 : dc_out_arburst;
    assign dmem_arlock  = 1'b0;

    assign dmem_rready  = !ENABLE_L1_CACHE ? pipe_dmem_rready :
                          is_mmio          ? pipe_dmem_rready : dc_out_rready;
    assign dc_out_arready = (ENABLE_L1_CACHE && !is_mmio) ? dmem_arready : 1'b0;
    assign dc_out_rvalid  = (ENABLE_L1_CACHE && !is_mmio) ? dmem_rvalid  : 1'b0;
    assign dc_out_rdata   = dmem_rdata;
    assign dc_out_rlast   = dmem_rlast;
    assign dc_out_rresp   = dmem_rresp;


    // -------------------------------------------------------
    // Floating Point Unit (rv_fpu) & 32x64-bit FP Register File
    // -------------------------------------------------------
    reg [63:0] fp_rf [0:31];
    integer fp_i;
    initial begin
        for (fp_i = 0; fp_i < 32; fp_i = fp_i + 1)
            fp_rf[fp_i] = 64'h0;
    end

    wire [4:0]  fp_rs1_addr = de_rs1a;
    wire [4:0]  fp_rs2_addr = de_rs2a;
    wire [4:0]  fp_rs3_addr = de_instr[31:27];
    wire [63:0] fp_src1     = fp_rf[fp_rs1_addr];
    wire [63:0] fp_src2     = fp_rf[fp_rs2_addr];
    wire [63:0] fp_src3     = fp_rf[fp_rs3_addr];

    wire [63:0] fpu_res;
    wire        fpu_vld;
    wire [4:0]  fpu_flags;
    wire        fpu_done_sig;
    wire [63:0] fpu_int_res;
    wire        fpu_int_vld;
    wire [2:0]  frm_from_csr;
    wire        fp_stall;

    wire is_fp_op = (de_op == `OP_FP)    || (de_op == `OP_FMADD) ||
                    (de_op == `OP_FMSUB)  || (de_op == `OP_FNMSUB) ||
                    (de_op == `OP_FNMADD);

    rv_fpu u_fpu (
        .clk             (clk),
        .rst_n           (rst_n),
        .fop             (de_instr[31:27]),
        .fmt             (de_instr[26:25]),
        .rm              (de_instr[14:12]),
        .valid_in        (de_valid && is_fp_op),
        .fp_src1         (fp_src1),
        .fp_src2         (fp_src2),
        .fp_src3         (fp_src3),
        .int_src         (de_rs1),
        .frm_csr         (frm_from_csr),
        .fp_result       (fpu_res),
        .result_valid    (fpu_vld),
        .fflags          (fpu_flags),
        .fpu_done        (fpu_done_sig),
        .int_result      (fpu_int_res),
        .int_result_valid(fpu_int_vld)
    );

    always @(posedge clk) begin
        if (wb_we && (wb_rd != 5'h0) && (ex_op == `OP_LOAD_FP)) begin
            fp_rf[wb_rd] <= wb_data;
        end else if (fpu_vld && (ex_rd != 5'h0) && is_fp_op && !fpu_int_vld) begin
            fp_rf[ex_rd] <= fpu_res;
        end
    end

    // -------------------------------------------------------
    // Core-level 2-to-1 PTW Arbiter (I-MMU vs D-MMU)
    // -------------------------------------------------------
    reg ptw_active_r;
    reg ptw_grant_d_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ptw_active_r  <= 1'b0;
            ptw_grant_d_r <= 1'b0;
        end else begin
            if (ptw_active_r) begin
                if (ptw_rvalid && ptw_rready)
                    ptw_active_r <= 1'b0;
            end else begin
                if (ptw_dmem_arvalid) begin
                    ptw_grant_d_r <= 1'b1;
                    ptw_active_r  <= 1'b1;
                end else if (ptw_imem_arvalid) begin
                    ptw_grant_d_r <= 1'b0;
                    ptw_active_r  <= 1'b1;
                end
            end
        end
    end

    wire eff_ptw_d = ptw_active_r ? ptw_grant_d_r : ptw_dmem_arvalid;

    assign ptw_arvalid = ptw_active_r ? (ptw_grant_d_r ? ptw_dmem_arvalid : ptw_imem_arvalid) :
                                        (ptw_dmem_arvalid || ptw_imem_arvalid);
    assign ptw_araddr  = eff_ptw_d ? ptw_dmem_araddr : ptw_imem_araddr;

    assign ptw_dmem_arready = eff_ptw_d && ptw_arready;
    assign ptw_imem_arready = !eff_ptw_d && ptw_arready;

    assign ptw_rready      = eff_ptw_d ? ptw_dmem_rready : ptw_imem_rready;
    assign ptw_dmem_rvalid = eff_ptw_d ? ptw_rvalid : 1'b0;
    assign ptw_imem_rvalid = !eff_ptw_d ? ptw_rvalid : 1'b0;
    assign ptw_dmem_rdata  = ptw_rdata;
    assign ptw_imem_rdata  = ptw_rdata;
    assign ptw_dmem_rresp  = ptw_rresp;
    assign ptw_imem_rresp  = ptw_rresp;

    // -------------------------------------------------------
    // Writeback Stage
    // -------------------------------------------------------
    rv_writeback u_wb (
        .clk      (clk),
        .rst_n    (rst_n),
        .result   (mem_result),
        .rd_in    (mem_rd),
        .reg_write(mem_regw),
        .valid_in (mem_valid),
        .wb_data  (wb_data),
        .wb_rd    (wb_rd),
        .wb_we    (wb_we),
        .fwd_wb_data (fwd_wb_data),
        .fwd_wb_rd   (fwd_wb_rd),
        .fwd_wb_valid(fwd_wb_valid)
    );

    // -------------------------------------------------------
    // Hazard / stall / debug
    // -------------------------------------------------------
    assign stall = mul_div_stall || mem_stall || halt_req || fe_trans_busy || mem_trans_busy || fp_stall;
    assign stall_ex = mem_stall || halt_req;

    // Active snoop acknowledgement for L2 snoop filter
    reg snoop_ack_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            snoop_ack_r <= 1'b0;
        else
            snoop_ack_r <= snoop_valid;
    end

    assign snoop_ack        = ENABLE_L1_CACHE ? dc_snoop_ack        : snoop_ack_r;
    assign snoop_data_valid = ENABLE_L1_CACHE ? dc_snoop_data_valid : 1'b0;
    assign snoop_data       = ENABLE_L1_CACHE ? dc_snoop_data       : 512'h0;

    assign hart_halted = halt_req;
    assign hart_running = !halt_req;

`ifndef SYNTHESIS
    integer trace_cnt;
    integer cycle_cnt;
    reg [63:0] pc_hist [0:15];
    reg [31:0] instr_hist [0:15];
    integer h_idx;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            trace_cnt <= 0;
            cycle_cnt <= 0;
            h_idx <= 0;
        end else if (HART_ID == 0) begin
            cycle_cnt <= cycle_cnt + 1;
`ifdef DEBUG_CORE_TRACE
            if (cycle_cnt % 50000 == 0) begin
                $display("[CORE 0 CYC %0d] instr_cnt=%0d dec_pc=0x%016x fe_pc=0x%016x stall=%b",
                         cycle_cnt, trace_cnt, u_decode.pc_in, fe_pc, stall);
            end
`endif
            if (u_decode.valid_in && !stall) begin
                trace_cnt <= trace_cnt + 1;
                pc_hist[h_idx[3:0]] <= u_decode.pc_in;
                instr_hist[h_idx[3:0]] <= u_decode.instr_in;
                h_idx <= h_idx + 1;

                if (u_decode.pc_in == 64'h80000550) begin
                    $display("[HANG DETECTED] Core 0 entered _start_hang at instr #%0d! History:", trace_cnt);
                    for (integer k = 0; k < 16; k = k + 1) begin
                        $display("  hist[%0d]: PC=0x%016x Instr=0x%08x", k,
                                 pc_hist[(h_idx - 15 + k) & 4'hf],
                                 instr_hist[(h_idx - 15 + k) & 4'hf]);
                    end
                    $finish;
                end

                if (u_decode.pc_in == 64'h8000ddbc) begin
                    $display("[SBI_HART_HANG DETECTED] Core 0 entered sbi_hart_hang at instr #%0d! ra=0x%016x a0=0x%016x a1=0x%016x a2=0x%016x",
                             trace_cnt, u_decode.u_rf.mem[1], u_decode.u_rf.mem[10], u_decode.u_rf.mem[11], u_decode.u_rf.mem[12]);
                    for (integer k = 0; k < 16; k = k + 1) begin
                        $display("  hist[%0d]: PC=0x%016x Instr=0x%08x", k,
                                 pc_hist[(h_idx - 15 + k) & 4'hf],
                                 instr_hist[(h_idx - 15 + k) & 4'hf]);
                    end
                    $finish;
                end

`ifdef DEBUG_CORE_TRACE
                if (u_decode.pc_in >= 64'h8000deb0 && u_decode.pc_in <= 64'h8000debc) begin
                    $display("[SWITCH_MODE] PC=0x%016x Instr=0x%08x ra=0x%016x a0=0x%016x a1=0x%016x",
                             u_decode.pc_in, u_decode.instr_in, u_decode.u_rf.mem[1], u_decode.u_rf.mem[10], u_decode.u_rf.mem[11]);
                end

                if (u_decode.pc_in >= 64'h80200000 && u_decode.pc_in <= 64'h80200090) begin
                    $display("[PAYLOAD EXEC] PC=0x%016x Instr=0x%08x a0=0x%016x a1=0x%016x",
                             u_decode.pc_in, u_decode.instr_in, u_decode.u_rf.mem[10], u_decode.u_rf.mem[11]);
                end

                if (trace_cnt % 100000 == 0) begin
                    $display("[CORE 0 EXEC #%0d] PC=0x%016x Instr=0x%08x", trace_cnt, u_decode.pc_in, u_decode.instr_in);
                end
`endif
            end
`ifdef DEBUG_CORE_TRACE
            if (ex_trap_taken) begin
                $display("[CORE 0 TRAP taken] PC=0x%016x cause=0x%016x tval=0x%016x", ex_trap_pc, ex_trap_cause, ex_trap_tval);
            end
`endif
        end
    end
`endif

endmodule
