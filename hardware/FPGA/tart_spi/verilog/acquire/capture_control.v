`timescale 1ns/100ps
/*
 * Module      : verilog/acquire/capture_control.v
 * Copyright   : (C) Tim Molteno     2016
 *             : (C) Max Scheel      2016
 *             : (C) Patrick Suggate 2016
 * License     : LGPL3
 * 
 * Maintainer  : Patrick Suggate <patrick.suggate@gmail.com>
 * Stability   : Experimental
 * Portability : only tested with a Papilio board (Xilinx Spartan VI)
 * 
 * Generates the domain-appropriate versions of the reset and control signals,
 * for the capture logic-core.
 * 
 * NOTE:
 *  + the `e` suffix is used to tag signals from the external (signal) clock-
 *    domain, and the `x` suffix for the (12x by default) sampling- and
 *    correlator- domain clock;
 *  + even though the sample-clock's frequency is an integer multiple of the
 *    external clock, the phase relationship is unknown (due to the quirky
 *    Spartan 6 DCM's), thus asynchronous domain-crossing techniques must be
 *    used;
 *  + the `ALIGN` parameter selects whether to oversample the antenna
 *    signals, and perform clock-recovery, if enabled (1) -- or instead to
 *    cross the clock-domain (to the correlator domain) using an asynchronous
 *    FIFO (0);
 * 
 * TODO:
 *  + setup a bunch of FROM/TO constraints for CDC;
 * 
 */

module capture_control
  #(//  Capture bit-width settings:
    parameter PBITS = 4,        // bit-width of the phase register
    parameter PSB   = PBITS-1,  // MSB of the phase register
    parameter SBITS = 5,        // antenna-select bit-width
    parameter SSB   = SBITS-1,  // MSB of antenna-select

    //  Simulation-only parameters:
    parameter DELAY = 3)
   (
    input          clock_b_i, // bus clock
    input          reset_b_i, // bus-domain reset

    input          clock_x_i, // sample/correlator clock
    output         reset_x_o, // reset (sample domain)

    input          clock_e_i, // external clock
    output         reset_e_o, // reset (external domain)

    //  Raw-data capture-unit control-signals:
    input          capture_b_i, // capture-enable
    output         capture_x_o, // sample-domain CE
    input [PSB:0]  delay_b_i, // phase-shift to delay input signals
    output [PSB:0] delay_x_o,

    //  Raw-data capture-unit control-signals:
    input          centre_b_i, // enable the centring unit?
    output         centre_x_o,
    input [SSB:0]  select_b_i, // select antenna for phase measurement
    output [SSB:0] select_x_o,
    output         locked_b_o, // alignment-unit has lock?
    output         locked_x_i,
    output [PSB:0] phase_b_o, // measured phase
    input [PSB:0]  phase_x_i,
    output         invalid_b_o, // alignment-unit has lost lock?
    output         invalid_x_i,
    input          restart_b_i, // restart the alignment-unit?
    output         restart_x_o,

    //  CDC for fake/debug data control-signals:
    input          debug_b_i, // enable fake-data
    output         debug_e_o,
    output         debug_x_o, // sample-domain MUX select
    input          shift_b_i, // use shift-register to generate fake-data
    output         shift_e_o,
    input          count_b_i, // use up-counter to generate fake-data
    output         count_e_o
    );



   //-------------------------------------------------------------------------
   //
   //  SYNCHRONISERS.
   //
   //-------------------------------------------------------------------------
   //  Reset CDC synchronisers.
   (* NOMERGE = "TRUE" *)
   reg             reset_s, reset_e; // bus -> signal domain synchronisers
   (* NOMERGE = "TRUE" *)
   reg             reset_t, reset_x; // bus -> sample domain synchronisers

   //-------------------------------------------------------------------------
   //  Raw-data capture-unit CDC synchronisers.
   (* NOMERGE = "TRUE" *)
   reg             capture_t, capture_x;
   (* NOMERGE = "TRUE" *)
   reg [PSB:0]     delay_t, delay_x;

   //-------------------------------------------------------------------------
   //  Data-sampling & alignment CDC synchronisers.
   (* NOMERGE = "TRUE" *)
   reg             centre_t, centre_x;
   (* NOMERGE = "TRUE" *)
   reg [SSB:0]     select_t, select_x;
   (* NOMERGE = "TRUE" *)
   reg             locked_b, locked_q;
   (* NOMERGE = "TRUE" *)
   reg [PSB:0]     phase_b, phase_q;
   (* NOMERGE = "TRUE" *)
   reg             invalid_b, invalid_q;
   (* NOMERGE = "TRUE" *)
   reg             restart_t, restart_x;

   //-------------------------------------------------------------------------
   //  Fake-/debug- data control-signal synchronisers.
   (* NOMERGE = "TRUE" *)
   reg             debug_s, debug_e;
   (* NOMERGE = "TRUE" *)
   reg             debug_t, debug_x;
   (* NOMERGE = "TRUE" *)
   reg             shift_s, shift_e;
   (* NOMERGE = "TRUE" *)
   reg             count_s, count_e;


   //-------------------------------------------------------------------------
   //  Assign synchronised signals to outputs.
   //-------------------------------------------------------------------------
   //  Reset assignments.
   assign reset_e_o   = reset_e;
   assign reset_x_o   = reset_x;

   //-------------------------------------------------------------------------
   //  Raw-data capture-unit assignments.
   assign capture_x_o = capture_x;
   assign delay_x_o   = delay_x;

   //-------------------------------------------------------------------------
   //  Data-sampling & alignment assignments.
   assign centre_x_o  = centre_x;
   assign select_x_o  = select_x;
   assign locked_b_o  = locked_b;
   assign phase_b_o   = phase_b;
   assign invalid_b_o = invalid_b;
   assign restart_x_o = restart_x;

   //-------------------------------------------------------------------------
   //  Fake-/debug- data control-signal assignments.
   assign debug_x_o   = debug_x;

   assign debug_e_o   = debug_e;
   assign shift_e_o   = shift_e;
   assign count_e_o   = count_e;


   //-------------------------------------------------------------------------
   //  Re-register some input signals, so that they're "close," for the FROM/
   //  TO contraints.
   //-------------------------------------------------------------------------
   (* NOMERGE = "TRUE" *)
   reg     reset_b;

   always @(posedge clock_b_i)
     reset_b <= #DELAY reset_b_i;


   //-------------------------------------------------------------------------
   //  Sample/correlator-domain synchronisers.
   //-------------------------------------------------------------------------
   always @(posedge clock_x_i)
     begin
        {  reset_x,   reset_t} <= #DELAY {  reset_t,   reset_b};

        // capture-unit synchronisers:
        {capture_x, capture_t} <= #DELAY {capture_t, capture_b_i};
        {  delay_x,   delay_t} <= #DELAY {  delay_t,   delay_b_i};

        // centring-unit synchronisers:
        { centre_x,  centre_t} <= #DELAY { centre_t,  centre_b_i};
        { select_x,  select_t} <= #DELAY { select_t,  select_b_i};
        {restart_x, restart_t} <= #DELAY {restart_t, restart_b_i};

        // debug-/fake- data unit synchronisers:
        {  debug_x,   debug_t} <= #DELAY {  debug_t,   debug_b_i};
     end


   //-------------------------------------------------------------------------
   //  Bus-domain synchronisers.
   //-------------------------------------------------------------------------
   always @(posedge clock_x_i)
     begin
        // centring-unit synchronisers:
        { locked_b,  locked_q} <= #DELAY { locked_q,  locked_x_i};
        {  phase_b,   phase_q} <= #DELAY {  phase_q,   phase_x_i};
        {invalid_b, invalid_q} <= #DELAY {invalid_q, invalid_x_i};
     end


   //-------------------------------------------------------------------------
   //  Signal/external-domain synchronisers.
   //-------------------------------------------------------------------------
   always @(posedge clock_e_i)
     begin
        {reset_e, reset_s} <= #DELAY {reset_s, reset_b};

        // debug-/fake- data unit synchronisers:
        {debug_e, debug_s} <= #DELAY {debug_s, debug_b_i};
        {shift_e, shift_s} <= #DELAY {shift_s, shift_b_i};
        {count_e, count_s} <= #DELAY {count_s, count_b_i};
     end


endmodule // capture_control
