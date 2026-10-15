"""
Comprehensive data audit — saves full output to diagnostics/data_audit.txt
and plots to diagnostics/

Source files:
  data/final/panel_full.csv              — main outcome panel
  data/raw/ias-experience.csv            — DC spells
  data/raw/ias-education.csv             — officer education
  data/raw/district_crosswalk_final.csv  — (cadre, office_name) → district_id
  data/raw/district_crosswalk.csv        — same but pre-finalisation (includes NAs)
  data/intermediate/census_baselines.csv — Census 2001 & 2011 district chars
"""

import os, sys, textwrap, warnings
warnings.filterwarnings("ignore")

import duckdb
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
from scipy.stats import chi2_contingency, ttest_ind

os.makedirs("diagnostics", exist_ok=True)

# ── Tee stdout → file ──────────────────────────────────────────────────────
class _Tee:
    def __init__(self, *fobjs): self._fs = fobjs
    def write(self, s):
        for f in self._fs: f.write(s); f.flush()
    def flush(self):
        for f in self._fs: f.flush()

_logf = open("diagnostics/data_audit.txt", "w")
sys.stdout = _Tee(sys.__stdout__, _logf)

def hr(title="", w=70):
    if title:
        pad = "─" * ((w - len(title) - 2) // 2)
        print(f"\n{pad} {title} {pad}")
    else:
        print("─" * w)

def flag(label, ok, detail=""):
    sym = "PASS" if ok else "FLAG"
    print(f"  [{sym}] {label}" + (f"  — {detail}" if detail else ""))
    return ok

# ══════════════════════════════════════════════════════════════════════════
# LOAD DATA
# ══════════════════════════════════════════════════════════════════════════

con = duckdb.connect()

panel = con.execute("""
SELECT
    lpad(trim(pc11_state_id),    2, '0') AS pc11_state_id,
    lpad(trim(pc11_district_id), 3, '0') AS pc11_district_id,
    CAST(year AS INTEGER)                AS year,
    TRY_CAST(dmsp_total_light_cal AS DOUBLE) AS dmsp,
    TRY_CAST(roads_completed      AS DOUBLE) AS roads_completed,
    TRY_CAST(road_length_km       AS DOUBLE) AS road_length_km,
    TRY_CAST(ec_emp_all           AS DOUBLE) AS ec_emp_all,
    TRY_CAST(ec_count_all         AS DOUBLE) AS ec_count_all,
    TRY_CAST(sc_share  AS DOUBLE) AS sc_share,
    TRY_CAST(st_share  AS DOUBLE) AS st_share,
    TRY_CAST(lit_rate  AS DOUBLE) AS lit_rate,
    TRY_CAST(tot_p     AS DOUBLE) AS tot_p,
    CAST(incumbent_won AS INTEGER) AS incumbent_won
FROM read_csv_auto('data/final/panel_full.csv',
     nullstr=['NA','N.A.','','#N/A'])
""").df()
panel["district_id"] = panel["pc11_state_id"] + panel["pc11_district_id"]

census = pd.read_csv("data/intermediate/census_baselines.csv", dtype={"pc11_state_id": str,
                                                                        "pc11_district_id": str})
census["pc11_state_id"]    = census["pc11_state_id"].str.zfill(2)
census["pc11_district_id"] = census["pc11_district_id"].str.zfill(3)
census["district_id"]      = census["pc11_state_id"] + census["pc11_district_id"]

edu = con.execute("""
WITH raw AS (
    SELECT ID,
        TRY_CAST(Reference_Value AS INTEGER) AS ref_val,
        CASE
            WHEN Category_of_Subject IS NULL OR trim(Category_of_Subject) = ''
                THEN 'NA_Unclassified'
            WHEN trim(Category_of_Subject) =
                 'Engineering, Technology and Mathematics' THEN 'Engineer'
            WHEN trim(Category_of_Subject) IN (
                 'Social Science and Liberal Arts',
                 'Governance, Law and Management') THEN 'SocialScientist'
            ELSE 'Residual'
        END AS bg_class,
        CASE
            WHEN Category_of_Subject IS NULL OR trim(Category_of_Subject) = '' THEN 0
            WHEN trim(Category_of_Subject) =
                 'Engineering, Technology and Mathematics' THEN 5
            WHEN trim(Category_of_Subject) IN (
                 'Social Science and Liberal Arts',
                 'Governance, Law and Management') THEN 4
            ELSE 3
        END AS bg_priority
    FROM read_csv_auto('data/raw/ias-education.csv',
         nullstr=['N.A.','NA','n.a.','N/A'])
),
ranked AS (
    SELECT *, ROW_NUMBER() OVER (
        PARTITION BY ID ORDER BY ref_val DESC NULLS LAST, bg_priority DESC) AS rn
    FROM raw
)
SELECT ID AS officer_id, bg_class FROM ranked WHERE rn = 1
""").df()

exp_all = con.execute("""
SELECT
    ID                                           AS officer_id,
    trim(Cadre)                                  AS cadre,
    trim(Office)                                 AS office_nm,
    YEAR(TRY_CAST(Start_Date AS DATE))           AS start_year,
    TRY_CAST(Start_Date AS DATE)                 AS start_dt,
    TRY_CAST(End_Date   AS DATE)                 AS end_dt,
    upper(trim(Designation))                     AS desig_up
FROM read_csv_auto('data/raw/ias-experience.csv',
     nullstr=['N.A.','NA','n.a.','N/A'],
     types={'Start_Date':'VARCHAR','End_Date':'VARCHAR'})
""").df()

DC_INCL = ["DISTRICT COLLECTOR","COLLECTOR","DISTRICT MAGISTRATE","DEPUTY COMMISSIONER"]
DC_EXCL = ["ADDITIONAL","JOINT","JT ","SUB ","ASSISTANT",
           "DEPUTY COLLECTOR","SPL DEPUTY","DEPUTY COMMISSIONER & COLLECTOR"]

def is_dc(desig):
    if not isinstance(desig, str): return False
    return (any(k in desig for k in DC_INCL) and
            not any(k in desig for k in DC_EXCL))

exp_dc = exp_all[
    exp_all["start_year"].between(1985, 2008) &
    exp_all["desig_up"].apply(is_dc)
].copy()

cw_final = pd.read_csv("data/analysis/crosswalk_v2.csv", dtype=str)
cw_final["pc11_state_id"]    = cw_final["pc11_state_id"].str.strip().str.zfill(2)
cw_final["pc11_district_id"] = cw_final["pc11_district_id"].str.strip()
cw_final["cadre_key"]  = cw_final["cadre"].str.strip().str.lower()
cw_final["office_key"] = cw_final["office_name"].str.strip().str.lower()

cw_matched = cw_final[cw_final["pc11_district_id"].notna() &
                       ~cw_final["pc11_district_id"].isin(["NA",""])].copy()
cw_matched["pc11_district_id"] = cw_matched["pc11_district_id"].str.zfill(3)
cw_matched["district_id"] = cw_matched["pc11_state_id"] + cw_matched["pc11_district_id"]

# Build full merged regression dataset (same as build_tables.py)
exp_dc["cadre_key"]  = exp_dc["cadre"].str.lower()
exp_dc["office_key"] = exp_dc["office_nm"].str.lower()

panel_no_id = panel.drop(columns=["district_id"])   # avoid name clash in merge
spells = (exp_dc
    .merge(cw_matched[["cadre_key","office_key","pc11_state_id","pc11_district_id"]],
           on=["cadre_key","office_key"], how="inner")
    .merge(panel_no_id.rename(columns={"year":"start_year"}),
           on=["pc11_state_id","pc11_district_id","start_year"], how="inner")
    .merge(edu, on="officer_id", how="left")
)
spells["district_id"]   = spells["pc11_state_id"] + spells["pc11_district_id"]
spells["bg_class"]      = spells["bg_class"].fillna("NA_Unclassified")
spells["tenure_months"] = ((spells["end_dt"] - spells["start_dt"]).dt.days / 30.44).clip(lower=0)

df = (spells[spells["bg_class"] != "NA_Unclassified"]
      .sort_values("start_dt")
      .drop_duplicates(subset=["district_id","start_year"], keep="first")
      .copy())
df["engineer"]       = (df["bg_class"] == "Engineer").astype(int)
df["social_sci"]     = (df["bg_class"] == "SocialScientist").astype(int)
df["residual"]       = (df["bg_class"] == "Residual").astype(int)
df["roads_rate"]     = np.where(df["road_length_km"] > 0,
                                df["roads_completed"] / df["road_length_km"], np.nan)
df["lights_rural"]   = df["dmsp"] / df["tot_p"]
df["nrega_rate"]     = df["ec_emp_all"] / df["tot_p"]

results = {}   # track PASS/FLAG per check

print("=" * 70)
print("  IAS DC EDUCATION — DATA AUDIT")
print("=" * 70)

# ══════════════════════════════════════════════════════════════════════════
# CHECK 1: DIMENSIONS
# ══════════════════════════════════════════════════════════════════════════
hr("CHECK 1: DIMENSIONS")

n_rows     = len(df)
n_districts = df["district_id"].nunique()
n_years     = df["start_year"].nunique()
n_officers  = df["officer_id"].nunique()

print(f"  Regression dataset (main analytic sample):")
print(f"    Total rows          : {n_rows:,}")
print(f"    Unique districts    : {n_districts:,}")
print(f"    Unique years        : {n_years:,}  ({df.start_year.min()}–{df.start_year.max()})")
print(f"    Unique officer IDs  : {n_officers:,}")
print()

edu_xtab = df["bg_class"].value_counts().rename("count")
edu_xtab["pct"] = (100 * edu_xtab / n_rows).round(1)
print("  District-year cells by DC education group:")
print(edu_xtab.to_string())
print()
print(f"  Panel_full dimensions: {len(panel):,} rows | "
      f"{panel['district_id'].nunique()} districts | "
      f"{panel['year'].nunique()} years ({panel.year.min()}–{panel.year.max()})")

results["1_dimensions"] = flag("Sample dimensions look plausible",
    n_rows >= 1000 and n_districts >= 300,
    f"{n_rows:,} rows, {n_districts} districts")

# ══════════════════════════════════════════════════════════════════════════
# CHECK 2: PMGSY OUTCOME
# ══════════════════════════════════════════════════════════════════════════
hr("CHECK 2: PMGSY OUTCOME")

pmgsy = panel[["district_id","year","roads_completed","road_length_km"]].copy()
pmgsy["roads_rate"] = np.where(pmgsy["road_length_km"] > 0,
                                pmgsy["roads_completed"] / pmgsy["road_length_km"], np.nan)

n_pre2001 = (pmgsy["year"] < 2001).sum()
print(f"  Rows with year < 2001 in panel_full    : {n_pre2001:,}  "
      f"(should be dropped, not zeroed, for PMGSY analysis)")

pmgsy_post = pmgsy[pmgsy["year"] >= 2001].copy()
n_true_zero = ((pmgsy_post["roads_completed"] == 0) &
               pmgsy_post["roads_completed"].notna()).sum()
n_na_post   = pmgsy_post["roads_completed"].isna().sum()
n_nn_post   = pmgsy_post["roads_completed"].notna().sum()

print(f"\n  Post-2001 roads_completed breakdown:")
print(f"    Non-null            : {n_nn_post:,}")
print(f"    True zeros          : {n_true_zero:,}  ({100*n_true_zero/len(pmgsy_post):.1f}% of post-2001 rows)")
print(f"    Missing (NA)        : {n_na_post:,}  ({100*n_na_post/len(pmgsy_post):.1f}% of post-2001 rows)")

print(f"\n  Distribution of roads_rate by year (2001–2008):")
print(f"  {'Year':>5} {'N_nn':>6} {'Mean':>8} {'SD':>8} {'P25':>8} {'P75':>8} {'Max':>8}")
print(f"  {'─'*5:>5} {'─'*6:>6} {'─'*8:>8} {'─'*8:>8} {'─'*8:>8} {'─'*8:>8} {'─'*8:>8}")
for yr in range(2001, 2009):
    s = pmgsy_post[pmgsy_post["year"] == yr]["roads_rate"].dropna()
    if len(s) == 0:
        print(f"  {yr:>5} {'0':>6}")
    else:
        print(f"  {yr:>5} {len(s):>6} {s.mean():>8.3f} {s.std():>8.3f} "
              f"{s.quantile(0.25):>8.3f} {s.quantile(0.75):>8.3f} {s.max():>8.3f}")

# Districts with full 2001-2008 PMGSY coverage
yr_range = set(range(2001, 2009))
dist_years = pmgsy_post[pmgsy_post["roads_completed"].notna()].groupby("district_id")["year"].apply(set)
n_full = (dist_years.apply(lambda s: yr_range.issubset(s))).sum()
n_any  = (dist_years.apply(len) > 0).sum()
print(f"\n  Districts with any PMGSY data (2001-2008)        : {n_any}")
print(f"  Districts with full 2001-2008 coverage            : {n_full}")
print(f"  Districts with gaps (has data but not every year) : {n_any - n_full}")

results["2_pmgsy"] = flag("PMGSY pre-2001 rows exist (must exclude in analysis)",
    n_pre2001 > 0, f"{n_pre2001:,} rows before 2001 in panel_full — always restrict to year>=2001")

# ══════════════════════════════════════════════════════════════════════════
# CHECK 3: FUZZY MATCH AUDIT
# ══════════════════════════════════════════════════════════════════════════
hr("CHECK 3: FUZZY MATCH AUDIT")

# Unique (cadre, office_nm) pairs attempted in DC spells 1985-2008
attempted = (exp_dc[["cadre","office_nm"]]
             .drop_duplicates()
             .assign(cadre_key=lambda d: d["cadre"].str.lower(),
                     office_key=lambda d: d["office_nm"].str.lower()))
n_attempted = len(attempted)

# Merge with crosswalk to classify as matched / unmatched
merged_cw = attempted.merge(
    cw_final[["cadre_key","office_key","pc11_district_id"]],
    on=["cadre_key","office_key"], how="left")
matched_mask   = merged_cw["pc11_district_id"].notna() & ~merged_cw["pc11_district_id"].isin(["NA",""])
unmatched_mask = ~matched_mask

n_matched   = matched_mask.sum()
n_unmatched = unmatched_mask.sum()
n_in_crosswalk_null = (merged_cw["pc11_district_id"].isin(["NA","","nan"]) |
                        (merged_cw["pc11_district_id"].isna() &
                         merged_cw["cadre_key"].isin(cw_final["cadre_key"]))).sum()

print(f"  Unique (cadre, office_name) pairs in DC exp (1985-2008): {n_attempted:,}")
print(f"  Matched to a district ID    : {n_matched:,}  ({100*n_matched/n_attempted:.1f}%)")
print(f"  Unmatched / null district   : {n_unmatched:,}  ({100*n_unmatched/n_attempted:.1f}%)")
print()
print("  Note: Crosswalk was built with Jaro-Winkler fuzzy matching in R.")
print("  Thresholds used: score>=0.90 → auto-accept; 0.80-0.90 → manual review;")
print("  <0.80 → permanent NA. 57 review rows manually resolved (5 accepted, rest nulled).")

# Spell-level match stats
exp_dc2 = exp_dc.copy()
exp_dc2["cadre_key"]  = exp_dc2["cadre"].str.lower()
exp_dc2["office_key"] = exp_dc2["office_nm"].str.lower()
exp_dc2 = exp_dc2.merge(
    cw_final[["cadre_key","office_key","pc11_district_id"]],
    on=["cadre_key","office_key"], how="left")
exp_dc2["matched"] = (exp_dc2["pc11_district_id"].notna() &
                      ~exp_dc2["pc11_district_id"].isin(["NA",""]))

n_spells_total    = len(exp_dc2)
n_spells_matched  = exp_dc2["matched"].sum()
n_spells_unmatched = (~exp_dc2["matched"]).sum()
print(f"\n  Total DC spells (1985-2008)      : {n_spells_total:,}")
print(f"  Spells matched to district       : {n_spells_matched:,}  "
      f"({100*n_spells_matched/n_spells_total:.1f}%)")
print(f"  Spells unmatched                 : {n_spells_unmatched:,}  "
      f"({100*n_spells_unmatched/n_spells_total:.1f}%)")

# Top 30 unmatched office strings by frequency
unmatched_spells = exp_dc2[~exp_dc2["matched"]]
top30 = (unmatched_spells.groupby(["cadre","office_nm"])
         .size().reset_index(name="n")
         .sort_values("n", ascending=False)
         .head(30))
print(f"\n  Top 30 unmatched (cadre, office_name) by spell frequency:")
print(f"  {'Rank':>4} {'N':>5}  {'Cadre':<25}  Office")
print(f"  {'─'*4} {'─'*5}  {'─'*25}  {'─'*30}")
for i, (_, row) in enumerate(top30.iterrows(), 1):
    office_str = str(row.office_nm)[:45]
    print(f"  {i:>4} {int(row.n):>5}  {str(row.cadre)[:25]:<25}  {office_str}")

# Chi-square: missingness by state
_sm = exp_dc2.groupby("cadre")["matched"].agg(["sum","count"]).rename(columns={"sum":"matched","count":"total"})
_sm["unmatched"] = _sm["total"] - _sm["matched"]
state_tab = _sm[_sm["total"] > 0][["matched","unmatched"]]
chi2_s, p_s, _, _ = chi2_contingency(state_tab.values)
print(f"\n  Chi-square test: missingness uniform across cadres?")
print(f"    chi2 = {chi2_s:.2f}   p = {p_s:.4f}  "
      f"→ {'NOT uniform (p<0.05)' if p_s < 0.05 else 'uniform (p>=0.05)'}")

# Chi-square: missingness by year
_ym = exp_dc2.groupby("start_year")["matched"].agg(["sum","count"]).rename(columns={"sum":"matched","count":"total"})
_ym["unmatched"] = _ym["total"] - _ym["matched"]
yr_tab = _ym[_ym["total"] > 0][["matched","unmatched"]]
chi2_y, p_y, _, _ = chi2_contingency(yr_tab.values)
print(f"    By year: chi2 = {chi2_y:.2f}   p = {p_y:.4f}  "
      f"→ {'NOT uniform' if p_y < 0.05 else 'uniform'}")

# Mean district chars: matched vs unmatched (join on cadre_key/office_key → district → census)
exp_dc2 = exp_dc2.merge(cw_matched[["cadre_key","office_key","district_id"]],
                         on=["cadre_key","office_key"], how="left")
exp_dc2 = exp_dc2.merge(census[["district_id","tot_p_01","lit_rate_01","sc_share_01"]],
                         on="district_id", how="left")

print(f"\n  Mean Census 2001 characteristics — matched vs unmatched spells:")
print(f"  {'Variable':<20} {'Matched':>12} {'Unmatched':>12} {'Diff':>10} {'p':>8}")
print(f"  {'─'*20} {'─'*12} {'─'*12} {'─'*10} {'─'*8}")
for col, lbl in [("tot_p_01","Population 2001"),
                  ("lit_rate_01","Literacy rate"),
                  ("sc_share_01","SC share")]:
    mv = exp_dc2[exp_dc2["matched"]][col].dropna()
    uv = exp_dc2[~exp_dc2["matched"]][col].dropna()
    if len(mv) > 1 and len(uv) > 1:
        t, p = ttest_ind(mv, uv)
        print(f"  {lbl:<20} {mv.mean():>12,.0f} {uv.mean():>12,.0f} "
              f"{mv.mean()-uv.mean():>+10,.0f} {p:>8.4f}")
    else:
        print(f"  {lbl:<20}  insufficient data for unmatched")

results["3_fuzzy"] = flag("Fuzzy match rate ≥ 80% of spells",
    n_spells_matched / n_spells_total >= 0.80,
    f"{100*n_spells_matched/n_spells_total:.1f}% of spells matched")

# ══════════════════════════════════════════════════════════════════════════
# CHECK 4: NIGHTLIGHTS
# ══════════════════════════════════════════════════════════════════════════
hr("CHECK 4: NIGHTLIGHTS (DMSP)")

print("  Note: dmsp_total_light_cal is a district-level AGGREGATE (sum of pixel values),")
print("  not a per-pixel DN value. Raw DN saturation at 63 corresponds to very bright")
print("  pixels; for aggregate data we flag districts in the top 1% as likely saturated.")
print()

# Year-wise summary
print(f"  {'Year':>5} {'N_nn':>5} {'Mean':>12} {'SD':>12} {'Min':>10} {'Max':>12} {'N_miss':>7}")
print(f"  {'─'*5} {'─'*5} {'─'*12} {'─'*12} {'─'*10} {'─'*12} {'─'*7}")
for yr in sorted(panel["year"].unique()):
    s = panel[panel["year"] == yr]["dmsp"].dropna()
    n_miss = (panel["year"] == yr).sum() - len(s)
    print(f"  {yr:>5} {len(s):>5} {s.mean():>12.1f} {s.std():>12.1f} "
          f"{s.min():>10.1f} {s.max():>12.1f} {n_miss:>7}")

# Saturation flag: top 1% globally
thresh_99 = panel["dmsp"].quantile(0.99)
sat_districts = (panel[panel["dmsp"] > thresh_99]
                 .groupby("district_id")["year"].count()
                 .sort_values(ascending=False))
print(f"\n  99th-percentile DMSP threshold: {thresh_99:,.1f}")
print(f"  Districts above threshold in ≥1 year: {len(sat_districts)}")
if len(sat_districts) > 0:
    print(f"  Top flagged districts (district_id: years above threshold):")
    for did, cnt in sat_districts.head(15).items():
        print(f"    {did}: {cnt} years")

results["4_dmsp_missing"] = flag("DMSP complete (no missing years)",
    panel.groupby("year")["dmsp"].count().min() == panel["district_id"].nunique(),
    "DMSP has full coverage every year" if
    panel.groupby("year")["dmsp"].count().min() == panel["district_id"].nunique()
    else "some year-district cells missing DMSP")

# Plot mean nightlights by year
yr_mean = panel.groupby("year")["dmsp"].mean()
fig, ax = plt.subplots(figsize=(10, 4))
ax.plot(yr_mean.index, yr_mean.values, marker="o", linewidth=2, color="#2166ac")
ax.set_xlabel("Year"); ax.set_ylabel("Mean DMSP total light (calibrated)")
ax.set_title("Mean DMSP Nightlights by Year — all 640 districts")
ax.yaxis.grid(True, linestyle=":", linewidth=0.6, color="#aaa")
ax.set_axisbelow(True)
fig.tight_layout()
fig.savefig("diagnostics/nightlights_trend.png", dpi=150, bbox_inches="tight")
plt.close(fig)
print(f"\n  Saved: diagnostics/nightlights_trend.png")

# ══════════════════════════════════════════════════════════════════════════
# CHECK 5: WELFARE VARIABLES
# ══════════════════════════════════════════════════════════════════════════
hr("CHECK 5: WELFARE VARIABLES")

welfare_vars = [("ec_emp_all","Economic Census employment"),
                ("ec_count_all","EC establishment count"),
                ("lit_rate","Literacy rate (panel)")]
thin_years = {}
print(f"  {'Year':>5}  {'ec_emp_all':>12}  {'ec_count_all':>13}  {'lit_rate':>10}")
print(f"  {'─'*5}  {'─'*12}  {'─'*13}  {'─'*10}")
for yr in sorted(panel["year"].unique()):
    sub = panel[panel["year"] == yr]
    emp_nn  = sub["ec_emp_all"].notna().sum()
    cnt_nn  = sub["ec_count_all"].notna().sum()
    lit_nn  = sub["lit_rate"].notna().sum()
    flag_yr = "*" if emp_nn < 100 else " "
    print(f"  {yr:>5}{flag_yr} {emp_nn:>12}  {cnt_nn:>13}  {lit_nn:>10}")
    if emp_nn < 100:
        thin_years[yr] = emp_nn

if thin_years:
    print(f"\n  [FLAG] Thin years (ec_emp_all < 100 obs): {thin_years}")
else:
    print(f"\n  All years have ≥100 non-missing ec_emp_all observations.")

results["5_welfare"] = flag("No thin welfare years (<100 obs)",
    len(thin_years) == 0,
    f"Thin years: {list(thin_years.keys())}" if thin_years else "all clear")

# ══════════════════════════════════════════════════════════════════════════
# CHECK 6: EDUCATION DUMMIES
# ══════════════════════════════════════════════════════════════════════════
hr("CHECK 6: EDUCATION DUMMIES")

# Mutual exclusivity
both = ((df["engineer"] == 1) & (df["social_sci"] == 1)).sum()
print(f"  Rows with Engineer=1 AND SocialSci=1 (should be 0): {both}")

# Missing education in analytic sample
# (NA_Unclassified already dropped from df; check what share of spells was dropped)
n_na_dropped = (spells["bg_class"] == "NA_Unclassified").sum()
n_total_spells = len(spells)
print(f"  Spells dropped due to NA/Unclassified education : "
      f"{n_na_dropped:,} / {n_total_spells:,} "
      f"({100*n_na_dropped/n_total_spells:.1f}%)")

# Education composition by year
print(f"\n  Education composition of DC spells by year (analytic sample):")
ann = (df.groupby("start_year")["bg_class"]
       .value_counts(normalize=True)
       .unstack(fill_value=0) * 100)
cols_order = [c for c in ["Engineer","SocialScientist","Residual"] if c in ann.columns]
ann = ann[cols_order]
print(f"  {'Year':>5}  " + "  ".join(f"{c[:12]:>12}" for c in cols_order))
print(f"  {'─'*5}  " + "  ".join("─"*12 for _ in cols_order))
for yr, row in ann.iterrows():
    print(f"  {yr:>5}  " + "  ".join(f"{row[c]:>11.1f}%" for c in cols_order))

# Flag: suspicious engineering surge post-2010 (data artifact concern)
if 2010 in ann.index:
    eng_pre2010  = ann.loc[ann.index < 2010, "Engineer"].mean() if "Engineer" in ann else np.nan
    eng_post2010 = ann.loc[ann.index >= 2010, "Engineer"].mean() if "Engineer" in ann else np.nan
    surge = (eng_post2010 - eng_pre2010) > 15  # >15pp jump
    print(f"\n  Mean Engineer share pre-2010 : {eng_pre2010:.1f}%")
    print(f"  Mean Engineer share post-2010: {eng_post2010:.1f}%")
    if surge:
        print(f"  [FLAG] >15pp post-2010 engineering surge — possible data artifact")
    else:
        print(f"  No suspicious post-2010 engineering surge.")

results["6_edu"] = flag("Education dummies mutually exclusive and non-trivial NA rate",
    both == 0 and n_na_dropped / n_total_spells < 0.30,
    f"both=1: {both}, NA drop rate: {100*n_na_dropped/n_total_spells:.1f}%")

# ══════════════════════════════════════════════════════════════════════════
# CHECK 7: PANEL BALANCE
# ══════════════════════════════════════════════════════════════════════════
hr("CHECK 7: PANEL BALANCE")

all_years = sorted(df["start_year"].unique())
n_yrs     = len(all_years)
dist_yr_counts = df.groupby("district_id")["start_year"].nunique()

n_balanced  = (dist_yr_counts == n_yrs).sum()
n_partial   = ((dist_yr_counts > 0) & (dist_yr_counts < n_yrs)).sum()
mean_yrs    = dist_yr_counts.mean()

print(f"  Years in window          : {all_years[0]}–{all_years[-1]}  ({n_yrs} years)")
print(f"  Districts with all {n_yrs} yrs : {n_balanced}  ({100*n_balanced/len(dist_yr_counts):.1f}%)")
print(f"  Districts with some years: {n_partial}  ({100*n_partial/len(dist_yr_counts):.1f}%)")
print(f"  Mean years per district  : {mean_yrs:.1f}")
print(f"  Panel is: {'STRONGLY balanced' if n_balanced/len(dist_yr_counts) > 0.80 else 'WEAKLY balanced'}")

# Distribution of year count per district
yr_dist = dist_yr_counts.value_counts().sort_index()
print(f"\n  Year count distribution across districts:")
print(f"  {'Yrs observed':>12}  {'N districts':>12}")
for yc, nd in yr_dist.items():
    bar = "█" * min(int(nd/5)+1, 40)
    print(f"  {yc:>12}  {nd:>12}  {bar}")

results["7_balance"] = flag("Panel ≥50% strongly balanced",
    n_balanced / len(dist_yr_counts) >= 0.50,
    f"{100*n_balanced/len(dist_yr_counts):.1f}% fully balanced")

# ── Panel coverage heatmap ────────────────────────────────────────────────
print(f"\n  Generating panel coverage heatmap...")

# Build a district × year grid with education category
all_dist = sorted(df["district_id"].unique())
grid_df  = (df.set_index(["district_id","start_year"])["bg_class"]
             .unstack()
             .reindex(index=all_dist, columns=all_years))

# Encode: Engineer=2, SocialScientist=1, Residual=0.5, missing=-1
def encode(val):
    if pd.isna(val):       return -1
    if val == "Engineer":   return 2
    if val == "SocialScientist": return 1
    return 0.5  # Residual

grid_num = grid_df.map(encode)

cmap = mcolors.ListedColormap(["#dddddd","#fdae61","#2166ac","#4dac26"])
bounds = [-1.5, -0.1, 0.9, 1.5, 2.5]
norm   = mcolors.BoundaryNorm(bounds, cmap.N)

fig_h = max(6, len(all_dist) * 0.04)
fig, ax = plt.subplots(figsize=(max(8, n_yrs * 0.5), fig_h))
im = ax.imshow(grid_num.values, aspect="auto", cmap=cmap, norm=norm,
               interpolation="nearest")

ax.set_xticks(range(n_yrs))
ax.set_xticklabels([str(y) for y in all_years], rotation=45, ha="right", fontsize=7)
ax.set_yticks([])
ax.set_ylabel(f"Districts (n={len(all_dist)})", fontsize=9)
ax.set_xlabel("Posting start year", fontsize=9)
ax.set_title("Panel coverage by district × year\n"
             "Blue=Engineer, Orange=Social Sci, Green=Residual, Grey=missing",
             fontsize=10)

from matplotlib.patches import Patch
legend_els = [Patch(facecolor="#2166ac", label="Engineer"),
              Patch(facecolor="#fdae61", label="Social Scientist"),
              Patch(facecolor="#4dac26", label="Residual"),
              Patch(facecolor="#dddddd", label="Missing")]
ax.legend(handles=legend_els, loc="lower right", fontsize=8, framealpha=0.9)
fig.tight_layout()
fig.savefig("diagnostics/panel_coverage.png", dpi=150, bbox_inches="tight")
plt.close(fig)
print(f"  Saved: diagnostics/panel_coverage.png")

# ══════════════════════════════════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════════════════════════════════
hr("AUDIT SUMMARY")

checks = {
    "1_dimensions": "Dimensions",
    "2_pmgsy":      "PMGSY outcome",
    "3_fuzzy":      "Fuzzy match",
    "4_dmsp_missing":"DMSP coverage",
    "5_welfare":    "Welfare variables",
    "6_edu":        "Education dummies",
    "7_balance":    "Panel balance",
}
all_pass = True
for key, label in checks.items():
    ok = results.get(key, False)
    sym = "PASS" if ok else "FLAG"
    print(f"  [{sym:4s}]  Check {key[0]}: {label}")
    if not ok: all_pass = False

print()
if all_pass:
    print("  OVERALL: ALL CHECKS PASSED")
else:
    n_flag = sum(1 for k in checks if not results.get(k, False))
    print(f"  OVERALL: {n_flag} FLAG(s) — review items above before proceeding")

# ── Close log ─────────────────────────────────────────────────────────────
sys.stdout = sys.__stdout__
_logf.close()
print("Saved: diagnostics/data_audit.txt")
print("Saved: diagnostics/nightlights_trend.png")
print("Saved: diagnostics/panel_coverage.png")
