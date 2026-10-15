"""
Apply manual accept/reject/hardcode decisions to the 57 flagged review rows
and save the finalised crosswalk as data/raw/district_crosswalk_final.csv.
"""

import pandas as pd

cw = pd.read_csv("data/raw/district_crosswalk.csv", dtype=str)
cw["pc11_state_id"]    = cw["pc11_state_id"].str.strip().str.zfill(2)
cw["pc11_district_id"] = cw["pc11_district_id"].str.strip()
cw.loc[cw["pc11_district_id"] == "NA", "pc11_district_id"] = None

# helper: pandas boolean mask matching a dict of column→value
def match(df, **kw):
    mask = pd.Series([True] * len(df), index=df.index)
    for col, val in kw.items():
        mask &= (df[col].str.strip() == val)
    return mask

total_before = cw["pc11_district_id"].notna().sum()

# ── HARDCODE: Kadapa → Y.S.R. (district 554, state 28) ───────────────────
# Covers Cuddapah too (already in R hardcoded list, but Kadapa was not).
# Y.S.R. is offset 531 + position of Y.S.R. in sorted AP district list = 554
ysr_id = "554"
kadapa_mask = (cw["display_name"].str.strip().isin(["Kadapa", "Cuddapah"])) & \
              (cw["pc11_state_id"] == "28")
cw.loc[kadapa_mask, "pc11_district_id"] = ysr_id
n_hardcoded = kadapa_mask.sum()
print(f"Hardcoded Kadapa/Cuddapah → Y.S.R. (554): {n_hardcoded} rows")

# ── ACCEPT: keep these specific review matches ────────────────────────────
accept_list = [
    dict(cadre="A G M U T", display_name="West Siang (Aru. Pradesh)",
         pc11_state_id="12", pc11_district_id="260"),
    dict(cadre="A G M U T", display_name="Saiha (Mizoram)",
         pc11_state_id="15", pc11_district_id="287"),
    dict(cadre="Maharashtra", display_name="Raigarh",
         pc11_state_id="27", pc11_district_id="522"),
    dict(cadre="A G M U T", display_name="Karaikal (Pondi)",
         pc11_state_id="34", pc11_district_id="634"),
    dict(cadre="A G M U T", display_name="Pondicherry",
         pc11_state_id="34", pc11_district_id="636"),
]
# Mark accepted rows so we don't accidentally null them below
cw["_accepted"] = False
for a in accept_list:
    m = match(cw, **a)
    cw.loc[m, "_accepted"] = True
    print(f"  ACCEPT: {a['display_name']} ({a['cadre']}, st={a['pc11_state_id']}) "
          f"→ {a['pc11_district_id']}  [{m.sum()} row(s)]")

# ── REJECT: all other flagged review rows → set pc11_district_id = None ──
# Each row is identified by (cadre, display_name, pc11_state_id, old_district_id).
# Where the same display_name appears multiple times with the same IDs we
# null all of them (both Bhadohi rows, etc.).
reject_list = [
    dict(cadre="Jammu & Kashmir", display_name="Ghazipur",        pc11_state_id="01", pc11_district_id="022"),
    dict(cadre="A G M U T",       display_name="N C T of Delhi",   pc11_state_id="07", pc11_district_id="093"),
    dict(cadre="Rajasthan",        display_name="Bardhaman",        pc11_state_id="08", pc11_district_id="102"),
    dict(cadre="Rajasthan",        display_name="Balasore",         pc11_state_id="08", pc11_district_id="116"),
    dict(cadre="Rajasthan",        display_name="Dholpur",          pc11_state_id="08", pc11_district_id="119"),
    # Uttarakhand districts mismatched to UP (state 09)
    dict(cadre="Uttar Pradesh",    display_name="Uttarkashi",       pc11_state_id="09", pc11_district_id="202"),
    dict(cadre="Uttar Pradesh",    display_name="Udham Singh Nagar",pc11_state_id="09", pc11_district_id="175"),
    dict(cadre="Uttar Pradesh",    display_name="Pauri Garhwal",    pc11_state_id="09", pc11_district_id="136"),
    dict(cadre="Uttar Pradesh",    display_name="Dehradun",         pc11_state_id="09", pc11_district_id="147"),
    dict(cadre="Uttar Pradesh",    display_name="Lakhimpur Kheri",  pc11_state_id="09", pc11_district_id="191"),
    dict(cadre="Uttar Pradesh",    display_name="Pithoragarh",      pc11_state_id="09", pc11_district_id="189"),
    dict(cadre="Uttar Pradesh",    display_name="Rudraprayag",      pc11_state_id="09", pc11_district_id="136"),
    dict(cadre="Uttar Pradesh",    display_name="Almora",           pc11_state_id="09", pc11_district_id="132"),
    dict(cadre="Uttar Pradesh",    display_name="Haridwar",         pc11_state_id="09", pc11_district_id="164"),
    dict(cadre="Uttar Pradesh",    display_name="Amroha",           pc11_state_id="09", pc11_district_id="180"),
    dict(cadre="Uttar Pradesh",    display_name="Bageshwar",        pc11_state_id="09", pc11_district_id="138"),
    dict(cadre="Uttar Pradesh",    display_name="Chamoli",          pc11_state_id="09", pc11_district_id="149"),
    dict(cadre="Uttar Pradesh",    display_name="Garhwal",          pc11_state_id="09", pc11_district_id="132"),
    dict(cadre="Uttar Pradesh",    display_name="Lakhimpur",        pc11_state_id="09", pc11_district_id="176"),
    dict(cadre="Uttar Pradesh",    display_name="Bharuch",          pc11_state_id="09", pc11_district_id="139"),
    dict(cadre="Uttar Pradesh",    display_name="Badaun",           pc11_state_id="09", pc11_district_id="142"),
    dict(cadre="Uttarakhand",      display_name="Badaun",           pc11_state_id="09", pc11_district_id="142"),
    dict(cadre="Assam Meghalya",   display_name="Kanpur",           pc11_state_id="09", pc11_district_id="170"),
    dict(cadre="Uttar Pradesh",    display_name="Kanpur",           pc11_state_id="09", pc11_district_id="170"),
    dict(cadre="Uttar Pradesh",    display_name="Bellary",          pc11_state_id="09", pc11_district_id="144"),
    dict(cadre="Uttar Pradesh",    display_name="Bhadohi",          pc11_state_id="09", pc11_district_id="164"),
    # Bihar
    dict(cadre="Bihar",            display_name="Hassan",           pc11_state_id="10", pc11_district_id="233"),
    dict(cadre="Bihar",            display_name="Sehore",           pc11_state_id="10", pc11_district_id="235"),
    # West Bengal / AGMUT
    dict(cadre="A G M U T",       display_name="Alipurduar",       pc11_state_id="19", pc11_district_id="343"),
    dict(cadre="West Bengal",      display_name="Alipurduar",       pc11_state_id="19", pc11_district_id="343"),
    # Jharkhand
    dict(cadre="Jharkhand",        display_name="Chaibassa",        pc11_state_id="20", pc11_district_id="347"),
    # Chhattisgarh
    dict(cadre="Chhattisgarh",     display_name="Balrampur",        pc11_state_id="22", pc11_district_id="413"),
    # Madhya Pradesh
    dict(cadre="Madhya Pradesh",   display_name="Bastar",           pc11_state_id="23", pc11_district_id="454"),
    dict(cadre="Madhya Pradesh",   display_name="Kabirdham",        pc11_state_id="23", pc11_district_id="436"),
    dict(cadre="Madhya Pradesh",   display_name="Bilaspur",         pc11_state_id="23", pc11_district_id="418"),
    dict(cadre="Madhya Pradesh",   display_name="East Nimar",       pc11_state_id="23", pc11_district_id="455"),
    dict(cadre="Madhya Pradesh",   display_name="Agra",             pc11_state_id="23", pc11_district_id="436"),
    dict(cadre="Madhya Pradesh",   display_name="Raipur",           pc11_state_id="23", pc11_district_id="418"),
    dict(cadre="Madhya Pradesh",   display_name="Dholpur",          pc11_state_id="23", pc11_district_id="460"),
    # Gujarat
    dict(cadre="Gujarat",          display_name="Gujarat",          pc11_state_id="24", pc11_district_id="489"),
    dict(cadre="Gujarat",          display_name="Mahisagar",        pc11_state_id="24", pc11_district_id="476"),
    # AGMUT Daman Diu
    dict(cadre="A G M U T",       display_name="Daman Diu / Dadra Nagar Haveli",
                                                                    pc11_state_id="25", pc11_district_id="494"),
    # Kerala
    dict(cadre="Kerala",           display_name="Kerala",           pc11_state_id="32", pc11_district_id="589"),
    # Tamil Nadu
    dict(cadre="Tamil Nadu",       display_name="Chengalpattu",     pc11_state_id="33", pc11_district_id="603"),
    dict(cadre="Tamil Nadu",       display_name="Kanpur",           pc11_state_id="33", pc11_district_id="609"),
]

n_rejected = 0
for r in reject_list:
    m = match(cw, **r) & ~cw["_accepted"]
    n_rejected += m.sum()
    cw.loc[m, "pc11_district_id"] = None

print(f"\nRejected review rows → NA: {n_rejected} rows")
cw.drop(columns=["_accepted"], inplace=True)

# ── Summary ────────────────────────────────────────────────────────────────
total_after  = cw["pc11_district_id"].notna().sum()
still_na     = len(cw) - total_after

print(f"\n{'='*55}")
print(f"FINAL FILL RATE")
print(f"{'='*55}")
print(f"Total crosswalk rows           : {len(cw)}")
print(f"pc11_district_id filled before : {total_before}")
print(f"  Hardcoded additions          : +{n_hardcoded}")
print(f"  Accepted review rows kept    : (already counted)")
print(f"  Rejected review rows nulled  : -{n_rejected}")
print(f"pc11_district_id filled after  : {total_after}  ({100*total_after/len(cw):.1f}%)")
print(f"Still NA                       : {still_na}  ({100*still_na/len(cw):.1f}%)")

# ── Save ───────────────────────────────────────────────────────────────────
cw.to_csv("data/raw/district_crosswalk_final.csv", index=False)
print(f"\nSaved: data/raw/district_crosswalk_final.csv")

# ── Merge check ────────────────────────────────────────────────────────────
print(f"\n{'='*55}")
print(f"MERGE CHECK: DC spell-years → panel outcomes")
print(f"{'='*55}")

import duckdb
con = duckdb.connect()

merge_q = """
WITH exp AS (
    SELECT
        ID,
        Cadre,
        trim(Office)                         AS office_nm,
        YEAR(TRY_CAST(Start_Date AS DATE))   AS start_year
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
),
cw AS (
    SELECT
        trim(cadre)           AS cadre,
        trim(office_name)     AS office_name,
        trim(display_name)    AS display_name,
        lpad(trim(pc11_state_id), 2, '0')    AS pc11_state_id,
        lpad(trim(pc11_district_id), 3, '0') AS pc11_district_id
    FROM read_csv_auto('data/raw/district_crosswalk_final.csv', all_varchar=true)
    WHERE pc11_district_id IS NOT NULL
      AND pc11_district_id NOT IN ('NA','')
),
exp_cw AS (
    SELECT exp.ID, exp.start_year,
           cw.pc11_state_id, cw.pc11_district_id
    FROM exp
    -- match on cadre + office_name
    LEFT JOIN cw
           ON lower(trim(exp.Cadre))    = lower(cw.cadre)
          AND lower(exp.office_nm)      = lower(cw.office_name)
),
panel AS (
    SELECT lpad(trim(pc11_state_id), 2, '0')    AS pc11_state_id,
           lpad(trim(pc11_district_id), 3, '0') AS pc11_district_id,
           year
    FROM read_csv_auto('data/final/panel_full.csv', all_varchar=true)
)
SELECT
    COUNT(*)                                         AS dc_spell_years,
    SUM(CASE WHEN exp_cw.pc11_district_id IS NOT NULL THEN 1 ELSE 0 END)
                                                     AS matched_to_district,
    SUM(CASE WHEN p.year IS NOT NULL THEN 1 ELSE 0 END)
                                                     AS matched_to_panel
FROM exp_cw
LEFT JOIN panel p
       ON exp_cw.pc11_state_id    = p.pc11_state_id
      AND exp_cw.pc11_district_id = p.pc11_district_id
      AND exp_cw.start_year       = CAST(p.year AS INTEGER)
"""
result = con.execute(merge_q).df()
row = result.iloc[0]
print(f"Total DC spell-years (1985-2008)  : {int(row.dc_spell_years):,}")
print(f"Matched to a district ID          : {int(row.matched_to_district):,}  "
      f"({100*row.matched_to_district/row.dc_spell_years:.1f}%)")
print(f"Matched to a panel outcome row    : {int(row.matched_to_panel):,}  "
      f"({100*row.matched_to_panel/row.dc_spell_years:.1f}%)")
print()
print("Note: panel covers 1994-2013 only, so pre-1994 spells cannot match.")
print("Breakdown by whether start_year is in panel range:")
yr_q = """
WITH exp AS (
    SELECT YEAR(TRY_CAST(Start_Date AS DATE)) AS start_year
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
)
SELECT
    CASE WHEN start_year < 1994 THEN 'pre-1994 (outside panel)'
         WHEN start_year > 2013 THEN 'post-2013 (outside panel)'
         ELSE '1994-2013 (in panel range)' END AS yr_range,
    COUNT(*) AS spells
FROM exp GROUP BY yr_range ORDER BY yr_range
"""
print(con.execute(yr_q).df().to_string(index=False))
