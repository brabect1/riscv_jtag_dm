/*
Copyright 2018 Tomas Brabec
Copyright 2017 Silicon Integrated Microelectronics, Inc.
Code origin: https://github.com/SI-RISCV/e200_opensource

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

Change log:
    2018, Sep.
    - Flattened module hierarchy (by replacing instantiated flops with
      always blocks).
    - Fixed interpretting DTM NOP as a write request.
    - Allowed to use the offset 0x07 of the Debug RAM.
*/



//=====================================================================
//--        _______   ___
//--       (   ____/ /__/
//--        \ \     __
//--     ____\ \   / /
//--    /_______\ /_/   MICROELECTRONICS
//--
//=====================================================================
//
// Designer   : Bob Hu
//
// Description:
//  The debug module
//
// ====================================================================

module sirv_debug_module
# (
  parameter SUPPORT_JTAG_DTM = 1,
  parameter ASYNC_FF_LEVELS = 2,
  parameter PC_SIZE = 32,
  parameter HART_NUM = 1,
  parameter HART_ID_W = 1
) (

  output  inspect_jtag_clk,

    // The interface with commit stage
  input   [PC_SIZE-1:0] cmt_dpc,
  input   cmt_dpc_ena,

  input   [3-1:0] cmt_dcause,
  input   cmt_dcause_ena,

  input  dbg_irq_r,

    // The interface with CSR control
  input  wr_dcsr_ena    ,
  input  wr_dpc_ena     ,
  input  wr_dscratch_ena,



  input  [32-1:0] wr_csr_nxt    ,

  output[32-1:0] dcsr_r    ,
  output[PC_SIZE-1:0] dpc_r     ,
  output[32-1:0] dscratch_r,

  output dbg_mode,
  output dbg_halt_r,
  output dbg_step_r,
  output dbg_ebreakm_r,
  output dbg_stopcycle,


  // The system memory bus interface
  input                      i_icb_cmd_valid,
  output                     i_icb_cmd_ready,
  input  [12-1:0]            i_icb_cmd_addr,
  input                      i_icb_cmd_read,
  input  [32-1:0]            i_icb_cmd_wdata,

  output                     i_icb_rsp_valid,
  input                      i_icb_rsp_ready,
  output [32-1:0]            i_icb_rsp_rdata,


  input   io_pads_jtag_TCK_i_ival,
  input   io_pads_jtag_TMS_i_ival,
  input   io_pads_jtag_TDI_i_ival,
  output  io_pads_jtag_TDO_o_oval,
  output  io_pads_jtag_TDO_o_oe,
  input   io_pads_jtag_TRST_n_i_ival,

  // To the target hart
  output [HART_NUM-1:0]      o_dbg_irq,
  output [HART_NUM-1:0]      o_ndreset,
  output [HART_NUM-1:0]      o_fullreset,

  input   core_csr_clk,
  input   hfclk,
  input   corerst,

  input   test_mode
);


  wire dm_rst_n;

  // This is to reset Debug module's logic, the debug module have same clock domain
  // as the main domain, so just use the same reset.
  reg[19:0] sync_dmrst;

  always @(posedge hfclk or posedge corerst) begin: p_sync_dmrst
      if (corerst) begin
          sync_dmrst <= {20{1'b0}};
      end begin
          sync_dmrst <= {1'b1,sync_dmrst[19:1]};
      end
  end: p_sync_dmrst

  assign dm_rst_n = test_mode ? ~corerst : sync_dmrst[0];

  //This is to reset the JTAG_CLK relevant logics, since the chip does not
  //  have the JTAG_RST used really, so we need to use the global chip reset to reset
  //  JTAG relevant logics
  wire jtag_TCK;
  wire jtag_reset;


  reg[2:0] sync_corerst;

  always @(posedge jtag_TCK or posedge corerst) begin: p_sync_corerst
      if (corerst) begin
          sync_corerst <= 3'b111;
      end begin
          sync_corerst <= {1'b0,sync_corerst[2:1]};
      end
  end: p_sync_corerst

  assign jtag_reset = test_mode ? corerst : sync_corerst[0];

  wire dm_clk = hfclk;// Currently Debug Module have same clock domain as core

  wire jtag_TDI;
  wire jtag_TDO;
  wire jtag_TMS;
  wire jtag_TRST;
  wire jtag_DRV_TDO;

  assign jtag_TCK = io_pads_jtag_TCK_i_ival;
  assign jtag_TRST = io_pads_jtag_TRST_n_i_ival;
  assign jtag_TDI = io_pads_jtag_TDI_i_ival;
  assign jtag_TMS = io_pads_jtag_TMS_i_ival;
  assign io_pads_jtag_TDO_o_oe = jtag_DRV_TDO;
  assign io_pads_jtag_TDO_o_oval = jtag_TDO;

  sirv_debug_csr # (
          .PC_SIZE(PC_SIZE)
      ) u_sirv_debug_csr (
    .dbg_stopcycle   (dbg_stopcycle  ),
    .dbg_irq_r       (dbg_irq_r      ),

    .cmt_dpc         (cmt_dpc        ),
    .cmt_dpc_ena     (cmt_dpc_ena    ),
    .cmt_dcause      (cmt_dcause     ),
    .cmt_dcause_ena  (cmt_dcause_ena ),

    .wr_dcsr_ena     (wr_dcsr_ena    ),
    .wr_dpc_ena      (wr_dpc_ena     ),
    .wr_dscratch_ena (wr_dscratch_ena),



    .wr_csr_nxt      (wr_csr_nxt     ),

    .dcsr_r          (dcsr_r         ),
    .dpc_r           (dpc_r          ),
    .dscratch_r      (dscratch_r     ),

    .dbg_mode        (dbg_mode),
    .dbg_halt_r      (dbg_halt_r),
    .dbg_step_r      (dbg_step_r),
    .dbg_ebreakm_r   (dbg_ebreakm_r),

    .clk             (core_csr_clk),
    .rst_n           (dm_rst_n )
  );



  // The debug bus interface
  wire                     dtm_req_valid;
  wire                     dtm_req_ready;
  wire [41-1 :0]           dtm_req_bits;

  wire                     dtm_resp_valid;
  wire                     dtm_resp_ready;
  wire [36-1 : 0]          dtm_resp_bits;

  generate
    if(SUPPORT_JTAG_DTM == 1) begin: jtag_dtm_gen
      sirv_jtag_dtm # (
          .ASYNC_FF_LEVELS(ASYNC_FF_LEVELS)
      ) u_sirv_jtag_dtm (

        .jtag_TDI           (jtag_TDI      ),
        .jtag_TDO           (jtag_TDO      ),
        .jtag_TCK           (jtag_TCK      ),
        .jtag_TMS           (jtag_TMS      ),
        .jtag_TRST          (jtag_reset    ),

        .jtag_DRV_TDO       (jtag_DRV_TDO  ),

        .dtm_req_valid      (dtm_req_valid ),
        .dtm_req_ready      (dtm_req_ready ),
        .dtm_req_bits       (dtm_req_bits  ),

        .dtm_resp_valid     (dtm_resp_valid),
        .dtm_resp_ready     (dtm_resp_ready),
        .dtm_resp_bits      (dtm_resp_bits )
      );
   end
   else begin: no_jtag_dtm_gen
      assign jtag_TDI  = 1'b0;
      assign jtag_TDO  = 1'b0;
      assign jtag_TCK  = 1'b0;
      assign jtag_TMS  = 1'b0;
      assign jtag_DRV_TDO = 1'b0;
      assign dtm_req_valid = 1'b0;
      assign dtm_req_bits = 41'b0;
      assign dtm_resp_ready = 1'b0;
   end
  endgenerate

  wire        i_dtm_req_valid;
  wire        i_dtm_req_ready;
  wire [40:0] i_dtm_req_bits;

  wire        i_dtm_resp_valid;
  wire        i_dtm_resp_ready;
  wire [35:0] i_dtm_resp_bits;

  cdc_tx #(
     .DW      (36),
     .SYNC_DP (ASYNC_FF_LEVELS)
   ) u_cdc_tx (
     .o_vld  (dtm_resp_valid),
     .o_rdy  (dtm_resp_ready),
     .o_dat  (dtm_resp_bits ),
     .i_vld  (i_dtm_resp_valid),
     .i_rdy  (i_dtm_resp_ready),
     .i_dat  (i_dtm_resp_bits ),

     .clk    (dm_clk),
     .rst_n  (dm_rst_n)
   );

   cdc_rx #(
     .DW      (41),
     .SYNC_DP (ASYNC_FF_LEVELS)
   ) u_dm2dtm_cdc_rx (
     .i_vld  (dtm_req_valid),
     .i_rdy  (dtm_req_ready),
     .i_dat  (dtm_req_bits ),
     .o_vld  (i_dtm_req_valid),
     .o_rdy  (i_dtm_req_ready),
     .o_dat  (i_dtm_req_bits ),

     .clk    (dm_clk),
     .rst_n  (dm_rst_n)
   );

  wire i_dtm_req_hsked = i_dtm_req_valid & i_dtm_req_ready;

  wire [ 4:0] dtm_req_bits_addr;
  wire [33:0] dtm_req_bits_data;
  wire [ 1:0] dtm_req_bits_op;

  wire [33:0] dtm_resp_bits_data;
  wire [ 1:0] dtm_resp_bits_resp;

  assign dtm_req_bits_addr = i_dtm_req_bits[40:36];
  assign dtm_req_bits_data = i_dtm_req_bits[35:2];
  assign dtm_req_bits_op   = i_dtm_req_bits[1:0];
  assign i_dtm_resp_bits = {dtm_resp_bits_data, dtm_resp_bits_resp};

  // The OP field
  //   0: Ignore data. (nop)
  //   1: Read from address. (read)
  //   2: Read from address. Then write data to address. (write)
  //   3: Reserved.
  wire dtm_req_rd = (dtm_req_bits_op == 2'd1);
  wire dtm_req_wr = (dtm_req_bits_op == 2'd2);

  // Indicates that the operation represents a valid access to DM's resources.
  // It protects spurious reads or writes when the operation is NOP.
  wire access_valid = dtm_req_rd | dtm_req_wr;

  wire dtm_req_sel_dbgram   = access_valid & (dtm_req_bits_addr[4:3] == 2'b0);
  wire dtm_req_sel_dmcontrl = access_valid & (dtm_req_bits_addr == 5'h10);
  wire dtm_req_sel_dminfo   = access_valid & (dtm_req_bits_addr == 5'h11);
  wire dtm_req_sel_haltstat = access_valid & (dtm_req_bits_addr == 5'h1C);

  wire [33:0] dminfo_r;
  wire [33:0] dmcontrol_r;

  reg [HART_NUM-1:0] dm_haltnot_r;
  reg [HART_NUM-1:0] dm_debint_r;

  //In the future if it is multi-core, then we need to add the core ID, to support this
  //   text from the debug_spec_v0.11
  //   At the cost of more hardware, this can be resolved in two ways. If
  //   the bus knows an ID for the originator, then the Debug Module can refuse write
  //   accesses to originators that don't match the hart ID set in hartid of dmcontrol.
  //

  // The Resp field
  //   0: The previous operation completed successfully.
  //   1: Reserved.
  //   2: The previous operation failed. The data scanned into dbus in this access
  //      will be ignored. This status is sticky and can be cleared by writing dbusreset in dtmcontrol.
  //   3: The previous operation is still in progress. The data scanned into dbus
  //      in this access will be ignored.
  wire [31:0] dram_dout;
  assign dtm_resp_bits_data =
            ({34{dtm_req_sel_dbgram  }} & {dmcontrol_r[33:32],dram_dout})
          | ({34{dtm_req_sel_dmcontrl}} & dmcontrol_r)
          | ({34{dtm_req_sel_dminfo  }} & dminfo_r)
          | ({34{dtm_req_sel_haltstat}} & {{34-HART_ID_W{1'b0}},dm_haltnot_r});

  assign dtm_resp_bits_resp = 2'd0;

  wire icb_access_dbgram_ena;

  wire i_dtm_req_condi = dtm_req_sel_dbgram ? (~icb_access_dbgram_ena) : 1'b1;
  assign i_dtm_req_ready    = i_dtm_req_condi & i_dtm_resp_ready;
  assign i_dtm_resp_valid   = i_dtm_req_condi & i_dtm_req_valid;


  assign dminfo_r[33:16] = 18'b0;
  assign dminfo_r[15:10] = 6'h6;
  assign dminfo_r[9:6]   = 4'b0;
  assign dminfo_r[5]     = 1'h1;
  assign dminfo_r[4:2]   = 3'b0;
  assign dminfo_r[1:0]   = 2'h1;


  reg[HART_ID_W-1:0] dm_hartid_r;

  wire [1:0] dm_debint_arr  = {1'b0,dm_debint_r };
  wire [1:0] dm_haltnot_arr = {1'b0,dm_haltnot_r};
  assign dmcontrol_r[33] = dm_debint_arr [dm_hartid_r];
  assign dmcontrol_r[32] = dm_haltnot_arr[dm_hartid_r];
  assign dmcontrol_r[31:12] = 20'b0;
  assign dmcontrol_r[11:2] = {{10-HART_ID_W{1'b0}},dm_hartid_r};
  assign dmcontrol_r[1:0] = 2'b0;

  wire dtm_wr_dmcontrol = dtm_req_sel_dmcontrl & dtm_req_wr;
  wire dtm_wr_dbgram    = dtm_req_sel_dbgram   & dtm_req_wr;

  wire dtm_wr_interrupt_ena = i_dtm_req_hsked & (dtm_wr_dmcontrol | dtm_wr_dbgram) & dtm_req_bits_data[33];//W1
  wire dtm_wr_haltnot_ena   = i_dtm_req_hsked & (dtm_wr_dmcontrol | dtm_wr_dbgram) & (~dtm_req_bits_data[32]);//W0
  wire dtm_wr_hartid_ena    = i_dtm_req_hsked & dtm_wr_dmcontrol;
  wire dtm_wr_dbgram_ena    = i_dtm_req_hsked & dtm_wr_dbgram;

  wire dtm_access_dbgram_ena    = i_dtm_req_hsked & dtm_req_sel_dbgram;

  always @(posedge dm_clk or negedge dm_rst_n) begin: p_dm_hartid
      if (!dm_rst_n)
          dm_hartid_r <= {HART_ID_W{1'b0}};
      else if (dtm_wr_hartid_ena)
          dm_hartid_r <= dtm_req_bits_data[HART_ID_W+2-1:2];
  end: p_dm_hartid


  //////////////////////////////////////////////////////////////
  // Impelement the DM ICB system bus agent
  //   0x100 - 0x2ff Debug Module registers described in Section 7.12.
  //       * Only two registers needed, others are not supported
  //                  cleardebint, at 0x100
  //                  sethaltnot,  at 0x10c
  //   0x400 - 0x4ff Up to 256 bytes of Debug RAM. Each unique address species 8 bits.
  //       * Since this is remapped to each core's ITCM, we dont handle it at this module
  //   0x800 - 0x9ff Up to 512 bytes of Debug ROM.
  //
  //
  wire i_icb_cmd_hsked = i_icb_cmd_valid & i_icb_cmd_ready;
  wire icb_wr_ena = i_icb_cmd_hsked & (~i_icb_cmd_read);
  wire icb_sel_cleardebint = (i_icb_cmd_addr == 12'h100);
  wire icb_sel_sethaltnot  = (i_icb_cmd_addr == 12'h10c);
  wire icb_sel_dbgrom  = (i_icb_cmd_addr[12-1:8] == 4'h8);
  wire icb_sel_dbgram  = (i_icb_cmd_addr[12-1:8] == 4'h4);


  wire icb_wr_cleardebint_ena = icb_wr_ena & icb_sel_cleardebint;
  wire icb_wr_sethaltnot_ena  = icb_wr_ena & icb_sel_sethaltnot ;

  assign icb_access_dbgram_ena = i_icb_cmd_hsked & icb_sel_dbgram;

  reg[HART_ID_W-1:0] cleardebint_r;
  always @(posedge dm_clk or negedge dm_rst_n) begin: p_cleardebint
      if (!dm_rst_n)
          cleardebint_r <= {HART_ID_W{1'b0}};
      else if (icb_wr_cleardebint_ena)
          cleardebint_r <= i_icb_cmd_wdata[HART_ID_W-1:0];
  end: p_cleardebint

  reg[HART_ID_W-1:0] sethaltnot_r;
  always @(posedge dm_clk or negedge dm_rst_n) begin: p_sethaltnot
      if (!dm_rst_n)
          sethaltnot_r <= {HART_ID_W{1'b0}};
      else if (icb_wr_sethaltnot_ena)
          sethaltnot_r <= i_icb_cmd_wdata[HART_ID_W-1:0];
  end: p_sethaltnot


  assign i_icb_rsp_valid = i_icb_cmd_valid;// Just directly pass back the valid in 0 cycle
  assign i_icb_cmd_ready = i_icb_rsp_ready;

  wire [31:0] rom_dout;

  assign i_icb_rsp_rdata =
            ({32{icb_sel_cleardebint}} & {{32-HART_ID_W{1'b0}}, cleardebint_r})
          | ({32{icb_sel_sethaltnot }} & {{32-HART_ID_W{1'b0}}, sethaltnot_r})
          | ({32{icb_sel_dbgrom  }} & rom_dout)
          | ({32{icb_sel_dbgram  }} & dram_dout);

   sirv_debug_rom u_sirv_debug_rom (
     .rom_addr (i_icb_cmd_addr[7-1:2]),
     .rom_dout (rom_dout)
   );

  wire         dram_cs   = dtm_access_dbgram_ena | icb_access_dbgram_ena;
  wire [ 2:0]  dram_addr = dtm_access_dbgram_ena ? dtm_req_bits_addr[2:0] : i_icb_cmd_addr[4:2];
  wire         dram_we   = dtm_access_dbgram_ena ? dtm_req_wr             : ~i_icb_cmd_read;
  wire [31:0]  dram_din  = dtm_access_dbgram_ena ? dtm_req_bits_data[31:0]: i_icb_cmd_wdata;

  debug_ram u_dram(
    .clk  (dm_clk),
    .en   (dram_cs),
    .we   (dram_we),
    .addr (dram_addr),
    .din  (dram_din),
    .dout (dram_dout)
  );

  wire [HART_NUM-1:0] dm_haltnot_set;
  wire [HART_NUM-1:0] dm_haltnot_clr;

  wire [HART_NUM-1:0] dm_debint_set;
  wire [HART_NUM-1:0] dm_debint_clr;
  wire [HART_NUM-1:0] dm_debint_ena;
  wire [HART_NUM-1:0] dm_debint_nxt;

  genvar i;
  generate
    for(i = 0; i < HART_NUM; i = i+1)
    begin:dm_halt_int_gen

        // The haltnot will be set by system bus set its ID to sethaltnot_r
      assign dm_haltnot_set[i] = icb_wr_sethaltnot_ena & (i_icb_cmd_wdata[HART_ID_W-1:0] == i[HART_ID_W-1:0]);
        // The haltnot will be cleared by DTM write 0 to haltnot
      assign dm_haltnot_clr[i] = dtm_wr_haltnot_ena & (dm_hartid_r == i[HART_ID_W-1:0]);

      always @(posedge dm_clk or negedge dm_rst_n) begin: p_dm_haltnot
          if (!dm_rst_n)
              dm_haltnot_r[i] <= 1'b0;
          else if (dm_haltnot_set[i] | dm_haltnot_clr[i])
              dm_haltnot_r[i] <= dm_haltnot_set[i] | (~dm_haltnot_clr[i]);
      end: p_dm_haltnot

      // The debug intr will be set by DTM write 1 to interrupt
      assign dm_debint_set[i] = dtm_wr_interrupt_ena & (dm_hartid_r == i[HART_ID_W-1:0]);
      // The debug intr will be clear by system bus set its ID to cleardebint_r
      assign dm_debint_clr[i] = icb_wr_cleardebint_ena & (i_icb_cmd_wdata[HART_ID_W-1:0] == i[HART_ID_W-1:0]);

      always @(posedge dm_clk or negedge dm_rst_n) begin: p_dm_debint
          if (!dm_rst_n)
              dm_debint_r[i] <= 1'b0;
          else if (dm_debint_set[i] | dm_debint_clr[i])
              dm_debint_r[i] <= dm_debint_set[i] | (~dm_debint_clr[i]);
      end: p_dm_debint
    end
  endgenerate

  assign o_dbg_irq = dm_debint_r;


  assign o_ndreset   = {HART_NUM{1'b0}};
  assign o_fullreset = {HART_NUM{1'b0}};

  assign inspect_jtag_clk = jtag_TCK;

endmodule
