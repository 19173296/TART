`timescale 1ns/100ps
/*
 * Module      : verilog/tart_control.v
 * Copyright   : (C) Tim Molteno     2016
 *             : (C) Max Scheel      2016
 *             : (C) Patrick Suggate 2016
 * License     : LGPL3
 * 
 * Maintainer  : Patrick Suggate <patrick.suggate@gmail.com>
 * Stability   : Experimental
 * Portability : only tested with a Papilio board (Xilinx Spartan VI)
 * 
 * TART's control registers module, connected via a Wishbone-like
 * interconnect.
 * 
 * Has system registers for:
 *   00  --  status register;
 *   01  --  extra status-flags;
 *   10  --  miscellaneous register;
 *   11  --  reset register;
 * 
 * NOTE:
 *  + supports both classic and pipelined transfers;
 * 
 * TODO:
 *  + upgrade to Wishbone SPEC B4;
 * 
 */

`include "tartcfg.v"

module tart_control
  #(// Wishbone bus-width parameters:
    parameter WIDTH = 8,        // SPI data-bus bit-width
    parameter MSB   = WIDTH-1,  // MSB of bus bit-width
    parameter COUNT = 24,       // checksum and accumulator bit-widths
    parameter CSB   = COUNT-1,  // MSB of checksum
    parameter RTIME = 4,        // sets the reset pulse duration

    // Wishbone bus mode parameters:
    parameter PIPED = 1,        // pipelined Wishbone transfers (0/1)?
    parameter CHECK = 1,        // TODO: extra sanity-checking (0/1)?

    // Simulation-only parameters:
    parameter DELAY = 3)        // simulation combinational delay
   (input          clk_i,
    input          rst_i,

    // Wishbone (SPEC B4) bus interface:
    input          cyc_i,
    input          stb_i,
    input          we_i,
    output         ack_o,
    output         wat_o,
    output         rty_o,
    output         err_o,
    input [1:0]    adr_i,
    input [MSB:0]  dat_i,
    output [MSB:0] dat_o,

    input [MSB:0]  status_i,
    input [MSB:0]  extra_i,
    input          reset_ni,
    output         reset_o
    );

   reg [MSB:0]     dat;
   reg             ack = 1'b0;
   wire            stb_w, ack_w, r_stb;


   //-------------------------------------------------------------------------
   //  Wishbone output assignments.
   assign ack_o = ack;
   assign wat_o = 1'b0;         // does not stall
   assign rty_o = 1'b0;         // always completes
   assign err_o = 1'b0;         // never causes errors
   assign dat_o = dat;

   //  Pipelined transfers generate an ACK for each cycle that STB is
   //  asserted; whereas classic transfers expect STB to be asserted until
   //  an ACK response.
   assign stb_w = CHECK ? cyc_i && stb_i : stb_i;
   assign ack_w = PIPED ? stb_w : stb_w && !ack;

   //  Reset module address-decoder.
   assign r_stb = stb_w && adr_i == 2'b11;


   //-------------------------------------------------------------------------
   //  Drive the Wishbone slave's response signals.
   //-------------------------------------------------------------------------
   always @(posedge clk_i)
     if (rst_i)
       ack <= #DELAY 1'b0;
     else
       ack <= #DELAY ack_w;

   //  TODO: Put status and reset onto the same register?
   always @(posedge clk_i)
     if (cyc_i && stb_i && !we_i)
       case (adr_i)
         2'b00:   dat <= #DELAY status_i;
         2'h01:   dat <= #DELAY extra_i;
         default: dat <= #DELAY 8'bx;
       endcase // case (adr_i)


   //-------------------------------------------------------------------------
   //     RESET HANDLER
   //-------------------------------------------------------------------------
   wb_reset #( .WIDTH(WIDTH), .RTIME(RTIME) ) WB_RESET0
     ( .clk_i(clk_i),
       .rst_i(rst_i),
       .cyc_i(cyc_i),
       .stb_i(r_stb),
       .we_i (we_i),
       .ack_o(),
       .dat_i(dat_i),
       .dat_o(),

       .reset_ni(reset_ni),
       .reset_o (reset_o)
       );


endmodule // tart_control
