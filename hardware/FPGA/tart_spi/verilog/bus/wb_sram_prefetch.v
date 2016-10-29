`timescale 1ns/100ps
/*
 * Module      : verilog/bus/wb_sram_prefetch.v
 * Copyright   : (C) Tim Molteno     2016
 *             : (C) Max Scheel      2016
 *             : (C) Patrick Suggate 2016
 * License     : LGPL3
 * 
 * Maintainer  : Patrick Suggate <patrick.suggate@gmail.com>
 * Stability   : Experimental
 * Portability : only tested with Icarus Verilog
 * 
 * Has a master Wishbone bus, for prefetching, and a slave Wishbone bus, for
 * retrieving the prefetched data (and both buses are Wishbone SPEC B4). Data
 * is buffered locally using Xilinx block SRAM's.
 * 
 * The data-prefetches are broken up into multiple block-transfers, of the
 * parameterised sizes, so that data blocks can be sequentially-fetched from
 * multiple, similar devices.
 * 
 * NOTE:
 *  + currently synchronous, and both bus interfaces share the same clock;
 *  + it would be unwise to change the input `count_i` value while this module
 *    is active;
 *  + built to support Wishbone B4 SPEC Pipelined BURST READS & WRITES;
 * 
 * Changelog:
 *  + 29/10/2016  --  initial file;
 * 
 * TODO:
 * 
 */

module wb_sram_prefetch
  #(// Wishbone bus parameters:
    parameter WIDTH = 32,       // word bit-width (32-bit is max)
    parameter MSB   = WIDTH-1,  // word MSB
    parameter BYTES = WIDTH>>3, // Byte-select bits
    parameter SSB   = BYTES-1,  // MSB of the byte-selects
    parameter ABITS = CBITS+BBITS, // address bit-width
    parameter ASB   = ABITS-1,     // address MSB
    parameter ESB   = ASB+2,       // address MSB for byte-wide access

    //  Prefetcher, block-size parameters:
    parameter COUNT = 24,       // blocks per complete prefetch
    parameter CBITS = 5,        // block-counter bits
    parameter CSB   = CBITS-1,  // block-counter MSB
    parameter CMAX  = COUNT-1,  // maximum (block-)counter value
    parameter BSIZE = 24,       // words/block
    parameter BBITS = 5,        // word-counter bits
    parameter BSB   = BBITS-1,  // word-counter MSB
    parameter BMAX  = BSIZE-1,  // maximum (word-)counter value

    parameter DELAY = 3)
   (
    input          clk_i,
    input          rst_i,

    //  Prefetcher control & status signals:
    input          begin_i,
    output reg     ready_o = 1'b0,

    //  The prefetching, Wishbone (master, SPEC B4) bus interface:
    output         cyc_o,
    output         stb_o,
    output         we_o,
    input          ack_i,
    input          wat_i,
    input          rty_i,
    input          err_i,
    output [ASB:0] adr_o,
    output [SSB:0] sel_o,
    input [MSB:0]  dat_i,
    output [MSB:0] dat_o,

    //  Interface to the buffering SRAM:
    output         sram_ce_o,
    output         sram_we_o,
    output [ASB:0] sram_ad_o,
    output [SSB:0] sram_be_o,
    input [MSB:0]  sram_do_i,
    output [MSB:0] sram_di_o
    );


   //-------------------------------------------------------------------------
   //  Prefetcher signal definitions.
   //-------------------------------------------------------------------------
   //  Block-fetcher (lower-address) control signals.
   reg                 read = 1'b0;
   wire                done;
   wire [BSB:0]        lower;

   //  Block (upper-address) counter.
   reg [CSB:0]         block = {CBITS{1'b0}};
   reg [CSB:0]         block_nxt;
   reg                 block_end = 1'b0;
   wire [CBITS:0]      block_inc = block + 1;

   //  Local address counter.
   reg [ASB:0]         count = {ABITS{1'b0}};
   wire [ABITS:0]      count_inc = count + 1;

   //  Fetch signals.
   wire                f_cyc, f_stb, f_we, f_ack;
   wire [ASB:0]        f_adr;
   wire [SSB:0]        f_sel;
   wire [MSB:0]        f_dat;


   //-------------------------------------------------------------------------
   //  Additional Wishbone interface signals.
   //-------------------------------------------------------------------------
   //  External (master) Wishbone interface signals.
   assign adr_o = {block, lower};
   assign sel_o = {BYTES{1'b1}};
   assign dat_o = dat_q[MSB:0];

   //  Internal (fetch) Wishbone interface signals.
   assign f_cyc = cyc_o;
   assign f_stb = ack_i;
   assign f_we  = cyc_o;
   assign f_adr = count;
   assign f_sel = {BYTES{1'b1}};
   assign f_dat = dat_i;


   //-------------------------------------------------------------------------
   //  Block address.
   //-------------------------------------------------------------------------
   //  Increment the block-counter after each block has been prefetched.
   always @(posedge clk_i)
     if (begin_i)
       block <= #DELAY {CBITS{1'b0}};
     else if (done)
       block <= #DELAY block_nxt;

   //  Pipeline these signals, since the block-prefetches take several clock-
   //  cycles to complete.
   always @(posedge clk_i)
     begin
        block_nxt <= #DELAY block_inc[CSB:0];
        block_end <= #DELAY !begin_i && block_nxt == COUNT;
     end


   //-------------------------------------------------------------------------
   //  Strobe the `ready_o` signal when a prefetch has been completed.
   //-------------------------------------------------------------------------
   always @(posedge clk_i)
     if (rst_i || begin_i)
       ready_o <= #DELAY 1'b0;
     else
       ready_o <= #DELAY block_end && done;


   //-------------------------------------------------------------------------
   //  Local SRAM address/counter.
   //-------------------------------------------------------------------------
   //  Increment the counter after each word has been transferred over the
   //  Wishbone master interface.
   always @(posedge clk_i)
     if (begin_i)
       count <= #DELAY {ABITS{1'b0}};
     else if (a_cyc_o && a_ack_i)
       count <= #DELAY count_inc[ASB:0];


   //-------------------------------------------------------------------------
   //  Address-generation unit, for each block.
   //-------------------------------------------------------------------------
`ifdef  __USE_ASYNC_FETCH
   wire read_s = read_w;
`else
   wire read_s = read;
`endif
   wire read_w = begin_i || done && !block_end;

   always @(posedge clk_i)
     read <= #DELAY read_w;


   //-------------------------------------------------------------------------
   //  Wishbone pipelined BURST READS functional unit.
   //-------------------------------------------------------------------------
   wb_fetch
     #(  .FETCH(BSIZE), .FBITS(BBITS), .DELAY(DELAY)
         ) FETCH0
       ( .clk_i(clk_i),
         .rst_i(rst_i),

         .fetch_i(read_s),
         .ready_o(done),

         .cyc_o(cyc_o),         // Drives the external Wishbone interface
         .stb_o(stb_o),
         .we_o (we_o),
         .ack_i(ack_i),
         .wat_i(wat_i),
         .rty_i(rty_i),
         .err_i(err_i),
         .adr_o(lower)
         );


   //-------------------------------------------------------------------------
   //  Wishbone to SRAM interface for storing the prefetched data.
   //-------------------------------------------------------------------------
   wb_sram_interface
     #(  .WIDTH(WIDTH),
         .ABITS(ABITS),
         .TICKS(TICKS),
         .READ (0),
         .WRITE(1),
         .USEBE(0),
         .BYTES(BYTES),
         .PIPED(1),
         .ASYNC(1),
         .CHECK(0),
         .DELAY(DELAY)
         ) SRAMWB
       ( .clk_i(clk_i),
         .rst_i(rst_i),
         .cyc_i(f_cyc),
         .stb_i(f_stb),
         .we_i (f_we),
         .ack_o(f_ack),
         .wat_o(),
         .rty_o(),
         .err_o(),
         .adr_i(f_adr),
         .sel_i(f_sel),
         .dat_i(f_dat),
         .dat_o(dat_o),

         .sram_ce_o(sram_ce_o),
         .sram_we_o(sram_we_o),
         .sram_be_o(sram_be_o),
         .sram_ad_o(sram_ad_o),
         .sram_do_i(sram_do_i),
         .sram_di_o(sram_di_o)
         );


`ifdef __icarus
   //-------------------------------------------------------------------------
   //  Debug information.
   //-------------------------------------------------------------------------
   initial begin : SRAM_PREFETCH
      $display("\nModule : wb_sram_prefetch (%m)\n\tWIDTH\t= %4d\n\tBYTES\t= %4d\n\tABITS\t= %4d\n\tCOUNT\t= %4d\n\tCBITS\t= %4d\n\tBSIZE\t= %4d\n\tBBITS\t= %4d\n", WIDTH, BYTES, ABITS, COUNT, CBITS, BSIZE, BBITS);
   end // PREFETCH_BLOCK


   //-------------------------------------------------------------------------
   //  Count the number of prefetched words.
   //-------------------------------------------------------------------------
   integer             rxd = 0;

   always @(posedge clk_i)
     if (rst_i || begin_i) rxd <= #DELAY 0;
     else if (a_cyc_o && a_ack_i) rxd <= #DELAY rxd+1;
`endif //  `ifdef __icarus


endmodule // wb_sram_prefetch
