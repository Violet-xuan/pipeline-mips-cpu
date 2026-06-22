# UART hardware diagnostic — runs on the same CPU/MemBus/UART, but instead of
# the 传纸条 task it just exercises the serial link:
#   * continuously transmits 0x55 ('U') — a TX + baud + which-COM-port check
#   * echoes back any byte it receives — an RX check
# Expected on the PC: a steady stream of 0x55; whatever byte you send comes back.
# MMIO: 0x40000018 TXD | 0x4000001C RXD | 0x40000020 CON (bit2 tx_done, bit3 rx_done)

main:
    lui   $t9, 0x4000
    ori   $s0, $t9, 0x0020         # CON
    ori   $s1, $t9, 0x0018         # TXD
    ori   $s2, $t9, 0x001C         # RXD
loop:
    # wait for TX idle, then send 0x55
wtx1:
    lw    $t0, 0($s0)
    andi  $t0, $t0, 0x4            # tx_done (1 = idle)
    beq   $t0, $zero, wtx1
    addiu $t1, $zero, 0x55
    sw    $t1, 0($s1)

    # if a byte was received, echo it
    lw    $t0, 0($s0)
    andi  $t0, $t0, 0x8            # rx_done
    beq   $t0, $zero, norx
    lw    $t2, 0($s2)             # read RXD (clears rx_done)
    andi  $t2, $t2, 0xFF
wtx2:
    lw    $t0, 0($s0)
    andi  $t0, $t0, 0x4
    beq   $t0, $zero, wtx2
    sw    $t2, 0($s1)             # echo
norx:
    # short gap so the 0x55 stream is ~1 kHz
    addiu $t3, $zero, 2000
dly:
    addiu $t3, $t3, -1
    bne   $t3, $zero, dly
    j     loop
