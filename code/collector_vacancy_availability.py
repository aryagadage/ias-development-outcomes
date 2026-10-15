"""
Collector-post vacancy and officer-availability, state(cadre)-month panel, 1994-2008.

Standalone analysis. Does NOT modify or depend on any existing built file
(dc_analysis_*.csv, panel_full.csv, etc.) -- it reads only the raw officer
records (data/raw/ias-experience.csv, data/raw/ias-profile.csv) and the
cadre/office->pc11-district crosswalk (data/analysis/crosswalk_v2.csv), which
are treated as read-only inputs.

Unit of analysis is the CADRE ("state cadre" in IAS usage), not pc11_state_id:
several cadres (Andhra Pradesh, Rajasthan, Punjab, ...) match to more than one
pc11_state_id in crosswalk_v2.csv due to office-name fuzzy-matching noise, so
pc11_state_id is not a clean aggregation key. Cadre is: (a) the unit the
existing pipeline already uses for seniority/turnover variables (cadre_queue_pct,
CM_turnover, Queue_st/QueueT_st), and (b) literally what "state cadre" means
institutionally, including the joint UT cadres (A G M U T, Assam Meghalya,
Manipur-Tripura) which are genuinely multi-state/UT by design, not a data error.

Definitions
-----------
(a) Vacant Collector posts, cadre-month: districts in that cadre's roster
    (distinct pc11_district_id in crosswalk_v2.csv for that cadre) with no
    Collector-designation spell interval covering the month.
(b) Officers available, cadre-month, three definitions, built from the
    officer's FULL posting history (all designations, not just Collector):
      def1 "any"          -- no posting interval (of any kind) covers the month.
      def2 "gap<24mo"      -- as def1, AND the specific gap covering the month
                              has a recorded posting on both sides AND is
                              under 24 months long.
      def3 "both-sided"    -- as def1, AND the specific gap covering the month
                              has a recorded posting on both sides (no duration
                              cap).
    By construction def2 (subset) <= def3 (subset) <= def1 in every cell.
    An open-ended gap (before an officer's first-ever posting, or after their
    last) only ever counts toward def1.
(c) New Collector spells starting in the cadre-month (by spell start month).

Outputs
-------
diagnostics/collector_availability/state_month_panel.csv
diagnostics/collector_availability/summary.md
"""
import os
import numpy as np
import pandas as pd

OUT_DIR = "diagnostics/collector_availability"
os.makedirs(OUT_DIR, exist_ok=True)

STUDY_START = pd.Timestamp("1994-01-01")
STUDY_END   = pd.Timestamp("2008-12-31")
N_MONTHS    = (2008 - 1994 + 1) * 12  # 180
MONTH_IDX   = pd.period_range("1994-01", "2008-12", freq="M")  # length 180


def month_index(dt):
    """Map a Timestamp to an integer month index, 0 = 1994-01 .. 179 = 2008-12.
    Values outside [1994-01, 2008-12] are clipped to -1 / N_MONTHS (out of range)."""
    idx = (dt.dt.year - 1994) * 12 + (dt.dt.month - 1)
    return idx


# ─────────────────────────────────────────────────────────────────────────────
# 1. LOAD RAW INPUTS (read-only)
# ─────────────────────────────────────────────────────────────────────────────

exp = pd.read_csv("data/raw/ias-experience.csv", dtype=str)
prof = pd.read_csv("data/raw/ias-profile.csv", dtype=str)
cw_raw = pd.read_csv("data/analysis/crosswalk_v2.csv", dtype=str)

exp["start_dt"] = pd.to_datetime(exp["Start_Date"], errors="coerce")
exp["end_raw"]  = exp["End_Date"]
exp["end_dt"]   = pd.to_datetime(exp["End_Date"], errors="coerce")
exp["ongoing"]  = exp["end_raw"].eq("N.A.")

n_bad_start = exp["start_dt"].isna().sum()
n_bad_end   = (~exp["ongoing"]) & exp["end_dt"].isna()
n_end_lt_start = (exp["end_dt"].notna() & exp["start_dt"].notna() &
                   (exp["end_dt"] < exp["start_dt"])).sum()

# Ongoing ("N.A." end date) -> cap at study window end for interval purposes.
exp.loc[exp["ongoing"], "end_dt"] = STUDY_END

# Drop rows we cannot place in time, and the small number of end<start anomalies.
exp_clean = exp[
    exp["start_dt"].notna()
    & exp["end_dt"].notna()
    & (exp["end_dt"] >= exp["start_dt"])
].copy()

cw = cw_raw[cw_raw["pc11_district_id"].notna() & (cw_raw["pc11_district_id"] != "")].copy()
cw["cadre_key"]  = cw["cadre"].str.strip().str.lower()
cw["office_key"] = cw["office_name"].str.strip().str.lower()
cw["pc11_district_id"] = cw["pc11_district_id"].str.strip()

prof["cadre_clean"] = prof["Cadre"].str.strip()
prof_valid = prof[prof["cadre_clean"].notna() & (prof["cadre_clean"] != "")].copy()

CADRES = sorted(prof_valid["cadre_clean"].unique())
cadre_size = prof_valid.groupby("cadre_clean")["ID"].nunique().sort_values(ascending=False)

print(f"Officers (profile): {prof['ID'].nunique():,}  |  cadres: {len(CADRES)}")
print(f"Experience rows: {len(exp):,}  |  unparseable start: {n_bad_start}  "
      f"|  unparseable non-N.A. end: {n_bad_end.sum()}  |  end<start dropped: {n_end_lt_start}")
print(f"Usable posting-interval rows: {len(exp_clean):,}\n")

TOP5 = cadre_size.head(5).index.tolist()
print("Five largest state cadres (by officer headcount):")
for c in TOP5:
    print(f"  {c:20s} {cadre_size[c]:5d} officers")
print()

# ─────────────────────────────────────────────────────────────────────────────
# 2. COLLECTOR-DESIGNATION SPELLS  (identical filter to build_iv_v2.py)
# ─────────────────────────────────────────────────────────────────────────────

d = exp_clean["Designation"].str.upper().fillna("")
is_dc = (
    d.str.contains("DISTRICT COLLECTOR")
    | d.str.contains("COLLECTOR")
    | d.str.contains("DISTRICT MAGISTRATE")
    | d.str.contains("DEPUTY COMMISSIONER")
) & ~(
    d.str.contains("ADDITIONAL")
    | d.str.contains("JOINT")
    | d.str.contains("JT ")
    | d.str.contains("SUB ")
    | d.str.contains("ASSISTANT")
    | d.str.contains("DEPUTY COLLECTOR")
    | d.str.contains("SPL DEPUTY")
)
dc_spells = exp_clean[is_dc].copy()
dc_spells["cadre_key"]  = dc_spells["Cadre"].str.strip().str.lower()
dc_spells["office_key"] = dc_spells["Office"].fillna("").str.strip().str.lower()

dc_spells = dc_spells.merge(
    cw[["cadre_key", "office_key", "pc11_district_id"]],
    on=["cadre_key", "office_key"], how="inner"
)
dc_spells["cadre"] = dc_spells["Cadre"].str.strip()

print(f"Collector-designation spells (all years): {len(exp_clean[is_dc]):,}")
print(f"Collector spells matched to a pc11 district via crosswalk: {len(dc_spells):,}\n")

# ─────────────────────────────────────────────────────────────────────────────
# 3. (a) VACANCY  --  cadre x district x month occupancy, via sweep-line
# ─────────────────────────────────────────────────────────────────────────────

def occupied_month_matrix(spells, key_col, key_values):
    """Boolean [n_keys x N_MONTHS] matrix: True if `key` has >=1 spell/interval
    covering that month. Built with a start/end sweep (+1 at start month,
    -1 at (end month + 1)), then a cumulative sum per key."""
    key_to_row = {k: i for i, k in enumerate(key_values)}
    n = len(key_values)
    delta = np.zeros((n, N_MONTHS + 1), dtype=np.int32)
    s_idx = month_index(spells["start_dt"])
    e_idx = month_index(spells["end_dt"])
    rows = spells[key_col].map(key_to_row).to_numpy()
    s_idx = np.clip(s_idx.to_numpy(), 0, N_MONTHS)
    e_idx = np.clip(e_idx.to_numpy() + 1, 0, N_MONTHS)
    valid = rows == rows  # non-nan mask (all should be valid post-merge)
    for r, s, e in zip(rows[valid], s_idx[valid], e_idx[valid]):
        if s < e:
            delta[r, s] += 1
            delta[r, e] -= 1
    occ_count = np.cumsum(delta[:, :N_MONTHS], axis=1)
    return occ_count > 0  # boolean n x N_MONTHS


cadre_key_to_name = (cw[["cadre_key", "cadre"]].drop_duplicates("cadre_key")
                     .set_index("cadre_key")["cadre"].str.strip())

district_roster = (cw[["cadre_key", "pc11_district_id"]]
                    .drop_duplicates()
                    .assign(cadre=lambda x: x["cadre_key"].map(cadre_key_to_name)))
district_roster["district_cadre_key"] = district_roster["cadre_key"] + "||" + district_roster["pc11_district_id"]

dc_spells["district_cadre_key"] = dc_spells["cadre_key"] + "||" + dc_spells["pc11_district_id"]

all_district_cadre_keys = district_roster["district_cadre_key"].unique().tolist()
occ_matrix = occupied_month_matrix(dc_spells, "district_cadre_key", all_district_cadre_keys)

roster_lookup = district_roster.set_index("district_cadre_key")["cadre"]
row_cadre = np.array([roster_lookup[k] for k in all_district_cadre_keys])

vacancy_rows = []
for cadre in CADRES:
    mask = row_cadre == cadre
    n_dist = mask.sum()
    if n_dist == 0:
        continue
    vacant_count = n_dist - occ_matrix[mask].sum(axis=0)  # per month
    vacancy_rows.append(pd.DataFrame({
        "cadre": cadre, "month": MONTH_IDX, "n_districts": n_dist,
        "vacant_districts": vacant_count
    }))
vacancy_df = pd.concat(vacancy_rows, ignore_index=True)

# ─────────────────────────────────────────────────────────────────────────────
# 4. (c) NEW COLLECTOR SPELLS STARTING, cadre-month
# ─────────────────────────────────────────────────────────────────────────────

dc_spells["start_month_idx"] = month_index(dc_spells["start_dt"])
new_spells_ct = (
    dc_spells[(dc_spells["start_month_idx"] >= 0) & (dc_spells["start_month_idx"] < N_MONTHS)]
    .groupby(["cadre", "start_month_idx"]).size()
)
new_spells_df = pd.DataFrame({"month": MONTH_IDX}).assign(key=1).merge(
    pd.DataFrame({"cadre": CADRES}).assign(key=1), on="key").drop(columns="key")
new_spells_df["month_idx"] = np.tile(np.arange(N_MONTHS), len(CADRES))
new_spells_df["new_spells"] = new_spells_df.apply(
    lambda r: new_spells_ct.get((r["cadre"], r["month_idx"]), 0), axis=1)
new_spells_df = new_spells_df.drop(columns="month_idx")

# ─────────────────────────────────────────────────────────────────────────────
# 5. (b) OFFICER AVAILABILITY -- three definitions, per officer then aggregated
# ─────────────────────────────────────────────────────────────────────────────

exp_for_avail = exp_clean.merge(prof_valid[["ID", "cadre_clean"]], on="ID", how="inner")
exp_for_avail = exp_for_avail.sort_values(["ID", "start_dt"])

# def1/def2/def3 accumulator matrices, one row per cadre (aggregated directly,
# since we only need cadre-level counts, not officer-level detail).
avail1 = {c: np.zeros(N_MONTHS, dtype=np.int64) for c in CADRES}
avail2 = {c: np.zeros(N_MONTHS, dtype=np.int64) for c in CADRES}
avail3 = {c: np.zeros(N_MONTHS, dtype=np.int64) for c in CADRES}

months_arange = np.arange(N_MONTHS)

for officer_id, g in exp_for_avail.groupby("ID", sort=False):
    cadre = g["cadre_clean"].iloc[0]
    if cadre not in avail1:
        continue

    # merge overlapping/touching busy intervals for this officer
    s_idx = np.clip(month_index(g["start_dt"]).to_numpy(), -10_000, N_MONTHS + 10_000)
    e_idx = np.clip(month_index(g["end_dt"]).to_numpy(), -10_000, N_MONTHS + 10_000)
    iv = sorted(zip(s_idx.tolist(), e_idx.tolist()))
    merged = []
    for s, e in iv:
        if merged and s <= merged[-1][1] + 1:  # touching or overlapping (inclusive month indices)
            merged[-1] = (merged[-1][0], max(merged[-1][1], e))
        else:
            merged.append((s, e))

    if not merged:
        # officer has literally no usable posting record -> available (def1) whole window
        avail1[cadre] += 1
        continue

    busy = np.zeros(N_MONTHS, dtype=bool)
    for s, e in merged:
        lo = max(s, 0)
        hi = min(e, N_MONTHS - 1)
        if lo <= hi:
            busy[lo:hi + 1] = True
    avail1[cadre] += (~busy).astype(np.int64)

    # def2/def3: gaps strictly BETWEEN two consecutive merged (real, possibly
    # out-of-window) intervals only -- never the open-ended gap before the
    # officer's first posting or after their last, by construction.
    for (_, e_prev), (s_next, _) in zip(merged[:-1], merged[1:]):
        gap_s, gap_e = e_prev + 1, s_next - 1
        if gap_s > gap_e:
            continue  # touching/adjacent intervals, no real gap
        duration = gap_e - gap_s + 1  # true duration in months, unclipped
        lo, hi = max(gap_s, 0), min(gap_e, N_MONTHS - 1)
        if lo > hi:
            continue  # gap lies entirely outside the study window
        avail3[cadre][lo:hi + 1] += 1
        if duration < 24:
            avail2[cadre][lo:hi + 1] += 1

avail_rows = []
for cadre in CADRES:
    avail_rows.append(pd.DataFrame({
        "cadre": cadre, "month": MONTH_IDX,
        "avail_def1_any": avail1[cadre],
        "avail_def2_gap_lt24mo": avail2[cadre],
        "avail_def3_both_sided": avail3[cadre],
    }))
avail_df = pd.concat(avail_rows, ignore_index=True)

# ─────────────────────────────────────────────────────────────────────────────
# 6. ASSEMBLE PANEL
# ─────────────────────────────────────────────────────────────────────────────

panel = (vacancy_df
         .merge(new_spells_df, on=["cadre", "month"])
         .merge(avail_df, on=["cadre", "month"]))
panel["year"] = panel["month"].dt.year
panel["month_num"] = panel["month"].dt.month
panel = panel[["cadre", "year", "month_num", "n_districts", "vacant_districts",
               "new_spells", "avail_def1_any", "avail_def2_gap_lt24mo",
               "avail_def3_both_sided"]].sort_values(["cadre", "year", "month_num"])
panel.to_csv(os.path.join(OUT_DIR, "state_month_panel.csv"), index=False)
print(f"Saved {OUT_DIR}/state_month_panel.csv  ({len(panel):,} rows)")

# ─────────────────────────────────────────────────────────────────────────────
# 7. TURNOVER GAP: spell-end -> next spell-start, same district
# ─────────────────────────────────────────────────────────────────────────────

dc_sorted = dc_spells.sort_values(["district_cadre_key", "start_dt"]).copy()
dc_sorted["next_start"] = dc_sorted.groupby("district_cadre_key")["start_dt"].shift(-1)
dc_sorted["this_end"]   = dc_sorted["end_dt"]
pairs = dc_sorted.dropna(subset=["next_start"]).copy()
pairs["gap_months"] = (pairs["next_start"] - pairs["this_end"]).dt.days / 30.44
pairs["cadre"] = roster_lookup.reindex(pairs["district_cadre_key"]).values

turnover_all = pairs["gap_months"]
turnover_nonneg = pairs.loc[pairs["gap_months"] >= 0, "gap_months"]

print(f"\nDistrict succession pairs: {len(pairs):,}  "
      f"(negative/overlapping gaps: {(pairs['gap_months'] < 0).sum()})")
print(f"Mean turnover gap, all pairs incl. overlaps: {turnover_all.mean():.2f} months")
print(f"Mean turnover gap, non-negative only:        {turnover_nonneg.mean():.2f} months")

# ─────────────────────────────────────────────────────────────────────────────
# 8. SUMMARY STATS + CORRELATIONS + MARKDOWN
# ─────────────────────────────────────────────────────────────────────────────

def dist_stats(s):
    s = s.dropna()
    return {
        "mean": s.mean(), "median": s.median(),
        "iqr": s.quantile(0.75) - s.quantile(0.25),
        "p10": s.quantile(0.10), "p90": s.quantile(0.90),
    }

METRICS = ["vacant_districts", "avail_def1_any", "avail_def2_gap_lt24mo",
           "avail_def3_both_sided", "new_spells"]
METRIC_LABELS = {
    "vacant_districts": "(a) Vacant Collector posts",
    "avail_def1_any": "(b1) Officers available -- any gap",
    "avail_def2_gap_lt24mo": "(b2) Officers available -- both-sided gap, <24mo",
    "avail_def3_both_sided": "(b3) Officers available -- both-sided gap",
    "new_spells": "(c) New Collector spells starting",
}

def build_stats_table(df, group_label):
    rows = []
    for m in METRICS:
        st = dist_stats(df[m])
        rows.append({"group": group_label, "metric": METRIC_LABELS[m], **st})
    return pd.DataFrame(rows)

pooled_stats = build_stats_table(panel, "Pooled (all cadres)")
top5_stats = pd.concat(
    [build_stats_table(panel[panel["cadre"] == c], c) for c in TOP5],
    ignore_index=True
)

corr_rows = []
for m in ["avail_def1_any", "avail_def2_gap_lt24mo", "avail_def3_both_sided"]:
    r_pooled = panel["vacant_districts"].corr(panel[m])
    r_top5 = {c: panel.loc[panel["cadre"] == c, "vacant_districts"].corr(panel.loc[panel["cadre"] == c, m])
              for c in TOP5}
    corr_rows.append({"available_definition": METRIC_LABELS[m], "pooled_r": r_pooled, **r_top5})
corr_df = pd.DataFrame(corr_rows)

turnover_by_cadre = pairs.groupby("cadre")["gap_months"].mean()

# ---- write markdown ----
def fmt(x, nd=2):
    return f"{x:.{nd}f}" if pd.notna(x) else "NA"

lines = []
lines.append("# Collector Vacancy and Officer Availability, State(-Cadre)-Month Panel, 1994-2008\n")
lines.append("Standalone read-only analysis of `data/raw/ias-experience.csv`, "
              "`data/raw/ias-profile.csv`, and `data/analysis/crosswalk_v2.csv`. "
              "No existing pipeline file was read for its *derived* columns and none was modified.\n")
lines.append("**Unit of analysis: cadre (\"state cadre\"), not `pc11_state_id`.** "
              "`crosswalk_v2.csv` maps several cadres to more than one `pc11_state_id` "
              "(office-name matching noise), so cadre is the clean, unambiguous grouping "
              "key -- and it is what the existing pipeline already uses for "
              "seniority/turnover variables. Joint cadres (A G M U T, Assam Meghalya, "
              "Manipur-Tripura) are genuinely multi-state/UT by institutional design, "
              "not a data artefact.\n")
lines.append(f"- Officers in profile file: {prof['ID'].nunique():,}; distinct cadres: {len(CADRES)}\n"
              f"- Experience rows: {len(exp):,}; unparseable start date: {n_bad_start}; "
              f"unparseable (non-\"N.A.\") end date: {int(n_bad_end.sum())}; "
              f"end-before-start dropped: {n_end_lt_start}\n"
              f"- Collector-designation spells (all years, same filter as `build_iv_v2.py`): "
              f"{len(exp_clean[is_dc]):,}; matched to a pc11 district via crosswalk: {len(dc_spells):,}\n")
roster_size_by_cadre = panel.groupby("cadre")["n_districts"].first()
lines.append("**Five largest state cadres** (by officer headcount in `ias-profile.csv`), "
              "with their Collector-post roster size:\n")
for c in TOP5:
    lines.append(f"- {c}: {cadre_size[c]:,} officers, {int(roster_size_by_cadre[c])} districts on roster")
lines.append("")
lines.append(f"(2 officers' cadre values -- \"Chhasttisgarh\" (n=2), \"Maharastra\" (n=5), both "
              f"misspellings of an existing cadre in `ias-profile.csv` -- do not match any "
              f"crosswalk row and are therefore excluded from the panel entirely; "
              f"{7} officers total, negligible relative to N={prof['ID'].nunique():,}.)\n")

lines.append("## Definitions\n")
lines.append("- **(a) Vacant** -- cadre-month count of districts on that cadre's roster "
              "(distinct `pc11_district_id` in the crosswalk for that cadre) with no "
              "Collector-spell interval covering the month.\n"
              "- **(b) Available officers**, built from each officer's *entire* posting "
              "history (all designations), not just Collector spells:\n"
              "  - *def1 (any)*: no posting interval of any kind covers the month.\n"
              "  - *def3 (both-sided)*: as def1, and the specific gap covering the month "
              "has a recorded posting immediately before **and** after it (excludes gaps "
              "open at the start or end of the officer's known career).\n"
              "  - *def2 (both-sided, <24mo)*: as def3, and that gap is under 24 months long.\n"
              "  - By construction def2 &sube; def3 &sube; def1 in every cell.\n"
              "- **(c) New spells** -- Collector-spell count by start month.\n\n"
              "**Caveat on def1:** because it is built from the officer's full recorded "
              "history with no career-span restriction, def1 also counts officers who "
              "have not yet joined the service, have already retired, or otherwise have "
              "no record at all in a given month -- as \"available\" for every one of "
              "those months. It should be read as an upper bound / \"not on record as "
              "posted anywhere,\" not a genuine standby pool; def2 and def3 are the "
              "readings closer to actual administrative availability.\n")

lines.append("## Distribution across cadre-months\n")
lines.append("### Pooled (all cadres, all months)\n")
lines.append(pooled_stats.round(2).to_markdown(index=False))
lines.append("")
lines.append("### Five largest state cadres, separately\n")
lines.append(top5_stats.round(2).to_markdown(index=False))
lines.append("")

lines.append("## Correlation: vacancy count vs. available-officer count (cadre-month level)\n")
lines.append(corr_df.round(3).to_markdown(index=False))
lines.append("")

lines.append("## District succession gap (Collector spell ending -> next spell starting, same district)\n")
lines.append(f"- Succession pairs identified: {len(pairs):,} "
              f"(district-cadre keys with &ge;2 Collector spells)\n"
              f"- Overlapping/negative-gap pairs: {(pairs['gap_months'] < 0).sum():,} "
              f"({100 * (pairs['gap_months'] < 0).mean():.1f}%)\n"
              f"- **Mean gap, non-negative pairs only: {turnover_nonneg.mean():.2f} months** "
              f"(median {turnover_nonneg.median():.2f}, IQR "
              f"{turnover_nonneg.quantile(.75) - turnover_nonneg.quantile(.25):.2f})\n"
              f"- Mean gap, all pairs including overlaps as negative values: "
              f"{turnover_all.mean():.2f} months (reported for transparency only; "
              f"the non-negative figure above is the substantive one)\n")
lines.append("By state cadre (mean gap in months, all consecutive-spell pairs "
              "in that cadre's districts, non-negative only):\n")
for c in TOP5:
    v = pairs.loc[(pairs["cadre"] == c) & (pairs["gap_months"] >= 0), "gap_months"]
    lines.append(f"- {c}: {fmt(v.mean())} months (N pairs = {len(v):,})")
lines.append("")

with open(os.path.join(OUT_DIR, "summary.md"), "w") as f:
    f.write("\n".join(lines))
print(f"Saved {OUT_DIR}/summary.md")
