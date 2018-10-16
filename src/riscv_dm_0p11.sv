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
    2018, Sep., Tomas Brabec
    - Flattened module hierarchy (by replacing instantiated flops with
      always blocks).
    - Fixed interpretting DTM NOP as a write request.
    - Allowed to use the offset 0x07 of the Debug RAM.
    - Renamed from sirv_debug_module to riscv_dm_0p11 and changed to
      SystemVerilog.
    - Removed Silicon Integrated Micro. logo due to extensive changes
      to the module.
    - Removed Debug CSRs from the Debug Module as they would rather be
      a part of an RISC-V core.
    - Moved JTAG DTM from the module and replaced JTAG ports with DMI
      interface.
*/


/**
* Implements the Debug Module (DM) compliant to RISC-V External Debug Support
* v0.11.
*
* This is a rather minimal implementation with the following features:
*
* - Debug RAM (8x32b), mapped at `0x800`
*
* - Debug ROM, mapped at `0x400`:
*   DROM implementation differs from the one described in RISC-V External Debug
*   Support v0.11, but shall comply with Open OCD implementation of that spec
*   version.
*
* - Debug Module Registers
*   - dmcontrol (Control), at DMI addr `0x10`
*   - dminfo (Info), at DMI addr `0x11`
*   - haltstat (Halt Status), at DMI addr `0x1c`, this register is non-standard
*
* - System Bus Registers
*   - cleardebint (Clear Debug Interrupt), mapped at `0x100`
*   - sethaltnot (Set Halt Notification), mapped at `0x10c`
*
* Known limitations:
*
* - Number of HARTs: The module has been made configurable in the number of
*   HARTs, but the implementation has really been exercised only for a single
*   HART.
*/
module riscv_dm_0p11 #(
    parameter int ASYNC_FF_LEVELS = 2,
    parameter int PC_SIZE = 32,
    parameter int HART_NUM = 1,
    parameter int HART_ID_W = 1
) (
  // The system memory bus interface
  input         i_icb_cmd_valid,
  output        i_icb_cmd_ready,
  input  [11:0] i_icb_cmd_addr,
  input         i_icb_cmd_read,
  input  [31:0] i_icb_cmd_wdata,

  output        i_icb_rsp_valid,
  input         i_icb_rsp_ready,
  output [31:0] i_icb_rsp_rdata,

  // The debug bus interface/DMI (Debug Module Interface)
  input        dtm_req_valid,
  output       dtm_req_ready,
  input [40:0] dtm_req_bits,

  output       dtm_resp_valid,
  input        dtm_resp_ready,
  output[35:0] dtm_resp_bits,

  // To the target hart
  output [HART_NUM-1:0]      o_dbg_irq,
  output [HART_NUM-1:0]      o_ndreset,
  output [HART_NUM-1:0]      o_fullreset,

  input   clk,
  input   rst_n,
  input   test_mode
);


  // synchronized reset
  logic dm_rst_n;

  // reset synchtonizer
  // TODO: There seems to be too many stages. Reduce.
  logic [19:0] sync_dmrst;

  always @(posedge clk or negedge rst_n) begin: p_sync_dmrst
      if (!rst_n) begin
          sync_dmrst <= {20{1'b0}};
      end else begin
          sync_dmrst <= {1'b1,sync_dmrst[19:1]};
      end
  end: p_sync_dmrst

  assign dm_rst_n = test_mode ? rst_n : sync_dmrst[0];

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

     .clk    (clk),
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

     .clk    (clk),
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

  always @(posedge clk or negedge dm_rst_n) begin: p_dm_hartid
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
  always @(posedge clk or negedge dm_rst_n) begin: p_cleardebint
      if (!dm_rst_n)
          cleardebint_r <= {HART_ID_W{1'b0}};
      else if (icb_wr_cleardebint_ena)
          cleardebint_r <= i_icb_cmd_wdata[HART_ID_W-1:0];
  end: p_cleardebint

  reg[HART_ID_W-1:0] sethaltnot_r;
  always @(posedge clk or negedge dm_rst_n) begin: p_sethaltnot
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
    .clk  (clk),
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

      always @(posedge clk or negedge dm_rst_n) begin: p_dm_haltnot
          if (!dm_rst_n)
              dm_haltnot_r[i] <= 1'b0;
          else if (dm_haltnot_set[i] | dm_haltnot_clr[i])
              dm_haltnot_r[i] <= dm_haltnot_set[i] | (~dm_haltnot_clr[i]);
      end: p_dm_haltnot

      // The debug intr will be set by DTM write 1 to interrupt
      assign dm_debint_set[i] = dtm_wr_interrupt_ena & (dm_hartid_r == i[HART_ID_W-1:0]);
      // The debug intr will be clear by system bus set its ID to cleardebint_r
      assign dm_debint_clr[i] = icb_wr_cleardebint_ena & (i_icb_cmd_wdata[HART_ID_W-1:0] == i[HART_ID_W-1:0]);

      always @(posedge clk or negedge dm_rst_n) begin: p_dm_debint
          if (!dm_rst_n)
              dm_debint_r[i] <= 1'b0;
          else if (dm_debint_set[i] | dm_debint_clr[i])
              dm_debint_r[i] <= dm_debint_set[i] | (~dm_debint_clr[i]);
      end: p_dm_debint
    end
  endgenerate

  assign o_dbg_irq = dm_debint_r;

  // TODO: Check if complies to the spec. If so, remove the outputs as unused.
  assign o_ndreset   = {HART_NUM{1'b0}};
  assign o_fullreset = {HART_NUM{1'b0}};

endmodule: riscv_dm_0p11
