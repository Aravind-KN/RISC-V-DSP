////////////////////////////////////////////////////////////
// Stage 2: Execute
////////////////////////////////////////////////////////////

module execute 
    #(
        parameter  [31:0]    RESET   = 32'h0000_0000
    ) 
    (   input clk,
        input reset
    );
//////////////// Including OPCODES ////////////////////////////

`include "opcode.vh"

    reg [15:0] buf_A_in; // 16-bit input A
    reg [15:0] buf_B_in; // 16-bit input B
    reg [3:0] seq_A_no;
    reg [3:0] seq_B_no;
    //reg clk;
    //reg rst;
    reg wr_A_en;
    reg wr_B_en;
    wire [31:0] result;
    wire rcv_bit;
    reg [3:0] count_A; 
    reg [3:0] count_B; 
    reg conv_reset;
    
    integer i, j, latency, latency_total;
    integer fp_r, fp_i, int_r, int_i;
    integer SNR_ratio;

parameter FFT_size		= 64;
parameter dataset		= 1;
parameter IN_width		= 12;
parameter OUT_width		= 16;
parameter latency_limit		= 68;

parameter cycle			= 10.0;

reg rst_n, in_valid;
wire out_valid;
reg signed [IN_width-1:0] din_r, din_i;
wire signed [OUT_width-1:0] dout_r, dout_i;
reg signed [OUT_width:0] gold_r, gold_i;

reg signed [31:0] noise, signal;
reg [31:0] noise_energy, signal_energy;







// Selecting the first and second operands of ALU unit

assign pipe.alu_operand1         = pipe.reg_rdata1;                     //First operand gets data from register file
assign pipe.alu_operand2         = (pipe.immediate_sel) ? pipe.execute_immediate : pipe.reg_rdata2;     //Second operand gats data either from immediate or register file
assign pipe.result_subs[32: 0]   = {pipe.alu_operand1[31], pipe.alu_operand1} - {pipe.alu_operand2[31], pipe.alu_operand2};     //Substraction Signed
assign pipe.result_subu[32: 0]   = {1'b0, pipe.alu_operand1} - {1'b0, pipe.alu_operand2};           //Substraction Unsigned
assign pipe.write_address        = pipe.alu_operand1 + pipe.execute_immediate;          //Calculating write address for data memory
assign pipe.branch_stall         = pipe.wb_branch_nxt || pipe.wb_branch;                //Calculating branch stall value

//Calculating next PC value

always @(*) 
begin
    pipe.next_pc      = pipe.fetch_pc + 4;
    pipe.branch_taken = !pipe.branch_stall;
        case(1'b1)
        pipe.jal   : pipe.next_pc = pipe.pc + pipe.execute_immediate;
        pipe.jalr  : pipe.next_pc = pipe.alu_operand1 + pipe.execute_immediate;
        pipe.branch: begin
            case(pipe.alu_operation) 
                BEQ : begin
                            pipe.next_pc = (pipe.result_subs[32: 0] == 'd0) ? pipe.pc + pipe.execute_immediate : pipe.fetch_pc + 4;
                            if (pipe.result_subs[32: 0] != 'd0) 
                                pipe.branch_taken = 1'b0;
                         end
                BNE : begin
                            pipe.next_pc = (pipe.result_subs[32: 0] != 'd0) ? pipe.pc + pipe.execute_immediate : pipe.fetch_pc + 4;
                            if (pipe.result_subs[32: 0] == 'd0) 
                                pipe.branch_taken = 1'b0;
                         end
                BLT : begin
                            pipe.next_pc = pipe.result_subs[32] ? pipe.pc + pipe.execute_immediate : pipe.fetch_pc + 4;
                            if (!pipe.result_subs[32]) 
                                pipe.branch_taken = 1'b0;
                         end
                BGE : begin
                            pipe.next_pc = !pipe.result_subs[32] ? pipe.pc + pipe.execute_immediate : pipe.fetch_pc + 4;
                            if (pipe.result_subs[32]) 
                                pipe.branch_taken = 1'b0;
                         end
                BLTU: begin
                            pipe.next_pc = pipe.result_subu[32] ? pipe.pc + pipe.execute_immediate : pipe.fetch_pc + 4;
                            if (!pipe.result_subu[32]) 
                                pipe.branch_taken = 1'b0;
                         end
                BGEU: begin
                            pipe.next_pc = !pipe.result_subu[32] ? pipe.pc + pipe.execute_immediate : pipe.fetch_pc + 4;
                            if (pipe.result_subu[32]) 
                                pipe.branch_taken = 1'b0;
                         end
                default: begin
                         pipe.next_pc    = pipe.fetch_pc;
                         end
            endcase
        end
        default  : begin
                   pipe.next_pc          = pipe.fetch_pc + 4;
                   pipe.branch_taken     = 1'b0;
                   end
    endcase
end

    parameter a_c = 15;
    parameter b_c = 15;

    reg signed[15:0]A,B;
    
    wire signed[31:0]prod;
    reg en=1'b1;
    wire done;
    
    
Convolution conv( .buf_A_in(buf_A_in), .buf_B_in(buf_B_in), .seq_A_no(seq_A_no), .seq_B_no(seq_B_no), .clk(clk), .rst(conv_reset), 
                .wr_A_en(wr_A_en), .wr_B_en(wr_B_en), .result(result), .rcv_bit(rcv_bit));

Top_PPA mult_inst(.A(A),.B(B),.clk(clk),.product(prod),.done(done),.en(en));

always@(posedge clk)
begin
        case(pipe.alu_operation)
            MUL :
                begin
                    A= pipe.alu_operand1;
                    B= pipe.alu_operand2;
                end
         endcase
end


initial begin

    conv_reset=1'b1;
    seq_A_no=0;
    seq_B_no=0;
    buf_A_in =0;
    buf_B_in=0;
    wr_A_en  =0; 
    wr_B_en =0;
    count_A =0;
    count_B =0;


end

always@(posedge clk)
begin
        case(pipe.alu_operation)
            FEED :
                begin
                    conv_reset=1'b0;
                end
         endcase
end
                
always@(posedge clk)
begin
    if(!conv_reset && (count_A != a_c))
        begin
        count_A =count_A + 1;
        buf_A_in = pipe.alu_operand1;
        wr_A_en  =1;      
        seq_A_no=a_c;
        


        end
        else begin
                wr_A_en  =0; 

 end
end



always@(posedge clk)
begin
    if(!conv_reset && (count_B != b_c))
        begin
        count_B =count_B + 1 ;
        if(pipe.alu_operation==FEED)
            begin
                buf_B_in = pipe.alu_operand2;
            end 
        seq_B_no=b_c;
        wr_B_en =1;

        end
        else begin
                
 wr_B_en =0;
 end
end

always@(pipe.result) begin

	rst_n = 0;
	in_valid = 0;
	
	if(pipe.result==6'd42)
	begin
	for(i=0;i<dataset;i=i+1) begin
		
		signal_energy = 0;
		noise_energy = 0;
		
		case(i)
	   0: begin 
			fp_r = $fopen("IN_real_pattern01.txt", "r");
			fp_i = $fopen("IN_imag_pattern01.txt", "r");
		end
		endcase


		@(negedge clk);
		@(negedge clk) rst_n = 1;
		@(negedge clk) rst_n = 1;
		@(negedge clk);

		for(j=0;j<FFT_size;j=j+1) begin

			@(negedge clk);
			in_valid = 1;
			int_r = $fscanf(fp_r, "%d", din_r);
			int_i = $fscanf(fp_i, "%d", din_i);

		end
		@(negedge clk) in_valid = 0;


		latency = 0;
		while(!out_valid) begin
			@(negedge clk);
			
		end

		for(j=0;j<FFT_size;j=j+1) begin
			@(negedge clk);
		end

		
	end
	$finish;
	end

end
//Calculating ALU result depending on the opcode

always @(*) 
begin
    case(1'b1)
        pipe.mem_write:   pipe.result          = pipe.alu_operand2;
        pipe.jal:         pipe.result          = pipe.pc + 4;
        pipe.jalr:        pipe.result          = pipe.pc + 4;
        pipe.lui:         pipe.result          = pipe.execute_immediate;
        pipe.alu:
            case(pipe.alu_operation)
                ADD : if (pipe.arithsubtype == 1'b0)
                            pipe.result  = pipe.alu_operand1 + pipe.alu_operand2;
                         else
                            pipe.result  = pipe.alu_operand1 - pipe.alu_operand2;
                //MUL : pipe.result     = pipe.result_subs[32] ? 'd1 : 'd0;
                
                FEED : pipe.result=32'b1;
                FFT  : pipe.result=pipe.alu_operand1 + pipe.alu_operand2;
                SR  : if (pipe.arithsubtype == 1'b0)
                            pipe.result  = pipe.alu_operand1 >>> pipe.alu_operand2;
                         else
                            pipe.result  = $signed(pipe.alu_operand1) >>> pipe.alu_operand2;
                OR  : pipe.result     = pipe.alu_operand1 | pipe.alu_operand2;
                AND : pipe.result     = pipe.alu_operand1 & pipe.alu_operand2;
        
                default: pipe.result     = 'hx;
            endcase
        default: pipe.result = 'hx;
    endcase
end

always @(posedge clk or negedge reset) 
begin
    if (!reset) 
    begin
        pipe.fetch_pc <= RESET;
    end 
    else if (!pipe.stall_read) 
    begin
        pipe.fetch_pc            <= (pipe.branch_stall) ? pipe.fetch_pc + 4 : pipe.next_pc;     //Assigning next PC value
    end
end



FFT_64 FFT_CORE(
.clk(clk),
.rst_n(rst_n),
.in_valid(in_valid),
.din_r(din_r),
.din_i(din_i),
.out_valid(out_valid),
.dout_r(dout_r),
.dout_i(dout_i)
);

//Preparing output for writeback stage

always @(posedge clk or negedge reset) 
begin
    if (!reset) 
    begin
        pipe.wb_result               <= 32'h0;
        pipe.wb_mem_write            <= 1'b0;
        pipe.wb_alu_to_reg           <= 1'b0;
        pipe.wb_dest_reg_sel         <= 5'h0;
        pipe.wb_branch               <= 1'b0;
        pipe.wb_branch_nxt           <= 1'b0;
        pipe.wb_mem_to_reg           <= 1'b0;
        pipe.wb_read_address         <= 2'h0;
        pipe.wb_alu_operation        <= 3'h0;
    end 
    else if (!pipe.stall_read) 
    begin
        pipe.wb_result               <= pipe.result;
        pipe.wb_mem_write            <= pipe.mem_write && !pipe.branch_stall;
        pipe.wb_alu_to_reg           <= pipe.alu | pipe.lui | pipe.jal | pipe.jalr | pipe.mem_to_reg;
        pipe.wb_dest_reg_sel         <= pipe.dest_reg_sel;
        pipe.wb_branch               <= pipe.branch_taken;
        pipe.wb_branch_nxt           <= pipe.wb_branch;
        pipe.wb_mem_to_reg           <= pipe.mem_to_reg;
        pipe.wb_read_address         <= pipe.dmem_read_address[1:0];
        pipe.wb_alu_operation        <= pipe.alu_operation;
    end
end

endmodule 