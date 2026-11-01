# paper_figs.py : column-width (3.4 in) figures for the IEEE paper, from the same VCD data
import re, os
src = open("tools/plot_waves.py").read()
exec(src[:src.index("# ============================================================ system testbench")])
import matplotlib.pyplot as plt
OUT = "paper"
plt.rcParams.update({"font.size": 7.5})

class PWave(Wave):
    def __init__(self, rows, t0, t1, unit, title=None):
        self.t0, self.t1, self.unit = t0, t1, unit
        self.scale = {"ns": 1e9, "us": 1e6, "ms": 1e3, "s": 1}[unit]
        self.fig, self.ax = plt.subplots(figsize=(3.45, 0.36 * rows + 0.55), dpi=300)
        self.rows, self.row = rows, 0
        self.ax.set_xlim(t0 * self.scale, t1 * self.scale); self.ax.set_ylim(-0.4, rows * 1.0)
        self.ax.set_yticks([])
        for s in ("top", "right", "left"): self.ax.spines[s].set_visible(False)
        self.ax.set_xlabel(f"time ({unit})", fontsize=7); self.ax.tick_params(labelsize=6.5)
        self.ax.grid(axis="x", color=GRID, lw=0.5)
    def label(self, y, name):
        self.ax.text(self.t0 * self.scale - (self.t1 - self.t0) * self.scale * 0.015, y + 0.3, name,
                     ha="right", va="center", fontsize=7, color=INK)
    def save(self, fname):
        self.fig.tight_layout(); self.fig.subplots_adjust(left=0.24)
        self.fig.savefig(os.path.join(OUT, fname), bbox_inches="tight"); plt.close(self.fig); print("wrote", fname)

# gas latency
G = read_vcd("sim/tb_gas_latency.vcd")
t0, t1 = G["clk"][0][0], G["clk"][-1][0]
w = PWave(6, t0, t1, "ns")
w.bit(G["clk"], "clk (100 MHz)", MUTED); w.bit(G["gas_sw"], "gas input", RED)
w.bit(G["sync_ff1"], "sync FF1", PURPLE); w.bit(G["sync_ff2"], "sync FF2", PURPLE)
w.bit(G["valve"], "valve close", RED); w.bit(G["fan_pwm"], "exhaust fan", BLUE)
tg = next(t for t, v, r in G["gas_sw"] if v == 1); tv = next(t for t, v, r in G["valve"] if v == 1)
w.ax.axvline(tg * 1e9, color=RED, lw=0.7, ls="--"); w.ax.axvline(tv * 1e9, color=RED, lw=0.7, ls="--")
w.ax.annotate("", xy=(tv*1e9, 5.85), xytext=(tg*1e9, 5.85), arrowprops=dict(arrowstyle="<->", color=RED, lw=0.8))
w.ax.text((tg+tv)/2*1e9, 5.95, f"{(tv-tg)*1e9:.0f} ns", color=RED, fontsize=6.5, ha="center")
w.save("p_gas_latency.png")

# fan control
S = read_vcd("sim/tb_smart_home.vcd"); us = 1e-6
tempC = lambda v: signed(v, 13) / 16.0 if v is not None else 0
w = PWave(3, 640 * us, 1135 * us, "us")
w.analog(S["temp_raw"], "temperature", tempC, 27, 33, ORANGE, " C")
w.bit(S["hot"], "hysteresis H", GREEN)
w.bus(S["duty"], "fan duty", lambda v, r: f"{v}%")
w.save("p_fan.png")

# learned profile
log = open("sim/tb_smart_home.log").read()
m = re.search(r"<< PROFILE DAYS=(\d+)((?: \d\d=\d{3})+)", log)
vals = [int(x.split("=")[1]) for x in m.group(2).split()]
fig, ax = plt.subplots(figsize=(3.45, 1.7), dpi=300)
cols = [BLUE if v >= 160 else (GREEN if v >= 96 else ("#93c5fd" if v > 0 else GRID)) for v in vals]
ax.bar(range(24), [max(v, 1.5) for v in vals], color=cols, width=0.75)
for th, lab, c in [(160, "HIGH 160", RED), (96, "PRED 96", ORANGE), (40, "LOW 40", PURPLE)]:
    ax.axhline(th, color=c, lw=0.6, ls="--"); ax.text(-0.4, th + 4, lab, fontsize=5.5, color=c)
ax.set_xticks(range(0, 24, 2)); ax.tick_params(labelsize=6)
ax.set_xlabel("hour of day", fontsize=7); ax.set_ylabel("score s[h]", fontsize=7); ax.set_ylim(0, 260)
for s in ("top", "right"): ax.spines[s].set_visible(False)
fig.tight_layout(); fig.savefig(os.path.join(OUT, "p_profile.png")); plt.close(fig); print("wrote p_profile.png")
