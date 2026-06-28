`timescale 1ns/1ps
// CPI measurement testbench — directly feeds UART grid data and counts
// clock cycles + instructions committed (WB stage writes).
// Uses the same fast-UART approach as tb_chuanzhitiao_uart.v.
module tb_cpu_cpi_measure;
    reg clk = 0, reset = 1;
    wire MemRead, MemWrite;
    wire [31:0] MemAddr, MemWriteData, MemReadData;
    wire [11:0] digi;
    reg  rxd = 1'b1;
    wire txd;

    localparam integer DIVB = 10;  // UART cycles-per-bit (sim only, fast)

    PipelineCPU cpu(.clk(clk),.reset(reset),.MemRead(MemRead),.MemWrite(MemWrite),
        .MemAddr(MemAddr),.MemWriteData(MemWriteData),.MemReadData(MemReadData));
    MemBus #(.CLK_FREQ(10000),.BAUD(1000)) bus(.clk(clk),.reset(reset),
        .MemRead(MemRead),.MemWrite(MemWrite),.Address(MemAddr),.WriteData(MemWriteData),
        .ReadData(MemReadData),.digi(digi),.uart_txd(txd),.uart_rxd(rxd));

    always #5 clk = ~clk;

    // ---- cycle & instruction counters ----
    integer cycles = 0, insts = 0, algo_done = 0;
    always @(posedge clk) if (!reset) begin
        cycles = cycles + 1;
        if (cpu.wb_RegWrite) insts = insts + 1;     // count committed instructions
        if (!algo_done && MemWrite && MemAddr == 32'h00003FF8) begin
            algo_done = 1;
            $display("ALGO_DONE: cycles=%0d insts=%0d scratch=0x%h",
                     cycles, insts, MemWriteData);
        end
    end

    // ---- UART send/recv tasks (same as tb_chuanzhitiao_uart.v) ----
    reg  [7:0] inb [0:1023];
    integer total, i;
    reg  [7:0] rb;
    reg  [31:0] result;

    task send_byte(input [7:0] b);
        integer k;
        begin
            rxd = 1'b0; repeat (DIVB) @(posedge clk);
            for (k = 0; k < 8; k = k + 1) begin
                rxd = b[k]; repeat (DIVB) @(posedge clk);
            end
            rxd = 1'b1; repeat (DIVB) @(posedge clk);
            repeat (DIVB) @(posedge clk);
        end
    endtask

    task recv_byte(output [7:0] b);
        integer k;
        begin
            @(negedge txd);
            repeat (DIVB + DIVB/2) @(posedge clk);
            for (k = 0; k < 8; k = k + 1) begin
                b[k] = txd; repeat (DIVB) @(posedge clk);
            end
        end
    endtask

    initial begin
        for (i = 0; i < 1024; i = i + 1) inb[i] = 8'h00;
        $readmemh(`UART_IN, inb);
        total = 2 + inb[0] * inb[1];
        #12 reset = 0;
        repeat (20) @(posedge clk);
        for (i = 0; i < total; i = i + 1) send_byte(inb[i]);
        recv_byte(rb); result[31:24] = rb;
        recv_byte(rb); result[23:16] = rb;
        recv_byte(rb); result[15:8]  = rb;
        recv_byte(rb); result[7:0]   = rb;
        // Wait for algorithm to finish (scratch write)
        repeat (10000) @(posedge clk);
        $display("FINAL: result=%0d cycles=%0d insts=%0d CPI=%.2f",
                 $signed(result), cycles, insts, cycles * 1.0 / insts);
        $finish;
    end

    initial begin
        #5000000;
        $display("TIMEOUT cycles=%0d insts=%0d", cycles, insts);
        $finish;
    end
endmodule
