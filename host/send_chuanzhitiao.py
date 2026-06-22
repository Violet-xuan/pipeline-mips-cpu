#!/usr/bin/env python3
"""Host-side driver for the 传纸条 board over a PC serial port.

Sends each dataset to the FPGA (binary protocol) and reads the answer back:
    host -> board:  byte m, byte n, then m*n grid bytes (row-major), each 0..255
    board -> host:  4 bytes of the 32-bit result, MSB first (big-endian)

The board's UART is 9600 8N1 (set in top.v: BAUD=9600). Pick the COM port that
shows up for the board's USB-serial bridge (Device Manager -> Ports).

    pip install pyserial
    python host/send_chuanzhitiao.py --port COM3
    python host/send_chuanzhitiao.py --port COM3 --grid "3 3 0 3 9 2 8 5 5 7 0"

Each result is compared against a built-in reference DP solver, so you get an
immediate OK/FAIL next to the value the board returned.
"""
import argparse, sys, time, functools

try:
    import serial  # pyserial
except ImportError:
    sys.exit("pyserial not installed.  Run:  pip install pyserial")


def solve(m, n, g):
    """Reference: max sum of two monotone (0,0)->(m-1,n-1) paths, distinct cells."""
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
        return -1 if best == -1 else cur + best
    return f(0, 0, 0)


# A few datasets to try out of the box (m, n, grid). g[0][0]=g[m-1][n-1]=0 by convention.
DATASETS = [
    (2, 2, [[0, 5], [7, 0]]),
    (3, 3, [[0, 3, 9], [2, 8, 5], [5, 7, 0]]),          # classic -> 34
    (3, 4, [[0, 1, 2, 3], [4, 5, 6, 7], [8, 9, 1, 0]]),
    (4, 4, [[0, 2, 4, 6], [1, 3, 5, 7], [8, 6, 4, 2], [1, 1, 1, 0]]),
    (5, 5, [[0, 4, 8, 2, 6], [3, 7, 1, 5, 9], [2, 6, 4, 8, 1],
            [9, 3, 7, 1, 5], [4, 2, 6, 8, 0]]),
]


def send_case(ser, m, n, g):
    payload = bytes([m & 0xff, n & 0xff] +
                    [g[i][j] & 0xff for i in range(m) for j in range(n)])
    ser.reset_input_buffer()
    ser.write(payload)
    ser.flush()
    resp = ser.read(4)
    if len(resp) != 4:
        return None
    return int.from_bytes(resp, "big", signed=True)


def parse_grid(text):
    nums = [int(x) for x in text.replace(",", " ").split()]
    m, n = nums[0], nums[1]
    flat = nums[2:2 + m * n]
    if len(flat) != m * n:
        sys.exit("expected %d grid values, got %d" % (m * n, len(flat)))
    g = [flat[i * n:(i + 1) * n] for i in range(m)]
    return m, n, g


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", required=True, help="serial port, e.g. COM3 or /dev/ttyUSB0")
    ap.add_argument("--baud", type=int, default=9600)
    ap.add_argument("--grid", help='one dataset inline: "m n v00 v01 ... v(m-1)(n-1)"')
    ap.add_argument("--timeout", type=float, default=5.0, help="read timeout seconds")
    args = ap.parse_args()

    cases = [parse_grid(args.grid)] if args.grid else DATASETS

    with serial.Serial(args.port, args.baud, timeout=args.timeout) as ser:
        time.sleep(0.1)
        allok = True
        for idx, (m, n, g) in enumerate(cases):
            got = send_case(ser, m, n, g)
            exp = solve(m, n, g)
            if got is None:
                print("case %d: %dx%d  TIMEOUT (no/short response)" % (idx, m, n))
                allok = False
            else:
                ok = (got == exp)
                allok &= ok
                print("case %d: %dx%d  board=%d  ref=%d  %s"
                      % (idx, m, n, got, exp, "OK" if ok else "FAIL"))
            time.sleep(0.05)
        print("ALL OK" if allok else "SOME MISMATCH")
        sys.exit(0 if allok else 1)


if __name__ == "__main__":
    main()
