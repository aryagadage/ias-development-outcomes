"""
Tables 1, 3, 4, 6  —  IAS DC education analysis
Baseline: SocialScientist; drop NA_Unclassified officers.

Table 3 Panel A — nightlights: full sample 1994-2008
Table 3 Panel B — roads:       restricted to start_year >= 2001
Table 4          — employment:  restricted to start_year >= 2006
"""
import os, warnings
warnings.filterwarnings("ignore")

import duckdb
import numpy as np
import pandas as pd
from scipy import stats
from linearmodels.panel import PanelOLS

os.makedirs("tables", exist_ok=True)
con = duckdb.connect()

# ══════════════════════════════════════════════════════════════════════════
# 1.  LOAD RAW DATA
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

# Log outcomes (kept for reference)
spells["log_dmsp"]  = np.log1p(spells["dmsp"])
spells["log_roads"] = np.log1p(spells["roads_completed"])
spells["log_emp"]   = np.log1p(spells["ec_emp_all"])

# Alternative ratio outcomes
spells["lights_rural"] = spells["dmsp"] / spells["tot_p"]          # nightlights per capita
spells["roads_rate"]   = np.where(                                  # completion rate
    spells["road_length_km"] > 0,
    spells["roads_completed"] / spells["road_length_km"],
    np.nan)
spells["nrega_rate"]   = spells["ec_emp_all"] / spells["tot_p"]    # employment per capita

# Drop NA_Unclassified; dedup to first spell per district-year
df = (spells[spells["bg_class"] != "NA_Unclassified"]
      .sort_values("start_dt")
      .drop_duplicates(subset=["district_id","start_year"], keep="first")
      .copy())

df["engineer"] = (df["bg_class"] == "Engineer").astype(float)
df["residual"] = (df["bg_class"] == "Residual").astype(float)

print(f"Full regression dataset: {len(df):,} obs | "
      f"{df['district_id'].nunique()} districts | "
      f"{df['start_year'].nunique()} years  "
      f"({df.start_year.min()}-{df.start_year.max()})")
print(df["bg_class"].value_counts().to_string())
print(f"\nroads non-null: {df['roads_completed'].notna().sum()} "
      f"(start_year>=2001: {df[df.start_year>=2001]['roads_completed'].notna().sum()})")
print(f"incumbent_won non-null: {df['incumbent_won'].notna().sum()}")

print("\n=== ALTERNATIVE OUTCOME SUMMARY STATS ===")
for var, lbl in [("lights_rural","lights_rural (DMSP/pop)"),
                 ("roads_rate",  "roads_rate (completed/km)"),
                 ("nrega_rate",  "nrega_rate (emp/pop)")]:
    s = df[var].dropna()
    sr = df[df.start_year>=2001][var].dropna() if var=="roads_rate" else s
    ref = sr if var=="roads_rate" else s
    print(f"  {lbl}: N={len(ref):,}  mean={ref.mean():.4f}  "
          f"sd={ref.std():.4f}  p25={ref.quantile(0.25):.4f}  "
          f"p75={ref.quantile(0.75):.4f}")

# ══════════════════════════════════════════════════════════════════════════
# 3.  TABLE 1  — Summary statistics
# ══════════════════════════════════════════════════════════════════════════

def panel_a_stats(df):
    rows = []
    for grp in ["Engineer","SocialScientist","Residual"]:
        g = df[df["bg_class"] == grp]
        rows.append({
            "Group":          grp,
            "N_spells":       len(g),
            "Tenure_mo":      g["tenure_months"].mean(),
            "Allot_yr":       g["allotment_year"].mean(),
            "Pct_female":     100 * g["is_female"].mean(),
        })
    return pd.DataFrame(rows)

def panel_b_stats(df):
    # sc_share, st_share, lit_rate, tot_p are time-invariant Census values
    chars = ["sc_share","st_share","lit_rate","tot_p"]
    eng = df[df["bg_class"]=="Engineer"]
    soc = df[df["bg_class"]=="SocialScientist"]
    rows = []
    for c in chars:
        ev = eng[c].dropna(); sv = soc[c].dropna()
        diff = ev.mean() - sv.mean()
        t, p = stats.ttest_ind(ev, sv) if (len(ev)>1 and len(sv)>1) else (np.nan, np.nan)
        rows.append({"var":c, "eng":ev.mean(), "soc":sv.mean(),
                     "difference":diff, "pval":p})
    pb = pd.DataFrame(rows)
    # Joint F-test
    tmp = df[df["bg_class"].isin(["Engineer","SocialScientist"])].copy()
    tmp["_eng"] = (tmp["bg_class"]=="Engineer").astype(float)
    tmp_c = tmp.dropna(subset=chars+["_eng"])
    from statsmodels.formula.api import ols as smf_ols
    if len(tmp_c) > len(chars)+2:
        fres = smf_ols("_eng ~ sc_share+st_share+lit_rate+np.log1p(tot_p)",
                       data=tmp_c).fit()
        fstat, fp = fres.fvalue, fres.f_pvalue
    else:
        fstat, fp = np.nan, np.nan
    return pb, fstat, fp

pa = panel_a_stats(df)
pb, fstat, fp = panel_b_stats(df)

print("\n=== TABLE 1: PANEL A ===")
print(pa.to_string(index=False))
print("\n=== TABLE 1: PANEL B ===")
print(pb.to_string(index=False))
print(f"Joint F={fstat:.3f}  p={fp:.3f}")

def pstar(p):
    return "***" if p<0.01 else "**" if p<0.05 else "*" if p<0.10 else ""

def write_table1(pa, pb, fstat, fp):
    path = "tables/table1_summary.tex"
    lbl = {"Engineer":"Engineer","SocialScientist":"Social Scientist","Residual":"Residual"}
    vlbl = {"sc_share":"SC pop. share","st_share":"ST pop. share",
            "lit_rate":"Literacy rate","tot_p":"Population (000s)"}
    L = [r"\begin{table}[htbp]", r"\centering",
         r"\caption{Summary Statistics}", r"\label{tab:summary}",
         r"\textbf{Panel A: Officer characteristics}\\[4pt]",
         r"\begin{tabular}{lrrrr}", r"\toprule",
         r"Group & $N$ spells & Tenure (mo.) & Allot.\ year & \% Female \\",
         r"\midrule"]
    for _, r in pa.iterrows():
        L.append(f"{lbl[r.Group]} & {int(r.N_spells):,} & "
                 f"{r.Tenure_mo:.1f} & {r.Allot_yr:.1f} & "
                 f"{r.Pct_female:.1f} \\\\")
    L += [r"\bottomrule", r"\end{tabular}", r"\\[10pt]",
          r"\textbf{Panel B: District characteristics (pre-treatment Census values)}\\[4pt]",
          r"\begin{tabular}{lcccc}", r"\toprule",
          r"Characteristic & Engineer & Soc.\ Sci. & Difference & $p$-value \\",
          r"\midrule"]
    for _, r in pb.iterrows():
        s = pstar(r.pval)
        v = vlbl.get(r.var, r.var)
        L.append(f"{v} & {r.eng:.4f} & {r.soc:.4f} & "
                 f"{r['difference']:.4f}{s} & {r.pval:.3f} \\\\")
    L += [r"\midrule",
          f"Joint $F$-test & & & {fstat:.2f} & {fp:.3f} \\\\",
          r"\bottomrule", r"\end{tabular}",
          r"\begin{tablenotes}\footnotesize",
          r"\item Panel A: spell-year means. Panel B: district-level means"
          r" from Census 2001 (time-invariant in panel).",
          r"\item Difference = Engineer $-$ Social Scientist. "
          r"Joint $F$: OLS of Engineer dummy on all characteristics.",
          r"\item $^{*}p<0.10$, $^{**}p<0.05$, $^{***}p<0.01$.",
          r"\end{tablenotes}", r"\end{table}"]
    with open(path,"w") as f: f.write("\n".join(L))
    print(f"Saved {path}")

write_table1(pa, pb, fstat, fp)

# ══════════════════════════════════════════════════════════════════════════
# 4.  REGRESSION HELPER
# ══════════════════════════════════════════════════════════════════════════

# sc_share/st_share/lit_rate are time-invariant → absorbed by district FE.
# We include only time-varying officer controls.
BASE = ["engineer","residual"]
CTRL = BASE + ["tenure_months","allotment_year","incumbent_won"]

SPECS = [
    ("(1)", BASE, False),
    ("(2)", CTRL, False),
    ("(3)", CTRL, True),
]

def run_spec(data, outcome, regressors, state_year_fe=False,
             cluster_at="district"):
    d = data.dropna(subset=[outcome]+regressors).copy()
    if len(d) < 50:
        return None, d

    if state_year_fe:
        d["_sy"] = d["pc11_state_id"] + "_" + d["start_year"].astype(str)
        sy_dum   = pd.get_dummies(d["_sy"], prefix="sy", drop_first=True)
        Xcols    = regressors + list(sy_dum.columns)
        d = pd.concat([d.reset_index(drop=True),
                       sy_dum.reset_index(drop=True)], axis=1)
        t_eff    = False
    else:
        Xcols = regressors
        t_eff = True

    d2 = d.set_index(["district_id","start_year"])
    y  = d2[outcome]
    X  = d2[Xcols].astype(float)

    model = PanelOLS(y, X, entity_effects=True, time_effects=t_eff,
                     drop_absorbed=True, check_rank=False)

    if cluster_at == "district":
        res = model.fit(cov_type="clustered", cluster_entity=True)
    else:
        state_s = d.set_index(["district_id","start_year"])["pc11_state_id"]
        res = model.fit(cov_type="clustered", clusters=state_s)

    return res, d

def get_coef(res, var):
    if res is None or var not in res.params.index:
        return np.nan, np.nan, np.nan
    return res.params[var], res.std_errors[var], res.pvalues[var]

def ctrl_mean(data, outcome, grp="SocialScientist"):
    return data[data["bg_class"]==grp][outcome].mean()

# ══════════════════════════════════════════════════════════════════════════
# 5.  TABLE 3  — Infrastructure (two panels with different samples)
# ══════════════════════════════════════════════════════════════════════════

df_lights = df.copy()                            # full 1994-2008
df_roads  = df[df["start_year"] >= 2001].copy()  # roads data starts 2001

print(f"\nTable 3 samples:")
print(f"  Panel A (lights): {len(df_lights):,} obs")
print(f"  Panel B (roads):  {len(df_roads):,} obs (start_year>=2001)")

res_lights = {}
res_roads  = {}

print("\n=== TABLE 3 COEFFICIENTS ===")
for spec_lbl, regs, sy_fe in SPECS:
    r, _ = run_spec(df_lights, "lights_rural", regs, sy_fe)
    res_lights[spec_lbl] = r
    ec,ese,ep = get_coef(r,"engineer"); rc,rse,rp = get_coef(r,"residual")
    print(f"  lights_rural {spec_lbl}: Eng={ec:.4f}({ese:.4f}) p={ep:.3f} | "
          f"Res={rc:.4f}({rse:.4f}) p={rp:.3f} | N={int(r.nobs) if r else '—'}")

for spec_lbl, regs, sy_fe in SPECS:
    r, _ = run_spec(df_roads, "roads_rate", regs, sy_fe)
    res_roads[spec_lbl] = r
    ec,ese,ep = get_coef(r,"engineer"); rc,rse,rp = get_coef(r,"residual")
    n = int(r.nobs) if r else "—"
    print(f"  roads_rate  {spec_lbl}: Eng={ec:.4f}({ese:.4f}) p={ep:.3f} | "
          f"Res={rc:.4f}({rse:.4f}) p={rp:.3f} | N={n}")

def write_table3(res_a, res_b, df_a, df_b):
    path = "tables/table3_infrastructure.tex"
    def fmt(c,s,p):
        if np.isnan(c): return "---","---"
        return f"{c:.4f}{pstar(p)}", f"({s:.4f})"
    def tick(x): return r"\checkmark" if x else ""

    subcols = "(1) & (2) & (3) & (4) & (5) & (6)"
    L = [r"\begin{table}[htbp]", r"\centering",
         r"\caption{Effect of DC Education on Infrastructure Outcomes}",
         r"\label{tab:infrastructure}",
         r"\begin{tabular}{lcccccc}", r"\toprule",
         r" & \multicolumn{3}{c}{Panel A: Nightlights per capita, 1994--2008}"
         r" & \multicolumn{3}{c}{Panel B: Road completion rate, 2001--2008} \\",
         r"\cmidrule(lr){2-4}\cmidrule(lr){5-7}",
         f" & {subcols} \\\\", r"\midrule"]

    for var, lbl in [("engineer","Engineer"),("residual","Residual")]:
        ca = [fmt(*get_coef(res_a[s], var)) for s,_,_ in SPECS]
        cb = [fmt(*get_coef(res_b[s], var)) for s,_,_ in SPECS]
        all_c = ca + cb
        L.append(lbl + " & " + " & ".join(c for c,_ in all_c) + " \\\\")
        L.append("       & " + " & ".join(s for _,s in all_c) + " \\\\")
        L.append(r"\addlinespace")

    L.append(r"\midrule")
    fe_ticks  = [r"\checkmark"] * 6
    yr_ticks  = [tick(not sy) for _,_,sy in SPECS] * 2
    sy_ticks  = [tick(sy)     for _,_,sy in SPECS] * 2
    ctl_ticks = [tick(len(r)>2) for _,r,_ in SPECS] * 2
    L.append("District FE          & " + " & ".join(fe_ticks)  + " \\\\")
    L.append("Year FE              & " + " & ".join(yr_ticks)  + " \\\\")
    L.append(r"State$\times$Year FE & " + " & ".join(sy_ticks) + " \\\\")
    L.append("Controls             & " + " & ".join(ctl_ticks) + " \\\\")
    L.append(r"\midrule")
    ns_a = [int(res_a[s].nobs) if res_a[s] else 0 for s,_,_ in SPECS]
    ns_b = [int(res_b[s].nobs) if res_b[s] else 0 for s,_,_ in SPECS]
    r2_a = [res_a[s].rsquared if res_a[s] else np.nan for s,_,_ in SPECS]
    r2_b = [res_b[s].rsquared if res_b[s] else np.nan for s,_,_ in SPECS]
    cm_a = [ctrl_mean(df_a,"lights_rural")]*3
    cm_b = [ctrl_mean(df_b,"roads_rate")]*3
    ns_row = [f"{n:,}" for n in ns_a+ns_b]
    r2_row = [f"{r:.3f}" for r in r2_a+r2_b]
    cm_row = [f"{m:.3f}" for m in cm_a+cm_b]
    L.append("$N$           & " + " & ".join(ns_row) + " \\\\")
    L.append("$R^2$         & " + " & ".join(r2_row) + " \\\\")
    L.append("Control mean  & " + " & ".join(cm_row) + " \\\\")
    L += [r"\bottomrule", r"\end{tabular}",
          r"\begin{tablenotes}\footnotesize",
          r"\item Baseline: Social Scientist DCs.",
          r"\item Panel A: nightlights per capita = DMSP total calibrated light / population.",
          r"\item Panel B: road completion rate = roads completed (km) / total road length (km); "
          r"restricted to 2001--2008 (PMGSY data availability).",
          r"\item Controls: tenure (months), allotment year, incumbent win dummy.",
          r"\item SC/ST shares and literacy rate controlled via district FE.",
          r"\item SE clustered at district. "
          r"$^{*}p<0.10$, $^{**}p<0.05$, $^{***}p<0.01$.",
          r"\end{tablenotes}", r"\end{table}"]
    with open(path,"w") as f: f.write("\n".join(L))
    print(f"Saved {path}")

write_table3(res_lights, res_roads, df_lights, df_roads)

# ══════════════════════════════════════════════════════════════════════════
# 6.  TABLE 4  — Welfare (ec_emp_all, start_year >= 2006)
# ══════════════════════════════════════════════════════════════════════════

df_emp = df[df["start_year"] >= 2006].copy()
print(f"\nTable 4 sample: {len(df_emp):,} obs (start_year>=2006)")

res_emp = {}
print("\n=== TABLE 4 COEFFICIENTS ===")
for spec_lbl, regs, sy_fe in SPECS:
    r, _ = run_spec(df_emp, "nrega_rate", regs, sy_fe)
    res_emp[spec_lbl] = r
    ec,ese,ep = get_coef(r,"engineer"); rc,rse,rp = get_coef(r,"residual")
    n = int(r.nobs) if r else "—"
    print(f"  nrega_rate {spec_lbl}: Eng={ec:.4f}({ese:.4f}) p={ep:.3f} | "
          f"Res={rc:.4f}({rse:.4f}) p={rp:.3f} | N={n}")

def write_table4(res, df_sub):
    path = "tables/table4_welfare.tex"
    def fmt(c,s,p):
        if np.isnan(c): return "---","---"
        return f"{c:.3f}{pstar(p)}", f"({s:.3f})"
    def tick(x): return r"\checkmark" if x else ""
    subcols = " & ".join(f"({i+1})" for i in range(3))
    L = [r"\begin{table}[htbp]", r"\centering",
         r"\caption{Effect of DC Education on Employment Outcomes (2006--2008)}",
         r"\label{tab:welfare}",
         r"\begin{tabular}{lccc}", r"\toprule",
         r" & \multicolumn{3}{c}{Employment per capita (ec\_emp\_all / tot\_p)} \\",
         r"\cmidrule(lr){2-4}",
         f" & {subcols} \\\\", r"\midrule"]
    for var, lbl in [("engineer","Engineer"),("residual","Residual")]:
        cs = [fmt(*get_coef(res[s],var)) for s,_,_ in SPECS]
        L.append(lbl + " & " + " & ".join(c for c,_ in cs) + " \\\\")
        L.append("       & " + " & ".join(s for _,s in cs) + " \\\\")
        L.append(r"\addlinespace")
    L.append(r"\midrule")
    L.append("District FE    & " + r"\checkmark & \checkmark & \checkmark \\")
    L.append("Year FE        & " + " & ".join(tick(not sy) for _,_,sy in SPECS) + " \\\\")
    L.append(r"State$\times$Year FE & " +
             " & ".join(tick(sy) for _,_,sy in SPECS) + " \\\\")
    L.append("Controls       & " +
             " & ".join(tick(len(r)>2) for _,r,_ in SPECS) + " \\\\")
    L.append(r"\midrule")
    ns  = [int(res[s].nobs) if res[s] else 0 for s,_,_ in SPECS]
    r2s = [res[s].rsquared if res[s] else np.nan for s,_,_ in SPECS]
    cm  = ctrl_mean(df_sub,"nrega_rate")
    L.append("$N$          & " + " & ".join(f"{n:,}" for n in ns) + " \\\\")
    L.append("$R^2$        & " + " & ".join(f"{r:.3f}" for r in r2s) + " \\\\")
    L.append(f"Control mean & {cm:.3f} & {cm:.3f} & {cm:.3f} \\\\")
    L += [r"\bottomrule", r"\end{tabular}",
          r"\begin{tablenotes}\footnotesize",
          r"\item Sample: DC spell-years 2006--2008 (post-NREGA launch, Feb.\ 2006).",
          r"\item Baseline: Social Scientist DCs.",
          r"\item Controls: tenure (months), allotment year, incumbent win dummy.",
          r"\item SE clustered at district. "
          r"$^{*}p<0.10$, $^{**}p<0.05$, $^{***}p<0.01$.",
          r"\end{tablenotes}", r"\end{table}"]
    with open(path,"w") as f: f.write("\n".join(L))
    print(f"Saved {path}")

write_table4(res_emp, df_emp)

# ══════════════════════════════════════════════════════════════════════════
# 7.  TABLE 6  — Robustness (Spec 2 baseline)
# ══════════════════════════════════════════════════════════════════════════

type_counts = df.groupby("district_id")["bg_class"].nunique()
df_r4 = df[df["district_id"].isin(type_counts[type_counts>1].index)].copy()
print(f"\nR4 (pure-ID) sample: {len(df_r4):,} obs | "
      f"{df_r4['district_id'].nunique()} districts")

CHECKS = [
    ("R1: tenure $\\geq 6$ mo.",  dict(data=df,    yr=None,        cl="district", min_ten=6)),
    ("R2: 1994--2004",             dict(data=df,    yr=(1994,2004), cl="district", min_ten=None)),
    ("R3: state cluster",          dict(data=df,    yr=None,        cl="state",    min_ten=None)),
    ("R4: pure-ID districts",      dict(data=df_r4, yr=None,        cl="district", min_ten=None)),
]

def run_robustness(kw, outcome, regs):
    d = kw["data"].copy()
    if kw["min_ten"]:
        d = d[d["tenure_months"] >= kw["min_ten"]]
    if kw["yr"]:
        d = d[(d["start_year"]>=kw["yr"][0]) & (d["start_year"]<=kw["yr"][1])]
    return run_spec(d, outcome, regs, state_year_fe=False, cluster_at=kw["cl"])

res_t6 = {}
print("\n=== TABLE 6 COEFFICIENTS ===")
for out_col, out_lbl in [("lights_rural","lights_rural"),("roads_rate","roads_rate")]:
    base_d = df if out_col=="lights_rural" else df[df["start_year"]>=2001]
    r4_d   = df_r4 if out_col=="lights_rural" else df_r4[df_r4["start_year"]>=2001]
    checks_out = [
        ("R1: tenure $\\geq 6$ mo.",  dict(data=base_d,    yr=None,        cl="district", min_ten=6)),
        ("R2: 1994--2004",             dict(data=base_d,    yr=(1994,2004), cl="district", min_ten=None)),
        ("R3: state cluster",          dict(data=base_d,    yr=None,        cl="state",    min_ten=None)),
        ("R4: pure-ID districts",      dict(data=r4_d,      yr=None,        cl="district", min_ten=None)),
    ]
    for r_lbl, kw in checks_out:
        r, _ = run_robustness(kw, out_col, CTRL)
        res_t6[(out_col, r_lbl)] = r
        ec,ese,ep = get_coef(r,"engineer")
        n = int(r.nobs) if r else "—"
        print(f"  {out_lbl} {r_lbl}: Eng={ec:.4f}({ese:.4f}) p={ep:.3f} N={n}")

def write_table6(res, checks_labels):
    path = "tables/table6_robustness.tex"
    def fmt(c,s,p):
        if np.isnan(c): return "---","---"
        return f"{c:.3f}{pstar(p)}", f"({s:.3f})"
    nc = len(checks_labels)
    cols = " & ".join(f"({i+1})" for i in range(nc))
    heads = " & ".join(r"\shortstack{"+l.replace("$\\geq","$\\geq\\\\")+"}" for l in checks_labels)
    L = [r"\begin{table}[htbp]", r"\centering",
         r"\caption{Robustness Checks — Engineer Coefficient (Spec 2 baseline)}",
         r"\label{tab:robustness}",
         r"\begin{tabular}{l"+"c"*nc+"}", r"\toprule",
         f" & {heads} \\\\",
         f" & {cols} \\\\", r"\midrule"]
    outcomes = [("lights_rural","Panel A: Nightlights per capita"),
                ("roads_rate",  "Panel B: Road completion rate")]
    for out_col, out_lbl in outcomes:
        L.append(f"\\multicolumn{{{nc+1}}}{{l}}{{\\textit{{{out_lbl}}}}} \\\\")
        coefs = [fmt(*get_coef(res[(out_col,rl)],"engineer")) for rl in checks_labels]
        L.append("Engineer & " + " & ".join(c for c,_ in coefs) + " \\\\")
        L.append("         & " + " & ".join(s for _,s in coefs) + " \\\\")
        ns = [int(res[(out_col,rl)].nobs) if res[(out_col,rl)] else 0
              for rl in checks_labels]
        L.append("$N$ & " + " & ".join(f"{n:,}" for n in ns) + " \\\\")
        L.append(r"\addlinespace")
    L += [r"\bottomrule", r"\end{tabular}",
          r"\begin{tablenotes}\footnotesize",
          r"\item All specs: district FE + year FE + controls (tenure, allotment year, incumbent win).",
          r"\item Baseline: Social Scientist DCs. Panel B (road completion rate) uses 2001--2008 sample.",
          r"\item Panel A outcome: DMSP total light / population. "
          r"Panel B outcome: roads completed (km) / total road length (km).",
          r"\item R1: drop spells $<6$ months. R2: 1994--2004 only.",
          r"\item R3: SE clustered at state instead of district.",
          r"\item R4: drop districts with only one observed education type.",
          r"\item $^{*}p<0.10$, $^{**}p<0.05$, $^{***}p<0.01$.",
          r"\end{tablenotes}", r"\end{table}"]
    with open(path,"w") as f: f.write("\n".join(L))
    print(f"Saved {path}")

checks_labels = [rl for rl,_ in CHECKS]
write_table6(res_t6, checks_labels)

print("\nDone. All four tables written to tables/")
