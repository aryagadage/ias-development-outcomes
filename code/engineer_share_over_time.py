"""
Engineer share of DC spells by year, 1985-2008.
Produces figures/engineer_share_over_time.pdf
"""

import duckdb
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from scipy.stats import gaussian_kde
from scipy.interpolate import make_smoothing_spline

con = duckdb.connect()

# ── 1. Classify officers from education ────────────────────────────────────
# Actual CSV value for engineering: 'Engineering, Technology and Mathematics'
# Priority for tiebreak: Engineer (2) > SocialScientist (1) > Residual (0)
edu_sql = """
WITH edu_raw AS (
    SELECT
        ID,
        TRY_CAST(Reference_Value AS INTEGER) AS ref_val,
        CASE
            WHEN trim(Category_of_Subject) = 'Engineering, Technology and Mathematics'
                THEN 'Engineer'
            WHEN trim(Category_of_Subject) IN (
                    'Social Science and Liberal Arts',
                    'Governance, Law and Management')
                THEN 'SocialScientist'
            ELSE 'Residual'
        END AS bg_class,
        CASE
            WHEN trim(Category_of_Subject) = 'Engineering, Technology and Mathematics'
                THEN 2
            WHEN trim(Category_of_Subject) IN (
                    'Social Science and Liberal Arts',
                    'Governance, Law and Management')
                THEN 1
            ELSE 0
        END AS bg_priority
    FROM read_csv_auto('data/raw/ias-education.csv',
                       nullstr=['N.A.','NA','n.a.','N/A',''])
),
-- For each officer: pick row with max ref_val; break ties by bg_priority
ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY ID
               ORDER BY ref_val DESC NULLS LAST, bg_priority DESC
           ) AS rn
    FROM edu_raw
)
SELECT ID, bg_class
FROM ranked
WHERE rn = 1
"""
edu = con.execute(edu_sql).df()
print(f"Officers classified: {len(edu):,}  "
      f"({edu.bg_class.value_counts().to_dict()})")

# ── 2. DC spells 1985-2008 from experience ────────────────────────────────
exp_sql = """
WITH exp_raw AS (
    SELECT
        ID,
        TRY_CAST(Start_Date AS DATE) AS start_dt,
        upper(trim(Designation))     AS desig_up
    FROM read_csv_auto('data/raw/ias-experience.csv',
                       nullstr=['N.A.','NA','n.a.','N/A',''],
                       types={'Start_Date':'VARCHAR','End_Date':'VARCHAR'})
),
dc_spells AS (
    SELECT ID, YEAR(start_dt) AS start_year
    FROM exp_raw
    WHERE start_dt IS NOT NULL
      AND YEAR(start_dt) BETWEEN 1985 AND 2008
      -- include primary DC titles
      AND (   desig_up LIKE '%DISTRICT COLLECTOR%'
           OR desig_up LIKE '%COLLECTOR%'
           OR desig_up LIKE '%DISTRICT MAGISTRATE%'
           OR desig_up LIKE '%DEPUTY COMMISSIONER%'
      )
      -- exclude subordinate / compound roles
      AND desig_up NOT LIKE '%ADDITIONAL%'
      AND desig_up NOT LIKE '%JOINT%'
      AND desig_up NOT LIKE '%JT %'
      AND desig_up NOT LIKE '%JT.%'
      AND desig_up NOT LIKE '%SUB %'
      AND desig_up NOT LIKE '%SUB-%'
      AND desig_up NOT LIKE '%ASSISTANT%'
      AND desig_up NOT LIKE '%DEPUTY COMMISSIONER & COLLECTOR%'
      AND desig_up NOT LIKE '%DEPUTY COLLECTOR%'
      AND desig_up NOT LIKE '%SPL DEPUTY%'
      AND desig_up NOT LIKE '%SPL. DEPUTY%'
)
SELECT * FROM dc_spells
"""
exp = con.execute(exp_sql).df()
print(f"DC spells 1985-2008: {len(exp):,}  years {exp.start_year.min()}-{exp.start_year.max()}")

# ── 3. Join & aggregate ────────────────────────────────────────────────────
merged = exp.merge(edu, on="ID", how="left")
merged["bg_class"] = merged["bg_class"].fillna("Residual")

annual = (
    merged.groupby(["start_year", "bg_class"])
    .size()
    .unstack(fill_value=0)
    .reindex(columns=["Engineer", "SocialScientist", "Residual"], fill_value=0)
)
annual_pct = annual.div(annual.sum(axis=1), axis=0) * 100
years = annual_pct.index.to_numpy()

print("\nAnnual spell counts (first 5 rows):")
print(annual.head())

# ── 4. Plot ────────────────────────────────────────────────────────────────
COLORS = {
    "Engineer":        "#2166ac",   # blue
    "SocialScientist": "#fdae61",   # amber
    "Residual":        "#d1d1d1",   # light grey
}
LABELS = {
    "Engineer":        "Engineer",
    "SocialScientist": "Social Scientist",
    "Residual":        "Residual / Unknown",
}

fig, ax = plt.subplots(figsize=(12, 5.5))

bottom = np.zeros(len(years))
for grp in ["Residual", "SocialScientist", "Engineer"]:
    vals = annual_pct[grp].to_numpy()
    ax.bar(years, vals, bottom=bottom,
           color=COLORS[grp], label=LABELS[grp],
           width=0.85, zorder=2)
    bottom += vals

# Smoothed trend line for Engineer share (lowess-style via smoothing spline)
eng_share = annual_pct["Engineer"].to_numpy()
try:
    spl = make_smoothing_spline(years.astype(float), eng_share, lam=50)
    xs  = np.linspace(years[0], years[-1], 300)
    ax.plot(xs, np.clip(spl(xs), 0, 100),
            color="white", linewidth=2.2, linestyle="--",
            zorder=5, label="Engineer share (smoothed)")
except Exception:
    # fallback: rolling mean
    from numpy.lib.stride_tricks import sliding_window_view
    w = 5
    rm = np.convolve(eng_share, np.ones(w)/w, mode='same')
    ax.plot(years, rm, color="white", linewidth=2.2, linestyle="--",
            zorder=5, label="Engineer share (5-yr avg)")

ax.set_xlim(years[0] - 0.5, years[-1] + 0.5)
ax.set_ylim(0, 100)
ax.set_xlabel("Posting start year", fontsize=11)
ax.set_ylabel("Share of DC spells (%)", fontsize=11)
ax.set_title("Educational background of IAS district collectors / DMs\n"
             "by posting start year, 1985–2008", fontsize=12, pad=10)
ax.set_xticks(range(years[0], years[-1] + 1, 2))
ax.tick_params(axis="x", rotation=45)
ax.yaxis.grid(True, linestyle=":", linewidth=0.6, color="#999999", zorder=0)
ax.set_axisbelow(True)

handles, lbls = ax.get_legend_handles_labels()
ax.legend(handles[::-1], lbls[::-1],
          loc="upper left", framealpha=0.9, fontsize=9)

n_spells = int(annual.sum().sum())
n_officers = merged["ID"].nunique()
ax.text(0.99, 0.03,
        f"N = {n_spells:,} spells | {n_officers:,} officers",
        transform=ax.transAxes, ha="right", va="bottom",
        fontsize=8, color="#555555")

fig.tight_layout()
fig.savefig("figures/engineer_share_over_time.pdf", dpi=150, bbox_inches="tight")
print("\nSaved: figures/engineer_share_over_time.pdf")
