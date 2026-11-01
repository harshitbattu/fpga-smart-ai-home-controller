#!/usr/bin/env python3
"""
ai_demo.py : hardware-in-the-loop test of the FPGA neural network.

Streams real, unseen measurements from the UCI Occupancy Detection test set to
the board with the command  "AI t rh lux co2", reads the FPGA's answer
"AI OCC=x P=yyy%", and reports the accuracy measured ON THE HARDWARE.

    pip install pyserial
    python tools/ai_demo.py COM5              (first 500 samples)
    python tools/ai_demo.py COM5 2000         (first 2000 samples)
"""
import csv, os, sys, time
import serial

port = sys.argv[1] if len(sys.argv) > 1 else "COM5"
n_max = int(sys.argv[2]) if len(sys.argv) > 2 else 500
here = os.path.dirname(os.path.abspath(__file__))
data = os.path.join(here, "..", "ai", "datatest2.txt")

rows = []
with open(data) as f:
    r = csv.reader(f); next(r)
    for row in r:
        rows.append((round(float(row[2]) * 10), round(float(row[3]) * 10),
                     min(9999, round(float(row[4]))), min(9999, round(float(row[5]))), int(row[7])))
# take an evenly spread subset so both occupied and empty periods are included
step = max(1, len(rows) // n_max)
rows = rows[::step][:n_max]

ser = serial.Serial(port, 115200, timeout=1)
time.sleep(0.2); ser.reset_input_buffer()
ok = tp = tn = fp = fn = 0
t0 = time.time()
for k, (t, rh, lx, co2, lab) in enumerate(rows, 1):
    ser.write(f"AI {t} {rh} {lx} {co2}\r".encode())
    while True:
        line = ser.readline().decode(errors="replace").strip()
        if line.startswith("AI OCC="):
            break
        if not line:
            print("no reply from board - check port / bitstream"); sys.exit(1)
    occ = int(line[7]); prob = line.split("P=")[1]
    ok += (occ == lab)
    tp += occ and lab; tn += (not occ) and (not lab); fp += occ and not lab; fn += (not occ) and lab
    if k <= 10 or k % 50 == 0:
        print(f"{k:5d}  T={t/10:4.1f}C RH={rh/10:4.1f}% lux={lx:4d} CO2={co2:4d}  truth={lab}  FPGA: occ={occ} P={prob:>4s}"
              f"   running accuracy {100*ok/k:6.2f} %")
dt = time.time() - t0
print(f"\nSamples {len(rows)}   hardware accuracy {100*ok/len(rows):.2f} %   TP {tp} TN {tn} FP {fp} FN {fn}   ({dt:.1f} s)")
