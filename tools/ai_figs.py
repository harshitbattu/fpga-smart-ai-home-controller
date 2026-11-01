import json, os
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Circle, FancyBboxPatch
r = json.load(open("ai/nn_results.json"))
INK, MUTED, GRID = "#1f2937", "#6b7280", "#e5e7eb"
BLUE, ORANGE, GREEN, RED, PURPLE = "#2563eb", "#d97706", "#059669", "#dc2626", "#7c3aed"
plt.rcParams.update({"font.family": "DejaVu Sans"})

def save(fig, name, dirs=("docs/figures", "paper")):
    for d in dirs:
        fig.savefig(os.path.join(d, name), bbox_inches="tight", dpi=250)
    plt.close(fig); print("wrote", name)

# ---------- accuracy vs baselines ----------
items = [("Always 'empty'", r["always_empty_acc"], MUTED), ("CO2 threshold", r["baseline_co2_acc"], MUTED),
         ("Temperature threshold", r["baseline_temp_acc"], MUTED), ("Logistic regression", r["logreg_acc"], MUTED),
         ("Light threshold (hand-tuned)", r["baseline_light_acc"], ORANGE),
         ("Neural network (float, Python)", r["acc_float"], BLUE), ("Neural network (8-bit, on FPGA)", r["acc_int8"], GREEN)]
fig, ax = plt.subplots(figsize=(6.4, 2.9))
ys = range(len(items))[::-1]
for y, (lab, v, c) in zip(ys, items):
    ax.barh(y, v * 100, color=c, height=0.62)
    ax.text(v * 100 + 0.4, y, f"{v*100:.2f} %", va="center", fontsize=8.5, color=INK)
ax.set_yticks(list(ys)); ax.set_yticklabels([i[0] for i in items], fontsize=8.5)
ax.set_xlim(70, 102); ax.set_xlabel("accuracy on 12 417 unseen test samples (%)", fontsize=9)
for s in ("top", "right"): ax.spines[s].set_visible(False)
ax.grid(axis="x", color=GRID, lw=0.6); ax.set_axisbelow(True)
save(fig, "fig_nn_accuracy.png")

# ---------- confusion matrix ----------
tp, tn, fp, fn = r["tp"], r["tn"], r["fp"], r["fn"]
fig, ax = plt.subplots(figsize=(3.1, 2.6))
M = [[tn, fp], [fn, tp]]
for i in range(2):
    for j in range(2):
        good = (i == j)
        ax.add_patch(plt.Rectangle((j, 1 - i), 1, 1, color=("#dcfce7" if good else "#fee2e2"), ec="white", lw=2))
        ax.text(j + 0.5, 1.5 - i, f"{M[i][j]}", ha="center", va="center", fontsize=13, color=INK, weight="bold")
ax.set_xlim(0, 2); ax.set_ylim(0, 2)
ax.set_xticks([0.5, 1.5]); ax.set_xticklabels(["predicted\nempty", "predicted\noccupied"], fontsize=8)
ax.set_yticks([1.5, 0.5]); ax.set_yticklabels(["actually\nempty", "actually\noccupied"], fontsize=8)
for s in ax.spines.values(): s.set_visible(False)
ax.tick_params(length=0)
ax.set_title(f"precision {r['precision']*100:.1f} %   recall {r['recall']*100:.1f} %", fontsize=8.5, color=MUTED)
save(fig, "fig_nn_confusion.png")

# ---------- network diagram ----------
fig, ax = plt.subplots(figsize=(6.4, 3.0)); ax.axis("off")
ins = ["Temperature\n(0.1 °C)", "Humidity\n(0.1 %)", "Light (lux)", "CO₂ (ppm)"]
xin, xn, xh, xo = 0.7, 2.3, 4.2, 6.0
yin = [2.7, 1.9, 1.1, 0.3]; yh = [3.15 - k * 0.43 for k in range(8)]
W1 = r["W1q"]; W2 = r["W2q"]
for i, y in enumerate(yin):
    for j, y2 in enumerate(yh):
        w = W1[j][i]
        ax.plot([xn + 0.35, xh - 0.13], [y, y2], color=(BLUE if w > 0 else RED), lw=0.2 + 1.6 * abs(w) / 127, alpha=0.55)
for j, y2 in enumerate(yh):
    w = W2[j]
    ax.plot([xh + 0.13, xo - 0.2], [y2, 1.5], color=(BLUE if w > 0 else RED), lw=0.2 + 1.6 * abs(w) / 127, alpha=0.7)
for lab, y in zip(ins, yin):
    ax.text(xin, y, lab, ha="center", va="center", fontsize=7.5, color=INK)
    ax.add_patch(FancyBboxPatch((xn - 0.35, y - 0.16), 0.7, 0.32, boxstyle="round,pad=0.02", fc="#fff7ed", ec=ORANGE))
    ax.text(xn, y, "normalise", ha="center", va="center", fontsize=6.5)
    ax.annotate("", xy=(xn - 0.36, y), xytext=(xin + 0.45, y), arrowprops=dict(arrowstyle="->", color=MUTED, lw=0.7))
for y2 in yh:
    ax.add_patch(Circle((xh, y2), 0.13, fc="#eef2ff", ec=PURPLE, lw=1))
ax.text(xh, -0.3, "8 hidden neurons\n(ReLU, 8-bit)", ha="center", fontsize=7.5, color=INK)
ax.add_patch(Circle((xo, 1.5), 0.2, fc="#ecfdf5", ec=GREEN, lw=1.4))
ax.text(xo + 0.35, 1.5, "occupied?\n+ probability", va="center", fontsize=7.5, color=INK)
ax.set_xlim(0, 7.4); ax.set_ylim(-0.6, 3.5)
ax.text(3.2, 3.45, "blue = positive weight, red = negative, thickness = |weight| (trained 8-bit values)", ha="center", fontsize=6.5, color=MUTED)
save(fig, "fig_nn_network.png")
