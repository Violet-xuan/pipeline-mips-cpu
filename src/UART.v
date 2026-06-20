// 8N1 UART (transmit + receive), single clock domain.
// Frame: 1 start (low) + 8 data (LSB first) + 1 stop (high). No parity.
// All control signals (tx_start / rxd_read) are 1-cycle pulses in the `clk` domain.
module UART #(
	parameter CLK_FREQ = 25_000_000,   // frequency of `clk` (= cpu_clk on board)
	parameter BAUD     = 9600
)(
	input            clk,
	input            reset,            // active high
	// MMIO side (same clock domain as the bus)
	input            tx_start,         // pulse: latch tx_data and begin transmit
	input      [7:0] tx_data,
	input            rxd_read,         // pulse: CPU read RXD -> clear rx_done
	output     [7:0] rx_data,
	output           tx_busy,
	output           tx_done,          // = ~tx_busy
	output           rx_done,          // a full frame is waiting to be read
	// serial pins
	output reg       txd,
	input            rxd
);
	localparam integer DIV = CLK_FREQ / BAUD;   // clk cycles per bit
	localparam integer DW  = 16;                // counter width (covers DIV up to 65535; avoids $clog2 in localparam, unsupported by Vivado 2017.3 synth)

	// ---------------- transmit ----------------
	reg            tx_active;
	reg  [DW-1:0]  tx_div;
	reg  [3:0]     tx_bitcnt;          // counts the 10 transmitted bits (0..9)
	reg  [9:0]     tx_shift;           // {stop=1, data[7:0], start=0}, shifted out LSB first
	assign tx_busy = tx_active;
	assign tx_done = ~tx_active;

	always @(posedge clk or posedge reset) begin
		if (reset) begin
			txd <= 1'b1; tx_active <= 1'b0; tx_div <= 0; tx_bitcnt <= 0; tx_shift <= 10'h3FF;
		end else if (!tx_active) begin
			txd <= 1'b1;                            // idle high
			if (tx_start) begin
				tx_shift  <= {1'b1, tx_data, 1'b0};
				tx_active <= 1'b1;
				tx_div    <= 0;
				tx_bitcnt <= 0;
			end
		end else begin
			txd <= tx_shift[0];
			if (tx_div == DIV-1) begin
				tx_div    <= 0;
				tx_shift  <= {1'b1, tx_shift[9:1]};  // shift in idle/stop high
				tx_bitcnt <= tx_bitcnt + 1'b1;
				if (tx_bitcnt == 4'd9) tx_active <= 1'b0;
			end else begin
				tx_div <= tx_div + 1'b1;
			end
		end
	end

	// ---------------- receive ----------------
	reg rxd_s1, rxd_s2;                 // 2-FF synchronizer
	always @(posedge clk) begin rxd_s1 <= rxd; rxd_s2 <= rxd_s1; end
	wire rxd_sync = rxd_s2;

	reg            rx_active;
	reg  [DW-1:0]  rx_div;
	reg  [3:0]     rx_bitcnt;           // 0 = start-bit check, 1..8 = data bits, 9 = stop bit
	reg  [7:0]     rx_shift;
	reg  [7:0]     rx_data_r;
	reg            rx_done_r;
	assign rx_data = rx_data_r;
	assign rx_done = rx_done_r;

	always @(posedge clk or posedge reset) begin
		if (reset) begin
			rx_active <= 1'b0; rx_div <= 0; rx_bitcnt <= 0; rx_shift <= 0;
			rx_data_r <= 0; rx_done_r <= 1'b0; rxd_s1 <= 1'b1; rxd_s2 <= 1'b1;
		end else begin
			if (rxd_read) rx_done_r <= 1'b0;        // consumed by CPU
			if (!rx_active) begin
				if (!rxd_sync) begin                 // start bit (line low)
					rx_active <= 1'b1;
					rx_div    <= DIV/2;              // first sample at center of start bit
					rx_bitcnt <= 0;
				end
			end else if (rx_div == DIV-1) begin
				rx_div <= 0;
				if (rx_bitcnt == 4'd0) begin
					if (rxd_sync) rx_active <= 1'b0; // false start, abort
					else          rx_bitcnt <= 4'd1;
				end else if (rx_bitcnt <= 4'd8) begin
					rx_shift  <= {rxd_sync, rx_shift[7:1]}; // LSB first
					rx_bitcnt <= rx_bitcnt + 1'b1;
				end else begin                       // rx_bitcnt == 9: stop bit
					rx_active <= 1'b0;
					if (rxd_sync) begin              // valid stop -> latch
						rx_data_r <= rx_shift;
						rx_done_r <= 1'b1;
					end
				end
			end else begin
				rx_div <= rx_div + 1'b1;
			end
		end
	end
endmodule
