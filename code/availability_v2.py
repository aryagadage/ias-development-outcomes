"""
Collector vacancy-and-availability panel, cadre-month level, 1994-2008 (v2).

Standalone, read-only analysis. Reads only data/raw/ias-experience.csv,
data/raw/ias-profile.csv, data/analysis/crosswalk_v2.csv. Does not read or
modify any built/derived pipeline file (dc_analysis_*.csv, panel_full.csv,
etc.) or any existing script.

Unit of analysis is CADRE ("state cadre"), same choice and same reasoning as
diagnostics/collector_availability/: crosswalk_v2.csv maps several cadres to
more than one pc11_state_id (office-name matching noise), so cadre is the
clean key, and it is what the existing pipeline already uses for
seniority/turnover variables.

"District" = (cadre, pc11_district_id) pair (a district-cadre roster slot),
for the same reason: it lets a district that appears under two cadres due to
bifurcation/crosswalk noise be tracked correctly within each cadre's roster
rather than conflated.

Outputs
-------
diagnostics/availability_v2/cadre_month_panel.csv
diagnostics/availability_v2/summary.md
"""
import os
import re
import numpy as np
import pandas as pd

OUT_DIR = "diagnostics/availability_v2"
os.makedirs(OUT_DIR, exist_ok=True)

N_MONTHS  = (2008 - 1994 + 1) * 12  # 180
MONTH_IDX = pd.period_range("1994-01", "2008-12", freq="M")
STUDY_END = pd.Timestamp("2008-12-31")


def month_index(dt):
    return (dt.dt.year - 1994) * 12 + (dt.dt.month - 1)


def merge_intervals(iv):
    """iv: list of (start_idx, end_idx), inclusive. Returns merged, sorted,
    touching/overlapping intervals combined."""
    iv = sorted(iv)
    merged = []
    for s, e in iv:
        if merged and s <= merged[-1][1] + 1:
            merged[-1] = (merged[-1][0], max(merged[-1][1], e))
        else:
            merged.append((s, e))
    return merged


def bucket_gap(g):
    if g < 0:
        return "negative (overlap)"
    if g <= 3:
        return "0-3mo"
    if g <= 12:
        return "4-12mo"
    if g <= 36:
        return "13-36mo"
    return ">36mo"


# ─────────────────────────────────────────────────────────────────────────────
# 0. LOAD
# ─────────────────────────────────────────────────────────────────────────────

exp = pd.read_csv("data/raw/ias-experience.csv", dtype=str)
prof = pd.read_csv("data/raw/ias-profile.csv", dtype=str)
cw_raw = pd.read_csv("data/analysis/crosswalk_v2.csv", dtype=str)

exp["start_dt"] = pd.to_datetime(exp["Start_Date"], errors="coerce")
exp["end_raw"]  = exp["End_Date"]
exp["end_dt"]   = pd.to_datetime(exp["End_Date"], errors="coerce")
exp["ongoing"]  = exp["end_raw"].eq("N.A.")

n_bad_start = int(exp["start_dt"].isna().sum())
n_bad_end   = int(((~exp["ongoing"]) & exp["end_dt"].isna()).sum())
# true data anomaly: end < start, measured BEFORE the ongoing/N.A. clip below,
# so it isn't inflated by "N.A." rows that legitimately start after the study
# window (those are a separate, expected exclusion, not a data error).
n_end_lt_start = int((exp["end_dt"].notna() & exp["start_dt"].notna()
                       & (exp["end_dt"] < exp["start_dt"])).sum())
n_ongoing_after_window = int((exp["ongoing"] & exp["start_dt"].notna()
                               & (exp["start_dt"] > STUDY_END)).sum())

exp.loc[exp["ongoing"], "end_dt"] = STUDY_END  # ongoing ("N.A." end) -> cap at study window end

exp_clean = exp[exp["start_dt"].notna() & exp["end_dt"].notna()
                 & (exp["end_dt"] >= exp["start_dt"])].copy()
exp_clean["start_idx"] = month_index(exp_clean["start_dt"])
exp_clean["end_idx"]   = month_index(exp_clean["end_dt"])

cw = cw_raw[cw_raw["pc11_district_id"].notna() & (cw_raw["pc11_district_id"] != "")].copy()
cw["cadre_key"]  = cw["cadre"].str.strip().str.lower()
cw["office_key"] = cw["office_name"].str.strip().str.lower()
cw["pc11_district_id"] = cw["pc11_district_id"].str.strip()

prof["cadre_clean"] = prof["Cadre"].str.strip()
prof["allotment_year"] = pd.to_numeric(prof["Allotment_Year"], errors="coerce")
prof_valid = prof[prof["cadre_clean"].notna() & (prof["cadre_clean"] != "")
                   & prof["allotment_year"].notna()].copy()

CADRES = sorted(prof_valid["cadre_clean"].unique())
cadre_size = prof_valid.groupby("cadre_clean")["ID"].nunique().sort_values(ascending=False)
TOP5 = cadre_size.head(5).index.tolist()

cadre_key_to_name = (cw[["cadre_key", "cadre"]].drop_duplicates("cadre_key")
                     .set_index("cadre_key")["cadre"].str.strip())
district_roster = (cw[["cadre_key", "pc11_district_id"]].drop_duplicates()
                    .assign(cadre=lambda x: x["cadre_key"].map(cadre_key_to_name)))
district_roster["dc_key"] = district_roster["cadre_key"] + "||" + district_roster["pc11_district_id"]
roster_lookup = district_roster.set_index("dc_key")["cadre"]
roster_size_by_cadre = district_roster.groupby("cadre")["dc_key"].nunique()

print(f"Officers with usable cadre+allotment_year: {prof_valid['ID'].nunique():,}  |  cadres: {len(CADRES)}")
print(f"Five largest state cadres: {TOP5}")
print(f"Experience rows: {len(exp):,} -> usable posting intervals: {len(exp_clean):,}  "
      f"(bad start {n_bad_start}, bad non-N.A. end {n_bad_end}, end<start anomaly {n_end_lt_start}, "
      f"ongoing-but-starts-after-2008 dropped {n_ongoing_after_window})\n")

# ─────────────────────────────────────────────────────────────────────────────
# STEP 6 -- POST CLASSIFIER  (standalone, inspectable)
# Built on `Designation` (job title), not `Office` (department/place name):
# Office holds strings like "M/o Education" or a district name, which carries
# no information about DC / sub-district / secretariat / deputation / training
# role content. Designation is where that information actually lives, and it
# is the same field the existing pipeline's DC filter already uses. FLAGGED
# explicitly here since the task described the source as "free-text office
# names" -- this is a deliberate, documented substitution, not a silent one.
# ─────────────────────────────────────────────────────────────────────────────

_DC_INCLUDE = ["DISTRICT COLLECTOR", "COLLECTOR", "DISTRICT MAGISTRATE", "DEPUTY COMMISSIONER"]
_DC_EXCLUDE = ["ADDITIONAL", "JOINT", "JT ", "SUB ", "ASSISTANT", "DEPUTY COLLECTOR", "SPL DEPUTY"]

_SUBDISTRICT_PAT = re.compile(
    r"\bS\s*D\s*[MO]\b|SUB[\s-]?DIVISIONAL|SUB\s*COLLECTOR|ADDITIONAL\s*COLLECTOR|"
    r"ADDL\.?\s*COLLECTOR|JOINT\s*COLLECTOR|JT\s*COLLECTOR|"
    r"ADDITIONAL\s*DISTRICT\s*MAGISTRATE|ADDL\.?\s*DISTRICT\s*MAGISTRATE|"
    r"ADDITIONAL\s*DEPUTY\s*COMMISSIONER|DEPUTY\s*COLLECTOR|ASSISTANT\s*COLLECTOR|"
    r"JT\s*MAGISTRATE|JOINT\s*MAGISTRATE|SUB\s*DIVISIONAL\s*MAGISTRATE"
)
_TRAINING_PAT = re.compile(r"TRAINING|STUDY\s*LEAVE|PROBATION")
_SECRETARIAT_PAT = re.compile(
    r"SECRETARY|SECY\b|DIRECTOR\b|DIR\.?\b|COMMISSIONER(?!\s*OF\s*POLICE)|CHAIRMAN|"
    r"MANAGING\s*DIRECTOR|\bM\s*D\b|MEMBER|REGISTRAR|ADVISER|CONTROLLER|VICE\s*CHAIRMAN|"
    r"SPECIAL\s*OFFICER|SPL\.?\s*OFFICER|GENERAL\s*MANAGER|C\s*E\s*O\b|\bDG\b|"
    r"OSD|ADMINISTRATOR"
)


def classify_post(designation, organisation=""):
    """Classify a single (Designation, Organisation) pair into one of:
    'dc_dm_collector', 'subdistrict', 'secretariat', 'deputation', 'training',
    'unclassified'. Priority order: DC (exact) > training > deputation
    (via Organisation) > sub-district > secretariat > unclassified.
    """
    d = (designation or "").upper()
    o = (organisation or "").upper()

    is_dc = any(k in d for k in _DC_INCLUDE) and not any(k in d for k in _DC_EXCLUDE)
    if is_dc:
        return "dc_dm_collector"

    if _TRAINING_PAT.search(d) or "TRAINING" in o or "STUDY LEAVE" in o:
        return "training"

    # Deputation: Organisation says the officer is away from their home cadre
    # (Centre, inter-cadre deputation, foreign posting, PSU, ex-cadre, non-AIS)
    if o and not o.startswith("CADRE (AIS)") and o != "N.A." and (
        o.startswith("CENTRE") or "INTER-CADRE" in o or "FOREIGN POSTING" in o
        or "PSU" in o or "EX-CADRE" in o or "NON-AIS" in o
    ):
        return "deputation"

    if _SUBDISTRICT_PAT.search(d):
        return "subdistrict"

    if _SECRETARIAT_PAT.search(d):
        return "secretariat"

    return "unclassified"


def is_dc_designation(designation):
    d = (designation or "").upper()
    return any(k in d for k in _DC_INCLUDE) and not any(k in d for k in _DC_EXCLUDE)


exp_clean["post_class"] = [
    classify_post(dsg, org) for dsg, org in zip(exp_clean["Designation"].fillna(""),
                                                  exp_clean["Organisation"].fillna(""))
]
exp_clean["is_dc"] = exp_clean["post_class"].eq("dc_dm_collector")

class_share = exp_clean["post_class"].value_counts(normalize=True).sort_values(ascending=False)
class_count = exp_clean["post_class"].value_counts().sort_values(ascending=False)
top20_unclassified = (exp_clean.loc[exp_clean["post_class"] == "unclassified", "Designation"]
                       .fillna("(blank)").value_counts().head(20))

print("Post classifier -- share of experience rows per bucket:")
print((100 * class_share).round(2).to_string())
print("\nTop 20 most frequent UNCLASSIFIED designation strings:")
print(top20_unclassified.to_string())
print()

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1 -- DC SPELLS, GAP TAXONOMY, SPELL-DURATION DISTRIBUTION
# ─────────────────────────────────────────────────────────────────────────────

dc_spells = exp_clean[exp_clean["is_dc"]].copy()
dc_spells["cadre_key"]  = dc_spells["Cadre"].str.strip().str.lower()
dc_spells["office_key"] = dc_spells["Office"].fillna("").str.strip().str.lower()
dc_spells = dc_spells.merge(cw[["cadre_key", "office_key", "pc11_district_id"]],
                             on=["cadre_key", "office_key"], how="inner")
dc_spells["cadre"] = dc_spells["Cadre"].str.strip()
dc_spells["dc_key"] = dc_spells["cadre_key"] + "||" + dc_spells["pc11_district_id"]

print(f"Collector-designation spells (all years): {int(exp_clean['is_dc'].sum()):,}")
print(f"Matched to a pc11 district via crosswalk: {len(dc_spells):,}\n")

dc_spells["duration_months"] = dc_spells["end_idx"] - dc_spells["start_idx"] + 1

dc_sorted = dc_spells.sort_values(["dc_key", "start_dt"]).copy()
dc_sorted["next_start_idx"] = dc_sorted.groupby("dc_key")["start_idx"].shift(-1)
gap_pairs = dc_sorted.dropna(subset=["next_start_idx"]).copy()
gap_pairs["next_start_idx"] = gap_pairs["next_start_idx"].astype(int)
gap_pairs["gap_months"] = gap_pairs["next_start_idx"] - gap_pairs["end_idx"] - 1
gap_pairs["bucket"] = gap_pairs["gap_months"].apply(bucket_gap)
gap_pairs["cadre"] = roster_lookup.reindex(gap_pairs["dc_key"]).values

BUCKET_ORDER = ["negative (overlap)", "0-3mo", "4-12mo", "13-36mo", ">36mo"]


def gap_bucket_table(df, label):
    t = df["bucket"].value_counts().reindex(BUCKET_ORDER, fill_value=0)
    out = pd.DataFrame({"group": label, "bucket": BUCKET_ORDER,
                         "n": t.values, "share": (t / t.sum()).round(4).values})
    return out


gap_bucket_pooled = gap_bucket_table(gap_pairs, "Pooled (all cadres)")
gap_bucket_top5 = pd.concat(
    [gap_bucket_table(gap_pairs[gap_pairs["cadre"] == c], c) for c in TOP5], ignore_index=True)


def dist_stats(s):
    s = s.dropna()
    if len(s) == 0:
        return {"mean": np.nan, "median": np.nan, "iqr": np.nan, "p10": np.nan, "p90": np.nan}
    return {"mean": s.mean(), "median": s.median(),
            "iqr": s.quantile(.75) - s.quantile(.25),
            "p10": s.quantile(.10), "p90": s.quantile(.90)}


duration_pooled = pd.DataFrame([{"group": "Pooled (all cadres)", **dist_stats(dc_spells["duration_months"])}])
duration_top5 = pd.DataFrame([{"group": c, **dist_stats(dc_spells.loc[dc_spells["cadre"] == c, "duration_months"])}
                               for c in TOP5])
duration_all_cadres = pd.DataFrame([{"group": c, **dist_stats(dc_spells.loc[dc_spells["cadre"] == c, "duration_months"])}
                                     for c in CADRES if c in dc_spells["cadre"].values])

print("Spell-duration distribution (months), pooled:")
print(duration_pooled.round(2).to_string(index=False))
print()

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2 -- VACANCY vs RECORD FAILURE, cadre-district-month
# genuine vacancy: uncovered month whose enclosing gap is bounded on both
# sides AND <= 3 months. everything else uncovered (bounded >3mo, or open-
# ended before the district's first spell / after its last) = record failure.
# ─────────────────────────────────────────────────────────────────────────────

all_dc_keys = district_roster["dc_key"].tolist()
key_to_row = {k: i for i, k in enumerate(all_dc_keys)}
n_keys = len(all_dc_keys)

occ_delta = np.zeros((n_keys, N_MONTHS + 1), dtype=np.int32)
rows_ = dc_spells["dc_key"].map(key_to_row).to_numpy()
s_ = np.clip(dc_spells["start_idx"].to_numpy(), 0, N_MONTHS)
e_ = np.clip(dc_spells["end_idx"].to_numpy() + 1, 0, N_MONTHS)
for r, s, e in zip(rows_, s_, e_):
    if s < e:
        occ_delta[r, s] += 1
        occ_delta[r, e] -= 1
occupied = np.cumsum(occ_delta[:, :N_MONTHS], axis=1) > 0  # n_keys x N_MONTHS, from union sweep

genuine_vacant = np.zeros((n_keys, N_MONTHS), dtype=bool)
record_failure = np.zeros((n_keys, N_MONTHS), dtype=bool)

for dc_key, g in dc_sorted.groupby("dc_key"):
    r = key_to_row[dc_key]
    starts = g["start_idx"].to_numpy()
    ends = g["end_idx"].to_numpy()
    first_s, last_e = starts.min(), ends.max()
    # before first ever spell -> open-ended -> record failure (if in window)
    lo, hi = 0, min(first_s - 1, N_MONTHS - 1)
    if lo <= hi:
        record_failure[r, lo:hi + 1] = True
    # after last ever spell -> open-ended -> record failure (if in window)
    lo, hi = max(last_e + 1, 0), N_MONTHS - 1
    if lo <= hi:
        record_failure[r, lo:hi + 1] = True
    # interior consecutive-pair gaps
    order = np.argsort(starts)
    s_ord, e_ord = starts[order], ends[order]
    for i in range(len(s_ord) - 1):
        gap_s, gap_e = e_ord[i] + 1, s_ord[i + 1] - 1
        if gap_s > gap_e:
            continue  # touching/overlap, no uncovered stretch
        duration = gap_e - gap_s + 1
        lo, hi = max(gap_s, 0), min(gap_e, N_MONTHS - 1)
        if lo > hi:
            continue
        if duration <= 3:
            genuine_vacant[r, lo:hi + 1] = True
        else:
            record_failure[r, lo:hi + 1] = True

# reconciliation check vs raw occupancy sweep (validation, not silently trusted)
uncovered_sweep = ~occupied
uncovered_pairs = genuine_vacant | record_failure
mismatch_cells = int((uncovered_sweep != uncovered_pairs).sum())
print(f"Reconciliation check (occupancy sweep vs consecutive-pair gap classification): "
      f"{mismatch_cells:,} / {n_keys * N_MONTHS:,} district-month cells disagree "
      f"({100 * mismatch_cells / (n_keys * N_MONTHS):.3f}%). "
      f"{'These are forced to record_failure as the conservative choice.' if mismatch_cells else ''}\n")
# Any cell where the sweep says occupied but the pair-method says uncovered
# (can happen with non-adjacent overlapping spells) is forced back to
# "occupied" (trust the direct evidence of a covering spell); the reverse
# (sweep says uncovered, pair-method silent) is forced to record_failure.
genuine_vacant &= occupied == False
record_failure &= occupied == False
still_uncovered_unclassified = uncovered_sweep & ~genuine_vacant & ~record_failure
record_failure |= still_uncovered_unclassified

row_cadre = np.array([roster_lookup[k] for k in all_dc_keys])

vac_rows = []
for cadre in CADRES:
    mask = row_cadre == cadre
    n_dist = int(mask.sum())
    if n_dist == 0:
        continue
    covered = occupied[mask].sum(axis=0)
    gvac = genuine_vacant[mask].sum(axis=0)
    rfail = record_failure[mask].sum(axis=0)
    vac_rows.append(pd.DataFrame({
        "cadre": cadre, "month": MONTH_IDX, "n_districts": n_dist,
        "n_covered": covered, "n_genuine_vacant": gvac, "n_record_failure": rfail,
    }))
vacancy_df = pd.concat(vac_rows, ignore_index=True)
# sanity: n_districts == covered+vacant+failure every row
recon = (vacancy_df["n_districts"]
         - vacancy_df["n_covered"] - vacancy_df["n_genuine_vacant"] - vacancy_df["n_record_failure"])
assert (recon == 0).all(), "district-month components do not sum to roster size"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3 -- ELIGIBILITY BAND (5-15 years of service)
# ─────────────────────────────────────────────────────────────────────────────

officers = prof_valid[["ID", "cadre_clean", "allotment_year"]].reset_index(drop=True)
month_years = np.array([p.year for p in MONTH_IDX])
yos_matrix = month_years[None, :] - officers["allotment_year"].to_numpy()[:, None]  # n_off x N_MONTHS
band = (yos_matrix >= 5) & (yos_matrix <= 15)

cadre_onehot = pd.get_dummies(officers["cadre_clean"]).reindex(columns=CADRES, fill_value=0).to_numpy(dtype=np.int64)
band_cadre_month = cadre_onehot.T @ band.astype(np.int64)  # n_cadres x N_MONTHS

eligible_rows = []
for i, cadre in enumerate(CADRES):
    eligible_rows.append(pd.DataFrame({"cadre": cadre, "month": MONTH_IDX,
                                        "n_eligible_band": band_cadre_month[i]}))
eligible_df = pd.concat(eligible_rows, ignore_index=True)

# observed yos at DC-spell start
dc_start_yos = dc_spells.merge(prof_valid[["ID", "allotment_year"]], on="ID", how="left")
dc_start_yos["yos_at_start"] = dc_start_yos["start_dt"].dt.year - dc_start_yos["allotment_year"]
yos_obs_pooled = dist_stats(dc_start_yos["yos_at_start"])
yos_obs_top5 = pd.DataFrame([{"group": c, **dist_stats(dc_start_yos.loc[dc_start_yos["cadre"] == c, "yos_at_start"])}
                              for c in TOP5])

print("Observed years-of-service at DC-spell start (pooled):", {k: round(v, 2) for k, v in yos_obs_pooled.items()})
band_lo, band_hi = 5, 15
band_flag = (yos_obs_pooled["p10"] < band_lo - 1) or (yos_obs_pooled["p90"] > band_hi + 1)
print(f"5-15yr band vs observed reality: "
      f"{'FLAG -- band and observed p10/p90 disagree materially' if band_flag else 'roughly consistent'}\n")

# ─────────────────────────────────────────────────────────────────────────────
# STEP 4 -- AVAILABILITY, DEFINITIONS A / B / C
# ─────────────────────────────────────────────────────────────────────────────

availA = {c: np.zeros(N_MONTHS, dtype=np.int64) for c in CADRES}
availB = {c: np.zeros(N_MONTHS, dtype=np.int64) for c in CADRES}
availC = {c: np.zeros(N_MONTHS, dtype=np.int64) for c in CADRES}

exp_by_officer = exp_clean.merge(prof_valid[["ID", "cadre_clean", "allotment_year"]], on="ID", how="inner")
exp_by_officer = exp_by_officer.sort_values(["ID", "start_dt"])

officer_band_lookup = {row.ID: month_years - row.allotment_year for row in officers.itertuples()}

for officer_id, g in exp_by_officer.groupby("ID", sort=False):
    cadre = g["cadre_clean"].iloc[0]
    if cadre not in availA or officer_id not in officer_band_lookup:
        continue
    yos_o = officer_band_lookup[officer_id]
    band_o = (yos_o >= 5) & (yos_o <= 15)
    if not band_o.any():
        continue

    all_iv = list(zip(g["start_idx"].tolist(), g["end_idx"].tolist()))
    dc_iv = list(zip(g.loc[g["is_dc"], "start_idx"].tolist(), g.loc[g["is_dc"], "end_idx"].tolist()))

    busy_any = np.zeros(N_MONTHS, dtype=bool)
    for s, e in merge_intervals(all_iv):
        lo, hi = max(s, 0), min(e, N_MONTHS - 1)
        if lo <= hi:
            busy_any[lo:hi + 1] = True
    busy_dc = np.zeros(N_MONTHS, dtype=bool)
    for s, e in merge_intervals(dc_iv):
        lo, hi = max(s, 0), min(e, N_MONTHS - 1)
        if lo <= hi:
            busy_dc[lo:hi + 1] = True
    busy_nondc = busy_any & ~busy_dc

    eligible_not_dc = band_o & ~busy_dc

    # condition (a): currently in a recorded non-DC post
    cond_a = eligible_not_dc & busy_nondc
    availA[cadre] += cond_a.astype(np.int64)
    availB[cadre] += cond_a.astype(np.int64)

    # condition (b): both-sided gap, duration <=3 (def A) / <=12 (def B)
    merged_all = merge_intervals(all_iv)
    for (_, e_prev), (s_next, _) in zip(merged_all[:-1], merged_all[1:]):
        gap_s, gap_e = e_prev + 1, s_next - 1
        if gap_s > gap_e:
            continue
        duration = gap_e - gap_s + 1
        lo, hi = max(gap_s, 0), min(gap_e, N_MONTHS - 1)
        if lo > hi:
            continue
        seg = np.zeros(N_MONTHS, dtype=bool)
        seg[lo:hi + 1] = True
        seg &= eligible_not_dc
        if duration <= 3:
            availA[cadre] += seg.astype(np.int64)
        if duration <= 12:
            availB[cadre] += seg.astype(np.int64)

    # condition C: def A restricted to officers with >=1 prior post in-cadre
    if len(all_iv) >= 2:
        earliest_start = min(s for s, _ in all_iv)
        has_prior = np.array([earliest_start < m for m in range(N_MONTHS)])
        cond_c = cond_a.copy()
        for (_, e_prev), (s_next, _) in zip(merged_all[:-1], merged_all[1:]):
            gap_s, gap_e = e_prev + 1, s_next - 1
            if gap_s > gap_e:
                continue
            duration = gap_e - gap_s + 1
            if duration > 3:
                continue
            lo, hi = max(gap_s, 0), min(gap_e, N_MONTHS - 1)
            if lo > hi:
                continue
            cond_c[lo:hi + 1] |= eligible_not_dc[lo:hi + 1]
        cond_c &= has_prior
        availC[cadre] += cond_c.astype(np.int64)

avail_rows = []
for cadre in CADRES:
    avail_rows.append(pd.DataFrame({
        "cadre": cadre, "month": MONTH_IDX,
        "avail_A_le3mo": availA[cadre], "avail_B_le12mo": availB[cadre], "avail_C_priorpost": availC[cadre],
    }))
avail_df = pd.concat(avail_rows, ignore_index=True)

# ─────────────────────────────────────────────────────────────────────────────
# ASSEMBLE PANEL
# ─────────────────────────────────────────────────────────────────────────────

panel = (vacancy_df
         .merge(eligible_df, on=["cadre", "month"])
         .merge(avail_df, on=["cadre", "month"]))
panel["year"] = panel["month"].dt.year
panel["month_num"] = panel["month"].dt.month
for defn in ["A_le3mo", "B_le12mo", "C_priorpost"]:
    panel[f"ratio_{defn}"] = panel[f"avail_{defn}"] / panel["n_genuine_vacant"].replace(0, np.nan)

panel_out = panel[["cadre", "year", "month_num", "n_districts", "n_covered",
                    "n_genuine_vacant", "n_record_failure", "n_eligible_band",
                    "avail_A_le3mo", "avail_B_le12mo", "avail_C_priorpost",
                    "ratio_A_le3mo", "ratio_B_le12mo", "ratio_C_priorpost"]].sort_values(
    ["cadre", "year", "month_num"])
panel_out.to_csv(os.path.join(OUT_DIR, "cadre_month_panel.csv"), index=False)
print(f"Saved {OUT_DIR}/cadre_month_panel.csv  ({len(panel_out):,} rows)")

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2 (cont.) -- vacancy / record-failure / eligible-band distributions
# ─────────────────────────────────────────────────────────────────────────────

vac_metrics = ["n_genuine_vacant", "n_record_failure", "n_eligible_band"]
VAC_LABEL = {"n_genuine_vacant": "Genuine vacancies (no spell, gap <=3mo both-sided)",
             "n_record_failure": "Record failures (no spell, gap >3mo or open-ended)",
             "n_eligible_band": "Officers in 5-15yr eligibility band"}

vac_stats_pooled = pd.DataFrame([{"metric": VAC_LABEL[m], "group": "Pooled", **dist_stats(panel[m])}
                                  for m in vac_metrics])
vac_stats_top5 = pd.concat(
    [pd.DataFrame([{"metric": VAC_LABEL[m], "group": c, **dist_stats(panel.loc[panel["cadre"] == c, m])}
                    for c in TOP5]) for m in vac_metrics], ignore_index=True)

# ─────────────────────────────────────────────────────────────────────────────
# STEP 5 -- RATIO STATS, THRESHOLD SHARES, CORRELATION, SANITY CHECK
# ─────────────────────────────────────────────────────────────────────────────

DEFS = ["A_le3mo", "B_le12mo", "C_priorpost"]
DEF_LABEL = {"A_le3mo": "Def A (currently non-DC post, or gap <=3mo)",
             "B_le12mo": "Def B (as A, gap widened to <=12mo)",
             "C_priorpost": "Def C (Def A + >=1 prior post in cadre)"}

ratio_pooled = pd.DataFrame([{"definition": DEF_LABEL[d], **dist_stats(panel[f"ratio_{d}"])}
                              for d in DEFS])
threshold_rows = []
for d in DEFS:
    r = panel[f"ratio_{d}"].dropna()
    threshold_rows.append({
        "definition": DEF_LABEL[d], "n_cadre_months_with_vacancy": len(r),
        "share_lt_1": (r < 1).mean(), "share_lt_2": (r < 2).mean(), "share_lt_5": (r < 5).mean(),
    })
threshold_df = pd.DataFrame(threshold_rows)

corr_rows = []
for d in DEFS:
    r_pooled = panel["n_genuine_vacant"].corr(panel[f"avail_{d}"])
    r_top5 = {c: panel.loc[panel["cadre"] == c, "n_genuine_vacant"].corr(panel.loc[panel["cadre"] == c, f"avail_{d}"])
              for c in TOP5}
    corr_rows.append({"definition": DEF_LABEL[d], "pooled_r": r_pooled, **r_top5})
corr_df = pd.DataFrame(corr_rows)

avail_dist_pooled = pd.concat(
    [pd.DataFrame([{"definition": DEF_LABEL[d], "group": "Pooled", **dist_stats(panel[f"avail_{d}"])}])
     for d in DEFS], ignore_index=True)
avail_dist_top5 = pd.concat(
    [pd.DataFrame([{"definition": DEF_LABEL[d], "group": c,
                     **dist_stats(panel.loc[panel["cadre"] == c, f"avail_{d}"])}
                    for c in TOP5]) for d in DEFS], ignore_index=True)

# sanity check: officers per cadre must exceed roster size, always
sanity = pd.DataFrame({"cadre": CADRES,
                        "n_officers": [int(cadre_size.get(c, 0)) for c in CADRES],
                        "n_districts_roster": [int(roster_size_by_cadre.get(c, 0)) for c in CADRES]})
sanity["officers_exceed_roster"] = sanity["n_officers"] > sanity["n_districts_roster"]
sanity_fail = sanity[~sanity["officers_exceed_roster"] & (sanity["n_districts_roster"] > 0)]

print("\nSanity check -- officers per cadre must exceed roster size:")
if len(sanity_fail) == 0:
    print("  PASS for all cadres with a matched roster.")
else:
    print("  FAIL for:", sanity_fail.to_string(index=False))

# ─────────────────────────────────────────────────────────────────────────────
# MARKDOWN
# ─────────────────────────────────────────────────────────────────────────────

L = []
L.append("# Collector Vacancy-and-Availability Panel, Cadre-Month, 1994-2008 (v2)\n")
L.append("Standalone, read-only analysis of `data/raw/ias-experience.csv`, "
         "`data/raw/ias-profile.csv`, `data/analysis/crosswalk_v2.csv`. No existing "
         "pipeline file was modified or used as a source.\n")
L.append("**Unit of analysis: cadre (\"state cadre\"), same choice and same reasoning "
         "as the earlier `diagnostics/collector_availability/` pass** -- crosswalk "
         "cadre->pc11_state_id is many-to-many due to office-name matching noise, so "
         "cadre is the unambiguous key. \"District\" = (cadre, pc11_district_id).\n")
L.append(f"- Officers with usable cadre + allotment year: {prof_valid['ID'].nunique():,} "
         f"across {len(CADRES)} cadres\n"
         f"- Experience rows: {len(exp):,} -> {len(exp_clean):,} usable posting intervals "
         f"(bad start date {n_bad_start}, bad non-\"N.A.\" end date {n_bad_end}, "
         f"true end-before-start anomaly {n_end_lt_start}, and {n_ongoing_after_window} "
         f"further rows dropped because they are \"N.A.\"-ended (ongoing) but start after "
         f"the 2008 study window closes -- not a data error, just out of scope)\n"
         f"- Collector-designation spells (all years): {int(exp_clean['is_dc'].sum()):,}; "
         f"matched to a pc11 district via crosswalk: {len(dc_spells):,}\n")
L.append("**Five largest state cadres** (by officer headcount):\n")
for c in TOP5:
    L.append(f"- {c}: {int(cadre_size[c]):,} officers, {int(roster_size_by_cadre.get(c, 0))} districts on roster")
L.append("")

L.append("## Step 6 -- Post classifier\n")
L.append("**Built on `Designation` (job title), not literally `Office` (department/place "
         "name).** Office holds strings like \"M/o Education\" or a district name and "
         "carries no DC / sub-district / secretariat / deputation / training role "
         "information; Designation is where that information lives, and it is the same "
         "field the existing pipeline's own DC filter already uses. This is a deliberate, "
         "flagged substitution for the task's \"free-text office names\" phrasing, not a "
         "silent one.\n\n"
         "Priority order: DC/DM/Collector (exact reuse of the existing pipeline filter) "
         "&rarr; training (Designation or Organisation) &rarr; deputation (Organisation "
         "indicates away from home cadre: Centre, inter-cadre, foreign posting, PSU, "
         "ex-cadre, non-AIS) &rarr; sub-district (SDM/SDO/sub-collector/additional "
         "collector/joint collector/etc., keyword list in code) &rarr; secretariat "
         "(broad HQ/board/leadership keyword list) &rarr; unclassified.\n")
L.append("Share of experience rows (N={:,}) per bucket:\n".format(len(exp_clean)))
cls_tbl = pd.DataFrame({"bucket": class_share.index, "n_rows": class_count.reindex(class_share.index).values,
                         "share": class_share.values})
L.append(cls_tbl.round(4).to_markdown(index=False))
L.append("\nTop 20 most frequent **unclassified** designation strings (candidates for "
         "extending the ruleset):\n")
L.append(pd.DataFrame({"designation": top20_unclassified.index, "n": top20_unclassified.values})
         .to_markdown(index=False))
L.append("")

L.append("## Step 1 -- Gap taxonomy and spell duration\n")
L.append(f"Consecutive-spell-pair gaps computed within each district-cadre roster slot, "
         f"ordered by start date: {len(gap_pairs):,} pairs.\n")
L.append("### Pooled\n")
L.append(gap_bucket_pooled[["bucket", "n", "share"]].round(4).to_markdown(index=False))
L.append("\n### Five largest cadres\n")
L.append(gap_bucket_top5[["group", "bucket", "n", "share"]].round(4).to_markdown(index=False))
L.append("\n### DC spell duration (months)\n")
L.append("**Pooled:**\n")
L.append(duration_pooled.round(2).to_markdown(index=False))
L.append("\n**Five largest cadres:**\n")
L.append(duration_top5.round(2).to_markdown(index=False))
L.append("\n**All cadres** (for completeness, not requested as a headline table):\n")
L.append(duration_all_cadres.round(2).to_markdown(index=False))
L.append("")

L.append("## Step 2 -- Vacancy vs. record failure\n")
L.append("**Rule:** a district-month with no spell covering it counts as a **genuine "
         "vacancy** only if the enclosing gap (Step 1's consecutive-pair gap) is bounded "
         "on both sides and <=3 months. Everything else uncovered -- a bounded gap >3 "
         "months, or an open-ended gap before a district's first-ever recorded spell or "
         "after its last -- is a **record failure**, not a vacancy: we cannot verify "
         "\"no administrator\" for an unbounded stretch, and a district cannot plausibly "
         "run headless for a year.\n")
L.append(f"Reconciliation against the raw occupancy sweep (independent check, not "
         f"silently trusted): {mismatch_cells:,} of {n_keys * N_MONTHS:,} district-month "
         f"cells ({100 * mismatch_cells / (n_keys * N_MONTHS):.3f}%) disagreed before "
         f"reconciliation; disagreements are resolved conservatively (trust a directly "
         f"observed covering spell over the pair-gap inference; anything left uncovered "
         f"and unclassified is folded into record failure).\n")
L.append("### Distribution across cadre-months, pooled\n")
L.append(vac_stats_pooled[vac_stats_pooled["metric"] != VAC_LABEL["n_eligible_band"]]
         .round(2).to_markdown(index=False))
L.append("\n### Five largest cadres\n")
L.append(vac_stats_top5[vac_stats_top5["metric"] != VAC_LABEL["n_eligible_band"]]
         .round(2).to_markdown(index=False))
L.append("")

L.append("## Step 3 -- Eligibility band (5-15 years of service)\n")
L.append("Distribution of officers in-band, cadre-months:\n")
L.append(vac_stats_pooled[vac_stats_pooled["metric"] == VAC_LABEL["n_eligible_band"]]
         .round(2).to_markdown(index=False))
L.append("")
L.append(vac_stats_top5[vac_stats_top5["metric"] == VAC_LABEL["n_eligible_band"]]
         .round(2).to_markdown(index=False))
L.append("\n**Observed years-of-service at actual DC-spell start** (the reality check "
         "against the 5-15yr band):\n")
L.append("Pooled: " + ", ".join(f"{k}={v:.2f}" for k, v in yos_obs_pooled.items()))
L.append("\n\nFive largest cadres:\n")
L.append(yos_obs_top5.round(2).to_markdown(index=False))
if band_flag:
    L.append("\n**FLAG:** the observed p10/p90 of years-of-service at DC-spell start "
              "falls materially outside the assumed 5-15yr band -- the band as specified "
              "does not match the data and should be revisited before it is used "
              "downstream (see Step 4 numbers, which are conditional on this band).")
else:
    L.append("\nObserved p10/p90 sit reasonably within the 5-15yr band; no revision flagged.")
L.append("")

L.append("## Step 4 -- Availability, Definitions A / B / C\n")
L.append("- **Def A**: in eligibility band, not currently in a DC spell, and either "
         "currently in a recorded non-DC post, or in a both-sided gap of <=3 months.\n"
         "- **Def B**: as A, gap tolerance widened to <=12 months.\n"
         "- **Def C**: Def A, restricted to officers with >=1 recorded posting (any "
         "designation) before the current month.\n\n"
         "**Caveat, not silently resolved:** \"currently in a recorded non-DC post\" "
         "counts *any* non-DC classified posting, including deputation and training "
         "postings (Step 6's finer categories). An officer on central deputation or in "
         "training is arguably not truly available for state DC posting; this reading "
         "of the definition as given will overstate availability under condition (a) to "
         "that extent. Restricting (a) to exclude deputation/training is a one-line "
         "change (`post_class not in {'deputation','training'}`) if a stricter reading "
         "is wanted.\n")
L.append("### Distribution across cadre-months, pooled\n")
L.append(avail_dist_pooled.round(2).to_markdown(index=False))
L.append("\n### Five largest cadres\n")
L.append(avail_dist_top5.round(2).to_markdown(index=False))
L.append("")

L.append("## Step 5 -- The ratio that matters (available / genuine vacancies)\n")
L.append(f"Computed only for the {int(panel['n_genuine_vacant'].gt(0).sum()):,} of "
         f"{len(panel):,} cadre-months with >=1 genuine vacancy (ratio undefined at "
         f"zero vacancies; those months are excluded from the distribution below, not "
         f"silently treated as 0 or infinite).\n")
L.append(ratio_pooled.round(3).to_markdown(index=False))
L.append("\n**Share of (vacancy>0) cadre-months where the ratio falls below threshold:**\n")
L.append(threshold_df.round(3).to_markdown(index=False))
L.append("\n**Correlation, genuine vacancies vs. available officers (cadre-month level):**\n")
L.append(corr_df.round(3).to_markdown(index=False))
L.append("")

L.append("## Sanity check -- officers must exceed roster size\n")
L.append(sanity[sanity["n_districts_roster"] > 0].to_markdown(index=False))
if len(sanity_fail):
    L.append("\n**FLAG:** the following cadres fail the officers > roster-size sanity "
              "check and should be investigated before trusting their numbers:\n")
    L.append(sanity_fail.to_markdown(index=False))
else:
    L.append("\nPASS for every cadre with a matched district roster: officer headcount "
              "exceeds Collector-post roster size in all cases, as expected.")
L.append("")

with open(os.path.join(OUT_DIR, "summary.md"), "w") as f:
    f.write("\n".join(L))
print(f"\nSaved {OUT_DIR}/summary.md")
