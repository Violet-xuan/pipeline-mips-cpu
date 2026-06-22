# Combined display + UART diagnostic.
#   * drives the 7-seg with a fixed 0x1234 (proves CPU/clock/reset + display work)
#   * sends 0x55 on UART once per display refresh (proves TX path + COM port)
# If the display shows "1234" but no serial arrives -> CPU is fine, UART link is the problem.
# If the display is dark too -> the CPU is not running on this bitstream.

main:
    lui   $s4, 0x4000
    ori   $s4, $s4, 0x0010        # digi (7-seg)
    lui   $t9, 0x4000
    ori   $s0, $t9, 0x0020         # CON
    ori   $s1, $t9, 0x0018         # TXD
    addiu $s5, $zero, 0x1234       # value to display

disp:
    andi  $t0, $s5, 0xF
    jal   seg7
    ori   $v0, $v0, 0x100
    sw    $v0, 0($s4)
    jal   dly
    srl   $t0, $s5, 4
    andi  $t0, $t0, 0xF
    jal   seg7
    ori   $v0, $v0, 0x200
    sw    $v0, 0($s4)
    jal   dly
    srl   $t0, $s5, 8
    andi  $t0, $t0, 0xF
    jal   seg7
    ori   $v0, $v0, 0x400
    sw    $v0, 0($s4)
    jal   dly
    srl   $t0, $s5, 12
    andi  $t0, $t0, 0xF
    jal   seg7
    ori   $v0, $v0, 0x800
    sw    $v0, 0($s4)
    jal   dly
    # send 0x55 once per full refresh
wtx:
    lw    $t0, 0($s0)
    andi  $t0, $t0, 0x4
    beq   $t0, $zero, wtx
    addiu $t1, $zero, 0x55
    sw    $t1, 0($s1)
    j     disp

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
    bne   $t0, $t1, seg7_d
    addiu $v0, $zero, 0x66
    jr    $ra
seg7_d:
    addiu $v0, $zero, 0x40         # '-' (segment g) for any other nibble
    jr    $ra

dly:
    addiu $t1, $zero, 30000
dly_l:
    addiu $t1, $t1, -1
    bne   $t1, $zero, dly_l
    jr    $ra
