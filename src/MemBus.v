module MemBus #(
	parameter CLK_FREQ = 25_000_000,   // cpu_clk frequency, forwarded to UART baud divider
	parameter BAUD     = 9600
)(
	input         clk,
	input         reset,
	input         MemRead,
	input         MemWrite,
	input  [31:0] Address,
	input  [31:0] WriteData,
	output [31:0] ReadData,
	output reg [11:0] digi,
	// UART serial pins
	output        uart_txd,
	input         uart_rxd
);
	wire is_periph = (Address[30]);            // 0x4xxxxxxx
	wire dmem_we = MemWrite & ~is_periph;
	wire dmem_re = MemRead  & ~is_periph;
	wire [31:0] dmem_rd;
	DataMemory dmem(.reset(reset),.clk(clk),.MemRead(dmem_re),.MemWrite(dmem_we),
		.Address(Address),.Write_data(WriteData),.Read_data(dmem_rd));

	always @(posedge clk or posedge reset)
		if (reset) digi <= 12'd0;
		else if (MemWrite & is_periph && Address==32'h40000010)
			digi <= WriteData[11:0];

	// ---- UART peripheral (0x18 TXD / 0x1C RXD / 0x20 CON) ----
	wire        uart_tx_start = MemWrite & is_periph & (Address==32'h40000018);
	wire        uart_rxd_read = MemRead  & is_periph & (Address==32'h4000001C);
	wire [7:0]  uart_rx_data;
	wire        uart_tx_busy, uart_tx_done, uart_rx_done;
	UART #(.CLK_FREQ(CLK_FREQ),.BAUD(BAUD)) uart(
		.clk(clk),.reset(reset),
		.tx_start(uart_tx_start),.tx_data(WriteData[7:0]),
		.rxd_read(uart_rxd_read),.rx_data(uart_rx_data),
		.tx_busy(uart_tx_busy),.tx_done(uart_tx_done),.rx_done(uart_rx_done),
		.txd(uart_txd),.rxd(uart_rxd));
	// CON: bit2 tx_done, bit3 rx_done, bit4 tx_busy
	wire [31:0] uart_con = {27'd0, uart_tx_busy, uart_rx_done, uart_tx_done, 2'd0};

	// peripheral read mux
	reg [31:0] periph_rd;
	always @* begin
		case (Address)
			32'h40000010: periph_rd = {20'd0, digi};
			32'h4000001C: periph_rd = {24'd0, uart_rx_data};
			32'h40000020: periph_rd = uart_con;
			default:      periph_rd = 32'd0;
		endcase
	end
	assign ReadData = is_periph ? periph_rd : dmem_rd;
endmodule
