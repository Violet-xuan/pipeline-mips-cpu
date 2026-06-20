#!/usr/bin/env python3
"""Multi-case verification harness for the 传纸条 hardware program.

Reference DP for the passing-notes problem (two monotone paths, distinct cells,
endpoints valued 0), then for each random case: write dmem hex, run the CPU sim
via iverilog/vvp, parse the result, and compare against the reference.
"""
import os, sys, random, subprocess, re, tempfile

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

def write_dmem(path, m, n, g):
    with open(path, "w") as fh:
        fh.write("%08x\n" % (m & 0xffffffff))
        fh.write("%08x\n" % (n & 0xffffffff))
        for i in range(m):
            for j in range(n):
                fh.write("%08x\n" % (g[i][j] & 0xffffffff))

SRCS = ["PipelineCPU.v","Control.v","ALU.v","ALUControl.v","RegisterFile.v",
        "InstructionMemory.v","DataMemory.v","ForwardingUnit.v","HazardUnit.v","MemBus.v","UART.v"]

def run_case(m, n, g, idx):
    dmem = os.path.join(SIM, "dmem_case.hex")
    write_dmem(dmem, m, n, g)
    tb = os.path.join(SIM, "tb_chuanzhitiao_auto.v")
    out = os.path.join(tempfile.gettempdir(), "t_auto.out")
    imem = os.path.join(SIM, "imem_chuanzhitiao.hex")
    cmd = ["iverilog","-g2012",
           "-DIMEM_FILE=\"%s\"" % imem.replace("\\","/"),
           "-DDMEM_FILE=\"%s\"" % dmem.replace("\\","/"),
           "-o", out, tb] + [os.path.join(SRC,s) for s in SRCS]
    subprocess.run(cmd, check=True, capture_output=True)
    r = subprocess.run(["vvp", out], capture_output=True, text=True)
    msrc = re.search(r"RESULT=(-?\d+)", r.stdout)
    if not msrc:
        print("case %d: NO RESULT\n%s" % (idx, r.stdout)); return False
    got = int(msrc.group(1))
    exp = solve(m, n, g)
    ok = (got == exp)
    print("case %d: %dx%d got=%d exp=%d %s" % (idx, m, n, got, exp, "OK" if ok else "FAIL"))
    return ok

# auto testbench: prints RESULT=<scratch word as signed>
TB = r'''`timescale 1ns/1ps
module tb_chuanzhitiao_auto;
    reg clk=0,reset=1; wire MemRead,MemWrite; wire [31:0] MemAddr,MemWriteData,MemReadData;
    wire [11:0] digi;
    PipelineCPU cpu(.clk(clk),.reset(reset),.MemRead(MemRead),.MemWrite(MemWrite),
        .MemAddr(MemAddr),.MemWriteData(MemWriteData),.MemReadData(MemReadData));
    MemBus bus(.clk(clk),.reset(reset),.MemRead(MemRead),.MemWrite(MemWrite),
        .Address(MemAddr),.WriteData(MemWriteData),.ReadData(MemReadData),.digi(digi),
        .uart_txd(),.uart_rxd(1'b1));
    always #5 clk=~clk;
    initial begin
        #12 reset=0;
        #800000;
        $display("RESULT=%0d", $signed(bus.dmem.RAM[4094]));
        $finish;
    end
endmodule
'''

def main():
    with open(os.path.join(SIM,"tb_chuanzhitiao_auto.v"),"w") as fh:
        fh.write(TB)
    random.seed(12345)
    cases = [
        (2,2,[[0,5],[7,0]]),
        (3,3,[[0,3,9],[2,8,5],[5,7,0]]),   # the known 34 case
        (3,4,[[0,1,2,3],[4,5,6,7],[8,9,1,0]]),
        (4,4,[[0,2,4,6],[1,3,5,7],[8,6,4,2],[1,1,1,0]]),
    ]
    # a few random small grids
    for _ in range(4):
        m = random.randint(2,5); n = random.randint(2,5)
        g = [[random.randint(0,100) for _ in range(n)] for _ in range(m)]
        g[0][0]=0; g[m-1][n-1]=0
        cases.append((m,n,g))
    allok = True
    for i,(m,n,g) in enumerate(cases):
        allok &= run_case(m,n,g,i)
    print("ALL PASS" if allok else "SOME FAILED")
    sys.exit(0 if allok else 1)

if __name__ == "__main__":
    main()
