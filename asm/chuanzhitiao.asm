# 传纸条 (passing notes) — hardware version for the 5-stage pipeline MIPS CPU.
# DFS + memoization, faithfully transcribed from the theory-course recursion.asm,
# but with NO syscalls: input is preset in data RAM, result is shown on the
# 7-seg display via software decoding (and also stored to a scratch word for sim check).
#
# Data RAM layout (byte addresses; preset via dmem hex):
#   0x0000 : m (rows)
#   0x0004 : n (cols)
#   0x0008 : grid[m*n], row-major, grid[i][j] at 0x0008+(i*n+j)*4
#   then  : memo table (bump-allocated right after the grid)
#   0x3FF8 : result scratch (for simulation self-check)
#   0x3FF4 : initial $sp (stack grows down)
#
# Global registers (kept live across DFS): $s0=m $s1=n $s2=grid_base $s3=memo_base $s7=m+n-1
# DFS args: $a0=x1 $a1=y1 $a2=x2 ; returns best additional sum in $v0 (-1 if infeasible)

main:
    addiu $sp, $zero, 16372        # $sp = 0x3FF4
    lw    $s0, 0($zero)            # m
    lw    $s1, 4($zero)            # n
    addiu $s2, $zero, 8            # grid base = 0x0008
    add   $t0, $s0, $s1
    addi  $s7, $t0, -1             # s7 = m+n-1

    # memo_base = grid_base + m*n*4
    mul   $t1, $s0, $s1
    sll   $t1, $t1, 2
    add   $s3, $s2, $t1            # memo base

    # init memo table (size (m+n-1)*m*m words) to -1
    mul   $t2, $s7, $s0
    mul   $t2, $t2, $s0
    sll   $t2, $t2, 2              # bytes
    add   $t2, $s3, $t2            # end address
    addiu $t8, $zero, -1
    move  $t0, $s3
init_loop:
    sw    $t8, 0($t0)
    addiu $t0, $t0, 4
    blt   $t0, $t2, init_loop

    addiu $a0, $zero, 0
    addiu $a1, $zero, 0
    addiu $a2, $zero, 0
    jal   DFS

    move  $s5, $v0                 # result
    sw    $s5, 16376($zero)        # scratch 0x3FF8 (sim check)

    lui   $s4, 0x4000
    ori   $s4, $s4, 0x0010         # $s4 = 0x40000010 (7-seg register)

# ---- multiplexed 4-digit hex display (low 16 bits of result) ----
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

    j     display_loop

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

# ---- delay: software delay for display multiplexing (~tune for board) ----
delay:
    lui   $t1, 0x0002
delay_l:
    addiu $t1, $t1, -1
    bne   $t1, $zero, delay_l
    jr    $ra

# ============================ DFS ============================
# transcribed from the theory-course recursion.asm
DFS:
    addi    $sp, $sp, -32
    sw      $ra, 0($sp)
    sw      $a0, 4($sp)
    sw      $a1, 8($sp)
    sw      $a2, 12($sp)

    add     $s4, $a0, $a1          # s4 = k = x1+y1
    sub     $t5, $s4, $a2          # t5 = y2 = k - x2

    # boundary checks -> return -1
    bge     $s4, $s7, exit_boud
    bge     $a1, $s1, exit_boud
    bge     $a2, $s0, exit_boud
    bge     $a0, $s0, exit_boud
    blt     $t5, $zero, exit_boud
    bge     $t5, $s1, exit_boud

    # memo lookup: idx = k*m*m + x1*m + x2
    addiu   $t8, $zero, -1
    mul     $t1, $s4, $s0
    mul     $t1, $t1, $s0
    mul     $t2, $a0, $s0
    add     $t2, $t2, $a2
    add     $t0, $t1, $t2
    sll     $t0, $t0, 2
    add     $t0, $t0, $s3
    move    $s6, $t0               # current memo address
    sw      $s6, 24($sp)
    lw      $s5, 0($t0)            # memo[k][x1][x2]
    sw      $s5, 16($sp)
    bne     $s5, $t8, exit_memo    # if memo != -1, return it

    # base case: k == m+n-2 -> return 0
    add     $t0, $s7, -1
    beq     $s4, $t0, exit_final

    # current value = grid[x1][y1] (+ grid[x2][y2] if different cell)
    mul     $t0, $s1, $a0
    add     $t0, $t0, $a1
    sll     $t0, $t0, 2
    add     $t0, $t0, $s2
    lw      $v0, 0($t0)
    beq     $a0, $a2, equl

    mul     $t0, $s1, $a2
    add     $t0, $t0, $t5
    sll     $t0, $t0, 2
    add     $t0, $t0, $s2
    lw      $t6, 0($t0)
    add     $v0, $t6, $v0
equl:
    sw      $v0, 20($sp)           # save current value

    # try the 4 transitions, take max into $t6 (init -1)
    addiu   $t6, $zero, -1

    addi    $a0, $a0, 1
    addi    $a2, $a2, 1
    sw      $t6, 28($sp)
    jal     DFS                    # DFS(x1+1,y1,x2+1)
    lw      $t6, 28($sp)
    ble     $v0, $t6, notgreater1
    move    $t6, $v0
notgreater1:
    lw      $a0, 4($sp)
    lw      $a1, 8($sp)
    lw      $a2, 12($sp)
    addi    $a0, $a0, 1
    sw      $t6, 28($sp)
    jal     DFS                    # DFS(x1+1,y1,x2)
    lw      $t6, 28($sp)
    ble     $v0, $t6, notgreater2
    move    $t6, $v0
notgreater2:
    lw      $a0, 4($sp)
    lw      $a1, 8($sp)
    lw      $a2, 12($sp)
    addi    $a1, $a1, 1
    addi    $a2, $a2, 1
    sw      $t6, 28($sp)
    jal     DFS                    # DFS(x1,y1+1,x2+1)
    lw      $t6, 28($sp)
    ble     $v0, $t6, notgreater3
    move    $t6, $v0
notgreater3:
    lw      $a0, 4($sp)
    lw      $a1, 8($sp)
    lw      $a2, 12($sp)
    addi    $a1, $a1, 1
    sw      $t6, 28($sp)
    jal     DFS                    # DFS(x1,y1+1,x2)
    lw      $t6, 28($sp)
    ble     $v0, $t6, notgreater4
    move    $t6, $v0
notgreater4:
    lw      $a0, 4($sp)
    lw      $a1, 8($sp)
    lw      $a2, 12($sp)

    lw      $v0, 20($sp)
    addiu   $t8, $zero, -1
    beq     $t6, $t8, exit_boud    # all transitions infeasible -> -1
    add     $v0, $v0, $t6
    j       exit

exit_final:                        # k == m+n-2 -> return 0
    addiu   $v0, $zero, 0
    j       exit
exit_boud:                         # out of bounds -> return -1
    addiu   $v0, $zero, -1
    j       real_exit
exit_memo:                         # cached valid value -> return it
    lw      $v0, 16($sp)
    j       real_exit
exit:                              # store result into memo, then return
    lw      $t0, 24($sp)
    sw      $v0, 0($t0)
    lw      $ra, 0($sp)
    addi    $sp, $sp, 32
    jr      $ra
real_exit:
    lw      $ra, 0($sp)
    addi    $sp, $sp, 32
    jr      $ra
