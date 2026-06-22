#!/usr/bin/env python3
"""Multi-case verification harness for the bidirectional-UART 传纸条 firmware.

For each dataset: write the input-byte file (m, n, grid bytes), run the CPU sim
(tb_chuanzhitiao_uart.v drives the bytes into uart_rxd and reads the 4-byte result
back from uart_txd), parse RESULT=, and compare against a reference DP solver.

Run with `python` (not python3 — the Store stub exits silently on this box).
"""
import os, sys, random, subprocess, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIM = os.path.join(ROOT, "sim")
SRC = os.path.join(ROOT, "src")

def solve(m, n, g):
    """Reference: max sum of two monotone (0,0)->(m-1,n-1) paths, distinct cells."""
    import functools
    sys.setrecursionlimit(100000)
    @functools.lru_cache(maxsize=None)
    def f(x1, y1, x2):
        k = x1 + y1
        y2 = k - x2
        if k >= m + n - 1 or y1 >= n or x2 >= m or x1 >= m or y2 < 0 or y2 >= n:
            return -1
        if k == m + n - 2:
            return 0
        cur = g[x1][y1]
        if (x1, y1) != (x2, y2):
            cur += g[x2][y2]
        best = max(f(x1+1, y1, x2+1), f(x1+1, y1, x2),
                   f(x1, y1+1, x2+1), f(x1, y1+1, x2))
        if best == -1:
            return -1
        return cur + best
    return f(0, 0, 0)

def write_uart_in(path, m, n, g):
    """Input byte stream the firmware expects: m, n, then m*n grid bytes (0..255)."""
    with open(path, "w") as fh:
        fh.write("%02x\n" % (m & 0xff))
        fh.write("%02x\n" % (n & 0xff))
        for i in range(m):
            for j in range(n):
                fh.write("%02x\n" % (g[i][j] & 0xff))

SRCS = ["PipelineCPU.v","Control.v","ALU.v","ALUControl.v","RegisterFile.v",
        "InstructionMemory.v","DataMemory.v","ForwardingUnit.v","HazardUnit.v",
        "MemBus.v","UART.v"]

IVERILOG = os.environ.get("IVERILOG", r"D:\iverilog\bin\iverilog.exe")
VVP      = os.environ.get("VVP",      r"D:\iverilog\bin\vvp.exe")

def run_case(m, n, g, idx):
    uin  = os.path.join(SIM, "uart_in.hex")
    write_uart_in(uin, m, n, g)
    tb   = os.path.join(SIM, "tb_chuanzhitiao_uart.v")
    out  = os.path.join(SIM, "_uart_tb.out")
    imem = os.path.join(SIM, "imem_chuanzhitiao.hex")
    dmem = os.path.join(SIM, "dmem_chuanzhitiao.hex")  # content irrelevant (UART overwrites)
    cmd = [IVERILOG, "-g2012",
           '-DIMEM_FILE="%s"' % imem.replace("\\", "/"),
           '-DDMEM_FILE="%s"' % dmem.replace("\\", "/"),
           '-DUART_IN="%s"'  % uin.replace("\\", "/"),
           "-o", out, tb] + [os.path.join(SRC, s) for s in SRCS]
    subprocess.run(cmd, check=True, capture_output=True)
    r = subprocess.run([VVP, out], capture_output=True, text=True)
    mres = re.search(r"RESULT=(-?\d+)", r.stdout)
    if not mres:
        print("case %d: NO RESULT\n%s\n%s" % (idx, r.stdout, r.stderr)); return False
    got = int(mres.group(1))
    exp = solve(m, n, g)
    ok = (got == exp)
    print("case %d: %dx%d got=%d exp=%d %s" % (idx, m, n, got, exp, "OK" if ok else "FAIL"))
    return ok

def main():
    random.seed(12345)
    cases = [
        (2,2,[[0,5],[7,0]]),
        (3,3,[[0,3,9],[2,8,5],[5,7,0]]),   # the known 34 case
        (3,4,[[0,1,2,3],[4,5,6,7],[8,9,1,0]]),
        (4,4,[[0,2,4,6],[1,3,5,7],[8,6,4,2],[1,1,1,0]]),
    ]
    for _ in range(4):
        m = random.randint(2,5); n = random.randint(2,5)
        g = [[random.randint(0,100) for _ in range(n)] for _ in range(m)]
        g[0][0] = 0; g[m-1][n-1] = 0
        cases.append((m,n,g))
    allok = True
    for i,(m,n,g) in enumerate(cases):
        allok &= run_case(m,n,g,i)
    print("ALL PASS" if allok else "SOME FAILED")
    sys.exit(0 if allok else 1)

if __name__ == "__main__":
    main()
