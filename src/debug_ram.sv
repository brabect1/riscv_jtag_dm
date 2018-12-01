/*
Copyright 2018 Tomas Brabec

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/


/**
* Implements 8x32b asynchronous RAM used as Debug RAM (DRAM).
*
* Asynchronous RAM is such that read data is updated asynchronously (i.e. with address change).
*
* Asynchronous RAM is used due to response strobe timing. Changing to a synchronous
* RAM would need changing timing of the response valid strobe (which might have yet
* other implications).
*
* This module is merely a wrapper over the actual RAM module, which is intentional
* to let users change underlying RAM implementation without affecting the Debug
* Module itself.
*/
module debug_ram(
  input  logic clk,
  input  logic en,
  input  logic we,
  input  logic [ 2:0] addr,
  input  logic [31:0] din,
  output logic [31:0] dout
);

// number of bytes per RAM word
localparam int NB_COL = 4;

sp_ram #(
    .NB_COL(NB_COL),
    .COL_WIDTH(8),
    .AWIDTH(3)
) u_ram (
    .we({NB_COL{we}}),
    .*
);

endmodule: debug_ram


module sp_ram #(
//    parameter string INIT_FILE = ""           // Specify name/location of RAM initialization file if using one (leave blank if not)
    parameter bit[200*8-1:0] INIT_FILE = '0,           // Specify name/location of RAM initialization file if using one (leave blank if not)
    parameter int NB_COL,                     // Specify number of columns (number of bytes)
    parameter int COL_WIDTH,                  // Specify column width (byte width, typically 8 or 9)
    parameter int AWIDTH                      // Specify RAM depth (number of entries)
) (
    input  logic [AWIDTH-1:0] addr,             // address bus, width determined from RAM_DEPTH
    input  logic [(NB_COL*COL_WIDTH)-1:0] din,  // RAM input data
    input  logic clk,                           // Clock
    input  logic [NB_COL-1:0] we,               // write enable
    input  logic en,                            // RAM Enable, for additional power savings, disable BRAM when not in use
    output logic [(NB_COL*COL_WIDTH)-1:0] dout  // RAM output data
);

    logic [(NB_COL*COL_WIDTH)-1:0] mem [2**AWIDTH-1:0];

    // The following code either initializes the memory values to a specified file or to all zeros to match hardware
//    if (INIT_FILE != "") begin: use_init_file
    if (|INIT_FILE != 1'b0) begin: use_init_file
        initial
            $readmemh(INIT_FILE, mem);
    end else begin: init_bram_to_zero
        integer ram_index;
        initial begin
            for (ram_index = 0; ram_index < 2**AWIDTH; ram_index = ram_index + 1)
                mem[ram_index] = {(NB_COL*COL_WIDTH){1'b0}};
        end
    end

//    always @(posedge clk)
//        if (en) begin
//            dout <= mem[addr];
//        end
    assign dout = mem[addr];

    for (genvar i = 0; i < NB_COL; i = i+1) begin: byte_write
        always @(posedge clk)
            if (en)
                if (we[i])
                    mem[addr][(i+1)*COL_WIDTH-1:i*COL_WIDTH] <= din[(i+1)*COL_WIDTH-1:i*COL_WIDTH];
    end

endmodule: sp_ram
