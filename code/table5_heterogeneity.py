"""
Table 5 – Heterogeneity analysis (IAS DC education project).

1. Panel B robustness: restrict to road_length_km > 0 (active PMGSY districts).
2. Engineer × Post2001 interaction on roads_rate.
3. Engineer × high_infra interaction on roads_rate, lights_rural, nrega_rate.
   Saves tables/table5_heterogeneity.tex.
"""

import os, warnings
warnings.filterwarnings("ignore")

import duckdb
import numpy as np
import pandas as pd
from linearmodels.panel import PanelOLS

os.makedirs("tables", exist_ok=True)
con = duckdb.connect()

# ══════════════════════════════════════════════════════════════════════════
# 1.  LOAD RAW DATA  (identical pipeline to build_tables.py)
# ══════════════════════════════════════════════════════════════════════════

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

profile = con.execute("""
SELECT
    ID                                           AS officer_id,
    TRY_CAST(Allotment_Year AS INTEGER)          AS allotment_year,
    CASE WHEN upper(trim(Gender)) = 'FEMALE'
         THEN 1 ELSE 0 END                       AS is_female
FROM read_csv_auto('data/raw/ias-profile.csv',
     nullstr=['N.A.','NA','n.a.','N/A'])
""").df()

exp = con.execute("""
SELECT
    ID                                           AS officer_id,
    trim(Cadre)                                  AS cadre,
    trim(Office)                                 AS office_nm,
    TRY_CAST(Start_Date AS DATE)                 AS start_dt,
    TRY_CAST(End_Date   AS DATE)                 AS end_dt,
    YEAR(TRY_CAST(Start_Date AS DATE))           AS start_year
FROM read_csv_auto('data/raw/ias-experience.csv',
     nullstr=['N.A.','NA','n.a.','N/A'],
     types={'Start_Date':'VARCHAR','End_Date':'VARCHAR'})
WHERE YEAR(TRY_CAST(Start_Date AS DATE)) BETWEEN 1985 AND 2008
  AND (upper(trim(Designation)) LIKE '%DISTRICT COLLECTOR%'
    OR upper(trim(Designation)) LIKE '%COLLECTOR%'
    OR upper(trim(Designation)) LIKE '%DISTRICT MAGISTRATE%'
    OR upper(trim(Designation)) LIKE '%DEPUTY COMMISSIONER%')
  AND upper(trim(Designation)) NOT LIKE '%ADDITIONAL%'
  AND upper(trim(Designation)) NOT LIKE '%JOINT%'
  AND upper(trim(Designation)) NOT LIKE '%JT %'
  AND upper(trim(Designation)) NOT LIKE '%SUB %'
  AND upper(trim(Designation)) NOT LIKE '%ASSISTANT%'
  AND upper(trim(Designation)) NOT LIKE '%DEPUTY COLLECTOR%'
  AND upper(trim(Designation)) NOT LIKE '%SPL DEPUTY%'
""").df()

cw_raw = pd.read_csv("data/analysis/crosswalk_v2.csv", dtype=str)
cw = (cw_raw[cw_raw["pc11_district_id"].notna() &
             ~cw_raw["pc11_district_id"].isin(["NA",""])].copy())
cw["cadre_key"]  = cw["cadre"].str.strip().str.lower()
cw["office_key"] = cw["office_name"].str.strip().str.lower()
cw["pc11_state_id"]    = cw["pc11_state_id"].str.strip().str.zfill(2)
cw["pc11_district_id"] = cw["pc11_district_id"].str.strip().str.zfill(3)

panel = con.execute("""
SELECT
    lpad(trim(pc11_state_id),    2, '0') AS pc11_state_id,
    lpad(trim(pc11_district_id), 3, '0') AS pc11_district_id,
    CAST(year AS INTEGER)                AS year,
    TRY_CAST(dmsp_total_light_cal AS DOUBLE) AS dmsp,
    TRY_CAST(roads_completed      AS DOUBLE) AS roads_completed,
    TRY_CAST(road_length_km       AS DOUBLE) AS road_length_km,
    TRY_CAST(ec_emp_all           AS DOUBLE) AS ec_emp_all,
    TRY_CAST(sc_share  AS DOUBLE) AS sc_share,
    TRY_CAST(st_share  AS DOUBLE) AS st_share,
    TRY_CAST(lit_rate  AS DOUBLE) AS lit_rate,
    TRY_CAST(tot_p     AS DOUBLE) AS tot_p,
    CAST(incumbent_won AS INTEGER) AS incumbent_won
FROM read_csv_auto('data/final/panel_full.csv',
     nullstr=['NA','N.A.','','#N/A'])
""").df()

# ══════════════════════════════════════════════════════════════════════════
# 2.  BUILD REGRESSION DATASET
# ══════════════════════════════════════════════════════════════════════════

exp["cadre_key"]  = exp["cadre"].str.lower()
exp["office_key"] = exp["office_nm"].str.lower()

spells = (exp
    .merge(cw[["cadre_key","office_key","pc11_state_id","pc11_district_id"]],
           on=["cadre_key","office_key"], how="inner")
    .merge(panel.rename(columns={"year":"start_year"}),
           on=["pc11_state_id","pc11_district_id","start_year"], how="inner")
    .merge(edu, on="officer_id", how="left")
)
spells["bg_class"] = spells["bg_class"].fillna("NA_Unclassified")
spells = spells.merge(profile[["officer_id","allotment_year","is_female"]],
                      on="officer_id", how="left")

spells["tenure_months"] = (
    (spells["end_dt"] - spells["start_dt"]).dt.days / 30.44).clip(lower=0)
spells["district_id"] = spells["pc11_state_id"] + spells["pc11_district_id"]

spells["lights_rural"] = spells["dmsp"] / spells["tot_p"]
spells["roads_rate"]   = np.where(
    spells["road_length_km"] > 0,
    spells["roads_completed"] / spells["road_length_km"],
    np.nan)
spells["nrega_rate"]   = spells["ec_emp_all"] / spells["tot_p"]

df = (spells[spells["bg_class"] != "NA_Unclassified"]
      .sort_values("start_dt")
      .drop_duplicates(subset=["district_id","start_year"], keep="first")
      .copy())

df["engineer"] = (df["bg_class"] == "Engineer").astype(float)
df["residual"] = (df["bg_class"] == "Residual").astype(float)

print(f"Regression dataset: {len(df):,} obs | {df['district_id'].nunique()} districts")

CTRL = ["engineer","residual","tenure_months","allotment_year","incumbent_won"]

# ══════════════════════════════════════════════════════════════════════════
# 3.  REGRESSION HELPER
# ══════════════════════════════════════════════════════════════════════════

def run_fe(data, outcome, regressors, cluster_at="district"):
    """District FE + state×year FE (always). Cluster by district or state."""
    d = data.dropna(subset=[outcome] + regressors).copy()
    if len(d) < 30:
        return None

    d["_sy"]  = d["pc11_state_id"] + "_" + d["start_year"].astype(str)
    sy_dum    = pd.get_dummies(d["_sy"], prefix="sy", drop_first=True)
    Xcols     = regressors + list(sy_dum.columns)
    d = pd.concat([d.reset_index(drop=True), sy_dum.reset_index(drop=True)], axis=1)

    d2 = d.set_index(["district_id", "start_year"])
    y  = d2[outcome]
    X  = d2[Xcols].astype(float)

    model = PanelOLS(y, X, entity_effects=True, time_effects=False,
                     drop_absorbed=True, check_rank=False)

    if cluster_at == "district":
        return model.fit(cov_type="clustered", cluster_entity=True)
    else:
        state_s = d.set_index(["district_id","start_year"])["pc11_state_id"]
        return model.fit(cov_type="clustered", clusters=state_s)


def gc(res, var):
    """Return (coef, se, pval) or (nan, nan, nan) if unavailable."""
    if res is None or var not in res.params.index:
        return np.nan, np.nan, np.nan
    return res.params[var], res.std_errors[var], res.pvalues[var]


def pstar(p):
    return "***" if p < 0.01 else "**" if p < 0.05 else "*" if p < 0.10 else ""


# ══════════════════════════════════════════════════════════════════════════
# PART 1: Panel B — restrict to road_length_km > 0
# ══════════════════════════════════════════════════════════════════════════

print(f"\n{'='*65}")
print("PART 1: Panel B restricted to road_length_km > 0")
print(f"{'='*65}")

df_roads_all    = df[df["start_year"] >= 2001].copy()
df_roads_active = df[(df["start_year"] >= 2001) & (df["road_length_km"] > 0)].copy()

for lbl, dat in [("Unrestricted (start>=2001)", df_roads_all),
                 ("road_length_km > 0 only",     df_roads_active)]:
    r = run_fe(dat, "roads_rate", CTRL)
    ec, ese, ep = gc(r, "engineer")
    rc, rse, rp = gc(r, "residual")
    n = int(r.nobs) if r else 0
    nn = dat["roads_rate"].notna().sum()
    print(f"\n  {lbl}:")
    print(f"    Obs in sample: {len(dat):,}   roads_rate non-null: {nn:,}   used in reg: {n:,}")
    print(f"    Engineer : {ec:+.4f} ({ese:.4f})  p={ep:.3f}")
    print(f"    Residual : {rc:+.4f} ({rse:.4f})  p={rp:.3f}")

# ══════════════════════════════════════════════════════════════════════════
# PART 2: Engineer × Post2001 interaction
# ══════════════════════════════════════════════════════════════════════════

print(f"\n{'='*65}")
print("PART 2: Engineer × Post2001 interaction  (outcome: roads_rate)")
print(f"{'='*65}")
print("  Post2001 = 1 if start_year >= 2002  |  full sample 1994-2008")
print("  (Post2001 itself absorbed by state×year FE)")

df_p2 = df.copy()
df_p2["post2001"] = (df_p2["start_year"] >= 2002).astype(float)
df_p2["eng_post"] = df_p2["engineer"] * df_p2["post2001"]

regs_p2 = ["engineer", "eng_post", "residual",
           "tenure_months", "allotment_year", "incumbent_won"]
r_p2 = run_fe(df_p2, "roads_rate", regs_p2)

ec,  ese,  ep  = gc(r_p2, "engineer")
epi, epse, epp = gc(r_p2, "eng_post")
rc,  rse,  rp  = gc(r_p2, "residual")
n_p2 = int(r_p2.nobs) if r_p2 else 0

print(f"\n  N (regression) = {n_p2:,}")
print(f"  Engineer (pre-2002 baseline) : {ec:+.4f} ({ese:.4f})  p={ep:.3f}")
print(f"  Engineer × Post2001          : {epi:+.4f} ({epse:.4f})  p={epp:.3f}")
print(f"  Implied post-2001 effect     : {ec+epi:+.4f}  (= Engineer + Eng×Post2001)")
print(f"  Residual                     : {rc:+.4f} ({rse:.4f})  p={rp:.3f}")
print(f"  Post2001 (main)              : absorbed by state×year FE")

# ══════════════════════════════════════════════════════════════════════════
# PART 3: Engineer × high_infra interaction
# ══════════════════════════════════════════════════════════════════════════

print(f"\n{'='*65}")
print("PART 3: Engineer × high_infra interaction")
print(f"{'='*65}")

# ── Compute high_infra from pre-period baseline ──────────────────────────
panel_km = panel.copy()
panel_km["district_id"] = panel_km["pc11_state_id"] + panel_km["pc11_district_id"]

# Step 1: road_length_km in year 2001 per district
road2001 = (panel_km[panel_km["year"] == 2001]
            .groupby("district_id")["road_length_km"]
            .first()
            .rename("baseline_road_km"))

# Step 2: fallback to earliest non-null year for districts missing 2001 obs
earliest = (panel_km
            .dropna(subset=["road_length_km"])
            .sort_values("year")
            .groupby("district_id")["road_length_km"]
            .first()
            .rename("fallback_km"))

baseline_km = (road2001.to_frame()
               .join(earliest, how="outer"))
baseline_km["baseline_road_km"] = (baseline_km["baseline_road_km"]
                                   .fillna(baseline_km["fallback_km"]))
baseline_km = baseline_km[["baseline_road_km"]].reset_index()

# Top-tercile cutoff (among districts with data)
thr = baseline_km["baseline_road_km"].quantile(2 / 3)
baseline_km["high_infra"] = (baseline_km["baseline_road_km"] >= thr).astype(float)

n_hi = int(baseline_km["high_infra"].sum())
n_tot = baseline_km["baseline_road_km"].notna().sum()
print(f"\n  Tercile threshold (top 33% of road_length_km in 2001): {thr:.2f} km")
print(f"  Districts with baseline data: {n_tot}  |  high_infra=1: {n_hi}")

# ── Merge high_infra into regression dataset ─────────────────────────────
df_hi = df.merge(baseline_km[["district_id","high_infra"]], on="district_id", how="left")
df_hi["eng_hi"] = df_hi["engineer"] * df_hi["high_infra"]

print(f"  Obs after merge (df_hi): {len(df_hi):,}  "
      f"| high_infra missing: {df_hi['high_infra'].isna().sum()}")

# Sub-samples matching each outcome's main table window
df_hi_roads = df_hi[df_hi["start_year"] >= 2001].copy()
df_hi_emp   = df_hi[df_hi["start_year"] >= 2006].copy()

OUTCOMES = [
    ("roads_rate",   df_hi_roads, "Roads completion rate  (2001-2008)"),
    ("lights_rural", df_hi,       "Nightlights per capita (1994-2008)"),
    ("nrega_rate",   df_hi_emp,   "Employment per capita  (2006-2008)"),
]

regs_hi = ["engineer", "eng_hi", "residual",
           "tenure_months", "allotment_year", "incumbent_won"]

res_hi = {}
print()
for outcome, dat, lbl in OUTCOMES:
    r = run_fe(dat, outcome, regs_hi)
    res_hi[outcome] = r

    ec,  ese,  ep  = gc(r, "engineer")
    ei,  eise, eip = gc(r, "eng_hi")
    rc,  rse,  rp  = gc(r, "residual")
    n = int(r.nobs) if r else 0

    print(f"  {lbl}   N={n:,}")
    print(f"    Engineer (low-infra):       {ec:+.4f} ({ese:.4f})  p={ep:.3f}")
    print(f"    Engineer × high_infra:      {ei:+.4f} ({eise:.4f})  p={eip:.3f}")
    print(f"    Implied (high-infra total): {ec+ei:+.4f}  (Engineer + Eng×high_infra)")
    print(f"    high_infra (main):          absorbed by district FE")
    print(f"    Residual:                   {rc:+.4f} ({rse:.4f})  p={rp:.3f}")
    print()

# ══════════════════════════════════════════════════════════════════════════
# SAVE TABLE 5
# ══════════════════════════════════════════════════════════════════════════

def write_table5(res_hi):
    path = "tables/table5_heterogeneity.tex"

    def fmt(c, s, p):
        if np.isnan(c):
            return "---", "---"
        return f"{c:.4f}{pstar(p)}", f"({s:.4f})"

    outcomes = [
        ("roads_rate",   "Roads rate"),
        ("lights_rural", "Lights/capita"),
        ("nrega_rate",   "Emp/capita"),
    ]

    L = [
        r"\begin{table}[htbp]", r"\centering",
        r"\caption{Heterogeneous Effects by Pre-Period Road Infrastructure}",
        r"\label{tab:heterogeneity}",
        r"\begin{tabular}{lccc}", r"\toprule",
        r" & (1) & (2) & (3) \\",
        r" & Roads rate & Lights/capita & Emp/capita \\",
        r"\midrule",
    ]

    # Engineer (low-infra)
    cv = [fmt(*gc(res_hi[oc], "engineer")) for oc, _ in outcomes]
    L.append("Engineer (low infra)         & " + " & ".join(c for c, _ in cv) + " \\\\")
    L.append("                             & " + " & ".join(s for _, s in cv) + " \\\\")
    L.append(r"\addlinespace")

    # Engineer × high_infra
    cv = [fmt(*gc(res_hi[oc], "eng_hi")) for oc, _ in outcomes]
    L.append(r"Engineer $\times$ high infra & " + " & ".join(c for c, _ in cv) + " \\\\")
    L.append("                             & " + " & ".join(s for _, s in cv) + " \\\\")
    L.append(r"\addlinespace")

    # Implied total effect in high-infra districts
    impl = []
    for oc, _ in outcomes:
        ec, _, _ = gc(res_hi[oc], "engineer")
        ei, _, _ = gc(res_hi[oc], "eng_hi")
        impl.append(f"{ec+ei:.4f}" if not (np.isnan(ec) or np.isnan(ei)) else "---")
    L.append(r"\quad Implied (high infra)   & " + " & ".join(impl) + " \\\\")
    L.append(r"\addlinespace")

    # high_infra main effect
    L.append(r"High infra (main)           & "
             r"\multicolumn{3}{c}{\textit{absorbed by district FE}} \\")
    L.append(r"\addlinespace")

    # Residual
    cv = [fmt(*gc(res_hi[oc], "residual")) for oc, _ in outcomes]
    L.append("Residual                     & " + " & ".join(c for c, _ in cv) + " \\\\")
    L.append("                             & " + " & ".join(s for _, s in cv) + " \\\\")

    L.append(r"\midrule")
    L.append(r"District FE        & \checkmark & \checkmark & \checkmark \\")
    L.append(r"State$\times$Year FE & \checkmark & \checkmark & \checkmark \\")
    L.append(r"Controls           & \checkmark & \checkmark & \checkmark \\")
    L.append(r"\midrule")

    ns  = [int(res_hi[oc].nobs)  if res_hi[oc] else 0       for oc, _ in outcomes]
    r2s = [res_hi[oc].rsquared   if res_hi[oc] else np.nan   for oc, _ in outcomes]
    L.append("$N$   & " + " & ".join(f"{n:,}" for n in ns) + " \\\\")
    L.append("$R^2$ & " + " & ".join(f"{r:.3f}" for r in r2s) + " \\\\")

    L += [
        r"\bottomrule", r"\end{tabular}",
        r"\begin{tablenotes}\footnotesize",
        r"\item Baseline education group: Social Scientist DCs.",
        r"\item \textit{High infra}: district in top tercile of total road length (km) "
        r"as of 2001 (or earliest available year). Time-invariant; main effect absorbed by "
        r"district FE. Interaction with Engineer is identified by within-district variation "
        r"in officer type across years.",
        r"\item Controls: tenure (months), allotment year, incumbent win dummy.",
        r"\item Col.\ (1): PMGSY sample 2001--2008. Col.\ (3): post-NREGA sample 2006--2008.",
        r"\item SE clustered at district. "
        r"$^{*}p<0.10$, $^{**}p<0.05$, $^{***}p<0.01$.",
        r"\end{tablenotes}", r"\end{table}",
    ]

    with open(path, "w") as f:
        f.write("\n".join(L))
    print(f"Saved {path}")


write_table5(res_hi)
print("\nDone.")
