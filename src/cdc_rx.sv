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
    - Created from sirv_gnrl_cdc_rx by flattening the module hierarchy
      and reducing the number of aliased signals.
*/

module cdc_rx #(
    parameter int DW = 32,
    parameter int SYNC_DP = 2
) (
    // The 4-phases handshake interface at in-side
    //     There are 4 steps required for a full transaction.
    //         (1) The i_vld is asserted high
    //         (2) The i_rdy is asserted high
    //         (3) The i_vld is asserted low
    //         (4) The i_rdy is asserted low
    input  logic i_vld,
    output logic i_rdy,
    input  logic [DW-1:0] i_dat,

    // The regular handshake interface at out-side
    //     Just the regular handshake o_vld & o_rdy like AXI
    output logic o_vld,
    input  logic o_rdy,
    output logic [DW-1:0] o_dat,

    input  logic clk,
    input  logic rst_n
);

// Sync the async signal first
logic [SYNC_DP:0] sync_vld;
always_ff @(posedge clk or negedge rst_n) begin: p_sync_vld
    if (!rst_n)
        sync_vld <= {SYNC_DP+1{1'b0}};
    else
        sync_vld <= {i_vld,sync_vld[SYNC_DP:1]};
end: p_sync_vld

wire i_vld_sync = sync_vld[1];
wire i_vld_sync_nedge = (~i_vld_sync) & sync_vld[0];

// Input ready
// - set when the buf is empty and incoming valid detected
// - clear when i_vld neg-edge is detected
wire i_rdy_set = ~o_vld & i_vld_sync & ~i_rdy;
always_ff @(posedge clk or negedge rst_n) begin: p_i_rdy
    if (!rst_n)
        i_rdy <= 1'b0;
    else if (i_rdy_set | i_vld_sync_nedge)
        i_rdy <= i_rdy_set | ~i_vld_sync_nedge;
end: p_i_rdy

// The buf is loaded with data when i_rdy is set high (i.e.,
//   when the buf is ready (can save data) and incoming valid detected
always_ff @(posedge clk or negedge rst_n) begin: p_dat_r
    if (!rst_n)
        o_dat <= {DW{1'b0}};
    else if (i_rdy_set)
        o_dat <= i_dat;
end: p_dat_r

// Output valid
// - set when the buf is loaded with data
// - clr when the buf is handshaked at the out-end
wire vld_clr = o_vld & o_rdy;
always_ff @(posedge clk or negedge rst_n) begin: p_o_vld
    if (!rst_n)
        o_vld <= 1'b0;
    else if (i_rdy_set | vld_clr)
        o_vld <= i_rdy_set | ~vld_clr;
end: p_o_vld

endmodule: cdc_rx
