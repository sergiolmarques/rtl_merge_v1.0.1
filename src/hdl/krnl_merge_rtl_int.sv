/**
* Copyright (C) 2019-2021 Xilinx, Inc
*
* Licensed under the Apache License, Version 2.0 (the "License"). You may
* not use this file except in compliance with the License. A copy of the
* License is located at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
* WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
* License for the specific language governing permissions and limitations
* under the License.
*/

///////////////////////////////////////////////////////////////////////////////
// Description: This is a example of how to create an RTL Kernel.  The function
// of this module is to add two 32-bit values and produce a result.  The values
// are read from one AXI4 memory mapped master, processed and then written out.
//
// Data flow: axi_read_master->fifo[2]->adder->fifo->axi_write_master
///////////////////////////////////////////////////////////////////////////////

// default_nettype of none prevents implicit wire declaration.
`default_nettype none
`timescale 1 ns / 1 ps 

module krnl_merge_rtl_int #( 
  parameter integer  C_S_AXI_CONTROL_DATA_WIDTH = 32,
  parameter integer  C_S_AXI_CONTROL_ADDR_WIDTH = 8, //6->8
  parameter integer  C_M_AXI_GMEM_ID_WIDTH = 1,
  parameter integer  C_M_AXI_GMEM_ADDR_WIDTH = 64,
  parameter integer  C_M_AXI_GMEM_DATA_WIDTH = 32
)
(
  // System signals
  input  wire  ap_clk,
  input  wire  ap_rst_n,
  // AXI4 master interface 
  output wire                                 m_axi_gmem_AWVALID,
  input  wire                                 m_axi_gmem_AWREADY,
  output wire [C_M_AXI_GMEM_ADDR_WIDTH-1:0]   m_axi_gmem_AWADDR,
  output wire [C_M_AXI_GMEM_ID_WIDTH - 1:0]   m_axi_gmem_AWID,
  output wire [7:0]                           m_axi_gmem_AWLEN,
  output wire [2:0]                           m_axi_gmem_AWSIZE,
  // Tie-off AXI4 transaction options that are not being used.
  output wire [1:0]                           m_axi_gmem_AWBURST,
  output wire [1:0]                           m_axi_gmem_AWLOCK,
  output wire [3:0]                           m_axi_gmem_AWCACHE,
  output wire [2:0]                           m_axi_gmem_AWPROT,
  output wire [3:0]                           m_axi_gmem_AWQOS,
  output wire [3:0]                           m_axi_gmem_AWREGION,
  output wire                                 m_axi_gmem_WVALID,
  input  wire                                 m_axi_gmem_WREADY,
  output wire [C_M_AXI_GMEM_DATA_WIDTH-1:0]   m_axi_gmem_WDATA,
  output wire [C_M_AXI_GMEM_DATA_WIDTH/8-1:0] m_axi_gmem_WSTRB,
  output wire                                 m_axi_gmem_WLAST,
  output wire                                 m_axi_gmem_ARVALID,
  input  wire                                 m_axi_gmem_ARREADY,
  output wire [C_M_AXI_GMEM_ADDR_WIDTH-1:0]   m_axi_gmem_ARADDR,
  output wire [C_M_AXI_GMEM_ID_WIDTH-1:0]     m_axi_gmem_ARID,
  output wire [7:0]                           m_axi_gmem_ARLEN,
  output wire [2:0]                           m_axi_gmem_ARSIZE,
  output wire [1:0]                           m_axi_gmem_ARBURST,
  output wire [1:0]                           m_axi_gmem_ARLOCK,
  output wire [3:0]                           m_axi_gmem_ARCACHE,
  output wire [2:0]                           m_axi_gmem_ARPROT,
  output wire [3:0]                           m_axi_gmem_ARQOS,
  output wire [3:0]                           m_axi_gmem_ARREGION,
  input  wire                                 m_axi_gmem_RVALID,
  output wire                                 m_axi_gmem_RREADY,
  input  wire [C_M_AXI_GMEM_DATA_WIDTH - 1:0] m_axi_gmem_RDATA,
  input  wire                                 m_axi_gmem_RLAST,
  input  wire [C_M_AXI_GMEM_ID_WIDTH - 1:0]   m_axi_gmem_RID,
  input  wire [1:0]                           m_axi_gmem_RRESP,
  input  wire                                 m_axi_gmem_BVALID,
  output wire                                 m_axi_gmem_BREADY,
  input  wire [1:0]                           m_axi_gmem_BRESP,
  input  wire [C_M_AXI_GMEM_ID_WIDTH - 1:0]   m_axi_gmem_BID,

  // AXI4-Lite slave interface
  input  wire                                    s_axi_control_AWVALID,
  output wire                                    s_axi_control_AWREADY,
  input  wire [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]   s_axi_control_AWADDR,
  input  wire                                    s_axi_control_WVALID,
  output wire                                    s_axi_control_WREADY,
  input  wire [C_S_AXI_CONTROL_DATA_WIDTH-1:0]   s_axi_control_WDATA,
  input  wire [C_S_AXI_CONTROL_DATA_WIDTH/8-1:0] s_axi_control_WSTRB,
  input  wire                                    s_axi_control_ARVALID,
  output wire                                    s_axi_control_ARREADY,
  input  wire [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]   s_axi_control_ARADDR,
  output wire                                    s_axi_control_RVALID,
  input  wire                                    s_axi_control_RREADY,
  output wire [C_S_AXI_CONTROL_DATA_WIDTH-1:0]   s_axi_control_RDATA,
  output wire [1:0]                              s_axi_control_RRESP,
  output wire                                    s_axi_control_BVALID,
  input  wire                                    s_axi_control_BREADY,
  output wire [1:0]                              s_axi_control_BRESP,
  output wire                                    interrupt, 

  // AXI4 master interface 
  output wire                                 m_axi_gmem1_AWVALID,
  input  wire                                 m_axi_gmem1_AWREADY,
  output wire [C_M_AXI_GMEM_ADDR_WIDTH-1:0]   m_axi_gmem1_AWADDR,
  output wire [C_M_AXI_GMEM_ID_WIDTH - 1:0]   m_axi_gmem1_AWID,
  output wire [7:0]                           m_axi_gmem1_AWLEN,
  output wire [2:0]                           m_axi_gmem1_AWSIZE,
  // Tie-off AXI4 transaction options that are not being used.
  output wire [1:0]                           m_axi_gmem1_AWBURST,
  output wire [1:0]                           m_axi_gmem1_AWLOCK,
  output wire [3:0]                           m_axi_gmem1_AWCACHE,
  output wire [2:0]                           m_axi_gmem1_AWPROT,
  output wire [3:0]                           m_axi_gmem1_AWQOS,
  output wire [3:0]                           m_axi_gmem1_AWREGION,
  output wire                                 m_axi_gmem1_WVALID,
  input  wire                                 m_axi_gmem1_WREADY,
  output wire [C_M_AXI_GMEM_DATA_WIDTH-1:0]   m_axi_gmem1_WDATA,
  output wire [C_M_AXI_GMEM_DATA_WIDTH/8-1:0] m_axi_gmem1_WSTRB,
  output wire                                 m_axi_gmem1_WLAST,
  output wire                                 m_axi_gmem1_ARVALID,
  input  wire                                 m_axi_gmem1_ARREADY,
  output wire [C_M_AXI_GMEM_ADDR_WIDTH-1:0]   m_axi_gmem1_ARADDR,
  output wire [C_M_AXI_GMEM_ID_WIDTH-1:0]     m_axi_gmem1_ARID,
  output wire [7:0]                           m_axi_gmem1_ARLEN,
  output wire [2:0]                           m_axi_gmem1_ARSIZE,
  output wire [1:0]                           m_axi_gmem1_ARBURST,
  output wire [1:0]                           m_axi_gmem1_ARLOCK,
  output wire [3:0]                           m_axi_gmem1_ARCACHE,
  output wire [2:0]                           m_axi_gmem1_ARPROT,
  output wire [3:0]                           m_axi_gmem1_ARQOS,
  output wire [3:0]                           m_axi_gmem1_ARREGION,
  input  wire                                 m_axi_gmem1_RVALID,
  output wire                                 m_axi_gmem1_RREADY,
  input  wire [C_M_AXI_GMEM_DATA_WIDTH - 1:0] m_axi_gmem1_RDATA,
  input  wire                                 m_axi_gmem1_RLAST,
  input  wire [C_M_AXI_GMEM_ID_WIDTH - 1:0]   m_axi_gmem1_RID,
  input  wire [1:0]                           m_axi_gmem1_RRESP,
  input  wire                                 m_axi_gmem1_BVALID,
  output wire                                 m_axi_gmem1_BREADY,
  input  wire [1:0]                           m_axi_gmem1_BRESP,
  input  wire [C_M_AXI_GMEM_ID_WIDTH - 1:0]   m_axi_gmem1_BID

);

initial begin
   $dumpfile("krnl_merge_rtl_int.vcd");
   $dumpvars(0, krnl_merge_rtl_int);
end

///////////////////////////////////////////////////////////////////////////////
// Local Parameters (constants)
///////////////////////////////////////////////////////////////////////////////
localparam integer LP_NUM_READ_CHANNELS  = 1;
localparam integer LP_LENGTH_WIDTH       = 32;
localparam integer LP_DW_BYTES           = C_M_AXI_GMEM_DATA_WIDTH/8;
localparam integer LP_AXI_BURST_LEN      = 4096/LP_DW_BYTES < 256 ? 4096/LP_DW_BYTES : 256;
localparam integer LP_LOG_BURST_LEN      = $clog2(LP_AXI_BURST_LEN);
localparam integer LP_RD_MAX_OUTSTANDING = 3;
localparam integer LP_RD_FIFO_DEPTH      = LP_AXI_BURST_LEN*(LP_RD_MAX_OUTSTANDING + 1);
localparam integer LP_WR_FIFO_DEPTH      = LP_AXI_BURST_LEN;

localparam integer LP_WR_FIFO_DEPTH2     = 4096; //1024 32768

///////////////////////////////////////////////////////////////////////////////
// Variables
///////////////////////////////////////////////////////////////////////////////
logic areset = 1'b0;  
logic ap_start;
logic ap_start_pulse;
logic ap_start_r;
logic ap_ready;
logic ap_done;
logic ap_idle = 1'b1;
logic [C_M_AXI_GMEM_ADDR_WIDTH-1:0] a;
logic [C_M_AXI_GMEM_ADDR_WIDTH-1:0] b;
logic [C_M_AXI_GMEM_ADDR_WIDTH-1:0] c;
logic [LP_LENGTH_WIDTH-1:0]         length_r;
logic [LP_LENGTH_WIDTH-1:0]         length_r1;

logic read_done;
logic read_done1;
//logic [LP_NUM_READ_CHANNELS-1:0] rd_tvalid;
//logic [LP_NUM_READ_CHANNELS-1:0] rd_tready_n; 
//logic [LP_NUM_READ_CHANNELS-1:0] [C_M_AXI_GMEM_DATA_WIDTH-1:0] rd_tdata;

logic [LP_NUM_READ_CHANNELS-1:0] rd_tvalid_a;
logic [LP_NUM_READ_CHANNELS-1:0] rd_tready_n_a; 
logic [LP_NUM_READ_CHANNELS-1:0] [C_M_AXI_GMEM_DATA_WIDTH-1:0] rd_tdata_a;
logic [LP_NUM_READ_CHANNELS-1:0] rd_tvalid_b;
logic [LP_NUM_READ_CHANNELS-1:0] rd_tready_n_b; 
logic [LP_NUM_READ_CHANNELS-1:0] [C_M_AXI_GMEM_DATA_WIDTH-1:0] rd_tdata_b;


wire [LP_NUM_READ_CHANNELS-1:0] ctrl_rd_fifo_full_a;
wire [LP_NUM_READ_CHANNELS-1:0] ctrl_rd_fifo_full_b;
wire [LP_NUM_READ_CHANNELS-1:0] ctrl_rd_fifo_prog_full_a;
wire [LP_NUM_READ_CHANNELS-1:0] ctrl_rd_fifo_prog_full_b;
logic [LP_NUM_READ_CHANNELS-1:0] [C_M_AXI_GMEM_DATA_WIDTH-1:0] rd_fifo_tdata;

logic                               wr_fifo_tvalid_n;
logic                               wr_fifo_tready; 
logic [C_M_AXI_GMEM_DATA_WIDTH-1:0] wr_fifo_tdata;

logic                               wr_fifo_tvalid_n_a;
logic                               wr_fifo_tready_a; 
logic [C_M_AXI_GMEM_DATA_WIDTH-1:0] wr_fifo_tdata_a;
logic                               wr_fifo_tvalid_n_b;
logic                               wr_fifo_tready_b; 
logic [C_M_AXI_GMEM_DATA_WIDTH-1:0] wr_fifo_tdata_b;

///////////////////////////////////////////////////////////////////////////////
// RTL Logic 
///////////////////////////////////////////////////////////////////////////////
// Tie-off unused AXI protocol features
assign m_axi_gmem_AWID     = {C_M_AXI_GMEM_ID_WIDTH{1'b0}};
assign m_axi_gmem_AWBURST  = 2'b01;
assign m_axi_gmem_AWLOCK   = 2'b00;
assign m_axi_gmem_AWCACHE  = 4'b0011;
assign m_axi_gmem_AWPROT   = 3'b000;
assign m_axi_gmem_AWQOS    = 4'b0000;
assign m_axi_gmem_AWREGION = 4'b0000;
assign m_axi_gmem_ARBURST  = 2'b01;
assign m_axi_gmem_ARLOCK   = 2'b00;
assign m_axi_gmem_ARCACHE  = 4'b0011;
assign m_axi_gmem_ARPROT   = 3'b000;
assign m_axi_gmem_ARQOS    = 4'b0000;
assign m_axi_gmem_ARREGION = 4'b0000;

assign m_axi_gmem1_AWID     = {C_M_AXI_GMEM_ID_WIDTH{1'b0}};
assign m_axi_gmem1_AWBURST  = 2'b01;
assign m_axi_gmem1_AWLOCK   = 2'b00;
assign m_axi_gmem1_AWCACHE  = 4'b0011;
assign m_axi_gmem1_AWPROT   = 3'b000;
assign m_axi_gmem1_AWQOS    = 4'b0000;
assign m_axi_gmem1_AWREGION = 4'b0000;
assign m_axi_gmem1_ARBURST  = 2'b01;
assign m_axi_gmem1_ARLOCK   = 2'b00;
assign m_axi_gmem1_ARCACHE  = 4'b0011;
assign m_axi_gmem1_ARPROT   = 3'b000;
assign m_axi_gmem1_ARQOS    = 4'b0000;
assign m_axi_gmem1_ARREGION = 4'b0000;

// Register and invert reset signal for better timing.
always @(posedge ap_clk) begin 
  areset <= ~ap_rst_n; 
end

// create pulse when ap_start transitions to 1
always @(posedge ap_clk) begin 
  begin 
    ap_start_r <= ap_start;
  end
end

assign ap_start_pulse = ap_start & ~ap_start_r;

// ap_idle is asserted when done is asserted, it is de-asserted when ap_start_pulse 
// is asserted
always @(posedge ap_clk) begin 
  if (areset) begin 
    ap_idle <= 1'b1;
  end
  else begin 
    ap_idle <= ap_done        ? 1'b1 : 
               ap_start_pulse ? 1'b0 : 
                                ap_idle;
  end
end

assign ap_ready = ap_done;

// AXI4-Lite slave
krnl_merge_rtl_control_s_axi #(
  .C_S_AXI_ADDR_WIDTH( C_S_AXI_CONTROL_ADDR_WIDTH ),
  .C_S_AXI_DATA_WIDTH( C_S_AXI_CONTROL_DATA_WIDTH )
) 
inst_krnl_merge_control_s_axi (
  .AWVALID   ( s_axi_control_AWVALID         ) ,
  .AWREADY   ( s_axi_control_AWREADY         ) ,
  .AWADDR    ( s_axi_control_AWADDR          ) ,
  .WVALID    ( s_axi_control_WVALID          ) ,
  .WREADY    ( s_axi_control_WREADY          ) ,
  .WDATA     ( s_axi_control_WDATA           ) ,
  .WSTRB     ( s_axi_control_WSTRB           ) ,
  .ARVALID   ( s_axi_control_ARVALID         ) ,
  .ARREADY   ( s_axi_control_ARREADY         ) ,
  .ARADDR    ( s_axi_control_ARADDR          ) ,
  .RVALID    ( s_axi_control_RVALID          ) ,
  .RREADY    ( s_axi_control_RREADY          ) ,
  .RDATA     ( s_axi_control_RDATA           ) ,
  .RRESP     ( s_axi_control_RRESP           ) ,
  .BVALID    ( s_axi_control_BVALID          ) ,
  .BREADY    ( s_axi_control_BREADY          ) ,
  .BRESP     ( s_axi_control_BRESP           ) ,
  .ACLK      ( ap_clk                        ) ,
  .ARESET    ( areset                        ) ,
  .ACLK_EN   ( 1'b1                          ) ,
  .ap_start  ( ap_start                      ) ,
  .interrupt ( interrupt                     ) ,
  .ap_ready  ( ap_ready                      ) ,
  .ap_done   ( done                       ) , // ap_done
  .ap_idle   ( ap_idle                       ) ,
  .a         ( a[0+:C_M_AXI_GMEM_ADDR_WIDTH] ) ,
  .b         ( b[0+:C_M_AXI_GMEM_ADDR_WIDTH] ) ,
  .c         ( c[0+:C_M_AXI_GMEM_ADDR_WIDTH] ) ,
  .length_r  ( length_r[0+:LP_LENGTH_WIDTH]  ) ,
  .length_r1 ( length_r1[0+:LP_LENGTH_WIDTH] ) ,
  .data0(start),
  .data1(done),
  .data2(vtotal0),
  .data3(vtotal1),
  .data4(mergedFifoFull),
  .data5(ctrl_rd_fifo_full_a),
  .data6(ctrl_rd_fifo_full_b),
  .data7(ctrl_rd_fifo_prog_full_a),
  .data8(ctrl_rd_fifo_prog_full_b),
  .data9(mergedFifoData),
  .data10(mergedFifoWrDataCount),
  .data11(mergedFifoRdDataCount),
  .data12(mergedFifoWrDataCount_a),
  .data13(mergedFifoRdDataCount_a),
  .data14(mergedFifoWrDataCount_b),
  .data15(mergedFifoRdDataCount_b)
);

// AXI4 Read Master
krnl_merge_rtl_axi_read_master #( 
  .C_ADDR_WIDTH       ( C_M_AXI_GMEM_ADDR_WIDTH ) ,
  .C_DATA_WIDTH       ( C_M_AXI_GMEM_DATA_WIDTH ) ,
  .C_ID_WIDTH         ( C_M_AXI_GMEM_ID_WIDTH   ) ,
  .C_LENGTH_WIDTH     ( LP_LENGTH_WIDTH         ) ,
  .C_BURST_LEN        ( LP_AXI_BURST_LEN        ) ,
  .C_LOG_BURST_LEN    ( LP_LOG_BURST_LEN        ) ,
  .C_MAX_OUTSTANDING  ( LP_RD_MAX_OUTSTANDING   )
)
inst_axi_read_master ( 
  .aclk           ( ap_clk                 ) ,
  .areset         ( areset                 ) ,

  .ctrl_start     ( ap_start_pulse         ) ,
  .ctrl_done      ( read_done              ) ,
  .ctrl_offset    ( a                  ) ,
  .ctrl_length    ( length_r               ) ,
  .ctrl_prog_full ( ctrl_rd_fifo_prog_full_a ) ,

  .arvalid        ( m_axi_gmem_ARVALID     ) ,
  .arready        ( m_axi_gmem_ARREADY     ) ,
  .araddr         ( m_axi_gmem_ARADDR      ) ,
  .arid           ( m_axi_gmem_ARID        ) ,
  .arlen          ( m_axi_gmem_ARLEN       ) ,
  .arsize         ( m_axi_gmem_ARSIZE      ) ,
  .rvalid         ( m_axi_gmem_RVALID      ) ,
  .rready         ( m_axi_gmem_RREADY      ) ,
  .rdata          ( m_axi_gmem_RDATA       ) ,
  .rlast          ( m_axi_gmem_RLAST       ) ,
  .rid            ( m_axi_gmem_RID         ) ,
  .rresp          ( m_axi_gmem_RRESP       ) ,

  .m_tvalid       ( rd_tvalid_a              ) ,
  .m_tready       ( ~rd_tready_n_a           ) ,
  .m_tdata        ( rd_tdata_a               ) 
);

krnl_merge_rtl_axi_read_master #( 
  .C_ADDR_WIDTH       ( C_M_AXI_GMEM_ADDR_WIDTH ) ,
  .C_DATA_WIDTH       ( C_M_AXI_GMEM_DATA_WIDTH ) ,
  .C_ID_WIDTH         ( C_M_AXI_GMEM_ID_WIDTH   ) ,
  .C_LENGTH_WIDTH     ( LP_LENGTH_WIDTH         ) ,
  .C_BURST_LEN        ( LP_AXI_BURST_LEN        ) ,
  .C_LOG_BURST_LEN    ( LP_LOG_BURST_LEN        ) ,
  .C_MAX_OUTSTANDING  ( LP_RD_MAX_OUTSTANDING   )
)
inst_axi_read_master1 ( 
  .aclk           ( ap_clk                    ) ,
  .areset         ( areset                    ) ,

  .ctrl_start     ( ap_start_pulse            ) ,
  .ctrl_done      ( read_done1                ) ,
  .ctrl_offset    ( b                         ) ,
  .ctrl_length    ( length_r1                 ) ,
  .ctrl_prog_full ( ctrl_rd_fifo_prog_full_b  ) ,

  .arvalid        ( m_axi_gmem1_ARVALID       ) ,
  .arready        ( m_axi_gmem1_ARREADY       ) ,
  .araddr         ( m_axi_gmem1_ARADDR        ) ,
  .arid           ( m_axi_gmem1_ARID          ) ,
  .arlen          ( m_axi_gmem1_ARLEN         ) ,
  .arsize         ( m_axi_gmem1_ARSIZE        ) ,
  .rvalid         ( m_axi_gmem1_RVALID        ) ,
  .rready         ( m_axi_gmem1_RREADY        ) ,
  .rdata          ( m_axi_gmem1_RDATA         ) ,
  .rlast          ( m_axi_gmem1_RLAST         ) ,
  .rid            ( m_axi_gmem1_RID           ) ,
  .rresp          ( m_axi_gmem1_RRESP         ) ,

  .m_tvalid       ( rd_tvalid_b               ) ,
  .m_tready       ( ~rd_tready_n_b            ) ,
  .m_tdata        ( rd_tdata_b                ) 
);

// xpm_fifo_sync: Synchronous FIFO
// Xilinx Parameterized Macro, Version 2016.4
xpm_fifo_sync # (
  .FIFO_MEMORY_TYPE          ("auto"),           //string; "auto", "block", "distributed", or "ultra";
  .ECC_MODE                  ("no_ecc"),         //string; "no_ecc" or "en_ecc";
  .FIFO_WRITE_DEPTH          (LP_WR_FIFO_DEPTH2),   //positive integer
  //.FIFO_WRITE_DEPTH          (LP_WR_FIFO_DEPTH2*2),   //positive integer
  .WRITE_DATA_WIDTH          (C_M_AXI_GMEM_DATA_WIDTH),               //positive integer
  .WR_DATA_COUNT_WIDTH       ($clog2(LP_WR_FIFO_DEPTH)),               //positive integer, Not used
  .PROG_FULL_THRESH          (LP_WR_FIFO_DEPTH2-1024),               //positive integer, Not used 
  .FULL_RESET_VALUE          (1),                //positive integer; 0 or 1
  .READ_MODE                 ("fwft"),            //string; "std" or "fwft";
  .FIFO_READ_LATENCY         (1),                //positive integer;
  .READ_DATA_WIDTH           (C_M_AXI_GMEM_DATA_WIDTH),               //positive integer
  .RD_DATA_COUNT_WIDTH       ($clog2(LP_WR_FIFO_DEPTH)),               //positive integer, not used
  .PROG_EMPTY_THRESH         (10),               //positive integer, not used 
  .DOUT_RESET_VALUE          ("0"),              //string, don't care
  .WAKEUP_TIME               (0)                 //positive integer; 0 or 2;

) inst_wr_xpm_fifo_sync (
  .sleep         ( 1'b0                   ) ,
  .rst           ( areset                 ) ,
  .wr_clk        ( ap_clk                 ) ,
  .wr_en         ( mergedFifoWrEn         ) ,
  .din           ( mergedFifoData         ) ,
  .full          ( mergedFifoFull         ) ,
  .prog_full     (                        ) ,
  .wr_data_count ( mergedFifoWrDataCount  ) ,
  .overflow      (                        ) ,
  .wr_rst_busy   (                        ) ,
  .rd_en         ( wr_fifo_tready         ) ,
  .dout          ( wr_fifo_tdata          ) ,
  .empty         ( wr_fifo_tvalid_n       ) ,
  .prog_empty    (                        ) ,
  .rd_data_count ( mergedFifoRdDataCount  ) ,
  .underflow     (                        ) ,
  .rd_rst_busy   (                        ) ,
  .injectsbiterr ( 1'b0                   ) ,
  .injectdbiterr ( 1'b0                   ) ,
  .sbiterr       (                        ) ,
  .dbiterr       (                        ) 

);

logic mergedFifoFull;
reg [C_M_AXI_GMEM_DATA_WIDTH-1:0] mergedFifoData;
reg [C_M_AXI_GMEM_DATA_WIDTH-1:0] mergedFifoWrDataCount;
reg [C_M_AXI_GMEM_DATA_WIDTH-1:0] mergedFifoRdDataCount;
reg [C_M_AXI_GMEM_DATA_WIDTH-1:0] mergedFifoRdDataCount_a;
reg [C_M_AXI_GMEM_DATA_WIDTH-1:0] mergedFifoWrDataCount_a;
reg [C_M_AXI_GMEM_DATA_WIDTH-1:0] mergedFifoRdDataCount_b;
reg [C_M_AXI_GMEM_DATA_WIDTH-1:0] mergedFifoWrDataCount_b;
reg mergedFifoWrEn;
reg FifoRdEn_a;
reg FifoRdEn_b;

wire done;
logic start;

logic end_data_ingestion;
logic end_data_ingestion1;
logic vstart[1:0];
logic vstart0, vstart1;
logic latch0, latch1;
logic l_read_done0, l_read_done1;

assign vstart[0] = (m_axi_gmem_RLAST) ? 1'b1 : 1'b0;
assign vstart[1] = (m_axi_gmem1_RLAST) ? 1'b1 : 1'b0;
assign vstart0 = !wr_fifo_tvalid_n_a;
assign vstart1 = !wr_fifo_tvalid_n_b;

assign m_axi_gmem_RREADY = 1'b1; //ap_start

logic vbegin0;
logic vbegin1;

logic [31:0] vtotal[1:0];
logic [31:0] vtotal0;
logic [31:0] vtotal1;
always @(posedge ap_clk)
begin
    if (areset)
    begin
      vtotal[0] = 0;
      vtotal[1] = 0;
      vbegin0 = 1'b0;
      vbegin1 = 1'b0;
      l_read_done0 = 1'b0;
      l_read_done1 = 1'b0;
    end
    else
    begin
      if (m_axi_gmem_RVALID)
      begin
        vtotal[0] = vtotal[0] + 1;
        if(vbegin0 == 1'b0)
        begin
          vbegin0 = 1'b1;
        end
      end
      if (m_axi_gmem1_RVALID)
      begin
        vtotal[1] = vtotal[1] + 1;
        if(vbegin1 == 1'b0)
        begin
          vbegin1 = 1'b1;
        end
      end
      if(read_done && ~l_read_done0)
        l_read_done0 = 1'b1;
      if(read_done1 && ~l_read_done1)
        l_read_done1 = 1'b1;
    end
end
assign vtotal0 = vtotal[0];
assign vtotal1 = vtotal[1];

assign end_data_ingestion = l_read_done0;
assign end_data_ingestion1 = l_read_done1;

always_ff @(posedge ap_clk) 
begin
    if (areset)
    begin
        latch0 <= 0;
        latch1 <= 0;
    end
    else
    begin
        latch0 <= latch0 | vstart0;
        latch1 <= latch1 | vstart1;
    end
end
assign start = latch0 & latch1;

krnl_merge_rtl_merger #(
  .C_DATA_WIDTH(C_S_AXI_CONTROL_DATA_WIDTH)
)
merger(
.aclk(ap_clk),
.areset(areset),
.start(start),
.FINISH(done),
.wr_fifo_tvalid_n_a(wr_fifo_tvalid_n_a),
.wr_fifo_tdata_a(wr_fifo_tdata_a),
.wr_fifo_tvalid_n_b(wr_fifo_tvalid_n_b),
.wr_fifo_tdata_b(wr_fifo_tdata_b),
.MERGED_FIFO_FULL(mergedFifoFull),
.MERGED_FIFO_Data(mergedFifoData),
.MERGED_FIFO_WrEn(mergedFifoWrEn),
.MERGED_FIFO1_RdEn(FifoRdEn_a),
.MERGED_FIFO2_RdEn(FifoRdEn_b)
);

// xpm_fifo_sync: Synchronous FIFO
// Xilinx Parameterized Macro, Version 2016.4
xpm_fifo_sync # (
  .FIFO_MEMORY_TYPE          ("auto"),           //string; "auto", "block", "distributed", or "ultra";
  .ECC_MODE                  ("no_ecc"),         //string; "no_ecc" or "en_ecc";
  .FIFO_WRITE_DEPTH          (LP_WR_FIFO_DEPTH2*2),   //positive integer
  .WRITE_DATA_WIDTH          (C_M_AXI_GMEM_DATA_WIDTH),               //positive integer
  .WR_DATA_COUNT_WIDTH       ($clog2(LP_WR_FIFO_DEPTH)),               //positive integer, Not used
  .PROG_FULL_THRESH          (LP_WR_FIFO_DEPTH2*2-1024),               //positive integer, Not used 
  .FULL_RESET_VALUE          (1),                //positive integer; 0 or 1
  .READ_MODE                 ("fwft"),            //string; "std" or "fwft";
  .FIFO_READ_LATENCY         (1),                //positive integer;
  .READ_DATA_WIDTH           (C_M_AXI_GMEM_DATA_WIDTH),               //positive integer
  .RD_DATA_COUNT_WIDTH       ($clog2(LP_WR_FIFO_DEPTH)),               //positive integer, not used
  .PROG_EMPTY_THRESH         (10), //10              //positive integer, not used 
  .DOUT_RESET_VALUE          ("0"),              //string, don't care
  .WAKEUP_TIME               (0)                 //positive integer; 0 or 2;

) inst_wr_xpm_fifo_sync_a (
  .sleep         ( 1'b0                     ) ,
  .rst           ( areset                   ) ,
  .wr_clk        ( ap_clk                   ) ,
  .wr_en         ( rd_tvalid_a              ) , 
  .din           ( rd_tdata_a               ) , 
  .full          ( ctrl_rd_fifo_full_a      ) , 
  .prog_full     ( ctrl_rd_fifo_prog_full_a ) ,
  .wr_data_count ( mergedFifoWrDataCount_a  ) ,
  .overflow      (                          ) ,
  .wr_rst_busy   (                          ) ,
  .rd_en         ( FifoRdEn_a               ) , 
  .dout          ( wr_fifo_tdata_a          ) ,
  .empty         ( wr_fifo_tvalid_n_a       ) ,
  .prog_empty    (                          ) ,
  .rd_data_count ( mergedFifoRdDataCount_a  ) ,
  .underflow     (                          ) ,
  .rd_rst_busy   (                          ) ,
  .injectsbiterr ( 1'b0                     ) ,
  .injectdbiterr ( 1'b0                     ) ,
  .sbiterr       (                          ) ,
  .dbiterr       (                          ) 
);

xpm_fifo_sync # (
  .FIFO_MEMORY_TYPE          ("auto"),           //string; "auto", "block", "distributed", or "ultra";
  .ECC_MODE                  ("no_ecc"),         //string; "no_ecc" or "en_ecc";
  .FIFO_WRITE_DEPTH          (LP_WR_FIFO_DEPTH2*2),   //positive integer
  .WRITE_DATA_WIDTH          (C_M_AXI_GMEM_DATA_WIDTH),               //positive integer
  .WR_DATA_COUNT_WIDTH       ($clog2(LP_WR_FIFO_DEPTH)),               //positive integer, Not used
  .PROG_FULL_THRESH          (LP_WR_FIFO_DEPTH2*2-1024),               //positive integer, Not used 
  .FULL_RESET_VALUE          (1),                //positive integer; 0 or 1
  .READ_MODE                 ("fwft"),            //string; "std" or "fwft";
  .FIFO_READ_LATENCY         (1),                //positive integer;
  .READ_DATA_WIDTH           (C_M_AXI_GMEM_DATA_WIDTH),               //positive integer
  .RD_DATA_COUNT_WIDTH       ($clog2(LP_WR_FIFO_DEPTH)),               //positive integer, not used
  .PROG_EMPTY_THRESH         (10),  //10             //positive integer, not used 
  .DOUT_RESET_VALUE          ("0"),              //string, don't care
  .WAKEUP_TIME               (0)                 //positive integer; 0 or 2;

) inst_wr_xpm_fifo_sync_b (
  .sleep         ( 1'b0                     ) ,
  .rst           ( areset                   ) ,
  .wr_clk        ( ap_clk                   ) ,
  .wr_en         ( rd_tvalid_b              ) , 
  .din           ( rd_tdata_b               ) , 
  .full          ( ctrl_rd_fifo_full_b      ) ,
  .prog_full     ( ctrl_rd_fifo_prog_full_b ) ,
  .wr_data_count ( mergedFifoWrDataCount_b  ) ,
  .overflow      (                          ) ,
  .wr_rst_busy   (                          ) ,
  .rd_en         ( FifoRdEn_b               ) ,
  .dout          ( wr_fifo_tdata_b          ) ,
  .empty         ( wr_fifo_tvalid_n_b       ) ,
  .prog_empty    (                          ) ,
  .rd_data_count ( mergedFifoRdDataCount_b  ) ,
  .underflow     (                          ) ,
  .rd_rst_busy   (                          ) ,
  .injectsbiterr ( 1'b0                     ) ,
  .injectdbiterr ( 1'b0                     ) ,
  .sbiterr       (                          ) ,
  .dbiterr       (                          ) 
);

// AXI4 Write Master
krnl_merge_rtl_axi_write_master #( 
  .C_ADDR_WIDTH       ( C_M_AXI_GMEM_ADDR_WIDTH ) ,
  .C_DATA_WIDTH       ( C_M_AXI_GMEM_DATA_WIDTH ) ,
  .C_MAX_LENGTH_WIDTH ( LP_LENGTH_WIDTH     ) ,
  .C_BURST_LEN        ( LP_AXI_BURST_LEN        ) ,
  .C_LOG_BURST_LEN    ( LP_LOG_BURST_LEN        ) 
)
inst_axi_write_master ( 
  .aclk        ( ap_clk             ) ,
  .areset      ( areset             ) ,

  .ctrl_start  ( ap_start_pulse     ) ,
  .ctrl_offset ( c                  ) ,
  .ctrl_length (length_r + length_r1) ,
  .ctrl_done   ( ap_done            ) ,

  .awvalid     ( m_axi_gmem_AWVALID ) ,
  .awready     ( m_axi_gmem_AWREADY ) ,
  .awaddr      ( m_axi_gmem_AWADDR  ) ,
  .awlen       ( m_axi_gmem_AWLEN   ) ,
  .awsize      ( m_axi_gmem_AWSIZE  ) ,

  .s_tvalid    ( ~wr_fifo_tvalid_n  ) , 
  .s_tready    ( wr_fifo_tready     ) ,
  .s_tdata     ( wr_fifo_tdata      ) ,

  .wvalid      ( m_axi_gmem_WVALID  ) ,
  .wready      ( m_axi_gmem_WREADY  ) ,
  .wdata       ( m_axi_gmem_WDATA   ) ,
  .wstrb       ( m_axi_gmem_WSTRB   ) ,
  .wlast       ( m_axi_gmem_WLAST   ) ,

  .bvalid      ( m_axi_gmem_BVALID  ) ,
  .bready      ( m_axi_gmem_BREADY  ) ,
  .bresp       ( m_axi_gmem_BRESP   ) 
);

endmodule : krnl_merge_rtl_int

`default_nettype wire
