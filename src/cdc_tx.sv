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
    - Created from sirv_gnrl_cdc_tx by flattening the module hierarchy
      and reducing the number of aliased signals.
*/

module cdc_tx #(
    parameter int DW = 32,
    parameter int SYNC_DP = 2
) (
    // The regular handshake interface at in-side
    //     Just the regular handshake o_vld & o_rdy like AXI
    input  logic i_vld,
    output logic i_rdy,
    input  logic [DW-1:0] i_dat,

    // The 4-phases handshake interface at out-side
    //     There are 4 steps required for a full transaction.
    //         (1) The i_vld is asserted high
    //         (2) The i_rdy is asserted high
    //         (3) The i_vld is asserted low
    //         (4) The i_rdy is asserted low
    output logic o_vld,
    input  logic o_rdy,
    output logic [DW-1:0] o_dat,

    input  logic clk,
    input  logic rst_n
);


// Sync the async signal first
logic[SYNC_DP:0] sync_rdy;
always @(posedge clk or negedge rst_n) begin: p_sync_rdy
    if (!rst_n)
        sync_rdy <= {SYNC_DP+1{1'b0}};
    else
        sync_rdy <= {o_rdy,sync_rdy[SYNC_DP:1]};
end: p_sync_rdy

wire o_rdy_sync = sync_rdy[1];

// Detect the neg-edge
wire o_rdy_nedge = ~o_rdy_sync & sync_rdy[0];

// Data valid
// - set when it is handshaked
// - clr when the TX o_rdy is high
wire vld_set = i_vld & i_rdy;
wire vld_clr = o_vld & o_rdy_sync;
always @(posedge clk or negedge rst_n) begin: p_vld_r
    if (!rst_n)
        o_vld <= 1'b0;
    else if (vld_set | vld_clr)
        o_vld <= vld_set | (~vld_clr);
end: p_vld_r

// The data buf is only loaded when the vld is set
always @(posedge clk or negedge rst_n) begin: p_dat_r
    if (!rst_n)
        o_dat <= {DW{1'b0}};
    else if (vld_set)
        o_dat <= i_dat;
end: p_dat_r

// Not-ready indication
// - set when the o_vld is set
// - clr when the o_rdy neg-edge is detected
logic nrdy_r;
always @(posedge clk or negedge rst_n) begin: p_nrdy_r
    if (!rst_n)
        nrdy_r <= 1'b0;
    else if (vld_set | o_rdy_nedge)
        nrdy_r <= vld_set | (~o_rdy_nedge);
end: p_nrdy_r

// The input is ready when the  Not-ready indication is low or under clearing
assign i_rdy = (~nrdy_r) | o_rdy_nedge;

endmodule: cdc_tx
