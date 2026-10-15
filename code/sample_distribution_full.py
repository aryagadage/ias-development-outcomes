"""
Full sample distribution of DC spells by education group, 1985-2008.
Produces figures/sample_distribution_full.pdf
"""

import duckdb
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

con = duckdb.connect()

# ── 1. Classify officers (highest Reference_Value row, tiebreak by priority) ──
edu_sql = """
WITH edu_raw AS (
    SELECT
        ID,
        Cadre,
        TRY_CAST(Reference_Value AS INTEGER) AS ref_val,
        CASE
            WHEN trim(Category_of_Subject) = 'Engineering, Technology and Mathematics'
                THEN 'Engineer'
            WHEN trim(Category_of_Subject) IN (
                    'Social Science and Liberal Arts',
                    'Governance, Law and Management')
                THEN 'SocialScientist'
            WHEN trim(Category_of_Subject) IN ('Natural Sciences', 'Medical')
                THEN 'NatSci_Medicine'
            WHEN trim(Category_of_Subject) = 'Languages and Fine Arts'
                THEN 'Arts'
            ELSE 'NA_Unclassified'
        END AS bg_class,
        CASE
            WHEN trim(Category_of_Subject) = 'Engineering, Technology and Mathematics'
                THEN 5
            WHEN trim(Category_of_Subject) IN (
                    'Social Science and Liberal Arts',
                    'Governance, Law and Management')
                THEN 4
            WHEN trim(Category_of_Subject) IN ('Natural Sciences', 'Medical')
                THEN 3
            WHEN trim(Category_of_Subject) = 'Languages and Fine Arts'
                THEN 2
            ELSE 1
        END AS bg_priority
    FROM read_csv_auto('data/raw/ias-education.csv',
                       nullstr=['N.A.','NA','n.a.','N/A',''])
),
ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY ID
               ORDER BY ref_val DESC NULLS LAST, bg_priority DESC
           ) AS rn
    FROM edu_raw
)
SELECT ID, Cadre, bg_class
FROM ranked
WHERE rn = 1
"""
edu = con.execute(edu_sql).df()

# ── 2. DC spells 1985-2008 ──────────────────────────────────────────────────
exp_sql = """
WITH exp_raw AS (
    SELECT
        ID,
        TRY_CAST(Start_Date AS DATE) AS start_dt,
        upper(trim(Designation))     AS desig_up
    FROM read_csv_auto('data/raw/ias-experience.csv',
                       nullstr=['N.A.','NA','n.a.','N/A',''],
                       types={'Start_Date':'VARCHAR','End_Date':'VARCHAR'})
)
SELECT ID, YEAR(start_dt) AS start_year
FROM exp_raw
WHERE start_dt IS NOT NULL
  AND YEAR(start_dt) BETWEEN 1985 AND 2008
  AND (   desig_up LIKE '%DISTRICT COLLECTOR%'
       OR desig_up LIKE '%COLLECTOR%'
       OR desig_up LIKE '%DISTRICT MAGISTRATE%'
       OR desig_up LIKE '%DEPUTY COMMISSIONER%'
  )
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
"""
exp = con.execute(exp_sql).df()

# ── 3. Join ─────────────────────────────────────────────────────────────────
merged = exp.merge(edu, on="ID", how="left")
merged["bg_class"] = merged["bg_class"].fillna("NA_Unclassified")
n_spells   = len(merged)
n_officers = merged["ID"].nunique()

# ── 4. Summary table: overall counts & % ────────────────────────────────────
ORDER = ["Engineer", "SocialScientist", "NatSci_Medicine", "Arts", "NA_Unclassified"]
LABELS = {
    "Engineer":        "Engineer",
    "SocialScientist": "Social Scientist",
    "NatSci_Medicine": "Nat. Sciences / Medical",
    "Arts":            "Languages & Arts",
    "NA_Unclassified": "N.A. / Unclassified",
}

overall = merged["bg_class"].value_counts().reindex(ORDER, fill_value=0)
print("=" * 55)
print("OVERALL GROUP DISTRIBUTION  (DC spells 1985-2008)")
print("=" * 55)
print(f"{'Group':<28} {'Count':>7}  {'%':>6}")
print("-" * 45)
for g in ORDER:
    n = overall[g]
    pct = 100 * n / n_spells
    print(f"{LABELS[g]:<28} {n:>7,}  {pct:>5.1f}%")
print("-" * 45)
print(f"{'TOTAL':<28} {n_spells:>7,}  100.0%")
print(f"\nUnique officers: {n_officers:,}")

# ── 5. NA breakdown by decade ────────────────────────────────────────────────
merged["decade"] = (merged["start_year"] // 10 * 10).astype(str) + "s"
na_mask = merged["bg_class"] == "NA_Unclassified"

dec_tab = (
    merged.groupby("decade")
    .agg(total=("ID","count"), na_count=("bg_class", lambda x: (x=="NA_Unclassified").sum()))
    .assign(na_pct=lambda d: (100 * d["na_count"] / d["total"]).round(1))
    .sort_index()
)
print("\n" + "=" * 45)
print("NA / UNCLASSIFIED BREAKDOWN BY DECADE")
print("=" * 45)
print(f"{'Decade':<10} {'Total':>7}  {'NA count':>9}  {'NA %':>6}")
print("-" * 38)
for dec, row in dec_tab.iterrows():
    print(f"{dec:<10} {int(row.total):>7,}  {int(row.na_count):>9,}  {row.na_pct:>5.1f}%")

# ── 6. NA breakdown by top-10 state cadres ──────────────────────────────────
# Use cadre from education file; for unmatched officers (left join miss) cadre is NaN
cadre_tab = (
    merged.groupby("Cadre")
    .agg(total=("ID","count"), na_count=("bg_class", lambda x: (x=="NA_Unclassified").sum()))
    .assign(na_pct=lambda d: (100 * d["na_count"] / d["total"]).round(1))
    .sort_values("total", ascending=False)
    .head(10)
)
print("\n" + "=" * 50)
print("NA / UNCLASSIFIED BY TOP-10 CADRES (by spell count)")
print("=" * 50)
print(f"{'Cadre':<22} {'Total':>7}  {'NA count':>9}  {'NA %':>6}")
print("-" * 45)
for cadre, row in cadre_tab.iterrows():
    lbl = str(cadre) if cadre == cadre else "[no cadre match]"
    print(f"{lbl[:22]:<22} {int(row.total):>7,}  {int(row.na_count):>9,}  {row.na_pct:>5.1f}%")

# ── 7. Annual stacked bar chart ──────────────────────────────────────────────
annual = (
    merged.groupby(["start_year", "bg_class"])
    .size()
    .unstack(fill_value=0)
    .reindex(columns=ORDER, fill_value=0)
)
annual_pct = annual.div(annual.sum(axis=1), axis=0) * 100
years = annual_pct.index.to_numpy()

COLORS = {
    "Engineer":        "#2166ac",
    "SocialScientist": "#fdae61",
    "NatSci_Medicine": "#4dac26",
    "Arts":            "#d01c8b",
    "NA_Unclassified": "#cccccc",
}

fig, ax = plt.subplots(figsize=(13, 5.5))

bottom = np.zeros(len(years))
# Plot from bottom: NA first so meaningful groups stack above
for grp in ["NA_Unclassified", "Arts", "NatSci_Medicine", "SocialScientist", "Engineer"]:
    vals = annual_pct[grp].to_numpy()
    ax.bar(years, vals, bottom=bottom,
           color=COLORS[grp], label=LABELS[grp],
           width=0.85, zorder=2)
    bottom += vals

ax.set_xlim(years[0] - 0.6, years[-1] + 0.6)
ax.set_ylim(0, 100)
ax.set_xlabel("Posting start year", fontsize=11)
ax.set_ylabel("Share of DC spells (%)", fontsize=11)
ax.set_title(
    "Educational background of IAS district collectors / DMs\n"
    "by posting start year, 1985–2008  (all groups)",
    fontsize=12, pad=10
)
ax.set_xticks(range(int(years[0]), int(years[-1]) + 1, 2))
ax.tick_params(axis="x", rotation=45)
ax.yaxis.grid(True, linestyle=":", linewidth=0.6, color="#999999", zorder=0)
ax.set_axisbelow(True)

# Legend: Engineer on top
handles, lbls = ax.get_legend_handles_labels()
ax.legend(handles[::-1], lbls[::-1],
          loc="upper left", framealpha=0.9, fontsize=9,
          title="Education background", title_fontsize=9)

ax.text(0.99, 0.03,
        f"N = {n_spells:,} spells | {n_officers:,} officers",
        transform=ax.transAxes, ha="right", va="bottom",
        fontsize=8, color="#555555")

fig.tight_layout()
out = "figures/sample_distribution_full.pdf"
fig.savefig(out, dpi=150, bbox_inches="tight")
print(f"\nSaved: {out}")
