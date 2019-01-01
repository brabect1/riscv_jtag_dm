/*
Copyright 2019 Tomas Brabec

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
    2019, Jan., Tomas Brabec
    - Created.
*/


module dut(
    input  logic clk,
    input  logic rst_n,

    input  logic tdi,
    output logic tdo,
    output logic tdo_oe,
    input  logic tck,
    input  logic tms,
    input  logic trstn,

    input  logic quit
);

// finish simulation on `quit` going high
always @(posedge quit) begin
    $display("Simulation indicated to quit ...");
    $finish();
end


logic        dtm_req_valid;
logic        dtm_req_ready;
logic[40:0]  dtm_req_bits;

logic       dtm_resp_valid;
logic       dtm_resp_ready;
logic[35:0] dtm_resp_bits;

riscv_jtag_dtm_0p11 u_jtag_dtm (
//    .tdo( ... ),
    .tdo_oe( ),
    .trst(~trstn),
    .*
);


logic        i_icb_cmd_valid;
logic        i_icb_cmd_ready;
logic [11:0] i_icb_cmd_addr;
logic        i_icb_cmd_read;
logic [31:0] i_icb_cmd_wdata;

logic        i_icb_rsp_valid;
logic        i_icb_rsp_ready;
logic [31:0] i_icb_rsp_rdata;

assign i_icb_cmd_valid = 1'b0;
assign i_icb_cmd_addr = '0;
assign i_icb_cmd_read = 1'b0;
assign i_icb_cmd_wdata = '0;

assign i_icb_rsp_ready = 1'b0;


riscv_dm_0p11 u_dm (
  .o_dbg_irq(),
  .o_ndreset(),
  .o_fullreset(),

  .test_mode( 1'b0 ),

  .*
);

endmodule
