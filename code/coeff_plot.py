"""
Coefficient plot for presentation.
Engineer coefficient (90% CI) from Spec 3: district + additive state + year FE
+ controls -- the same spec, sample, control set, and estimator (fixest) used
in tables/R1_infra.tex, tables/R1_lights.tex, tables/R1_welfare.tex.
Outcomes standardised to mean 0 SD 1 before regression so coefficients are
comparable across outcomes on one axis.

Numbers are computed in R (code/coeff_plot_data.R, via fixest::feols) rather
than recomputed here, so this figure is guaranteed to match the committed
tables' N, controls, and FE structure rather than drifting from them under a
separately-maintained Python implementation. Run
`Rscript code/coeff_plot_data.R` before this script if
diagnostics/coeff_plot_spec3.csv is stale or missing.
"""
import os, warnings
warnings.filterwarnings("ignore")

import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

os.makedirs("figures", exist_ok=True)

# ─────────────────────────────────────────────────────────────────────────────
# 1. LOAD  (precomputed by code/coeff_plot_data.R using fixest, matching the
#    R1_infra / R1_lights / R1_welfare table specification exactly)
# ─────────────────────────────────────────────────────────────────────────────

CI_Z = 1.645  # 90% two-sided

_res = pd.read_csv("diagnostics/coeff_plot_spec3.csv")
_order = ["roads_rate", "lights_rural", "emp_pc"]
_res = _res.set_index("var").loc[_order].reset_index()

results = []
for _, row in _res.iterrows():
    r = {"var": row["var"], "label": row["label"], "coef": row["coef"],
         "se": row["se"], "pval": row["pval"], "n": int(row["n"])}
    results.append(r)
    p_stars = "***" if r["pval"] < 0.01 else "**" if r["pval"] < 0.05 \
              else "*" if r["pval"] < 0.10 else ""
    print(f"{r['label'].split(chr(10))[0]:35s}  "
          f"β={r['coef']:+.4f}  SE={r['se']:.4f}  "
          f"p={r['pval']:.3f}{p_stars:3s}  N={r['n']:,}")

# ─────────────────────────────────────────────────────────────────────────────
# 3. PLOT
# ─────────────────────────────────────────────────────────────────────────────

# Presentation palette
BLUE      = "#2166AC"
BLUE_LITE = "#D1E5F0"
GREY      = "#AAAAAA"

fig, ax = plt.subplots(figsize=(7.5, 3.8))

# Outcomes plotted bottom-to-top
y_pos  = list(range(len(results)))           # 0, 1, 2
labels = [r["label"] for r in results]

for i, r in enumerate(results):
    lo = r["coef"] - CI_Z * r["se"]
    hi = r["coef"] + CI_Z * r["se"]

    # CI bar
    ax.plot([lo, hi], [i, i], color=BLUE, lw=2.2, solid_capstyle="round", zorder=3)
    # End ticks
    for x in [lo, hi]:
        ax.plot([x, x], [i - 0.08, i + 0.08], color=BLUE, lw=1.8, zorder=3)
    # Point estimate
    ax.scatter([r["coef"]], [i], color=BLUE, s=70, zorder=5, edgecolors="white", linewidths=0.8)

    # Annotate p-value
    stars = ("***" if r["pval"] < 0.01 else
             "**"  if r["pval"] < 0.05 else
             "*"   if r["pval"] < 0.10 else "")
    n_str = f"N={r['n']:,}{('  ' + stars) if stars else ''}"
    ax.text(hi + 0.01, i, n_str, va="center", ha="left",
            fontsize=8.5, color="#555555")

# Zero line
ax.axvline(0, color="#444444", lw=1.0, linestyle="--", zorder=2)

# Axes styling
ax.set_yticks(y_pos)
ax.set_yticklabels(labels, fontsize=10.5)
ax.set_xlabel("Engineer coefficient (standardised outcome)", fontsize=10.5)

# Determine x-axis limits with padding for annotation
all_lo = [r["coef"] - CI_Z * r["se"] for r in results]
all_hi = [r["coef"] + CI_Z * r["se"] for r in results]
x_min  = min(all_lo) - 0.05
x_max  = max(all_hi) + 0.20      # extra room for N labels
ax.set_xlim(x_min, x_max)
ax.set_ylim(-0.6, len(results) - 0.4)

# Remove top/right spines; keep bottom/left minimal
ax.spines["top"].set_visible(False)
ax.spines["right"].set_visible(False)
ax.spines["left"].set_visible(False)
ax.spines["bottom"].set_color("#CCCCCC")
ax.tick_params(axis="y", length=0)
ax.tick_params(axis="x", colors="#555555", labelsize=9)

# Shaded zero region
ax.axvspan(x_min, 0, alpha=0.03, color="#888888", zorder=1)

# Caption note inside figure
ax.text(0.99, -0.17,
        "Spec 3: district + state + year FE (additive) + controls (Residual, tenure, "
        "allotment year, opposition electoral turnover). 90% CI. SEs clustered at district.",
        transform=ax.transAxes, fontsize=7.5, color="#777777",
        ha="right", va="top", style="italic")

plt.tight_layout(rect=[0, 0.05, 1, 1])
plt.savefig("figures/coeff_plot_presentation.pdf", bbox_inches="tight", dpi=300)
plt.close()
print("\nSaved figures/coeff_plot_presentation.pdf")
