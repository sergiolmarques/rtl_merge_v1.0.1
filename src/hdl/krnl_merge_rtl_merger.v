`timescale 1ns / 1ps
//=============================================================================
// krnl_merge_rtl_merger
//
// Word-serial (NUM_WORDS = 1 equivalent) streaming merge of two sorted input
// FIFOs (A and B) into a single sorted output FIFO, translated from the HLS
// compute_merge() reference.
//
// Assumptions / interface semantics (no vSize/vSize2 ports exist here, so
// the notion of "total1"/"total2" from the HLS code is replaced by simply
// draining each input FIFO until it reports empty):
//
//   - wr_fifo_tvalid_n_a / wr_fifo_tvalid_n_b are ACTIVE-LOW "valid" flags
//     from the input FIFOs: 0 = a data word is present on tdata, 1 = FIFO
//     empty (no data).
//   - MERGED_FIFO1_RdEn / MERGED_FIFO2_RdEn are one-cycle read-enable pulses
//     issued to FIFO A / FIFO B whenever a word is popped from that FIFO.
//   - MERGED_FIFO_WrEn / MERGED_FIFO_Data write the chosen (smaller) word
//     into the output FIFO, qualified by MERGED_FIFO_FULL.
//   - The merge is considered complete (FINISH=1) once BOTH input FIFOs are
//     empty. The merge_loop + drain1_loop + drain2_loop,
//     here there are no separate "sizes" - both FIFOs are assumed to
//     be fully pre-loaded with the data for this merge pass before "start"
//     is asserted.
//=============================================================================

module krnl_merge_rtl_merger #(
  parameter integer C_DATA_WIDTH   = 32 // Data width of both input and output data
)
(
  input  wire                     aclk,
  input  wire                     areset,

  input  wire                     start,
  output wire                     FINISH,

  input  wire                     wr_fifo_tvalid_n_a,
  input  wire [C_DATA_WIDTH-1:0]  wr_fifo_tdata_a,

  input  wire                     wr_fifo_tvalid_n_b,
  input  wire [C_DATA_WIDTH-1:0]  wr_fifo_tdata_b,

  input  wire                     MERGED_FIFO_FULL,
  output wire [C_DATA_WIDTH-1:0]  MERGED_FIFO_Data,
  output wire                     MERGED_FIFO_WrEn,
  output wire                     MERGED_FIFO1_RdEn,
  output wire                     MERGED_FIFO2_RdEn
);

  //---------------------------------------------------------------------
  // Active-high "data available" versions of the FIFO valid flags
  //---------------------------------------------------------------------
  wire valid_a = ~wr_fifo_tvalid_n_a;
  wire valid_b = ~wr_fifo_tvalid_n_b;

  wire both_empty = ~valid_a & ~valid_b;

  //---------------------------------------------------------------------
  // busy / done control
  //---------------------------------------------------------------------
  reg busy_r;
  reg finish_r;

  always @(posedge aclk or posedge areset) begin
    if (areset) begin
      busy_r   <= 1'b0;
      finish_r <= 1'b0;
    end else begin
      if (start && !busy_r && !finish_r) begin
        // Kick off a new merge pass
        busy_r   <= 1'b1;
        finish_r <= 1'b0;
      end else if (busy_r && both_empty) begin
        // Both source FIFOs drained -> merge complete
        busy_r   <= 1'b0;
        finish_r <= 1'b1;
      end else if (finish_r && !start) begin
        // Host has seen FINISH and dropped start -> clear, ready for next run
        finish_r <= 1'b0;
      end
    end
  end

  assign FINISH = finish_r;

  //---------------------------------------------------------------------
  // Merge compare / select logic (combinational)
  //---------------------------------------------------------------------
  // Prefer A on ties, matching the HLS "if (val1 <= val2)" behavior.
  wire pick_a = valid_a && (!valid_b || (wr_fifo_tdata_a <= wr_fifo_tdata_b));
  wire pick_b = valid_b && !pick_a;

  wire can_write = busy_r && !MERGED_FIFO_FULL && (valid_a || valid_b);

  assign MERGED_FIFO_Data  = pick_a ? wr_fifo_tdata_a : wr_fifo_tdata_b;
  assign MERGED_FIFO_WrEn  = can_write;

  assign MERGED_FIFO1_RdEn = can_write && pick_a;
  assign MERGED_FIFO2_RdEn = can_write && pick_b;

endmodule