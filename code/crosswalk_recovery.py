"""
Crosswalk recovery — two tasks:

TASK 1: Add missing district-name entries for Karnataka, Punjab, Haryana,
        Himachal Pradesh, Delhi, and Assam cadres.
        District IDs verified against crosswalk anchors and panel district ranges.
        Saves data/analysis/crosswalk_v2.csv

TASK 2: Impute blank office_name spells.
        If an officer's preceding and following DC postings are in the same
        district, the blank spell is imputed to that district.
        Reports how many blank spells are recovered.
"""

import os, warnings
warnings.filterwarnings("ignore")

import duckdb
import numpy as np
import pandas as pd

os.makedirs("data/analysis", exist_ok=True)
con = duckdb.connect()

# ══════════════════════════════════════════════════════════════════════════
# PART 0 — shared data loading
# ══════════════════════════════════════════════════════════════════════════

exp_dc = con.execute("""
SELECT
    ID                                           AS officer_id,
    trim(Cadre)                                  AS cadre,
    trim(Office)                                 AS office_nm,
    TRY_CAST(Start_Date AS DATE)                 AS start_dt,
    TRY_CAST(End_Date   AS DATE)                 AS end_dt,
    YEAR(TRY_CAST(Start_Date AS DATE))           AS start_year,
    upper(trim(Designation))                     AS desig_up
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
  AND upper(trim(Designation)) NOT LIKE '%ASSISTANT%'
  AND upper(trim(Designation)) NOT LIKE '%DEPUTY COLLECTOR%'
  AND upper(trim(Designation)) NOT LIKE '%SPL DEPUTY%'
""").df()

cw = pd.read_csv("data/raw/district_crosswalk_final.csv", dtype=str)
cw["pc11_state_id"]    = cw["pc11_state_id"].str.strip().str.zfill(2)
cw["pc11_district_id"] = cw["pc11_district_id"].str.strip()
cw["cadre_key"]        = cw["cadre"].str.strip().str.lower()
cw["office_key"]       = cw["office_name"].str.strip().str.lower()

print("=" * 70)
print("  CROSSWALK RECOVERY")
print("=" * 70)

# ══════════════════════════════════════════════════════════════════════════
# PART 1 — Add missing district name entries
# ══════════════════════════════════════════════════════════════════════════
print("\n" + "─"*70)
print("TASK 1: Add missing district-name entries")
print("─"*70)

# ── District lookup table ─────────────────────────────────────────────────
# Key: (pc11_state_id, normalised_district_name)
# Value: pc11_district_id (zero-padded 3-digit string)
# Anchors verified from crosswalk_final:
#   Bangalore→556, Bijapur→561, Dakshina Kannada→566, Kodagu→573 (Karnataka)
#   Fatehgarh Sahib→039, Ludhiana→045, Sangrur→052 (Punjab)
#   Bhiwani→070, Hisar→074 (Haryana)
#   New Delhi→092 (Delhi)
#   Fatehgarh Sahib→039 (Punjab) — all IDs in 3-digit zfill format

DISTRICT_LOOKUP = {
    # ── Himachal Pradesh (02), 12 districts, 023-034 ─────────────────────
    ("02","bilaspur"):              "023",
    ("02","chamba"):                "024",
    ("02","hamirpur"):              "025",
    ("02","kangra"):                "026",
    ("02","kinnaur"):               "027",
    ("02","kullu"):                 "028",
    ("02","kulu"):                  "028",
    ("02","lahaul & spiti"):        "029",
    ("02","lahaul and spiti"):      "029",
    ("02","lahaul spiti"):          "029",
    ("02","mandi"):                 "030",
    ("02","shimla"):                "031",
    ("02","sirmaur"):               "032",
    ("02","sirmour"):               "032",
    ("02","solan"):                 "033",
    ("02","una"):                   "034",
    # common "(HP)" suffix variants in IAS data
    ("02","bilaspur (hp)"):         "023",
    ("02","chamba (hp)"):           "024",
    ("02","hamirpur (hp)"):         "025",
    ("02","kangra (hp)"):           "026",
    ("02","kinnaur (hp)"):          "027",
    ("02","kullu (hp)"):            "028",
    ("02","lahaul & spiti (hp)"):   "029",
    ("02","mandi (hp)"):            "030",
    ("02","shimla (hp)"):           "031",
    ("02","sirmaur (hp)"):          "032",
    ("02","solan (hp)"):            "033",
    ("02","una (hp)"):              "034",

    # ── Punjab (03), 20 districts, 035-054 ────────────────────────────────
    # ✓ anchors: Fatehgarh Sahib=039, Ludhiana=045, Sangrur=052
    ("03","amritsar"):              "035",
    ("03","barnala"):               "036",
    ("03","bathinda"):              "037",
    ("03","bhatinda"):              "037",
    ("03","faridkot"):              "038",
    ("03","fatehgarh sahib"):       "039",
    ("03","firozpur"):              "040",
    ("03","ferozepur"):             "040",
    ("03","gurdaspur"):             "041",
    ("03","hoshiarpur"):            "042",
    ("03","jalandhar"):             "043",
    ("03","kapurthala"):            "044",
    ("03","ludhiana"):              "045",
    ("03","mansa"):                 "046",
    ("03","moga"):                  "047",
    ("03","muktsar"):               "048",
    ("03","sri muktsar sahib"):     "048",
    ("03","nawanshahr"):            "049",
    ("03","shaheed bhagat singh nagar"): "049",
    ("03","patiala"):               "050",
    ("03","ropar"):                 "051",
    ("03","rupnagar"):              "051",
    ("03","roop nagar"):            "051",
    ("03","sangrur"):               "052",
    ("03","s.a.s. nagar"):          "053",
    ("03","sas nagar"):             "053",
    ("03","mohali"):                "053",
    ("03","tarn taran"):            "054",

    # ── Haryana (06), 21 districts, 069-089 ─────────────────────────────
    # ✓ anchors: Bhiwani=070, Hisar=074
    ("06","ambala"):                "069",
    ("06","bhiwani"):               "070",
    ("06","faridabad"):             "071",
    ("06","fatehabad"):             "072",
    ("06","gurgaon"):               "073",
    ("06","gurugram"):              "073",
    ("06","hisar"):                 "074",
    ("06","jhajjar"):               "075",
    ("06","jind"):                  "076",
    ("06","kaithal"):               "077",
    ("06","karnal"):                "078",
    ("06","kurukshetra"):           "079",
    ("06","mahendragarh"):          "080",
    ("06","mewat"):                 "081",
    ("06","nuh"):                   "081",
    ("06","palwal"):                "082",
    ("06","panchkula"):             "083",
    ("06","panipat"):               "084",
    ("06","rewari"):                "085",
    ("06","rohtak"):                "086",
    ("06","sirsa"):                 "087",
    ("06","sonepat"):               "088",
    ("06","sonipat"):               "088",
    ("06","yamuna nagar"):          "089",
    ("06","yamunanagar"):           "089",

    # ── Delhi (07), 9 districts, 090-098 ────────────────────────────────
    # ✓ anchor: New Delhi=092
    ("07","central delhi"):         "090",
    ("07","east delhi"):            "091",
    ("07","new delhi"):             "092",
    ("07","north delhi"):           "093",
    ("07","north east delhi"):      "094",
    ("07","north west delhi"):      "095",
    ("07","south delhi"):           "096",
    ("07","south west delhi"):      "097",
    ("07","west delhi"):            "098",

    # ── Assam (18), 27 districts, 300-326 ────────────────────────────────
    # (matched via Assam Meghalya cadre; Meghalaya officers rarely serve
    #  in Assam districts so we only add clear Assam district names)
    ("18","baksa"):                 "300",
    ("18","barpeta"):               "301",
    ("18","bongaigaon"):            "302",
    ("18","cachar"):                "303",
    ("18","chirang"):               "304",
    ("18","darrang"):               "305",
    ("18","dhemaji"):               "306",
    ("18","dhubri"):                "307",
    ("18","dibrugarh"):             "308",
    ("18","dima hasao"):            "309",
    ("18","goalpara"):              "310",
    ("18","golaghat"):              "311",
    ("18","hailakandi"):            "312",
    ("18","jorhat"):                "313",
    ("18","kamrup"):                "314",
    ("18","kamrup metropolitan"):   "315",
    ("18","kamrup metro"):          "315",
    ("18","karbi anglong"):         "316",
    ("18","karimganj"):             "317",
    ("18","kokrajhar"):             "318",
    ("18","lakhimpur"):             "319",
    ("18","lakhimpur (assam)"):     "319",
    ("18","marigaon"):              "320",
    ("18","morigaon"):              "320",
    ("18","nagaon"):                "321",
    ("18","nalbari"):               "322",
    ("18","sibsagar"):              "323",
    ("18","sibasagar"):             "323",
    ("18","sivasagar"):             "323",
    ("18","sonitpur"):              "324",
    ("18","tinsukia"):              "325",
    ("18","udalguri"):              "326",
    # common "(Assam)" suffix variants in IAS data
    ("18","baksa (assam)"):             "300",
    ("18","barpeta (assam)"):           "301",
    ("18","bongaigaon (assam)"):        "302",
    ("18","cachar (assam)"):            "303",
    ("18","darrang (assam)"):           "305",
    ("18","dhemaji (assam)"):           "306",
    ("18","dhubri (assam)"):            "307",
    ("18","dibrugarh (assam)"):         "308",
    ("18","goalpara (assam)"):          "310",
    ("18","golaghat (assam)"):          "311",
    ("18","hailakandi (assam)"):        "312",
    ("18","jorhat (assam)"):            "313",
    ("18","kamrup (assam)"):            "314",
    ("18","karbi anglong (assam)"):     "316",
    ("18","karimganj (assam)"):         "317",
    ("18","kokrajhar (assam)"):         "318",
    ("18","kokrajar (assam)"):          "318",   # typo variant in IAS data
    ("18","lakhimpur (assam)"):         "319",
    ("18","nagaon (assam)"):            "321",
    ("18","nalbari (assam)"):           "322",
    ("18","sibsagar (assam)"):          "323",
    ("18","sivasagar (assam)"):         "323",
    ("18","sivasagar / sibsagar (assam)"): "323",
    ("18","sonitpur (assam)"):          "324",
    ("18","tinsukia (assam)"):          "325",
    ("18","udalguri (assam)"):          "326",
    # Meghalaya districts (also served by Assam Meghalya cadre) — state 17
    # These entries need state 17 key but cadre maps to 18 (Assam);
    # handled via CADRE_STATE override below for office names ending in (Meghalaya)

    # ── Karnataka (29), 30 districts, 555-584 ────────────────────────────
    # ✓ anchors: Bangalore→556, Bijapur→561, Dakshina Kannada→566, Kodagu→573
    ("29","bagalkot"):              "555",
    ("29","bangalore rural"):       "556",
    ("29","bangalore"):             "556",
    ("29","bangalore (rural)"):     "556",
    ("29","bangalore city corpn"):  "556",   # treat city corp → Bangalore Rural
    ("29","bangalore urban"):       "557",
    ("29","bangalore (urban)"):     "557",
    ("29","belgaum"):               "558",
    ("29","belagavi"):              "558",
    ("29","bellary"):               "559",
    ("29","bidar"):                 "560",
    ("29","bijapur"):               "561",
    ("29","vijayapura"):            "561",
    ("29","chamarajanagar"):        "562",
    ("29","chikballapur"):          "563",
    ("29","chickballapur"):         "563",
    ("29","chikkamagaluru"):        "564",
    ("29","chickmagalur"):          "564",
    ("29","chikmagalur"):           "564",
    ("29","chitradurga"):           "565",
    ("29","dakshina kannada"):      "566",
    ("29","dakshin kannada"):       "566",
    ("29","davanagere"):            "567",
    ("29","davangere"):             "567",
    ("29","dharwad"):               "568",
    ("29","gadag"):                 "569",
    ("29","gulbarga"):              "570",
    ("29","kalaburagi"):            "570",
    ("29","hassan"):                "571",
    ("29","haveri"):                "572",
    ("29","kodagu"):                "573",
    ("29","coorg"):                 "573",
    ("29","kolar"):                 "574",
    ("29","koppal"):                "575",
    ("29","mandya"):                "576",
    ("29","mysore"):                "577",
    ("29","mysuru"):                "577",
    ("29","raichur"):               "578",
    ("29","ramanagara"):            "579",
    ("29","ramanagar"):             "579",
    ("29","shimoga"):               "580",
    ("29","shivamogga"):            "580",
    ("29","tumkur"):                "581",
    ("29","tumakuru"):              "581",
    ("29","udupi"):                 "582",
    ("29","uttara kannada"):        "583",
    ("29","karwar"):                "583",   # Karwar = HQ of Uttara Kannada
    ("29","yadgir"):                "584",

    # ── Meghalaya (17) via Assam Meghalya cadre ────────────────────────────
    # Meghalaya has 7 districts in Census 2011 (state 17)
    # Officers with cadre "Assam Meghalya" can serve in Meghalaya districts
    ("17","east garo hills"):           "288",
    ("17","east garo hills (meghalaya)"):  "288",
    ("17","east khasi hills"):          "289",
    ("17","east khasi hills (meghalaya)"): "289",
    ("17","jaintia hills"):             "290",
    ("17","jaintia hills (meghalaya)"): "290",
    ("17","ri bhoi"):                   "291",
    ("17","south garo hills"):          "292",
    ("17","south garo hills (meghalaya)"):  "292",
    ("17","west garo hills"):           "293",
    ("17","west garo hills (meghalaya)"): "293",
    ("17","west khasi hills"):          "294",
    ("17","west khasi hills (meghalaya)"): "294",
}

# ── Cadre → state mapping for lookup ──────────────────────────────────────
# Only for cadres where we have high-confidence district tables
CADRE_STATE = {
    "himachal pradesh": "02",
    "punjab":           "03",
    "haryana":          "06",
    "a g m u t":       "07",   # Delhi offices → state 07
    "assam meghalya":   "18",
    "karnataka":        "29",
}

# ── Find (cadre, office_name) pairs not in crosswalk ─────────────────────
cw_keys = set(zip(cw["cadre_key"], cw["office_key"]))

exp_dc["cadre_key"]  = exp_dc["cadre"].str.lower()
exp_dc["office_key"] = exp_dc["office_nm"].str.lower()

not_in_cw = (
    exp_dc[["cadre","cadre_key","office_nm","office_key"]]
    .drop_duplicates()
    .loc[lambda d: ~d.apply(
        lambda r: (r.cadre_key, r.office_key) in cw_keys, axis=1)]
    .copy()
)

# Count spells per unique pair (for reporting)
spell_counts = (exp_dc.groupby(["cadre_key","office_key"]).size()
                .reset_index(name="n_spells"))
not_in_cw = not_in_cw.merge(spell_counts, on=["cadre_key","office_key"], how="left")

# ── Attempt lookup for each missing pair ─────────────────────────────────
new_rows = []
skipped  = []

for _, row in not_in_cw.iterrows():
    cadre_k   = row.cadre_key
    office_k  = row.office_key.strip()

    state_id  = CADRE_STATE.get(cadre_k)
    if state_id is None:
        continue   # cadre not in our lookup table

    dist_id = DISTRICT_LOOKUP.get((state_id, office_k))

    # Assam Meghalya cadre: also try Meghalaya (state 17) if Assam (18) misses
    if dist_id is None and cadre_k == "assam meghalya":
        dist_id_mg = DISTRICT_LOOKUP.get(("17", office_k))
        if dist_id_mg is not None:
            state_id = "17"
            dist_id  = dist_id_mg

    if dist_id is None:
        skipped.append((row.cadre, row.office_nm, state_id, row.n_spells))
        continue

    new_rows.append({
        "cadre":            row.cadre,
        "office_name":      row.office_nm,
        "display_name":     row.office_nm,
        "pc11_state_id":    state_id,
        "pc11_district_id": dist_id,
        "source":           "manual_recovery_v2",
    })

new_df = pd.DataFrame(new_rows)
print(f"\n  New entries matched from lookup table : {len(new_df):,}")
print(f"  Cadre+office pairs still unresolved   : {len(skipped)}")

if len(new_df) > 0:
    print(f"\n  Added entries (sorted by cadre/district):")
    print(f"  {'Cadre':<22} {'Office':<30} St  Dist  N_spells")
    print(f"  {'─'*22} {'─'*30} ──  ────  ────────")
    summary = new_df.merge(
        not_in_cw[["cadre","office_nm","n_spells"]],
        left_on=["cadre","office_name"], right_on=["cadre","office_nm"], how="left")
    for _, r in summary.sort_values(["cadre","office_name"]).iterrows():
        print(f"  {r.cadre:<22} {r.office_name:<30} {r.pc11_state_id}  {r.pc11_district_id}  {int(r.n_spells):>6}")

if skipped:
    print(f"\n  Unresolved (in scope cadre but no lookup match):")
    for cadre, office, state, n in sorted(skipped, key=lambda x: -x[3])[:20]:
        print(f"    {cadre:<22} | {str(office)[:35]:<35} | state={state} | n={n}")

# ── Build crosswalk_v2 ────────────────────────────────────────────────────
cw2 = cw.copy()
if "source" not in cw2.columns:
    cw2["source"] = "original"

# Add only the truly new rows (not already in cw)
new_df["cadre_key"]  = new_df["cadre"].str.lower()
new_df["office_key"] = new_df["office_name"].str.lower()
new_df["pc11_district_id"] = new_df["pc11_district_id"].str.zfill(3)

cw2 = pd.concat([cw2, new_df], ignore_index=True)
# Drop duplicates keeping first (preserves original entries)
cw2 = cw2.drop_duplicates(subset=["cadre_key","office_key"], keep="first")

cw2.to_csv("data/analysis/crosswalk_v2.csv", index=False)
print(f"\n  crosswalk_final: {len(cw):,} rows")
print(f"  crosswalk_v2   : {len(cw2):,} rows  (+{len(cw2)-len(cw)} new)")

# ── Spell recovery count ──────────────────────────────────────────────────
panel = pd.read_csv("data/final/panel_full.csv", dtype=str)
panel["pc11_state_id"]    = panel["pc11_state_id"].str.strip().str.zfill(2)
panel["pc11_district_id"] = panel["pc11_district_id"].str.strip().str.zfill(3)
panel["year"]             = panel["year"].astype(int)

cw2_matched = cw2[cw2["pc11_district_id"].notna() &
                   ~cw2["pc11_district_id"].isin(["NA",""])].copy()
cw2_matched["pc11_district_id"] = cw2_matched["pc11_district_id"].str.zfill(3)

exp_dc["office_key"] = exp_dc["office_nm"].str.lower()
exp_dc["cadre_key"]  = exp_dc["cadre"].str.lower()

spells_v2 = (exp_dc
    .merge(cw2_matched[["cadre_key","office_key","pc11_state_id","pc11_district_id"]],
           on=["cadre_key","office_key"], how="inner"))
spells_v2["district_id"] = spells_v2["pc11_state_id"] + spells_v2["pc11_district_id"]
spells_v2_panel = spells_v2.merge(
    panel[["pc11_state_id","pc11_district_id","year"]].rename(columns={"year":"start_year"}),
    on=["pc11_state_id","pc11_district_id","start_year"], how="inner")

# Original
cw_matched_orig = cw[cw["pc11_district_id"].notna() & ~cw["pc11_district_id"].isin(["NA",""])].copy()
cw_matched_orig["pc11_district_id"] = cw_matched_orig["pc11_district_id"].str.zfill(3)
spells_v1 = (exp_dc
    .merge(cw_matched_orig[["cadre_key","office_key","pc11_state_id","pc11_district_id"]],
           on=["cadre_key","office_key"], how="inner"))
spells_v1_panel = spells_v1.merge(
    panel[["pc11_state_id","pc11_district_id","year"]].rename(columns={"year":"start_year"}),
    on=["pc11_state_id","pc11_district_id","start_year"], how="inner")

print(f"\n  ── Spell recovery ──")
print(f"  Spells matched (v1/original)   : {len(spells_v1):,}  "
      f"({len(spells_v1_panel):,} matched to panel 1994-2008)")
print(f"  Spells matched (v2/recovered)  : {len(spells_v2):,}  "
      f"({len(spells_v2_panel):,} matched to panel 1994-2008)")
print(f"  Additional spells recovered    : +{len(spells_v2)-len(spells_v1):,}  "
      f"(+{len(spells_v2_panel)-len(spells_v1_panel):,} in panel window)")

# breakdown by cadre
v1_cadre = spells_v1.groupby("cadre").size().rename("v1")
v2_cadre = spells_v2.groupby("cadre").size().rename("v2")
diff = pd.concat([v1_cadre, v2_cadre], axis=1).fillna(0)
diff["added"] = (diff["v2"] - diff["v1"]).astype(int)
diff = diff[diff["added"] > 0].sort_values("added", ascending=False)
if len(diff) > 0:
    print(f"\n  Recovery breakdown by cadre:")
    print(f"  {'Cadre':<25} {'Before':>8} {'After':>8} {'Added':>8}")
    for cadre, r in diff.iterrows():
        print(f"  {cadre:<25} {int(r.v1):>8,} {int(r.v2):>8,} {int(r.added):>+8,}")


# ══════════════════════════════════════════════════════════════════════════
# PART 2 — Blank office name imputation via neighbor matching
# ══════════════════════════════════════════════════════════════════════════
print(f"\n{'─'*70}")
print("TASK 2: Impute blank office_name spells via neighbor matching")
print(f"{'─'*70}")

# All DC spells (including blanks), sorted by officer and start date
exp_dc_sorted = exp_dc.sort_values(["officer_id","start_dt"]).copy()

# Build a district lookup for non-blank spells using v2 crosswalk
cw2_lookup = cw2_matched.set_index(["cadre_key","office_key"])["pc11_district_id"].to_dict()
cw2_state  = cw2_matched.set_index(["cadre_key","office_key"])["pc11_state_id"].to_dict()

def get_district(cadre_k, office_k):
    """Return (state_id, district_id) or (None, None)."""
    k = (cadre_k, office_k)
    return cw2_state.get(k), cw2_lookup.get(k)

# Identify blank spells
blank_mask = exp_dc_sorted["office_key"].str.strip() == ""
blank_spells = exp_dc_sorted[blank_mask].copy()
n_blank = len(blank_spells)
print(f"\n  Total DC spells with blank office_name: {n_blank:,}")

# For each officer, collect non-blank spells with their district
officer_districts = {}
for officer_id, grp in exp_dc_sorted[~blank_mask].groupby("officer_id"):
    rows = []
    for _, r in grp.iterrows():
        st, di = get_district(r.cadre_key, r.office_key)
        rows.append({
            "start_dt":      r.start_dt,
            "end_dt":        r.end_dt,
            "pc11_state_id": st,
            "pc11_district_id": di,
        })
    officer_districts[officer_id] = pd.DataFrame(rows).sort_values("start_dt")

imputed = []
no_neighbors = 0
different_neighbors = 0
no_district = 0

for _, blank_row in blank_spells.iterrows():
    oid  = blank_row.officer_id
    bdt  = blank_row.start_dt

    known = officer_districts.get(oid, pd.DataFrame())
    if len(known) == 0:
        no_neighbors += 1
        continue

    # Nearest non-blank spell BEFORE blank spell
    before = known[known["start_dt"] < bdt].sort_values("start_dt")
    # Nearest non-blank spell AFTER blank spell
    after  = known[known["start_dt"] > bdt].sort_values("start_dt")

    if len(before) == 0 or len(after) == 0:
        no_neighbors += 1
        continue

    prev_st, prev_di = before.iloc[-1]["pc11_state_id"], before.iloc[-1]["pc11_district_id"]
    next_st, next_di = after.iloc[0]["pc11_state_id"],  after.iloc[0]["pc11_district_id"]

    if prev_di is None or next_di is None:
        no_district += 1
        continue

    if prev_di == next_di and prev_st == next_st:
        imputed.append({
            "officer_id":       oid,
            "cadre":            blank_row.cadre,
            "office_nm":        blank_row.office_nm,
            "start_dt":         bdt,
            "start_year":       blank_row.start_year,
            "pc11_state_id":    prev_st,
            "pc11_district_id": prev_di,
            "district_imputed": True,
        })
    else:
        different_neighbors += 1

imputed_df = pd.DataFrame(imputed)
n_imputed = len(imputed_df)

print(f"\n  Blank spell disposition:")
print(f"    No non-blank neighbors for same officer  : {no_neighbors:,}")
print(f"    Neighbors exist but districts are unknown: {no_district:,}")
print(f"    Neighbors in DIFFERENT districts         : {different_neighbors:,}")
print(f"    Neighbors in SAME district → IMPUTED     : {n_imputed:,}")

if n_imputed > 0:
    # Check how many imputed spells fall in the panel window (1994-2008)
    imp_panel = imputed_df[imputed_df["start_year"].between(1994, 2008)]
    imp_panel_merged = imp_panel.merge(
        panel[["pc11_state_id","pc11_district_id","year"]].rename(columns={"year":"start_year"}),
        on=["pc11_state_id","pc11_district_id","start_year"], how="inner")

    print(f"\n  Imputed spells in panel window (1994-2008) : {len(imp_panel):,}")
    print(f"  Matched to panel_full outcome row          : {len(imp_panel_merged):,}")

    print(f"\n  Sample of imputed spells (first 10):")
    print(f"  {'Officer':>10} {'Year':>5} {'Cadre':<22} {'State':>6} {'District':>9}")
    for _, r in imputed_df.head(10).iterrows():
        print(f"  {r.officer_id:>10} {r.start_year:>5} {r.cadre:<22} "
              f"{r.pc11_state_id:>6}  {r.pc11_district_id:>8}")

    # Save imputed spells separately (for potential merge into analysis)
    imputed_df.to_csv("data/analysis/blank_spell_imputed.csv", index=False)
    print(f"\n  Saved imputed spells: data/analysis/blank_spell_imputed.csv")

    # Breakdown of imputed by cadre
    imp_cadre = imputed_df.groupby("cadre").size().sort_values(ascending=False)
    print(f"\n  Imputed spells by cadre:")
    for cadre, n in imp_cadre.items():
        print(f"    {cadre:<25} : {n}")

print(f"\n{'='*70}")
print("SUMMARY")
print(f"{'='*70}")
print(f"  Task 1 — Crosswalk recovery:")
print(f"    New district entries added    : {len(new_df):,}")
print(f"    Additional spells matched     : +{len(spells_v2)-len(spells_v1):,}")
print(f"    Additional panel-window spells: +{len(spells_v2_panel)-len(spells_v1_panel):,}")
print(f"    Saved: data/analysis/crosswalk_v2.csv")
print(f"\n  Task 2 — Blank spell imputation:")
print(f"    Blank spells total            : {n_blank:,}")
print(f"    Recovered via neighbor match  : {n_imputed:,}  "
      f"({100*n_imputed/n_blank:.1f}%)")
print(f"    Saved: data/analysis/blank_spell_imputed.csv")
print(f"{'='*70}")
