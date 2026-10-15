"""
Build data/analysis/dc_analysis_balanced.csv for IV estimation.
Adds to the main analytic sample:
  CM_turnover    : 1 if incumbent party lost in state s in year t
  seniority_rank : officer's rank within cadre by allotment_year (1=most senior)
  Queue_st       : CM_turnover × seniority_rank_std  (the instrument)
"""
import os, warnings
warnings.filterwarnings("ignore")

import duckdb
import numpy as np
import pandas as pd

os.makedirs("data/analysis", exist_ok=True)
con = duckdb.connect()

# ── Education ─────────────────────────────────────────────────────────────
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

# ── Officer profile ───────────────────────────────────────────────────────
profile = con.execute("""
SELECT
    ID                                           AS officer_id,
    trim(Cadre)                                  AS cadre,
    TRY_CAST(Allotment_Year AS INTEGER)          AS allotment_year,
    CASE WHEN upper(trim(Gender)) = 'FEMALE'
         THEN 1 ELSE 0 END                       AS is_female
FROM read_csv_auto('data/raw/ias-profile.csv',
     nullstr=['N.A.','NA','n.a.','N/A'])
""").df()

# ── DC spells ─────────────────────────────────────────────────────────────
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

# ── Panel outcomes ────────────────────────────────────────────────────────
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
    CASE WHEN upper(CAST(incumbent_won AS VARCHAR)) IN ('YES','TRUE','1') THEN 1
         WHEN upper(CAST(incumbent_won AS VARCHAR)) IN ('NO','FALSE','0') THEN 0
         ELSE NULL END AS incumbent_won_bin
FROM read_csv_auto('data/final/panel_full.csv',
     nullstr=['NA','N.A.','','#N/A'])
""").df()

# ── Crosswalk ─────────────────────────────────────────────────────────────
cw_raw = pd.read_csv("data/analysis/crosswalk_v2.csv", dtype=str)
cw = (cw_raw[cw_raw["pc11_district_id"].notna() &
             ~cw_raw["pc11_district_id"].isin(["NA",""])].copy())
cw["cadre_key"]  = cw["cadre"].str.strip().str.lower()
cw["office_key"] = cw["office_name"].str.strip().str.lower()
cw["pc11_state_id"]    = cw["pc11_state_id"].str.strip().str.zfill(2)
cw["pc11_district_id"] = cw["pc11_district_id"].str.strip().str.zfill(3)

# ══════════════════════════════════════════════════════════════════════════
# 2. CM_TURNOVER  (state × year)
# incumbent_won = 0 → incumbent party lost → new CM likely
# ══════════════════════════════════════════════════════════════════════════

politics = (panel[["pc11_state_id","year","incumbent_won_bin"]]
            .drop_duplicates(subset=["pc11_state_id","year"])
            .copy())
politics["CM_turnover"] = (politics["incumbent_won_bin"] == 0).astype(float)
# Carry forward: in years without a recorded election, treat as CM_turnover=0
politics["CM_turnover"] = politics["CM_turnover"].fillna(0.0)

print("CM_turnover distribution (state-year level):")
print(politics["CM_turnover"].value_counts())
n_st = len(politics)
n_to = int(politics["CM_turnover"].sum())
print(f"  Turnover: {n_to}/{n_st} state-years  ({100*n_to/n_st:.1f}%)\n")

# ══════════════════════════════════════════════════════════════════════════
# 3. SENIORITY_RANK  (officer level, within cadre)
# Rank 1 = most senior (earliest allotment_year)
# Standardised within cadre so coefficient is in SDs
# ══════════════════════════════════════════════════════════════════════════

sen = (profile[["officer_id","cadre","allotment_year"]]
       .dropna(subset=["allotment_year"])
       .copy())
sen["seniority_rank"] = (
    sen.groupby("cadre")["allotment_year"]
       .rank(method="average", ascending=True)
)
# Standardise within cadre (mean 0, sd 1)
sen["seniority_rank_std"] = (
    sen.groupby("cadre")["seniority_rank"]
       .transform(lambda x: (x - x.mean()) / x.std())
)
print("Seniority rank (std, within cadre):")
print(sen["seniority_rank_std"].describe().round(3), "\n")

# ══════════════════════════════════════════════════════════════════════════
# 4. MERGE EVERYTHING
# ══════════════════════════════════════════════════════════════════════════

exp["cadre_key"]  = exp["cadre"].str.lower()
exp["office_key"] = exp["office_nm"].str.lower()

spells = (exp
    .merge(cw[["cadre_key","office_key","pc11_state_id","pc11_district_id"]],
           on=["cadre_key","office_key"], how="inner")
    .merge(panel.rename(columns={"year":"start_year"}),
           on=["pc11_state_id","pc11_district_id","start_year"], how="inner")
    .merge(edu, on="officer_id", how="left")
    .merge(profile[["officer_id","allotment_year","is_female"]],
           on="officer_id", how="left")
    .merge(sen[["officer_id","seniority_rank","seniority_rank_std"]],
           on="officer_id", how="left")
    .merge(politics[["pc11_state_id","year","CM_turnover"]]
                   .rename(columns={"year":"start_year"}),
           on=["pc11_state_id","start_year"], how="left")
)
spells["bg_class"] = spells["bg_class"].fillna("NA_Unclassified")

# Outcomes
spells["tenure_months"] = (
    (spells["end_dt"] - spells["start_dt"]).dt.days / 30.44).clip(lower=0)
spells["district_id"]  = spells["pc11_state_id"] + spells["pc11_district_id"]
spells["lights_rural"] = spells["dmsp"] / spells["tot_p"]
spells["roads_rate"]   = np.where(
    spells["road_length_km"] > 0,
    spells["roads_completed"] / spells["road_length_km"], np.nan)

# Instrument
spells["Queue_st"] = spells["CM_turnover"] * spells["seniority_rank_std"]

# ══════════════════════════════════════════════════════════════════════════
# 5. ANALYTIC SAMPLE: drop unclassified, dedup to first spell per dist-year
# ══════════════════════════════════════════════════════════════════════════

df = (spells[spells["bg_class"] != "NA_Unclassified"]
      .sort_values("start_dt")
      .drop_duplicates(subset=["district_id","start_year"], keep="first")
      .copy())

df["Engineer"] = (df["bg_class"] == "Engineer").astype(float)
df["Residual"] = (df["bg_class"] == "Residual").astype(float)

print(f"Analytic sample: {len(df):,} obs | {df['district_id'].nunique()} districts")
print(f"Queue_st non-null : {df['Queue_st'].notna().sum():,}")
print(f"CM_turnover = 1   : {(df['CM_turnover']==1).sum():,} obs")
print(f"\nQueue_st summary:")
print(df["Queue_st"].describe().round(4))
print(f"\nEngineer vs Queue_st correlation: "
      f"{df[['Engineer','Queue_st']].dropna().corr().iloc[0,1]:.4f}")

# ══════════════════════════════════════════════════════════════════════════
# 6. SAVE
# ══════════════════════════════════════════════════════════════════════════

keep = [
    "district_id", "pc11_state_id", "start_year",
    "Engineer", "Residual",
    "roads_rate", "lights_rural", "ec_emp_all", "lit_rate",
    "tot_p", "sc_share", "st_share",
    "tenure_months", "allotment_year", "is_female",
    "CM_turnover", "seniority_rank", "seniority_rank_std", "Queue_st",
    "incumbent_won_bin",
]
out = df[[c for c in keep if c in df.columns]].rename(columns={
    "pc11_state_id": "state_id",
    "start_year":    "year",
})
out.to_csv("data/analysis/dc_analysis_balanced.csv", index=False)
print(f"\nSaved data/analysis/dc_analysis_balanced.csv  ({len(out):,} rows, {len(out.columns)} cols)")
