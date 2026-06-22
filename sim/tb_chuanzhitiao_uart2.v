`timescale 1ns/1ps
// Two consecutive datasets over UART WITHOUT reset between them.
// Reproduces the "second dataset fails unless you reset" bug: after the first
// answer the firmware sits in the display loop (slow UART poll); a back-to-back
// second dataset overruns the FIFO-less RX register and desyncs.
//   Dataset A: 2x2 [[0,5],[7,0]]            -> 12
//   Dataset B: 3x3 [[0,3,9],[2,8,5],[5,7,0]]-> 34
module tb_chuanzhitiao_uart2;
    reg clk = 0, reset = 1;
    wire MemRead, MemWrite;
    wire [31:0] MemAddr, MemWriteData, MemReadData;
    wire [11:0] digi;
    reg  rxd = 1'b1;
    wire txd;
    localparam integer DIVB = 10;

    PipelineCPU cpu(.clk(clk),.reset(reset),.MemRead(MemRead),.MemWrite(MemWrite),
        .MemAddr(MemAddr),.MemWriteData(MemWriteData),.MemReadData(MemReadData));
    MemBus #(.CLK_FREQ(10000),.BAUD(1000)) bus(.clk(clk),.reset(reset),
        .MemRead(MemRead),.MemWrite(MemWrite),.Address(MemAddr),.WriteData(MemWriteData),
        .ReadData(MemReadData),.digi(digi),.uart_txd(txd),.uart_rxd(rxd));

    always #5 clk = ~clk;

    task send_byte(input [7:0] b);
        integer k;
        begin
            rxd = 1'b0; repeat (DIVB) @(posedge clk);
            for (k = 0; k < 8; k = k + 1) begin rxd = b[k]; repeat (DIVB) @(posedge clk); end
            rxd = 1'b1; repeat (DIVB) @(posedge clk);
            repeat (DIVB) @(posedge clk);
        end
    endtask

    task recv_word(output [31:0] w);
        integer j, k;
        reg [7:0] b;
        begin
            w = 0;
            for (j = 0; j < 4; j = j + 1) begin
                @(negedge txd);
                repeat (DIVB + DIVB/2) @(posedge clk);
                for (k = 0; k < 8; k = k + 1) begin b[k] = txd; repeat (DIVB) @(posedge clk); end
                w = (w << 8) | b;            // MSB first
            end
        end
    endtask

    reg [31:0] rA, rB;

    initial begin
        #12 reset = 0;
        repeat (20) @(posedge clk);

        // dataset A (2x2 -> 12)
        send_byte(2); send_byte(2);
        send_byte(0); send_byte(5); send_byte(7); send_byte(0);
        recv_word(rA);
        $display("RESULT_A=%0d", $signed(rA));

        // dataset B (3x3 -> 34), sent immediately while board is in display loop
        send_byte(3); send_byte(3);
        send_byte(0); send_byte(3); send_byte(9);
        send_byte(2); send_byte(8); send_byte(5);
        send_byte(5); send_byte(7); send_byte(0);
        recv_word(rB);
        $display("RESULT_B=%0d", $signed(rB));

        if ($signed(rA) == 12 && $signed(rB) == 34) $display("PASS tb_uart2");
        else $display("FAIL tb_uart2 (A=%0d exp 12, B=%0d exp 34)", $signed(rA), $signed(rB));
        $finish;
    end

    initial begin
        #30000000;
        $display("TIMEOUT (A=%0d B=%0d)", $signed(rA), $signed(rB));
        $finish;
    end
endmodule
