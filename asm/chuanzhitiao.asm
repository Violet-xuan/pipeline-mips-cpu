# 传纸条 (passing notes) — hardware version for the 5-stage pipeline MIPS CPU.
# DFS + memoization, faithfully transcribed from the theory-course recursion.asm,
# but with NO syscalls. Bidirectional UART I/O: the PC sends a dataset over the
# serial port, the CPU computes, and sends the answer back. The result is ALSO
# shown on the 7-seg display (refreshed between datasets) and stored to a scratch
# word for simulation self-check.
#
# ---- Binary UART protocol (8N1) ----
#   host -> board:  byte m, byte n, then m*n grid bytes (row-major), each 0..255
#   board -> host:  4 bytes of the 32-bit result, MSB first (big-endian)
# After sending the answer the board keeps the 7-seg refreshed; the moment a new
# byte arrives (start of the next dataset) it loops back to receive again.
#
# Data RAM layout (byte addresses):
#   0x0000 : m (rows)            <- written by recv_dataset
#   0x0004 : n (cols)            <- written by recv_dataset
#   0x0008 : grid[m*n], row-major, grid[i][j] at 0x0008+(i*n+j)*4
#   then   : memo table (bump-allocated right after the grid)
#   0x3FF8 : result scratch (for simulation self-check)
#   0x3FF4 : initial $sp (stack grows down)
#
# MMIO: 0x40000010 7-seg digi | 0x40000018 UART TXD | 0x4000001C UART RXD | 0x40000020 UART CON
#   CON bits: bit2 tx_done(=idle) | bit3 rx_done | bit4 tx_busy
#
# Global registers (kept live across DFS): $s0=m $s1=n $s2=grid_base $s3=memo_base $s7=m+n-1
# DFS args: $a0=x1 $a1=y1 $a2=x2 ; returns best additional sum in $v0 (-1 if infeasible)

main:
    lui   $sp, 0x0001              # $sp = 0x1FFF4 (top of 128KB, reset every round)
    ori   $sp, $sp, 0xFFF4
    jal   recv_dataset             # read m, n, grid from UART into DMEM

    lw    $s0, 0($zero)            # m
    lw    $s1, 4($zero)            # n
    addiu $s2, $zero, 8            # grid base = 0x0008

    # Bottom-up DP with two rolling layers:
    #   dp[k][x1][x2], y1=k-x1, y2=k-x2
    # prev_base = grid_base + m*n*4
    # curr_base = prev_base + m*m*4
    mul   $t0, $s0, $s1
    sll   $t0, $t0, 2
    add   $s3, $s2, $t0            # s3 = prev_base
    mul   $t0, $s0, $s0
    sll   $s6, $t0, 2              # s6 = layer bytes = m*m*4
    add   $s4, $s3, $s6            # s4 = curr_base
    add   $t0, $s0, $s1
    addi  $s7, $t0, -2             # s7 = last step = m+n-2

    # clear both DP layers to -1
    addiu $t8, $zero, -1
    add   $t3, $s4, $s6            # end = curr_base + layer_bytes
    move  $t0, $s3
dp_clear_all:
    sw    $t8, 0($t0)
    addiu $t0, $t0, 4
    blt   $t0, $t3, dp_clear_all
    lw    $t9, 0($s2)
    sw    $t9, 0($s3)              # dp[0][0][0] = grid[0][0]

    addiu $t0, $zero, 1            # k = 1
dp_k_loop:
    bgt   $t0, $s7, dp_done

    # clear curr layer to -1
    addiu $t8, $zero, -1
    add   $t3, $s4, $s6
    move  $t6, $s4
dp_clear_curr:
    sw    $t8, 0($t6)
    addiu $t6, $t6, 4
    blt   $t6, $t3, dp_clear_curr

    addiu $t1, $zero, 0            # x1
dp_x1_loop:
    bge   $t1, $s0, dp_swap_layers
    sub   $t3, $t0, $t1            # y1 = k - x1
    blt   $t3, $zero, dp_next_x1
    bge   $t3, $s1, dp_next_x1

    addiu $t2, $zero, 0            # x2
dp_x2_loop:
    bge   $t2, $s0, dp_next_x1
    sub   $t4, $t0, $t2            # y2 = k - x2
    blt   $t4, $zero, dp_next_x2
    bge   $t4, $s1, dp_next_x2

    addiu $t5, $zero, -1           # best predecessor

    # predecessor (x1, x2)
    mul   $t6, $t1, $s0
    add   $t6, $t6, $t2
    sll   $t6, $t6, 2
    add   $t6, $t6, $s3
    lw    $t7, 0($t6)
    ble   $t7, $t5, dp_pred_10
    move  $t5, $t7

dp_pred_10:
    # predecessor (x1-1, x2)
    blez  $t1, dp_pred_01
    addi  $t9, $t1, -1
    mul   $t6, $t9, $s0
    add   $t6, $t6, $t2
    sll   $t6, $t6, 2
    add   $t6, $t6, $s3
    lw    $t7, 0($t6)
    ble   $t7, $t5, dp_pred_01
    move  $t5, $t7

dp_pred_01:
    # predecessor (x1, x2-1)
    blez  $t2, dp_pred_11
    addi  $t9, $t2, -1
    mul   $t6, $t1, $s0
    add   $t6, $t6, $t9
    sll   $t6, $t6, 2
    add   $t6, $t6, $s3
    lw    $t7, 0($t6)
    ble   $t7, $t5, dp_pred_11
    move  $t5, $t7

dp_pred_11:
    # predecessor (x1-1, x2-1)
    blez  $t1, dp_have_best
    blez  $t2, dp_have_best
    addi  $t9, $t1, -1
    mul   $t6, $t9, $s0
    addi  $t9, $t2, -1
    add   $t6, $t6, $t9
    sll   $t6, $t6, 2
    add   $t6, $t6, $s3
    lw    $t7, 0($t6)
    ble   $t7, $t5, dp_have_best
    move  $t5, $t7

dp_have_best:
    addiu $t8, $zero, -1
    beq   $t5, $t8, dp_next_x2
    beq   $t0, $s7, dp_store       # do not count the destination cell

    # add grid[x1][y1]
    mul   $t6, $t1, $s1
    add   $t6, $t6, $t3
    sll   $t6, $t6, 2
    add   $t6, $t6, $s2
    lw    $t7, 0($t6)
    add   $t5, $t5, $t7

    # add grid[x2][y2] if the two walkers are on different cells
    beq   $t1, $t2, dp_store
    mul   $t6, $t2, $s1
    add   $t6, $t6, $t4
    sll   $t6, $t6, 2
    add   $t6, $t6, $s2
    lw    $t7, 0($t6)
    add   $t5, $t5, $t7

dp_store:
    mul   $t6, $t1, $s0
    add   $t6, $t6, $t2
    sll   $t6, $t6, 2
    add   $t6, $t6, $s4
    sw    $t5, 0($t6)

dp_next_x2:
    addiu $t2, $t2, 1
    j     dp_x2_loop
dp_next_x1:
    addiu $t1, $t1, 1
    j     dp_x1_loop

dp_swap_layers:
    move  $t6, $s3
    move  $s3, $s4
    move  $s4, $t6
    addiu $t0, $t0, 1
    j     dp_k_loop

dp_done:
    addi  $t1, $s0, -1
    mul   $t6, $t1, $s0
    add   $t6, $t6, $t1
    sll   $t6, $t6, 2
    add   $t6, $t6, $s3
    lw    $s5, 0($t6)              # result
    sw    $s5, 16376($zero)        # scratch 0x3FF8 (sim check)
    jal   send_result              # send result (4 bytes, MSB first) over UART

    lui   $s4, 0x4000
    ori   $s4, $s4, 0x0010         # $s4 = 0x40000010 (7-seg register)

# ---- multiplexed 4-digit hex display; poll UART for the next dataset ----
display_loop:
    andi  $t0, $s5, 0xF            # digit 0 -> AN0 (bit8)
    jal   seg7
    ori   $v0, $v0, 0x100
    sw    $v0, 0($s4)
    jal   delay

    srl   $t0, $s5, 4              # digit 1 -> AN1 (bit9)
    andi  $t0, $t0, 0xF
    jal   seg7
    ori   $v0, $v0, 0x200
    sw    $v0, 0($s4)
    jal   delay

    srl   $t0, $s5, 8             # digit 2 -> AN2 (bit10)
    andi  $t0, $t0, 0xF
    jal   seg7
    ori   $v0, $v0, 0x400
    sw    $v0, 0($s4)
    jal   delay

    srl   $t0, $s5, 12            # digit 3 -> AN3 (bit11)
    andi  $t0, $t0, 0xF
    jal   seg7
    ori   $v0, $v0, 0x800
    sw    $v0, 0($s4)
    jal   delay

    # a byte waiting on UART RX means a new dataset is coming -> receive it
    lui   $t9, 0x4000
    ori   $t8, $t9, 0x0020         # CON
    lw    $t9, 0($t8)
    andi  $t9, $t9, 0x8            # rx_done (bit3)
    bne   $t9, $zero, main         # restart the round (re-inits $sp, reads dataset)
    j     display_loop

# ============================ UART I/O ============================
# recv_dataset: read m, n, then m*n grid bytes from UART into DMEM.
recv_dataset:
    addi  $sp, $sp, -4
    sw    $ra, 0($sp)
    jal   uart_getc
    sw    $v0, 0($zero)            # m -> 0x0
    move  $t3, $v0
    jal   uart_getc
    sw    $v0, 4($zero)            # n -> 0x4
    move  $t4, $v0
    mul   $t0, $t3, $t4            # count = m*n
    addiu $t1, $zero, 8            # dst byte addr (grid base)
    addiu $t2, $zero, 0            # i = 0
recv_grid_loop:
    bge   $t2, $t0, recv_done
    jal   uart_getc
    sw    $v0, 0($t1)              # grid[i] (zero-extended byte)
    addiu $t1, $t1, 4
    addiu $t2, $t2, 1
    j     recv_grid_loop
recv_done:
    lw    $ra, 0($sp)
    addi  $sp, $sp, 4
    jr    $ra

# send_result: transmit $s5 as 4 bytes over UART, MSB first.
send_result:
    addi  $sp, $sp, -4
    sw    $ra, 0($sp)
    srl   $a0, $s5, 24
    andi  $a0, $a0, 0xFF
    jal   uart_putc
    srl   $a0, $s5, 16
    andi  $a0, $a0, 0xFF
    jal   uart_putc
    srl   $a0, $s5, 8
    andi  $a0, $a0, 0xFF
    jal   uart_putc
    andi  $a0, $s5, 0xFF
    jal   uart_putc
    lw    $ra, 0($sp)
    addi  $sp, $sp, 4
    jr    $ra

# uart_getc: block until a byte arrives, return it in $v0. Uses $t7,$t8,$t9 only.
uart_getc:
    lui   $t9, 0x4000
    ori   $t8, $t9, 0x0020         # CON
    ori   $t7, $t9, 0x001C         # RXD
uart_getc_wait:
    lw    $t9, 0($t8)
    andi  $t9, $t9, 0x8            # rx_done (bit3)
    beq   $t9, $zero, uart_getc_wait
    lw    $v0, 0($t7)              # read RXD (clears rx_done)
    andi  $v0, $v0, 0xFF
    jr    $ra

# uart_putc: block until TX idle, then send the byte in $a0. Uses $t7,$t8,$t9.
uart_putc:
    lui   $t9, 0x4000
    ori   $t8, $t9, 0x0020         # CON
    ori   $t7, $t9, 0x0018         # TXD
uart_putc_wait:
    lw    $t9, 0($t8)
    andi  $t9, $t9, 0x4            # tx_done (bit2, 1 = idle)
    beq   $t9, $zero, uart_putc_wait
    sw    $a0, 0($t7)              # write TXD -> start transmit
    jr    $ra

# ---- seg7: nibble in $t0 -> 7-seg pattern (g..a, bit6..bit0) in $v0 ----
seg7:
    addiu $t1, $zero, 0
    bne   $t0, $t1, seg7_1
    addiu $v0, $zero, 0x3F
    jr    $ra
seg7_1:
    addiu $t1, $zero, 1
    bne   $t0, $t1, seg7_2
    addiu $v0, $zero, 0x06
    jr    $ra
seg7_2:
    addiu $t1, $zero, 2
    bne   $t0, $t1, seg7_3
    addiu $v0, $zero, 0x5B
    jr    $ra
seg7_3:
    addiu $t1, $zero, 3
    bne   $t0, $t1, seg7_4
    addiu $v0, $zero, 0x4F
    jr    $ra
seg7_4:
    addiu $t1, $zero, 4
    bne   $t0, $t1, seg7_5
    addiu $v0, $zero, 0x66
    jr    $ra
seg7_5:
    addiu $t1, $zero, 5
    bne   $t0, $t1, seg7_6
    addiu $v0, $zero, 0x6D
    jr    $ra
seg7_6:
    addiu $t1, $zero, 6
    bne   $t0, $t1, seg7_7
    addiu $v0, $zero, 0x7D
    jr    $ra
seg7_7:
    addiu $t1, $zero, 7
    bne   $t0, $t1, seg7_8
    addiu $v0, $zero, 0x07
    jr    $ra
seg7_8:
    addiu $t1, $zero, 8
    bne   $t0, $t1, seg7_9
    addiu $v0, $zero, 0x7F
    jr    $ra
seg7_9:
    addiu $t1, $zero, 9
    bne   $t0, $t1, seg7_A
    addiu $v0, $zero, 0x6F
    jr    $ra
seg7_A:
    addiu $t1, $zero, 10
    bne   $t0, $t1, seg7_B
    addiu $v0, $zero, 0x77
    jr    $ra
seg7_B:
    addiu $t1, $zero, 11
    bne   $t0, $t1, seg7_C
    addiu $v0, $zero, 0x7C
    jr    $ra
seg7_C:
    addiu $t1, $zero, 12
    bne   $t0, $t1, seg7_D
    addiu $v0, $zero, 0x39
    jr    $ra
seg7_D:
    addiu $t1, $zero, 13
    bne   $t0, $t1, seg7_E
    addiu $v0, $zero, 0x5E
    jr    $ra
seg7_E:
    addiu $t1, $zero, 14
    bne   $t0, $t1, seg7_F
    addiu $v0, $zero, 0x79
    jr    $ra
seg7_F:
    addiu $v0, $zero, 0x71
    jr    $ra

# ---- delay: software delay for display multiplexing ----
# Polls UART rx_done EVERY iteration (sub-us latency): the FIFO-less receiver
# holds only one byte, so when a new dataset's first byte arrives we must jump
# to the receiver before the second byte overwrites it. Without this, a second
# dataset sent while the board is in the display loop desyncs (needs a reset).
# 5000 iters (~2 ms/digit at 25 MHz with the poll body) keeps refresh >100 Hz.
delay:
    addiu $t1, $zero, 5000
delay_l:
    lui   $t2, 0x4000
    ori   $t2, $t2, 0x0020         # CON
    lw    $t2, 0($t2)
    andi  $t2, $t2, 0x8            # rx_done (bit3)
    bne   $t2, $zero, main         # new dataset arriving -> receive it now
    addiu $t1, $t1, -1
    bne   $t1, $zero, delay_l
    jr    $ra
