`timescale 1ns/1ps
module krnl_merge_rtl_merger #(
  parameter integer C_DATA_WIDTH   = 32 // Data width of both input and output data
)
(
  input wire			aclk,
  input wire			areset,
  
  input wire			start,
  output wire			FINISH,

  input wire 			wr_fifo_tvalid_n_a,
  input wire [C_DATA_WIDTH-1:0]	wr_fifo_tdata_a,

  input wire 			wr_fifo_tvalid_n_b,
  input wire [C_DATA_WIDTH-1:0] wr_fifo_tdata_b,
    
  input 			MERGED_FIFO_FULL,
  output [C_DATA_WIDTH-1:0] 	MERGED_FIFO_Data,
  output 			MERGED_FIFO_WrEn,
  output 			MERGED_FIFO1_RdEn,
  output 			MERGED_FIFO2_RdEn
  
);

localparam  IDLE  = 'd0,
            COMPARE = 'd1,
            FLUSH = 'd2,
            WRITE = 'd3,
            DONE = 'd4;

reg [C_DATA_WIDTH-1:0] mergedFifoData;
reg mergedFifoWrEn;
reg fifo1RdEn;
reg fifo2RdEn;
reg [2:0] state;
reg done;

assign MERGED_FIFO_Data = mergedFifoData;
assign MERGED_FIFO_WrEn = mergedFifoWrEn;
assign MERGED_FIFO1_RdEn = fifo1RdEn;
assign MERGED_FIFO2_RdEn = fifo2RdEn;

assign FINISH = done;

always @(posedge aclk)
begin
    if(areset) //reset
    begin
        state <= IDLE;
        fifo1RdEn <= 1'b0;
        fifo2RdEn <= 1'b0;
        mergedFifoWrEn <= 1'b0;
        done <= 1'b0;
    end
    else
    begin
        case(state)
            IDLE:begin
                if(start)
                begin
                    state <= COMPARE;
                end
            end
            COMPARE:begin 
                if(!wr_fifo_tvalid_n_a & !wr_fifo_tvalid_n_b)
                begin
                    if(wr_fifo_tdata_a < wr_fifo_tdata_b)
                    begin
                        mergedFifoData <= wr_fifo_tdata_a;
                        mergedFifoWrEn <= 1'b1;
                        fifo1RdEn <= 1'b1;
                    end
                    else
                    begin
                        mergedFifoData <= wr_fifo_tdata_b;
                        mergedFifoWrEn <= 1'b1;  
                        fifo2RdEn <= 1'b1;                      
                    end
                    state <= WRITE;
                 end
                 else if(wr_fifo_tvalid_n_a & wr_fifo_tvalid_n_b)
                 begin
                    state <= DONE;
                 end
                 else if(wr_fifo_tvalid_n_a)
                 begin
                    state <= FLUSH;
                    fifo2RdEn <= 1'b1;
                 end
                 else if(wr_fifo_tvalid_n_b)
                 begin
                    state <= FLUSH;
                    fifo1RdEn <= 1'b1;
                 end
            end
            FLUSH:begin
                if(wr_fifo_tvalid_n_a & wr_fifo_tvalid_n_b)
                begin
                     state <= DONE;
                     fifo1RdEn <= 1'b0;
                     fifo2RdEn <= 1'b0;
                     mergedFifoWrEn <= 1'b0; 
                end
                else if(wr_fifo_tvalid_n_a)
                begin
                    fifo2RdEn <= 1'b1;
                    mergedFifoWrEn <= 1'b1;
                    mergedFifoData <= wr_fifo_tdata_b;
                end
                else if(wr_fifo_tvalid_n_b)
                begin
                    fifo1RdEn <= 1'b1;
                    mergedFifoWrEn <= 1'b1;
                    mergedFifoData <= wr_fifo_tdata_a;
                end
            end
            WRITE:begin
                fifo1RdEn <= 1'b0;
                fifo2RdEn <= 1'b0;
                mergedFifoWrEn <= 1'b0;
                state <= COMPARE;
            end 
            DONE:begin
                done <= 1'b1;
                if(!start)
                begin
                    done <= 1'b0;
                    state <= IDLE;
                end
            end
       endcase
    end
end

endmodule
