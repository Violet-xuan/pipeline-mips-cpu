`timescale 1ns/1ps
// UART-driven integration test for the bidirectional 传纸条 firmware.
// Sends a dataset (m, n, grid bytes) into uart_rxd, then receives the 4-byte
// big-endian result from uart_txd and prints RESULT=<signed>.
// Dataset bytes are read from `UART_IN (hex, one byte/line): m, n, grid...
module tb_chuanzhitiao_uart;
    reg clk = 0, reset = 1;
    wire MemRead, MemWrite;
    wire [31:0] MemAddr, MemWriteData, MemReadData;
    wire [11:0] digi;
    reg  rxd = 1'b1;
    wire txd;

    // UART cycles-per-bit for SIM ONLY (fast). Must equal CLK_FREQ/BAUD below.
    localparam integer DIVB = 10;

    PipelineCPU cpu(.clk(clk),.reset(reset),.MemRead(MemRead),.MemWrite(MemWrite),
        .MemAddr(MemAddr),.MemWriteData(MemWriteData),.MemReadData(MemReadData));
    MemBus #(.CLK_FREQ(10000),.BAUD(1000)) bus(.clk(clk),.reset(reset),
        .MemRead(MemRead),.MemWrite(MemWrite),.Address(MemAddr),.WriteData(MemWriteData),
        .ReadData(MemReadData),.digi(digi),.uart_txd(txd),.uart_rxd(rxd));

    always #5 clk = ~clk;

    reg  [7:0] inb [0:1023];
    integer total, i;
    reg  [7:0] rb;
    reg  [31:0] result;

    task send_byte(input [7:0] b);
        integer k;
        begin
            rxd = 1'b0; repeat (DIVB) @(posedge clk);          // start
            for (k = 0; k < 8; k = k + 1) begin
                rxd = b[k]; repeat (DIVB) @(posedge clk);       // data LSB first
            end
            rxd = 1'b1; repeat (DIVB) @(posedge clk);          // stop
            repeat (DIVB) @(posedge clk);                       // inter-byte gap
        end
    endtask

    task recv_byte(output [7:0] b);
        integer k;
        begin
            @(negedge txd);                                     // start bit
            repeat (DIVB + DIVB/2) @(posedge clk);              // center of bit0
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
        $display("RESULT=%0d", $signed(result));
        $display("SCRATCH=%0d", $signed(bus.dmem.RAM[4094]));
        $finish;
    end

    initial begin
        #5000000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
