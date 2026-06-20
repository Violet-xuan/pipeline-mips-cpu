`timescale 1ns/1ps
// Self-checking UART test. Small DIV (CLK_FREQ/BAUD = 10 cycles/bit) for fast sim.
module tb_uart;
	localparam CLK_FREQ = 100, BAUD = 10;   // DIV = 10 clk/bit
	localparam BITNS = 10 * 10;             // 10 clk * 10ns period = 100ns per bit

	reg        clk = 0, reset = 1;
	reg        tx_start = 0, rxd_read = 0;
	reg  [7:0] tx_data = 0;
	reg        rxd = 1;
	wire [7:0] rx_data;
	wire       tx_busy, tx_done, rx_done, txd;
	integer    errors = 0;

	UART #(.CLK_FREQ(CLK_FREQ),.BAUD(BAUD)) dut(
		.clk(clk),.reset(reset),
		.tx_start(tx_start),.tx_data(tx_data),
		.rxd_read(rxd_read),.rx_data(rx_data),
		.tx_busy(tx_busy),.tx_done(tx_done),.rx_done(rx_done),
		.txd(txd),.rxd(rxd));

	always #5 clk = ~clk;   // 100MHz, 10ns period

	// Drive a serial frame onto rxd (8N1, LSB first).
	task send_serial(input [7:0] b); integer i; begin
		rxd = 0;             #BITNS;            // start
		for (i=0;i<8;i=i+1) begin rxd = b[i]; #BITNS; end
		rxd = 1;             #BITNS;            // stop
	end endtask

	// Capture a serial frame from txd and compare.
	reg [7:0] got; integer i;
	task recv_serial(output [7:0] b); begin
		@(negedge txd);          // start edge
		#(BITNS*3/2);            // center of data bit 0
		for (i=0;i<8;i=i+1) begin b[i] = txd; #BITNS; end
	end endtask

	// One-cycle pulse helpers (synchronous to clk)
	task pulse_tx(input [7:0] d); begin
		@(negedge clk); tx_data = d; tx_start = 1;
		@(negedge clk); tx_start = 0;
	end endtask
	task pulse_read; begin
		@(negedge clk); rxd_read = 1;
		@(negedge clk); rxd_read = 0;
	end endtask

	initial begin
		#23 reset = 0;

		// ---- RX test ----
		if (rx_done!==1'b0) begin errors=errors+1; $display("FAIL rx_done not clear at idle"); end
		send_serial(8'hA5);
		#(BITNS);                                  // let stop bit settle through synchronizer
		if (rx_done!==1'b1) begin errors=errors+1; $display("FAIL rx_done not set"); end
		if (rx_data!==8'hA5) begin errors=errors+1; $display("FAIL rx_data=%h exp A5",rx_data); end
		pulse_read;
		if (rx_done!==1'b0) begin errors=errors+1; $display("FAIL rx_done not cleared after read"); end

		// ---- TX test ----
		if (tx_busy!==1'b0 || tx_done!==1'b1) begin errors=errors+1; $display("FAIL tx idle state"); end
		fork
			recv_serial(got);
			pulse_tx(8'h3C);
		join
		if (got!==8'h3C) begin errors=errors+1; $display("FAIL txd byte=%h exp 3C",got); end
		// wait for transmitter to return to idle
		wait (tx_busy===1'b0); #(BITNS);
		if (tx_done!==1'b1) begin errors=errors+1; $display("FAIL tx_done not set after frame"); end

		if (errors==0) $display("PASS tb_uart");
		else           $display("tb_uart FAILED with %0d error(s)",errors);
		$finish;
	end
endmodule
