"""
Build data/analysis/dc_analysis_v2.csv for refined IV estimation.

Improvements over v1:
  opposition_turnover : party-change based (winning_party differs from prev year),
                        not just incumbent_won==0 — filters out same-party re-elections
  cadre_queue_rank    : officer's rank by allotment_year WITHIN their cadre IN EACH YEAR
                        (time-varying: only among actively-serving DCs that year)
  Queue_refined       : opposition_turnover_st × cadre_queue_rank_pct_it
                        (percentile within the cadre-year active queue)
"""
import os, warnings
warnings.filterwarnings("ignore")

import duckdb
import numpy as np
import pandas as pd

os.makedirs("data/analysis", exist_ok=True)
con = duckdb.connect()

# ─────────────────────────────────────────────────────────────────────────────
# 1. LOAD RAW DATA  (identical to build_tables.py)
# ─────────────────────────────────────────────────────────────────────────────

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
    trim(Cadre)                                  AS cadre,
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
         ELSE NULL END AS incumbent_won_bin,
    trim(winning_party) AS winning_party
FROM read_csv_auto('data/final/panel_full.csv',
     nullstr=['NA','N.A.','','#N/A'])
""").df()

cw_raw = pd.read_csv("data/analysis/crosswalk_v2.csv", dtype=str)
cw = (cw_raw[cw_raw["pc11_district_id"].notna() &
             ~cw_raw["pc11_district_id"].isin(["NA",""])].copy())
cw["cadre_key"]  = cw["cadre"].str.strip().str.lower()
cw["office_key"] = cw["office_name"].str.strip().str.lower()
cw["pc11_state_id"]    = cw["pc11_state_id"].str.strip().str.zfill(2)
cw["pc11_district_id"] = cw["pc11_district_id"].str.strip().str.zfill(3)

# ─────────────────────────────────────────────────────────────────────────────
# 2. OPPOSITION TURNOVER  (state × year)
#
# opposition_turnover = 1 iff winning_party this year differs from
# winning_party the previous year for the same state.
# This captures genuine party alternation (not just re-election of same party).
# ─────────────────────────────────────────────────────────────────────────────

pol = (panel[["pc11_state_id","year","winning_party","incumbent_won_bin"]]
       .drop_duplicates(subset=["pc11_state_id","year"])
       .sort_values(["pc11_state_id","year"])
       .copy())

pol["prev_party"] = pol.groupby("pc11_state_id")["winning_party"].shift(1)
pol["party_changed"] = (pol["winning_party"] != pol["prev_party"]).astype(float)
# First year per state has no prior — treat as no turnover
pol["party_changed"] = pol["party_changed"].fillna(0)

# Require incumbent_won_bin == 0 as additional guard against same-party re-elections
# that might coincidentally show a party-name variant
pol["opposition_turnover"] = (
    (pol["party_changed"] == 1) & (pol["incumbent_won_bin"] == 0)
).astype(float)
pol["opposition_turnover"] = pol["opposition_turnover"].fillna(0)

n_turnover   = int(pol["opposition_turnover"].sum())
n_state_year = len(pol)
print(f"opposition_turnover: {n_turnover}/{n_state_year} state-years "
      f"({100*n_turnover/n_state_year:.1f}%)")

# How many states have at least one turnover in 1994-2008?
panel_pol = pol[pol["year"].between(1994, 2008)]
states_with_turnover = panel_pol.groupby("pc11_state_id")["opposition_turnover"].max()
print(f"States with ≥1 opposition turnover in 1994-2008: "
      f"{int(states_with_turnover.sum())}/{len(states_with_turnover)}")
print("Turnover events by year:")
print(panel_pol.groupby("year")["opposition_turnover"].sum().astype(int).to_string())
print()

# ─────────────────────────────────────────────────────────────────────────────
# 3. BUILD SPELLS (pre-dedup) — needed for cadre-year queue
# ─────────────────────────────────────────────────────────────────────────────

exp["cadre_key"]  = exp["cadre"].str.lower()
exp["office_key"] = exp["office_nm"].str.lower()

spells_all = (exp
    .merge(cw[["cadre_key","office_key","pc11_state_id","pc11_district_id"]],
           on=["cadre_key","office_key"], how="inner")
    .merge(panel.rename(columns={"year":"start_year"}),
           on=["pc11_state_id","pc11_district_id","start_year"], how="inner")
    .merge(edu, on="officer_id", how="left")
    .merge(profile[["officer_id","allotment_year","is_female"]],
           on="officer_id", how="left")
)
spells_all["bg_class"] = spells_all["bg_class"].fillna("NA_Unclassified")
spells_all["district_id"] = spells_all["pc11_state_id"] + spells_all["pc11_district_id"]

# ─────────────────────────────────────────────────────────────────────────────
# 4. CADRE QUEUE RANK  (time-varying: officer's rank within cadre-year active pool)
#
# For each cadre × start_year, rank all officers who served as DC in that year
# by allotment_year ascending (rank 1 = most senior).
# Express as percentile [0,1] so scale is comparable across cadre-years.
# ─────────────────────────────────────────────────────────────────────────────

active_pool = (spells_all[spells_all["bg_class"] != "NA_Unclassified"]
               [["officer_id","cadre","start_year","allotment_year"]]
               .dropna(subset=["allotment_year"])
               .drop_duplicates(subset=["officer_id","cadre","start_year"])
               .copy())

# Raw rank within cadre-year
active_pool["raw_rank"] = (
    active_pool.groupby(["cadre","start_year"])["allotment_year"]
               .rank(method="average", ascending=True)
)
# Percentile: (rank - 1) / (n - 1) → 0 = most senior, 1 = most junior
active_pool["cadre_n"] = active_pool.groupby(["cadre","start_year"])["raw_rank"].transform("count")
active_pool["cadre_queue_pct"] = np.where(
    active_pool["cadre_n"] > 1,
    (active_pool["raw_rank"] - 1) / (active_pool["cadre_n"] - 1),
    0.5   # only 1 officer in that cadre-year → assign median
)

# Standardise within cadre-year (mean 0, sd 1) — alternative form for robustness
active_pool["cadre_queue_std"] = (
    active_pool.groupby(["cadre","start_year"])["raw_rank"]
               .transform(lambda x: (x - x.mean()) / x.std() if x.std() > 0 else 0)
)

queue_stats = active_pool.groupby("start_year")["cadre_n"].agg(["mean","max"])
print("Average active DCs per cadre per year:")
print(queue_stats.to_string())
print()

# ─────────────────────────────────────────────────────────────────────────────
# 5. BUILD ANALYTIC DATASET
# ─────────────────────────────────────────────────────────────────────────────

spells_all = spells_all.merge(
    active_pool[["officer_id","cadre","start_year",
                 "raw_rank","cadre_n","cadre_queue_pct","cadre_queue_std"]],
    on=["officer_id","cadre","start_year"], how="left"
)
spells_all = spells_all.merge(
    pol[["pc11_state_id","year","opposition_turnover"]]
       .rename(columns={"year":"start_year"}),
    on=["pc11_state_id","start_year"], how="left"
)
spells_all["opposition_turnover"] = spells_all["opposition_turnover"].fillna(0)

# Outcomes
spells_all["tenure_months"] = (
    (spells_all["end_dt"] - spells_all["start_dt"]).dt.days / 30.44).clip(lower=0)
spells_all["lights_rural"] = spells_all["dmsp"] / spells_all["tot_p"]
spells_all["roads_rate"]   = np.where(
    spells_all["road_length_km"] > 0,
    spells_all["roads_completed"] / spells_all["road_length_km"], np.nan)

# Instrument: opposition_turnover × percentile queue position
# Higher cadre_queue_pct → more junior → more likely Engineer
spells_all["Queue_refined"] = (
    spells_all["opposition_turnover"] * spells_all["cadre_queue_pct"]
)

# Drop unclassified; dedup to first spell per district-year
df = (spells_all[spells_all["bg_class"] != "NA_Unclassified"]
      .sort_values("start_dt")
      .drop_duplicates(subset=["district_id","start_year"], keep="first")
      .copy())

df["Engineer"] = (df["bg_class"] == "Engineer").astype(float)
df["Residual"] = (df["bg_class"] == "Residual").astype(float)

print(f"Analytic sample  : {len(df):,} obs | {df['district_id'].nunique()} districts")
print(f"opposition_turnover=1 : {int((df['opposition_turnover']==1).sum())} obs "
      f"({100*(df['opposition_turnover']==1).mean():.1f}%)")
print(f"Queue_refined non-null: {df['Queue_refined'].notna().sum():,}")
print(f"\nQueue_refined summary:")
print(df["Queue_refined"].describe().round(4))
print(f"\nCorrelations with Engineer:")
print(df[["Engineer","allotment_year","cadre_queue_pct","Queue_refined"]]
      .dropna().corr()["Engineer"].round(4))

# ─────────────────────────────────────────────────────────────────────────────
# 6. SAVE
# ─────────────────────────────────────────────────────────────────────────────

keep = [
    "district_id", "pc11_state_id", "start_year",
    "Engineer", "Residual",
    "roads_rate", "lights_rural", "ec_emp_all", "lit_rate",
    "tot_p", "sc_share", "st_share",
    "tenure_months", "allotment_year", "is_female",
    "opposition_turnover", "cadre_queue_pct", "cadre_queue_std",
    "raw_rank", "cadre_n", "Queue_refined",
]
out = df[[c for c in keep if c in df.columns]].rename(columns={
    "pc11_state_id": "state_id",
    "start_year":    "year",
})
out.to_csv("data/analysis/dc_analysis_v2.csv", index=False)
print(f"\nSaved data/analysis/dc_analysis_v2.csv  ({len(out):,} rows, {len(out.columns)} cols)")
