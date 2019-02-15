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
    2019, Feb.
    - Created.
*/


/**
* Implements a fair policy arbiter between two DTMs accessing the same DM.
* The module provides two DBus interfaces (i.e. DTM request/response pairs)
* arbitrated to a single DBus interface (i.e. DM request/response pair).
*
* The expected use case is that from two DTMs only one is used at a time
* to run a RISC-V debug session. Otherwise the fair arbitration policy makes
* little sense.
*/
module dbus_arbiter #(
    // Number of DBus Request data bits
    parameter int DBUS_REQ_BITS = 41,
    // Number of DBus Response data bits
    parameter int DBUS_RSP_BITS = 36
)(
    // Rising edge active clock. All DBus interfaces have CDC synchronizers
    // at inputs so the clock sources may be whichever.
    input  logic clk,

    // Active low reset, asynchronous with synchronized removal.
    input  logic rst_n,

    // --- Port 0 DTM Interface ---
    input  logic                     dtm0_req_req,
    output logic                     dtm0_req_ack,
    input  logic [DBUS_REQ_BITS-1:0] dtm0_req_bits,
    output logic                     dtm0_rsp_req,
    input  logic                     dtm0_rsp_ack,
    output logic [DBUS_RSP_BITS-1:0] dtm0_rsp_bits,

    // --- Port 1 DTM Interface ---
    input  logic                     dtm1_req_req,
    output logic                     dtm1_req_ack,
    input  logic [DBUS_REQ_BITS-1:0] dtm1_req_bits,
    output logic                     dtm1_rsp_req,
    input  logic                     dtm1_rsp_ack,
    output logic [DBUS_RSP_BITS-1:0] dtm1_rsp_bits,

    // --- DM Interface ---
    output logic                     dm_req_req,
    input  logic                     dm_req_ack,
    output logic [DBUS_REQ_BITS-1:0] dm_req_bits,
    input  logic                     dm_rsp_req,
    output logic                     dm_rsp_ack,
    input  logic [DBUS_RSP_BITS-1:0] dm_rsp_bits
);

// ----------------------------------------------
// DTM to DM Request Path
// ----------------------------------------------

// enables accepting requests from DTM0
logic dmt0_req_allow;
// strobe indicating to proceed with processing DTM0 request
logic dtm0_req_accept;
// strobe indicating DTM0 request fall
logic dtm0_req_req_fall;
// makes the internal DTM0 request asserted until DM's acknowledge
logic dtm0_req_pend;
// DTM0 Request synchronizer
logic [1:0] sync_dtm0_req_req;
// internal DTM0 request
logic dtm0_req_req_i;
// flopped version of DTM0 request (for fall detection)
logic dtm0_req_req_d;


// strobe indicating to proceed with processing DTM1 request
logic dtm1_req_accept;
// strobe indicating DTM1 request fall
logic dtm1_req_req_fall;
// makes the internal DTM1 request asserted until DM's acknowledge
logic dtm1_req_pend;
// DTM1 Request synchronizer
logic [1:0] sync_dtm1_req_req;
// internal DTM1 request
logic dtm1_req_req_i;
// flopped version of DTM1 request (for fall detection)
logic dtm1_req_req_d;


logic dm_req_ack_d;
logic [1:0] sync_dm_req_ack;
logic dm_req_clr;

// flopped versions of internal signals (used for fall detection of those signals)
always_ff @(posedge clk or negedge rst_n) begin: p_flopped_sigs
    if (!rst_n) begin
        dtm0_req_req_d <= 1'b0;
        dtm1_req_req_d <= 1'b0;
        dm_req_ack_d   <= 1'b0;
    end
    else begin
        dtm0_req_req_d <= dtm0_req_req_i;
        dtm1_req_req_d <= dtm1_req_req_i;
        dm_req_ack_d   <= sync_dm_req_ack[0];
    end
end: p_flopped_sigs


// DM request data (latches request data bits from a port, request of which
// gets accespted)
always_ff @(posedge clk or negedge rst_n) begin: p_dm_req_bits
    if (!rst_n)
        dm_req_bits <= '0;
    else if (dtm0_req_accept)
        dm_req_bits <= dtm0_req_bits;
    else if (dtm1_req_accept)
        dm_req_bits <= dtm1_req_bits;
end: p_dm_req_bits


// clear DM request after acknowledge from DM (conditioned be asserted
// request for extra safety, but may be omitted if DM follows the handshake
// protocol correctly)
assign dm_req_clr = dm_req_req & sync_dm_req_ack[0];


// DM request indication (set on acception of a request from an either DTM
// port, cleared on DM request acknowledge)
always_ff @(posedge clk or negedge rst_n) begin: p_dm_req_req
    if (!rst_n)
        dm_req_req <= 1'b0;
    else if (dtm0_req_accept | dtm1_req_accept | dm_req_clr)
        dm_req_req <= dtm0_req_accept | dtm1_req_accept | (~dm_req_clr);
end: p_dm_req_req


assign dtm0_req_req_i = sync_dtm0_req_req[0] | dtm0_req_pend;
assign dtm0_req_req_fall = dtm0_req_req_d & ~dtm_req_req_i;
assign dtm0_req_accept = dtm0_req_req_i & ~dtm0_req_ack & dtm0_req_allow;

assign dm_req_ack_fall = dm_req_ack_d & ~sync_dm_req_ack[0];


always_ff @(posedge clk or negedge rst_n) begin: p_dtm0_req_sync
    if (!rst_n) begin
        sync_dtm0_req_req <= '0;
    else 
        sync_dtm0_req_req <= {dtm0_req_req, sync_dtm0_req_req[$high(sync_dtm0_req_req):1]};
end: p_dtm0_req_sync


always_ff @(posedge clk or negedge rst_n) begin: p_dtm0_req_ack
    if (!rst_n) begin
        dtm0_req_ack <= 1'b0;
    end
    else if (dtm0_req_accept | dtm0_req_req_fall) begin
        dtm0_req_ack <= dtm0_req_accept | (~dtm0_req_req_fall);
    end
end: p_dtm0_req_ack


always_ff @(posedge clk or negedge rst_n) begin: p_dtm0_req_pend
    if (!rst_n) begin
        dtm0_req_pend <= 1'b0;
    end
    else if (dtm0_req_accept | dm_req_ack_fall) begin
        dtm0_req_pend <= dtm0_req_accept | (~dm_req_ack_fall);
    end
end: p_dtm0_req_pend


always_ff @(posedge clk or negedge rst_n) begin: p_dm_req_ack_sync
    if (!rst_n) begin
        sync_dm_req_ack <= '0;
    else 
        sync_dm_req_ack <= {dm_req_ack, sync_dm_req_ack[$high(sync_dm_req_ack):1]};
end: p_dm_req_ack_sync



endmodule: dbus_arbiter
