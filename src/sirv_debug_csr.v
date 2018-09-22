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
    - Replaced flop instantiation with always blocks.
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
//  The module to implement the core's debug control and relevant CSRs
//
// ===========================================================================

module sirv_debug_csr #(
    parameter PC_SIZE = 32
)(

    // The interface with commit stage
  input  [PC_SIZE-1:0] cmt_dpc,
  input  cmt_dpc_ena,

  input  [3-1:0] cmt_dcause,
  input  cmt_dcause_ena,

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

  input  clk,
  input  rst_n
);


// Implement DPC reg
//---->>>>
  reg [PC_SIZE-1:0] dpc_r;
//  wire dpc_ena = wr_dpc_ena | cmt_dpc_ena;
//  wire [PC_SIZE-1:0] dpc_nxt;
//  assign dpc_nxt[PC_SIZE-1:1] =
//       cmt_dpc_ena ? cmt_dpc[PC_SIZE-1:1]
//                   : wr_csr_nxt[PC_SIZE-1:1];
//  assign dpc_nxt[0] = 1'b0;
//  sirv_gnrl_dfflr #(PC_SIZE) dpc_dfflr (dpc_ena, dpc_nxt, dpc_r, clk, rst_n);
  always @(posedge clk or negedge rst_n) begin: p_dpc_r
      if (!rst_n)
          dpc_r <= {PC_SIZE{1'b0}};
      else if (cmt_dpc_ena)
          dpc_r[PC_SIZE-1:1] <= cmt_dpc[PC_SIZE-1:1];
      else if (wr_dpc_ena)
          dpc_r[PC_SIZE-1:1] <= wr_csr_nxt[PC_SIZE-1:1];
  end: p_dpc_r
//<<<<----

// Implement Dbg Scratch reg
//---->>>>
  reg [31:0] dscratch_r;
//  wire dscratch_ena = wr_dscratch_ena;
//  wire [32-1:0] dscratch_nxt;
//  assign dscratch_nxt = wr_csr_nxt;
//  sirv_gnrl_dfflr #(32) dscratch_dfflr (dscratch_ena, dscratch_nxt, dscratch_r, clk, rst_n);
  always @(posedge clk or negedge rst_n) begin: p_dscratch_r
      if (!rst_n)
          dscratch_r <= {32{1'b0}};
      else if (wr_dscratch_ena)
          dscratch_r <= wr_csr_nxt;
  end: p_dscratch_r
//<<<<----

  // We dont support the HW Trigger Module yet now

// Implement dcsr reg
    //
    // The ndreset field
//---->>>>
//  wire ndreset_ena = wr_dcsr_ena & wr_csr_nxt[29];
//  wire ndreset_nxt;
//  wire ndreset_r;
//  assign ndreset_nxt = wr_csr_nxt[29];
//  sirv_gnrl_dfflr #(1) ndreset_dfflr (ndreset_ena, ndreset_nxt, ndreset_r, clk, rst_n);
  reg ndreset_r;
  always @(posedge clk or negedge rst_n) begin: p_ndreset_r
      if (!rst_n)
          ndreset_r <= 1'b0;
      else if (wr_dcsr_ena & wr_csr_nxt[29])
          ndreset_r <= 1'b1;
  end: p_ndreset_r
//<<<<----
  // This bit is not used as rocket impelmentation
    //
    // The fullreset field
//---->>>>
//  wire fullreset_ena = wr_dcsr_ena & wr_csr_nxt[28];
//  wire fullreset_nxt;
//  wire fullreset_r;
//  assign fullreset_nxt = wr_csr_nxt[28];
//  sirv_gnrl_dfflr #(1) fullreset_dfflr (fullreset_ena, fullreset_nxt, fullreset_r, clk, rst_n);
  reg fullreset_r;
  always @(posedge clk or negedge rst_n) begin: p_fullreset_r
      if (!rst_n)
          fullreset_r <= 1'b0;
      else if (wr_dcsr_ena & wr_csr_nxt[28])
          fullreset_r <= 1'b1;
  end: p_fullreset_r
//<<<<----
  // This bit is not used as rocket impelmentation
    //
    // The cause field
//---->>>>
//  wire dcause_ena = cmt_dcause_ena;
//  wire [3-1:0] dcause_r;
//  wire [3-1:0] dcause_nxt = cmt_dcause;
//  sirv_gnrl_dfflr #(3) dcause_dfflr (dcause_ena, dcause_nxt, dcause_r, clk, rst_n);
  reg [2:0] dcause_r;
  always @(posedge clk or negedge rst_n) begin: p_dcause_r
      if (!rst_n)
          dcause_r <= 3'd0;
      else if (cmt_dcause_ena)
          dcause_r <= cmt_dcause;
  end: p_dcause_r
//<<<<----
    //
    // The halt field
//---->>>>
//  wire halt_ena = wr_dcsr_ena;
//  wire halt_nxt;
//  wire halt_r;
//  assign halt_nxt = wr_csr_nxt[3];
//  sirv_gnrl_dfflr #(1) halt_dfflr (halt_ena, halt_nxt, halt_r, clk, rst_n);
  reg halt_r;
  always @(posedge clk or negedge rst_n) begin: p_halt_r
      if (!rst_n)
          halt_r <= 1'b0;
      else if (wr_dcsr_ena)
          halt_r <= wr_csr_nxt[3];
  end: p_halt_r
//<<<<----
    //
    // The step field
//---->>>>
//  wire step_ena = wr_dcsr_ena;
//  wire step_nxt;
//  wire step_r;
//  assign step_nxt = wr_csr_nxt[2];
//  sirv_gnrl_dfflr #(1) step_dfflr (step_ena, step_nxt, step_r, clk, rst_n);
  reg step_r;
  always @(posedge clk or negedge rst_n) begin: p_step_r
      if (!rst_n)
          step_r <= 1'b0;
      else if (wr_dcsr_ena)
          step_r <= wr_csr_nxt[2];
  end: p_step_r
//<<<<----
    //
    // The ebreakm field
//---->>>>
//  wire ebreakm_ena = wr_dcsr_ena;
//  wire ebreakm_nxt;
//  wire ebreakm_r;
//  assign ebreakm_nxt = wr_csr_nxt[15];
//  sirv_gnrl_dfflr #(1) ebreakm_dfflr (ebreakm_ena, ebreakm_nxt, ebreakm_r, clk, rst_n);
  reg ebreakm_r;
  always @(posedge clk or negedge rst_n) begin: p_ebreakm_r
      if (!rst_n)
          ebreakm_r <= 1'b0;
      else if (wr_dcsr_ena)
          ebreakm_r <= wr_csr_nxt[15];
  end: p_ebreakm_r
//<<<<----
    //
  //  // The stopcycle field
  //wire stopcycle_ena = wr_dcsr_ena;
  //wire stopcycle_nxt;
  //wire stopcycle_r;
  //assign stopcycle_nxt = wr_csr_nxt[10];
  //sirv_gnrl_dfflr #(1) stopcycle_dfflr (stopcycle_ena, stopcycle_nxt, stopcycle_r, clk, rst_n);
  //  //
  //  // The stoptime field
  //wire stoptime_ena = wr_dcsr_ena;
  //wire stoptime_nxt;
  //wire stoptime_r;
  //assign stoptime_nxt = wr_csr_nxt[9];
  //sirv_gnrl_dfflr #(1) stoptime_dfflr (stoptime_ena, stoptime_nxt, stoptime_r, clk, rst_n);

  assign dbg_stopcycle = 1'b1;

  assign dcsr_r [31:30] = 2'd1;
  assign dcsr_r [29:16]  = 14'b0;
  assign dcsr_r [15:12]  = {4{ebreakm_r}};// we replicated the ebreakm for all ebreakh/s/u
  assign dcsr_r [11]  = 1'b0;
  assign dcsr_r [10]    = dbg_stopcycle;// Not writeable this bit is constant
  assign dcsr_r [9]     = 1'b0;//stoptime_r; Not use this bit same as rocket implmementation
  assign dcsr_r [8:6]   = dcause_r;
  assign dcsr_r [5]     = dbg_irq_r;
  assign dcsr_r [4]   = 1'b0;
  assign dcsr_r [3]   = halt_r;
  assign dcsr_r [2]   = step_r;
  assign dcsr_r [1:0]   = 2'b11;

  assign dbg_mode = ~(dcause_r == 3'b0);


  assign dbg_halt_r = halt_r;
  assign dbg_step_r = step_r;
  assign dbg_ebreakm_r = ebreakm_r;


endmodule

