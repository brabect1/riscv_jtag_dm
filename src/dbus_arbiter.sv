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
*
* All DBus ports implement the four-phase, request--acknowledge protocol. The
* phases are as follows:
*
* - Request asserts (i.e goes high),
* - acknowledge asserts (i.e. goes high),
* - request de-asserts,
* - acknowledge de-asserts.
*
* Acknowledges on the DTM Request ports and the DM Response port are implemented
* so that they de-assert only after the request--acknowledge handshake has been
* fully completed on the other side port. In addition, a DTM Request acknowledge
* de-asserts only after the corresponding DM response completed. A sample waveform
* may look like as follows:
*
*                      ___
*     DTM0 Req. req __|   |______________
*                        ______________
*     DTM0 Req. ack ____|              |_  (DTM Request ack. extends over the complete DM Respense handshake)
*                        ____
*     DM Req. req   ____|    |___________
*                          ____
*     DM Req. ack   ______|    |_________
*                          ___
*     DM Rsp. req   ______|   |__________
*                            ________
*     DM Rsp. ack   ________|        |___  (DM Response ack. extends over the DTM Response handshake)
*                            ___
*     DTM0 Rsp. req ________|   |________
*                              ____
*     DTM0 Rsp. ack __________|    |_____
*
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
    // (This is a four-phase handshake interface with Request and Response
    // channels. Each channel handshake is independent, except that that
    // a new request gets accepted only if a response for the previous
    // request has been handshaked.)
    input  logic                     dtm0_req_req,
    output logic                     dtm0_req_ack,
    input  logic [DBUS_REQ_BITS-1:0] dtm0_req_bits,
    output logic                     dtm0_rsp_req,
    input  logic                     dtm0_rsp_ack,
    output logic [DBUS_RSP_BITS-1:0] dtm0_rsp_bits,

    // --- Port 1 DTM Interface ---
    // (This is a four-phase handshake interface with Request and Response
    // channels. Each channel handshake is independent, except that that
    // a new request gets accepted only if a response for the previous
    // request has been handshaked.)
    input  logic                     dtm1_req_req,
    output logic                     dtm1_req_ack,
    input  logic [DBUS_REQ_BITS-1:0] dtm1_req_bits,
    output logic                     dtm1_rsp_req,
    input  logic                     dtm1_rsp_ack,
    output logic [DBUS_RSP_BITS-1:0] dtm1_rsp_bits,

    // --- DM Interface ---
    // (This is a four-phase handshake interface with Request and Response
    // channels. Each channel handshake is independent, except that that
    // a new request gets accepted only if a response for the previous
    // request has been handshaked.)
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
logic dtm0_req_allow;
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


// DTM1 signals with the same meaning as for DTM0
logic dtm1_req_allow;
logic dtm1_req_accept;
logic dtm1_req_req_fall;
logic dtm1_req_pend;
logic [1:0] sync_dtm1_req_req;
logic dtm1_req_req_i;
logic dtm1_req_req_d;

// delayed DM request acknowledge (used for detecting the acknowledge fall)
logic dm_req_ack_d;
// strobe indicating the DM request acknowledge fall
logic dm_req_ack_fall;
// DM request acknowledge synchronizer
logic [1:0] sync_dm_req_ack;
// clears DM request
logic dm_req_clr;


// flopped versions of internal signals (used for fall detection of those signals)
always_ff @(posedge clk or negedge rst_n) begin: p_req_flopped_sigs
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
end: p_req_flopped_sigs


// DM Request (Output) Port
// ------------------------

// DM Request acknowledge synchronizer (avoids potential CDC issues)
always_ff @(posedge clk or negedge rst_n) begin: p_dm_req_ack_sync
    if (!rst_n)
        sync_dm_req_ack <= '0;
    else 
        sync_dm_req_ack <= {dm_req_ack, sync_dm_req_ack[$high(sync_dm_req_ack):1]};
end: p_dm_req_ack_sync


// DM request data (latches request data bits from a DTM port, request of which
// gets accepted)
always_ff @(posedge clk or negedge rst_n) begin: p_dm_req_bits
    if (!rst_n)
        dm_req_bits <= '0;
    else if (dtm0_req_accept)
        dm_req_bits <= dtm0_req_bits;
    else if (dtm1_req_accept)
        dm_req_bits <= dtm1_req_bits;
end: p_dm_req_bits


// clear DM request after acknowledge from DM (conditioned by asserted
// request for extra safety, but may be omitted if DM follows the handshake
// protocol correctly)
assign dm_req_clr = dm_req_req & sync_dm_req_ack[0];


// DM request indication (set on acceptance of a request from an either DTM
// port, cleared on DM request acknowledge)
always_ff @(posedge clk or negedge rst_n) begin: p_dm_req_req
    if (!rst_n)
        dm_req_req <= 1'b0;
    else if (dtm0_req_accept | dtm1_req_accept | dm_req_clr)
        dm_req_req <= dtm0_req_accept | dtm1_req_accept | (~dm_req_clr);
end: p_dm_req_req


// detect fall on DM Request acknowledge
// (It is used to clear the Request pending flag on the corresponding DTM port.)
assign dm_req_ack_fall = dm_req_ack_d & ~sync_dm_req_ack[0];


// DTM0 Request (Input) Port
// -------------------------

// internal DTM0 Request
// (It is an OR combination of the actual DTM request and the DTM Request
// pending flag.)
assign dtm0_req_req_i = sync_dtm0_req_req[0] | dtm0_req_pend;

// detect fall of the internal DTM0 Request
// (Used to clear DTM0 Request acknowledge and hence complete the DTM request
// handshake.)
assign dtm0_req_req_fall = dtm0_req_req_d & ~dtm0_req_req_i;

// acceptance of the DTM0 Request
// (The use of the acknowledge signal blocks accepting another request until
// the active one completes. The "allow" condition is determined by the
// arbitration policy and the progress of the DBus Request-Response transaction.)
assign dtm0_req_accept = dtm0_req_req_i & ~dtm0_req_ack & dtm0_req_allow;


// DTM0 Request synchronizer (avoids potential CDC problems)
always_ff @(posedge clk or negedge rst_n) begin: p_dtm0_req_sync
    if (!rst_n)
        sync_dtm0_req_req <= '0;
    else 
        sync_dtm0_req_req <= {dtm0_req_req, sync_dtm0_req_req[$high(sync_dtm0_req_req):1]};
end: p_dtm0_req_sync


// DTM0 Request acknowledge
// (Set when DTM0 Request gets accepted, cleared when DTM0 de-asserts the request
// and the Request has also been fully handshaked on the DM port. The latter part
// is accomplished by using the DTM0 request pending flag.)
always_ff @(posedge clk or negedge rst_n) begin: p_dtm0_req_ack
    if (!rst_n) begin
        dtm0_req_ack <= 1'b0;
    end
    else if (dtm0_req_accept | dtm0_req_req_fall) begin
        dtm0_req_ack <= dtm0_req_accept | (~dtm0_req_req_fall);
    end
end: p_dtm0_req_ack


// DTM0 Request pending flag
// (Set when DTM0 Request gets accepted, cleared when the request has been fully
// handshaked on the DM port. The flag is ORed with the incoming DTM0 Request
// to keep the internal request signal asserted until the DM port handshake
// completes.)
always_ff @(posedge clk or negedge rst_n) begin: p_dtm0_req_pend
    if (!rst_n) begin
        dtm0_req_pend <= 1'b0;
    end
    else if (dtm0_req_accept | dm_req_ack_fall) begin
        dtm0_req_pend <= dtm0_req_accept | (~dm_req_ack_fall);
    end
end: p_dtm0_req_pend


// DTM1 Request (Input) Port
// -------------------------
// (The implementation is the same as for DMT0 and hence requires no extra
// comments.)

// internal DTM1 Request
assign dtm1_req_req_i = sync_dtm1_req_req[0] | dtm1_req_pend;

// detect fall of the internal DTM1 Request
assign dtm1_req_req_fall = dtm1_req_req_d & ~dtm1_req_req_i;

// acceptance of the DTM1 Request
assign dtm1_req_accept = dtm1_req_req_i & ~dtm1_req_ack & dtm1_req_allow;


// DTM1 Request synchronizer (avoids potential CDC problems)
always_ff @(posedge clk or negedge rst_n) begin: p_dtm1_req_sync
    if (!rst_n)
        sync_dtm1_req_req <= '0;
    else 
        sync_dtm1_req_req <= {dtm1_req_req, sync_dtm1_req_req[$high(sync_dtm1_req_req):1]};
end: p_dtm1_req_sync


// DTM1 Request acknowledge
always_ff @(posedge clk or negedge rst_n) begin: p_dtm1_req_ack
    if (!rst_n) begin
        dtm1_req_ack <= 1'b0;
    end
    else if (dtm1_req_accept | dtm1_req_req_fall) begin
        dtm1_req_ack <= dtm1_req_accept | (~dtm1_req_req_fall);
    end
end: p_dtm1_req_ack


// DTM1 Request pending flag
always_ff @(posedge clk or negedge rst_n) begin: p_dtm1_req_pend
    if (!rst_n) begin
        dtm1_req_pend <= 1'b0;
    end
    else if (dtm1_req_accept | dm_req_ack_fall) begin
        dtm1_req_pend <= dtm1_req_accept | (~dm_req_ack_fall);
    end
end: p_dtm1_req_pend


// ----------------------------------------------
// DM to DTM Response Path
// ----------------------------------------------

// enables accepting responses from DM
logic dm_rsp_allow;
// strobe indicating to proceed with processing DM response
logic dm_rsp_accept;
// strobe indicating DM response request fall
logic dm_rsp_req_fall;
// makes the internal DM response request asserted until DTM's acknowledge
logic dm_rsp_pend;
// DM Response request synchronizer
logic [1:0] sync_dm_rsp_req;
// internal DM Response request
logic dm_rsp_req_i;
// flopped version of DM Response request (for fall detection)
logic dm_rsp_req_d;

// Latched DM response forwarded to either DTM response port.
logic [DBUS_RSP_BITS-1:0] dtm_rsp_bits;
// Response acknowledge fall strobe from the arbitrated DTM port.
logic dtm_rsp_ack_fall;

// delayed  DTM0 response acknowledge (used for detecting acknowledge fall)
logic dtm0_rsp_ack_d;
// DTM0 acknowledge synchronizer
logic [1:0] sync_dtm0_rsp_ack;
// strobe indicates fall of DTM0 response acknowledge
logic dtm0_rsp_ack_fall;
// sets DTM0 response request
logic dtm0_rsp_accept;
// clears DTM0 response request (in return to DTM0 response acknowledge)
logic dtm0_rsp_clr;

// DTM1 signals with the same meaning as for DTM0
logic dtm1_rsp_ack_d;
logic [1:0] sync_dtm1_rsp_ack;
logic dtm1_rsp_ack_fall;
logic dtm1_rsp_accept;
logic dtm1_rsp_clr;


// DTM response data (latches request data bits from the DM port, this flop
// is shared for both DTM ports)
always_ff @(posedge clk or negedge rst_n) begin: p_dtm_rsp_bits
    if (!rst_n)
        dtm_rsp_bits <= '0;
    else if (dm_rsp_accept)
        dtm_rsp_bits <= dm_rsp_bits;
end: p_dtm_rsp_bits

assign dtm0_rsp_bits = dtm_rsp_bits;
assign dtm1_rsp_bits = dtm_rsp_bits;

// Internal DM Response request is combination of the Response request input
// and a Response pending flag. The flag asserts on acceptance of the Response
// and clears after the Response has been fully handshaked on the corresponding
// DTM Response port.
assign dm_rsp_req_i = dm_rsp_req | dm_rsp_pend;


// flopped versions of internal signals (used for fall detection of those signals)
always_ff @(posedge clk or negedge rst_n) begin: p_rsp_flopped_sigs
    if (!rst_n) begin
        dtm0_rsp_ack_d <= 1'b0;
        dtm1_rsp_ack_d <= 1'b0;
        dm_rsp_req_d   <= 1'b0;
    end
    else begin
        dtm0_rsp_ack_d <= sync_dtm0_rsp_ack[0];
        dtm1_rsp_ack_d <= sync_dtm1_rsp_ack[0];
        dm_rsp_req_d   <= dm_rsp_req_i;
    end
end: p_rsp_flopped_sigs


// DM Response (Input) Port
// ------------------------

// DM Response request synchronizer (avoids potential CDC problems)
always_ff @(posedge clk or negedge rst_n) begin: p_dm_rsp_sync
    if (!rst_n)
        sync_dm_rsp_req <= '0;
    else 
        sync_dm_rsp_req <= {dm_rsp_req, sync_dm_rsp_req[$high(sync_dm_rsp_req):1]};
end: p_dm_rsp_sync


// DM Response request fall (used to de-assert DM Response acknowledge)
assign dm_rsp_req_fall = dm_rsp_req_d & ~dm_rsp_req_i;


// DM Response acknowledge
always_ff @(posedge clk or negedge rst_n) begin: p_dm_rsp_ack
    if (!rst_n) begin
        dm_rsp_ack <= 1'b0;
    end
    else if (dm_rsp_accept | dm_rsp_req_fall) begin
        dm_rsp_ack <= dm_rsp_accept | (~dm_rsp_req_fall);
    end
end: p_dm_rsp_ack


// DM Response pending flag
// (The flag blocks starting a new DM Response until the previous response has
// been fully handshaked on a corresponding DTM port.)
always_ff @(posedge clk or negedge rst_n) begin: p_dm_rsp_pend
    if (!rst_n) begin
        dm_rsp_pend <= 1'b0;
    end
    else if (dm_rsp_accept | dtm_rsp_ack_fall) begin
        dm_rsp_pend <= dm_rsp_accept | (~dtm_rsp_ack_fall);
    end
end: p_dm_rsp_pend


// DTM0 Response (Output) Port
// ---------------------------

// DTM0 Response acknowledge fall detection
// (Used to clear the DM Response pending flag if DTM0 is used for Response
// handshaking.)
assign dtm0_rsp_ack_fall = dtm0_rsp_ack_d & ~sync_dtm0_rsp_ack[0];

// clear DTM0 Response request after acknowledge from DTM0 (conditioned by
// asserted request for extra safety, but may be omitted if the DTM follows
// the handshake protocol correctly)
assign dtm0_rsp_clr = dtm0_rsp_req & sync_dtm0_rsp_ack[0];


// DTM0 Response request indication
// (Set on acceptance of a response request from the DM port, cleared on
// response acknowledge from the selected DTM response port. The selection
// is based on the port index, `dtm_src_last`, captured during the last
// DTM Request handshake.)
always_ff @(posedge clk or negedge rst_n) begin: p_dtm0_rsp_req
    if (!rst_n)
        dtm0_rsp_req <= 1'b0;
    else if (dtm0_rsp_accept | dtm0_rsp_clr)
        dtm0_rsp_req <= dtm0_rsp_accept | (~dtm0_rsp_clr);
end: p_dtm0_rsp_req


// DTM0 Response acknowledge synchronizer (avoids potential CDC issues)
always_ff @(posedge clk or negedge rst_n) begin: p_dtm0_rsp_ack_sync
    if (!rst_n)
        sync_dtm0_rsp_ack <= '0;
    else 
        sync_dtm0_rsp_ack <= {dtm0_rsp_ack, sync_dtm0_rsp_ack[$high(sync_dtm0_rsp_ack):1]};
end: p_dtm0_rsp_ack_sync


// DTM1 Response (Output) Port
// ---------------------------
// (The implementation is the same as for DMT0 and hence requires no extra
// comments.)

// DTM1 Response acknowledge fall detection
assign dtm1_rsp_ack_fall = dtm1_rsp_ack_d & ~sync_dtm1_rsp_ack[0];

// clear DTM1 Response request after acknowledge from DTM1
assign dtm1_rsp_clr = dtm1_rsp_req & sync_dtm1_rsp_ack[0];


// DTM1 Response request indication
always_ff @(posedge clk or negedge rst_n) begin: p_dtm1_rsp_req
    if (!rst_n)
        dtm1_rsp_req <= 1'b0;
    else if (dtm1_rsp_accept | dtm1_rsp_clr)
        dtm1_rsp_req <= dtm1_rsp_accept | (~dtm1_rsp_clr);
end: p_dtm1_rsp_req


// DTM1 Response acknowledge synchronizer (avoids potential CDC issues)
always_ff @(posedge clk or negedge rst_n) begin: p_dtm1_rsp_ack_sync
    if (!rst_n)
        sync_dtm1_rsp_ack <= '0;
    else 
        sync_dtm1_rsp_ack <= {dtm1_rsp_ack, sync_dtm1_rsp_ack[$high(sync_dtm1_rsp_ack):1]};
end: p_dtm1_rsp_ack_sync


// ----------------------------------------------
// Arbitration Policy
// ----------------------------------------------
// (This is a fair arbitration policy. For two DTM ports, this is represented
// by a single flop that holds the index of the last arbitrated DTM port.
// Besides the arbitration policy, there is a FSM monitoring progress of the
// DBus Request-Response transaction. This FSM is used to prevent accepting
// a new Request when a preceding Request-Response pair is still ongoing.)

// Identifies which DTM port has been serviced last.
logic dtm_src_last;

// Represents states of a state machine that tracks completion of DBus
// Request-Response transaction cycle. While the Request and Response
// represent independent channels within the DBus link layer, the DBus
// transaction layer assumes a transaction starts with a Request and
// shall be followed by a response.
typedef enum bit {
    // In this state, the arbiter allows accepting a new request from
    // either DTM port (and blocks handshake in the DBus response channel).
    Q_REQ = 1'b0,
    // In this state, the arbiter blocks accepting new requests from any
    // DTM port (and allows DM responses pass towards the initiating DTM
    // port).
    Q_RSP = 1'b1
} t_transaction_fsm;

// Present and next FSM state.
t_transaction_fsm trans_fsm_q;
t_transaction_fsm trans_fsm_n;


// DTM arbitration policy
// (If both DTM ports indicate a request at the same time, the policy selects
// which port is allowed to proceed with the request. The policy is based on
// the last port allowed to proceed and the actual state of DTM requests, and
// translates into the following Boolean table. The transition is conditioned
// by the transaction monitor FSM being in the request phase.)
//
// last    req0    req1 |  last'
// ---------------------+------
// 0       0       0    |  0
// 0       0       1    |  1
// 0       1       0    |  0
// 0       1       1    |  1
// 1       0       0    |  1
// 1       0       1    |  1
// 1       1       0    |  0
// 1       1       1    |  0
//
// The above Boolean table (including the FSM state guard) is yielded through
// "accept" and "allow" signals for both DTM ports.
always_ff @(posedge clk or negedge rst_n) begin: p_dtm_src_last
    if (!rst_n)
        dtm_src_last <= 1'b0;
    else begin
        // Request from both ports cannot be accepted at the same time.
        assert( ~(dtm0_req_accept & dtm1_req_accept) );
        if (dtm0_req_accept | dtm1_req_accept) begin
            dtm_src_last <= dtm1_req_accept;
        end
    end
end: p_dtm_src_last

// DTM Request is allowed when a) no other request is in progress, and
// b) the request is arbitrated.
assign dtm0_req_allow = (trans_fsm_q == Q_REQ) & ( dtm_src_last | ~dtm1_req_req_i);
assign dtm1_req_allow = (trans_fsm_q == Q_REQ) & (~dtm_src_last | ~dtm0_req_req_i);

// DM Response is allowed when a) a request is in progress, b) DM requests
// a response, and c) no other response is in progress.
assign dm_rsp_accept = (trans_fsm_q == Q_RSP) & dm_rsp_req_i & ~dm_rsp_ack;

// DTM Response port is selected by the index of the port from which the last
// Request came (represented by the arbitration policy).
assign dtm0_rsp_accept = dm_rsp_accept & ~dtm_src_last;
assign dtm1_rsp_accept = dm_rsp_accept &  dtm_src_last;

// DTM Response acknowledge fall strobe is selected based on the last Request
// port.
assign dtm_rsp_ack_fall = dtm_src_last ? dtm1_rsp_ack_fall : dtm0_rsp_ack_fall;


// Transaction FSM current state
always_ff @(posedge clk or negedge rst_n) begin: p_trans_fsm_q
    if (!rst_n)
        trans_fsm_q <= Q_REQ;
    else
        trans_fsm_q <= trans_fsm_n;
end: p_trans_fsm_q


// Transaction FSM transition and output function
// (at the moment the FSM is fairly simple)
always_comb begin: p_trans_fsm_n
    trans_fsm_n = trans_fsm_q;

    case (trans_fsm_q)
        Q_REQ: begin
            if (dtm0_req_accept | dtm1_req_accept) begin
                trans_fsm_n = Q_RSP;
            end
        end

        Q_RSP: begin
            if (dm_rsp_req_fall) begin
                trans_fsm_n = Q_REQ;
            end
        end

        default: begin
            $error("Unexpected FSM state: %0s", trans_fsm_q);
        end
    endcase
end: p_trans_fsm_n


endmodule: dbus_arbiter
