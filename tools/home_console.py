#!/usr/bin/env python3
"""
home_console.py : simple PC terminal for the FPGA smart home controller.
Shows every line from the board with a timestamp (events highlighted) and
sends what you type.

    pip install pyserial
    python home_console.py COM5          (Windows)
    python home_console.py /dev/ttyUSB1  (Linux)
"""
import sys, threading, time
import serial

port = sys.argv[1] if len(sys.argv) > 1 else "COM5"
ser = serial.Serial(port, 115200, timeout=0.1)
RED, YEL, RST = "\033[91m", "\033[93m", "\033[0m"

def reader():
    buf = b""
    while True:
        buf += ser.read(256)
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            txt = line.decode(errors="replace").strip()
            ts = time.strftime("%H:%M:%S")
            if txt.startswith("EVT GAS") or txt.startswith("EVT INTRUSION"):
                print(f"\r{RED}[{ts}] {txt}{RST}\n> ", end="")
            elif txt.startswith("EVT"):
                print(f"\r{YEL}[{ts}] {txt}{RST}\n> ", end="")
            else:
                print(f"\r[{ts}] {txt}\n> ", end="")

threading.Thread(target=reader, daemon=True).start()
print(f"Connected to {port} at 115200. Type HELP-free commands like STATUS, FAN 50, ARM 1234. Ctrl+C to quit.")
try:
    while True:
        cmd = input("> ")
        ser.write((cmd.strip() + "\r").encode())
except KeyboardInterrupt:
    pass
