#!/usr/bin/env python3
"""
plot_waves.py : renders report figures from the simulation VCD files
(tb_smart_home.vcd, tb_units_realtime.vcd, tb_gas_latency.vcd).
Every figure is drawn directly from simulated signal values.

Run from the project folder:  python3 tools/plot_waves.py
"""
import os, re
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon

OUT = "docs/figures"
os.makedirs(OUT, exist_ok=True)

INK, MUTED, GRID = "#1f2937", "#6b7280", "#e5e7eb"
BLUE, ORANGE, GREEN, RED, PURPLE = "#2563eb", "#d97706", "#059669", "#dc2626", "#7c3aed"
plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 9, "axes.edgecolor": MUTED,
                     "axes.labelcolor": INK, "xtick.color": MUTED, "ytick.color": MUTED})


# ------------------------------------------------------------------ VCD reader
def read_vcd(path):
    sigs, data, scope, t = {}, {}, [], 0
    tscale = 1e-12
    with open(path) as f:
        txt = f.read()
    m = re.search(r"\$timescale\s+(\d+)\s*(\w+)", txt)
    if m:
        tscale = int(m.group(1)) * {"s": 1, "ms": 1e-3, "us": 1e-6, "ns": 1e-9, "ps": 1e-12, "fs": 1e-15}[m.group(2)]
    head, _, body = txt.partition("$enddefinitions")
    for vm in re.finditer(r"\$var\s+\w+\s+(\d+)\s+(\S+)\s+(\S+)", head):
        width, code, name = int(vm.group(1)), vm.group(2), vm.group(3)
        sigs.setdefault(code, []).append(name)
        data.setdefault(name, [])
    code2names = sigs
    for line in body.split("\n"):
        line = line.strip()
        if not line or line.startswith("$"):
            continue
        if line[0] == "#":
            t = int(line[1:]) * tscale
        elif line[0] in "bB":
            val, code = line[1:].split()
            v = None if ("x" in val or "z" in val) else int(val, 2)
            for n in code2names.get(code, []):
                data[n].append((t, v, val))
        elif line[0] in "01xz":
            code = line[1:]
            v = None if line[0] in "xz" else int(line[0])
            for n in code2names.get(code, []):
                data[n].append((t, v, line[0]))
    return data


def window(ev, t0, t1):
    """events clipped to [t0,t1], including the value at t0"""
    prev = None
    out = []
    for t, v, raw in ev:
        if t <= t0:
            prev = (t0, v, raw)
        elif t <= t1:
            if prev is not None:
                out.append(prev); prev = None
            out.append((t, v, raw))
    if prev is not None:
        out.append(prev)
    if out:
        out.append((t1, out[-1][1], out[-1][2]))
    return out


def step_xy(ev, scale):
    xs, ys = [], []
    for i, (t, v, _) in enumerate(ev):
        v = 0 if v is None else v
        if i:
            xs.append(t * scale); ys.append(ys[-1])
        xs.append(t * scale); ys.append(v)
    return xs, ys


def signed(v, bits):
    if v is None:
        return None
    return v - (1 << bits) if v & (1 << (bits - 1)) else v


class Wave:
    """stacked digital / bus / analog traces sharing one time axis"""
    def __init__(self, rows, t0, t1, unit="us", title=None, height=None):
        self.t0, self.t1, self.unit = t0, t1, unit
        self.scale = {"ns": 1e9, "us": 1e6, "ms": 1e3, "s": 1}[unit]
        h = height or (0.55 * rows + 0.9)
        self.fig, self.ax = plt.subplots(figsize=(7.2, h), dpi=200)
        self.rows, self.row = rows, 0
        self.ax.set_xlim(t0 * self.scale, t1 * self.scale)
        self.ax.set_ylim(-0.4, rows * 1.0)
        self.ax.set_yticks([])
        for s in ("top", "right", "left"):
            self.ax.spines[s].set_visible(False)
        self.ax.set_xlabel(f"time ({unit})")
        self.ax.grid(axis="x", color=GRID, lw=0.6)
        if title:
            self.ax.set_title(title, fontsize=10, color=INK, loc="left")

    def _y(self):
        y = self.rows - 1 - self.row
        self.row += 1
        return y

    def label(self, y, name):
        self.ax.text(self.t0 * self.scale - (self.t1 - self.t0) * self.scale * 0.01, y + 0.3, name,
                     ha="right", va="center", fontsize=8.5, color=INK)

    def bit(self, ev, name, color=BLUE):
        y = self._y()
        xs, ys = step_xy(window(ev, self.t0, self.t1), self.scale)
        self.ax.plot(xs, [y + 0.6 * v for v in ys], color=color, lw=1.1, drawstyle="default")
        self.label(y, name)
        return y

    def bus(self, ev, name, fmt=lambda v, raw: str(v), color=PURPLE):
        y = self._y()
        w = window(ev, self.t0, self.t1)
        span = (self.t1 - self.t0) * self.scale
        for i in range(len(w) - 1):
            a, b = w[i][0] * self.scale, w[i + 1][0] * self.scale
            if b <= a:
                continue
            d = min(span * 0.004, (b - a) / 3)
            poly = [(a, y + 0.3), (a + d, y + 0.6), (b - d, y + 0.6), (b, y + 0.3), (b - d, y), (a + d, y)]
            self.ax.add_patch(Polygon(poly, closed=True, fill=True, fc="#f5f3ff", ec=color, lw=0.9))
            txt = fmt(w[i][1], w[i][2])
            if (b - a) > span * 0.035:
                self.ax.text((a + b) / 2, y + 0.3, txt, ha="center", va="center", fontsize=7, color=INK)
        self.label(y, name)
        return y

    def analog(self, ev, name, conv, lo, hi, color=ORANGE, unit=""):
        y = self._y()
        xs, ys = step_xy(window(ev, self.t0, self.t1), self.scale)
        ys = [conv(v) for v in ys]
        self.ax.plot(xs, [y + 0.05 + 0.8 * (v - lo) / (hi - lo) for v in ys], color=color, lw=1.3)
        self.ax.text(self.t1 * self.scale, y + 0.85, f"{hi}{unit}", fontsize=6.5, color=MUTED, ha="left", va="center")
        self.ax.text(self.t1 * self.scale, y + 0.05, f"{lo}{unit}", fontsize=6.5, color=MUTED, ha="left", va="center")
        self.label(y, name)
        return y

    def levels(self, ev, name, labels, color=PURPLE, rows=2):
        """multi-level state trace with a label for every level (takes `rows` rows)"""
        self.row += rows - 1
        y = self._y()
        n = len(labels) - 1
        xs, ys = step_xy(window(ev, self.t0, self.t1), self.scale)
        top = rows - 0.25
        self.ax.plot(xs, [y + 0.05 + top * v / n for v in ys], color=color, lw=1.4)
        for k, lab in enumerate(labels):
            yy = y + 0.05 + top * k / n
            self.ax.axhline(yy, color=GRID, lw=0.5, zorder=0)
            self.ax.text(self.t1 * self.scale, yy, " " + lab, fontsize=6.5, color=MUTED, va="center", ha="left")
        self.label(y + (rows - 1) / 2, name)
        return y

    def note(self, t, y, txt, color=RED):
        self.ax.annotate(txt, xy=(t * self.scale, y), xytext=(t * self.scale, y + 0.1),
                         fontsize=7, color=color, ha="center")

    def vline(self, t, txt=None, color=RED):
        self.ax.axvline(t * self.scale, color=color, lw=0.8, ls="--")
        if txt:
            self.ax.text(t * self.scale, self.rows - 0.25, txt, fontsize=7, color=color, ha="left", va="bottom")

    def save(self, fname):
        self.fig.tight_layout()
        self.fig.subplots_adjust(left=0.19)
        self.fig.savefig(os.path.join(OUT, fname), bbox_inches="tight")
        plt.close(self.fig)
        print("wrote", fname)


def bitof(ev, k):
    return [(t, None if v is None else (v >> k) & 1, raw) for t, v, raw in ev]


# ============================================================ system testbench
S = read_vcd("sim/tb_smart_home.vcd")
us = 1e-6
tempC = lambda v: signed(v, 13) / 16.0 if v is not None else 0

# ---- Fig: automatic fan control (T3) ----
w = Wave(5, 640 * us, 1135 * us, "us", "Automatic fan control: hysteresis and proportional speed (simulated)")
w.analog(S["temp_raw"], "temperature", tempC, 27, 33, ORANGE, " C")
w.bus(S["th"], "threshold TH", lambda v, r: f"{v} C")
w.bit(S["hot"], "hysteresis state", GREEN)
w.analog(S["duty"], "fan duty", lambda v: v or 0, 0, 100, BLUE, " %")
w.bus(S["duty"], "duty value", lambda v, r: f"{v}%")
w.save("fig_fan_control.png")

# ---- Fig: occupancy + lighting (T4) ----
w = Wave(6, 1135 * us, 1870 * us, "us", "Occupancy timeout, lighting and ECO fan control (1 s = 100 us in simulation)")
w.bit(bitof(S["sw"], 0), "motion (PIR)", BLUE)
w.bit(bitof(S["sw"], 1), "dark (LDR)", BLUE)
w.bit(S["occupied"], "occupied", GREEN)
w.bit(S["light_out"], "light relay", ORANGE)
w.analog(S["temp_raw"], "temperature", tempC, 25, 31, ORANGE, " C")
w.bus(S["duty"], "fan duty", lambda v, r: f"{v}%")
w.save("fig_occupancy_light.png")

# ---- Fig: gas emergency sequence (T7) ----
w = Wave(6, 2015 * us, 2680 * us, "us", "Gas-leak interlock: fast trip, latched until clear + ACK (simulated)")
w.bit(bitof(S["sw"], 2), "gas sensor", RED)
w.bit(S["emergency"], "emergency latch", RED)
w.bit(S["valve"], "gas valve close", RED)
w.bit(S["siren"], "siren", ORANGE)
w.bit(S["uart_rxd"], "UART RX (cmds)", MUTED)
w.bit(S["uart_txd"], "UART TX (events)", MUTED)
w.save("fig_gas_sequence.png")

# ---- Fig: security (T8) ----
secname = {0: "DISARMED", 1: "EXIT", 2: "ARMED", 3: "ENTRY", 4: "ALARM"}
w = Wave(7, 2680 * us, 7260 * us, "ms", "Security FSM: exit delay, entry delay, intrusion and disarm (1 s = 100 us)")
w.levels(S["sec_state"], "security state", ["DISARMED", "EXIT", "ARMED", "ENTRY", "ALARM"])
w.bit(bitof(S["sw"], 3), "door open", BLUE)
w.bit(bitof(S["sw"], 0), "motion", BLUE)
w.bit(S["siren"], "siren", RED)
w.bit(S["light_out"], "panic light", ORANGE)
w.bit(S["uart_txd"], "UART TX", MUTED)
w.save("fig_security.png")

# ---- Fig: learning (T10) ----
w = Wave(6, 10760 * us, 22400 * us, "ms", "On-chip occupancy learning over 5 simulated days (fast mode: 1 h = 100 us)")
w.analog(S["hh"], "hour of day", lambda v: v or 0, 0, 23, PURPLE, " h")
w.bit(bitof(S["sw"], 0), "motion", BLUE)
w.analog(S["cur_score"], "score s[hour]", lambda v: v or 0, 0, 255, GREEN, "")
w.bus(S["days"], "days learned", lambda v, r: str(v))
w.bit(S["predicted"], "predicted occ.", ORANGE)
w.bit(bitof(S["led"], 10), "warning LED", RED)
w.save("fig_learning.png")

# ============================================================ real-rate units
U = read_vcd("sim/tb_units_realtime.vcd")
# find the transmission of byte 0x55 on the UART line
ev = U["line"]
rx = U["rxd"]
t55 = next(t for t, v, raw in rx if v == 0x55)
t_start = max(t for t, v, raw in ev if v == 0 and t < t55)       # last falling edge before valid
t_start = max(t for t, v, raw in ev if t < t55 - 80e-6 and v == 0) if False else t_start
# start bit = first falling edge ~ 10 bit times before the valid pulse
cands = [t for t, v, raw in ev if v == 0 and t55 - 95e-6 < t < t55]
t_start = cands[0]
w = Wave(3, t_start - 10e-6, t_start + 100e-6, "us", "UART frame at 115200 baud: byte 0x55 (8.68 us per bit, real clock)")
w.bit(U["line"], "UART line", BLUE)
w.bit(U["rxv"], "rx valid", GREEN)
w.bus(U["rxd"], "rx data (latched)", lambda v, r: f"0x{v:02X}" if v is not None else "x")
for k, lab in enumerate(["start"] + [f"D{i}" for i in range(8)] + ["stop"]):
    w.ax.text((t_start + (k + 0.5) * 8.6806e-6) * 1e6, 2.8, lab, fontsize=6.5, ha="center", color=MUTED)
w.save("fig_uart_frame.png")

# I2C transaction (first complete read after 27.5 C was set)
tv = [t for t, v, raw in U["tvalid"] if v == 1]
t_end = tv[1]
w = Wave(4, t_end - 400e-6, t_end + 20e-6, "us", "I2C read of the ADT7420 at 100 kHz: address 0x4B + 2 data bytes (real clock)")
w.bit(U["scl"], "SCL", BLUE)
w.bit(U["sda"], "SDA", ORANGE)
w.bit(U["tvalid"], "temp valid", GREEN)
w.bus(U["traw"], "temp_raw", lambda v, r: f"{signed(v,13)} ({signed(v,13)/16:.2f} C)" if v is not None else "x")
w.save("fig_i2c.png")

# PWM 25 kHz
pe = [t for t, v, raw in U["pwm"] if v == 1]
tp = pe[len(pe) // 2]
w = Wave(2, tp - 5e-6, tp + 85e-6, "us", "Fan PWM: 25 kHz, 47 % duty (period 40 us, high 18.8 us, real clock)")
w.bit(U["pwm"], "fan PWM", BLUE)
w.bus(U["duty"], "duty", lambda v, r: f"{v} %")
w.save("fig_pwm.png")

# ============================================================ gas latency zoom
G = read_vcd("sim/tb_gas_latency.vcd")
t0 = G["clk"][0][0]
t1 = G["clk"][-1][0]
w = Wave(8, t0, t1, "ns", "Gas interlock at 100 MHz: valve closes on the 2nd clock edge after detection (max 20 ns)")
w.bit(G["clk"], "clk 100 MHz", MUTED)
w.bit(G["gas_sw"], "gas input", RED)
w.bit(G["sync_ff1"], "sync FF 1", PURPLE)
w.bit(G["sync_ff2"], "sync FF 2", PURPLE)
w.bit(G["emergency"], "emergency", RED)
w.bit(G["valve"], "valve close", RED)
w.bit(G["fan_pwm"], "exhaust fan", BLUE)
w.bit(G["siren"], "siren", ORANGE)
tg = next(t for t, v, raw in G["gas_sw"] if v == 1)
tv = next(t for t, v, raw in G["valve"] if v == 1)
w.vline(tg, " gas")
w.vline(tv, f" valve closed (+{(tv - tg) * 1e9:.0f} ns)")
w.save("fig_gas_latency.png")

# ============================================================ learned profile bar chart
log = open("sim/tb_smart_home.log").read()
line = re.search(r"<< PROFILE DAYS=(\d+)((?: \d\d=\d{3})+)", log)
vals = [int(x.split("=")[1]) for x in line.group(2).split()]
fig, ax = plt.subplots(figsize=(7.2, 2.6), dpi=200)
cols = [BLUE if v >= 160 else (GREEN if v >= 96 else ("#93c5fd" if v > 0 else GRID)) for v in vals]
ax.bar(range(24), [max(v, 1.5) for v in vals], color=cols, width=0.75)
for th, lab, c in [(160, "HIGH_TH 160 (inactivity alert)", RED), (96, "PRED_TH 96 (pre-cool)", ORANGE), (40, "LOW_TH 40 (anomaly)", PURPLE)]:
    ax.axhline(th, color=c, lw=0.8, ls="--")
    ax.text(23.6, th + 3, lab, fontsize=6.5, color=c, ha="right")
ax.set_xticks(range(24)); ax.set_xlabel("hour of day"); ax.set_ylabel("score s[h]  (252 = always occupied)")
ax.set_ylim(0, 260)
for s in ("top", "right"):
    ax.spines[s].set_visible(False)
ax.set_title(f"Learned occupancy profile read back with the PROFILE command (day {int(line.group(1))+1}, 17:xx)",
             fontsize=10, loc="left", color=INK)
fig.tight_layout(); fig.savefig(os.path.join(OUT, "fig_profile.png")); plt.close(fig)
print("wrote fig_profile.png")
