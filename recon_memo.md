# Sample Reconciliation Memo — Tables vs. Coefficient Plot

**Scope:** read-only audit. No `.R`/`.py`/`.tex`/table file was modified. No committed
specification was re-run in a way that changes any file on disk. Two exceptions, both
disclosed inline where they occur: (1) simple `pandas`/`dplyr` row-count and `dropna`
tabulations, which fit no model and write no file, were used to explain the sample-size
gaps in Q1–Q3; (2) for Q5, the plot's exact `run_spec3()` computation from
`code/coeff_plot.py` was executed in an ephemeral, in-memory Python session (no
`plt.savefig`, no file write) purely to extract the coefficient/SE/N figures the script
itself would otherwise only print to the console — this is the one place the memo reports
a number that required fitting a model rather than just counting rows. Everything else
below is read directly off script lines or committed `.tex` cells.

Prior belief stated in the request — "the tables are correct, the plot uses a
different, probably more-controlled sample" — is **half right**: the plot's sample is
different, but it is *less* controlled in one sense (a variable with real missingness,
`incumbent_won_bin`) and *differently* controlled in another (it swaps
`opposition_turnover` for `incumbent_won_bin`, which isn't even a like-for-like
substitute), and it uses a different fixed-effect structure and, for one outcome, a
different dependent variable entirely.

## Six sample definitions, side by side

| | **Roads — Tables** | **Roads — Plot** | **Welfare — Tables** | **Welfare — Plot** | **Nightlights — Tables** | **Nightlights — Plot** |
|---|---|---|---|---|---|---|
| Source data | `dc_analysis_v2.csv` (`build_iv_v2.py`) | `dc_analysis_balanced.csv` (`build_iv_dataset.py`) | `dc_analysis_v2.csv` | `dc_analysis_balanced.csv` | `dc_analysis_v2.csv` | `dc_analysis_balanced.csv` |
| Outcome var | `roads_rate` (identical formula in both builds) | `roads_rate` | `emp_pc = ec_emp_all/tot_p` (`run_full_analysis.R:28`) | **`ec_emp_all`, raw level** (`coeff_plot.py:69`) | `lights_rural` | `lights_rural` |
| Year window | `year >= 2001` (`run_full_analysis.R:38`) | `year >= 2001` (`coeff_plot.py:67,74`) | full panel, `year>=1994` implicit (no floor) | `year >= 1994` (`coeff_plot.py:68`) | full panel | `year >= 1994` (`coeff_plot.py:68`) |
| FE | district + state + year, additive (`run_full_analysis.R:134`, table's own "Spec 3") | district + state×year, interacted dummies (`coeff_plot.py:46-54`) — **structurally the tables' "Spec 4"**, mislabeled "Spec 3" in the plot's own docstring/comments (`coeff_plot.py:3,29,37`) | district + state + year, additive | district + state×year, interacted | district + state + year, additive | district + state×year, interacted |
| Controls | `allotment_year + tenure_months + opposition_turnover` (`run_full_analysis.R:43,138`) | `Residual, tenure_months, allotment_year, incumbent_won_bin` (`coeff_plot.py:33`) | same as roads | same as roads | same as roads | same as roads |
| Estimator / singleton handling | `fixest::feols`, auto-drops FE-singleton rows | `linearmodels.PanelOLS`, does **not** auto-drop singleton dummy cells | feols | PanelOLS | feols | PanelOLS |
| Cluster | district (`run_full_analysis.R:164`) | district (`cluster_entity=True`, `coeff_plot.py:56`) | district | district | district | district |
| Reported N | **453** (`R1_infra.tex`) | **586** | **2,315** (`R1_welfare.tex`) | **2,252** | **2,339** (`R1_lights.tex`) | **2,274** |

---

## 1. Sample reconciliation

**Root cause, all three outcomes:** the plot's control set requires `incumbent_won_bin`
(`coeff_plot.py:33,39`), which is missing for 116/2390 district-years overall (verified
by direct count on `dc_analysis_balanced.csv`). `opposition_turnover`, the table's
analogous control, is built with `fillna(0)` (`build_iv_v2.py:148,235`) and is **never
missing**, so it costs the tables zero rows. Confirmed by direct replication of the
pre-regression `dropna` step (pure pandas, no model fit): dropping
`[outcome] + Engineer + Residual + tenure_months + allotment_year + incumbent_won_bin`
on `dc_analysis_balanced.csv` yields **N=586 (roads, year≥2001), N=2,274 (lights,
year≥1994), N=2,252 (ec_emp_all, year≥1994)** — matching the plot's reported Ns
exactly, with no further reduction from the regression-fitting step itself. That means
the entire "tables vs. plot" N gap is explained at the `dropna` stage; the choice of
estimator (`feols` vs. `PanelOLS`) does not additionally move these particular numbers,
though it explains why the *tables'* own Spec-3-vs-Spec-4 Ns differ from each other
(feols auto-drops FE-singleton rows; PanelOLS's dummy-variable approach does not).

Differences, in full:

- **Control set**: confirmed — the plot's controls **do** include `incumbent_won_bin`
  (raw incumbent-won indicator) and `allotment_year`, but **not** `opposition_turnover`.
  This isn't a stricter version of the same control; `dc_analysis_balanced.csv` doesn't
  even contain an `opposition_turnover` column (`build_iv_dataset.py`'s `keep` list,
  L219-227, has no such variable — it has `CM_turnover` instead, a related but distinctly
  defined political-turnover flag: `incumbent_won_bin==0` only, vs. `opposition_turnover`'s
  stricter "winning party actually changed AND incumbent lost," `build_iv_v2.py:145-148`).
  `CM_turnover` isn't used as a control in the plot either — it's not in `CONTROLS`
  (`coeff_plot.py:33`).
- **Fixed effects**: tables' Spec 3 is *additive* district+state+year
  (`run_full_analysis.R:134`); the plot's FE is district + state×year *interacted*
  dummies (`coeff_plot.py:46-54`), which is what the tables themselves call Spec 4
  (`run_full_analysis.R:135`). The plot's own code comments call this "Spec 3" three
  times (`coeff_plot.py:3,29,37`) — that label doesn't match the paper's own taxonomy.
- **Year window**: identical for roads (`>=2001`) and identical for lights/EC-employment
  (`>=1994`, i.e., no floor) — not a source of the gap.
- **Dropped-observation rules**: tables rely on `fixest`'s automatic FE-singleton removal
  (e.g. 143 rows dropped for the roads Spec-3 regression, per `R1_infra.tex`'s N=453 vs.
  the 596 raw non-missing `roads_rate` observations); the plot relies only on `dropna`
  and whatever `PanelOLS(..., drop_absorbed=True)` removes at the *column* level, not
  the row level — it does not replicate `feols`'s row-level singleton logic.
- **Upstream data-construction filter**: none additional — both builds source the same
  `panel_full.csv` and the same DC-spell dedup logic, so pre-control outcome availability
  is identical between the two CSVs (verified: 596/2,365/2,390 non-missing
  `roads_rate`/`ec_emp_all`/`lights_rural` respectively, in *both* `dc_analysis_v2.csv`
  and `dc_analysis_balanced.csv`).
- **Welfare outcome, additionally**: the plot regresses **raw `ec_emp_all`** (total EC
  employment, a level that scales with district population), standardized to mean-0/SD-1
  in-sample (`coeff_plot.py:41-43`) — not `emp_pc = ec_emp_all/tot_p` (the tables'
  per-capita rate, `run_full_analysis.R:28`). These are different constructs, not just
  different samples of the same variable; a raw employment *level* is highly correlated
  with district population, which the per-capita version is specifically designed to net
  out. This alone would move both the point estimate and its interpretation even before
  any sample-size question.

## 2. Roads window

Every script — tables and plot alike — filters to `year >= 2001`:
`run_full_analysis.R:38`, `run_ideas.R:20-21`, `fs_checks.R:20-21,108`, and
`coeff_plot.py:67,74`. The "2001–2008" axis label matches this filter exactly, and
matches `data.tex`'s own stated restriction ("regressions using this outcome are
restricted to 2001–2008").

`data.tex`'s "six district-years nationally in 2000, thirty-six in 2001" is **not**
about the estimation sample — it's a claim about the *upstream, DC-unmatched* PMGSY
panel. Verified directly on `data/final/panel_full.csv` (all ~640 pc11 districts × all
years, before any officer/DC-spell match): non-null `roads_completed` counts are
**exactly 6 in 2000 and 36 in 2001**, an exact match to the prose. The *DC-matched
analytic samples* (`dc_analysis_v2.csv` / `dc_analysis_balanced.csv`) are much thinner
in these two years — only **2** non-missing `roads_rate` rows in 2000 and **7** in 2001
— because most district-years never get matched to a Collector spell. Both of these
year-2000/2001 pools are excluded by the universal `year>=2001` filter regardless, so
neither figure ever enters an estimation. District-year counts 2001–2008 in the matched
analytic sample (identical across both CSVs): 7, 58, 85, 104, 86, 88, 75, 93.

**Verdict: none of the three is wrong.** The label and the filter are both correct and
consistent with each other and with the prose's stated window. The prose's 6/36 figures
are correct for what they measure (raw PMGSY district coverage) but describe a
different, larger population than the 2/7 figures implicit in the estimation sample —
worth one clarifying clause so a reader doesn't expect N≈36 for 2001 in the regression
tables.

## 3. Stacked panel

One-sentence description: **the stacked sample is every 2001–2008 district-year with a
non-missing `roads_rate` (596 rows, 317 districts), row-stacked once as an "infra" (k=1)
observation, together with every 2001–2008 district-year with a non-missing `emp_pc`
(1,229 rows, 482 districts — the full 317 infra districts are a strict subset of these
482), row-stacked as a "welfare" (k=0) observation** — it is not two copies of any
single-outcome sample; the two arms differ in size and in which district-years qualify,
they only share the `year>=2001` floor and the underlying district-officer panel.

- Infra arm: `run_full_analysis.R:194-196` — `df_roads %>% filter(!is.na(roads_rate))`,
  where `df_roads` was already restricted to `year>=2001` at L38. N=596, 317 districts,
  years 2001–2008 (read-only count on `dc_analysis_v2.csv`).
- Welfare arm: `run_full_analysis.R:198-200` — `df %>% filter(!is.na(emp_pc), year>=2001)`.
  **This is a `year>=2001`-restricted subset of the welfare sample**, not the full-panel
  welfare sample used elsewhere (`R1_welfare.tex` uses the full 1994–2008 window,
  N=2,315). N=1,229, 482 districts, years 2001–2008.
- Combined raw: 596+1,229 = **1,825** (`run_full_analysis.R`'s own printed
  "Combined: 1825 obs," consistent with the arithmetic).
- `did_k` = district×k (`run_full_analysis.R:209`); the two FE variants used downstream:
  - `did_k + state_id + year_fac + infra_k` (`run_full_analysis.R:226`, the paper's
    "add-state" spec) → post-singleton **N=1,561**, matching `R2A_sign_contrast.tex`
    column (1) exactly.
  - `did_k + state_year + infra_k` (`run_full_analysis.R:228`, "state×yr") →
    post-singleton **N=1,532**, matching `R2A_sign_contrast.tex` column (2) exactly.
- Clusters: district (both specs). The committed table does not print the number of
  *identifying* districts (those with within-Engineer variation) for the post-singleton
  N=1,561/1,532 samples, and producing that number precisely requires replicating
  `fixest`'s singleton-elimination algorithm on the FE set — which is model-fitting, so
  it is intentionally **not** computed in this read-only pass. The raw pre-singleton
  district counts (317 infra / 482 welfare / 482 union) are reported above instead.

## 4. Table 5 (`R2A_sign_contrast.tex`) interpretation

**Confirmed, omitted class is welfare.** `infra_k` is 1 only for the infra arm
(`run_full_analysis.R:196`) and 0 for the welfare arm (`run_full_analysis.R:200`); the
regression formula (`run_full_analysis.R:232-233`) is
`y_std ~ Engineer + Engineer:infra_k + Residual + Residual:infra_k + controls | did_k + ... + infra_k`
— `infra_k` appears only inside the fixed-effects block, never as a standalone
regressor, so the model is a standard interaction: the bare **`Engineer` coefficient is
the welfare-arm (infra_k=0) effect**, and **`Engineer` + `Engineer:infra_k` is the
infra-arm (infra_k=1) effect**.

`y_std` construction (`run_full_analysis.R:203-205`):
```r
std <- function(x) (x - mean(x, na.rm=TRUE)) / sd(x, na.rm=TRUE)
df_inf$y_std  <- std(df_inf$y_raw)
df_welf$y_std <- std(df_welf$y_raw)
```
Standardized **within programme class** (each arm uses its own arm's mean/SD; not
within class×year, not pooled across both arms together). **No sign flip** — `df_welf$y_std`
is `std(emp_pc)`, not `-std(emp_pc)`. (A different variable, `Y_signed`, used only in
`run_ideas.R`'s non-interacted pooled-OLS/2SLS rows — `run_ideas.R:23`,
`Y_signed=-z_emp` — *is* sign-flipped; do not conflate the two. `y_std` in
`run_full_analysis.R`'s R2A block and `y_z` in `run_ideas.R`'s Idea-2 interaction block
are both unflipped, consistently with each other.)

**Your reading is correct.** The −0.032 you're quoting is `R2A_sign_contrast.tex`
column (2), "Engineer $-0.0317^{*}$" — the welfare-arm, unflipped-standardized
coefficient. "Engineers deliver 0.032 SD less standardized welfare employment (relative
to Social Scientist DCs, year≥2001 stacked sample, state×year-FE spec)" is the correct
reading of that specific cell.

**Flag while you're in there:** this is the opposite sign from `R1_welfare.tex`'s own
standalone Engineer coefficient (+0.0007 to +0.0012, positive, full 1994–2008 panel, raw
`emp_pc` units, `R1_welfare.tex`). Both numbers are computed correctly for what they are
— they differ because of the year-window restriction (year≥2001 only vs. full panel)
and the standardized/interaction model form vs. raw levels — but if both get cited as
"the welfare effect" in the same section, a reader will see a sign contradiction that
needs one clarifying sentence. See also Q7.

## 5. Exact coefficient-plot numbers

Extracted by executing the plot's own unmodified `run_spec3()` (`coeff_plot.py:36-62`)
in memory; no file was written (the plotting/`savefig` code, `coeff_plot.py:84-157`, was
not run).

| Outcome | β | SE | p | N | 90% CI |
|---|---|---|---|---|---|
| Road completion rate | **0.0655** | 0.1009 | 0.5168 | 586 | [−0.1004, 0.2315] |
| Nightlights per capita | −0.0529 | 0.0434 | 0.2232 | 2,274 | [−0.1243, 0.0185] |
| EC employment (**total, raw level**, not per capita) | −0.0007 | 0.0039 | 0.8531 | 2,252 | [−0.0071, 0.0057] |

The roads point is **+0.0655**, not "+0.07" — close enough that misreading it off the
figure is understandable (the marker sits just past the 0.06 gridline), but the exact
value is meaningfully below +0.07 and its CI comfortably straddles zero either way.

## 6. IV sample

**Confirmed directly from the committed table**, no re-derivation needed:
`ideas_summary.tex` row 1 ("Pooled signed OLS," from `run_ideas.R:54-59`, fit on `stk`)
reports **N=1,561**; row 3 ("Pooled IV 2SLS [KP-F=34.54]," from `run_ideas.R:94-100`,
also fit on `stk` with no intervening `QueueT_st`-based filter) also reports **N=1,561**.
Same `stk` object (`run_ideas.R:24`) feeds both calls — same N is expected and confirmed.

## 7. Discrepancy list

- **Census round mislabeled in `table1_summary.tex`.** The footnote
  (`build_tables.py:270`, rendered into the table) reads *"district-level means from
  Census 2011"*. Traced the pipeline: `03_add_census.R` builds both `_01`- and
  `_11`-suffixed columns; `06_merge_all.R:51-55` assigns
  `if_else(year < 2011, ..._01, ..._11)` — since the estimation panel never reaches
  2011 (max year 2008), **every district-year in `panel_full.csv`'s `sc_share`,
  `st_share`, `lit_rate`, `tot_p` is actually the 2001 round**; `build_tables.py:117`
  reads that same merged file. `data.tex`'s own prose gets this right ("every
  district-year in the analysis sample in practice uses the 2001 Census baseline") —
  it's `table1_summary.tex`'s footnote that's wrong. **A 2001 version does exist in the
  code and is in fact what's silently being used; only the printed label says 2011.**
- **`table3_infrastructure.tex` / `table4_welfare.tex` are a third, separate pipeline**
  (built by `build_tables.py`, not `run_full_analysis.R`), using the same
  `incumbent_won`-based control convention as the coefficient plot rather than
  `opposition_turnover` (`build_tables.py:287`: `CTRL = BASE + ["tenure_months",
  "allotment_year","incumbent_won"]`) — so their Engineer coefficients for roads
  (0.0284/0.0233/0.0158) are not directly comparable to `R1_infra.tex`'s
  (0.0338/0.0223/0.0223/0.0175), for the same structural reason worked out in Q1.
- **`table4_welfare.tex` uses a 2006–2008-only sample** (`build_tables.py:432`,
  `start_year>=2006`, "post-NREGA launch Feb. 2006" per `build_tables.py:480`), N≈433–438
  — a different, narrower research question than `R1_welfare.tex`'s full 1994–2008
  window (N=2,315). Its Engineer coefficients (+0.100\*\*\*, −0.000, −0.000\*\*) look
  nothing like `R1_welfare.tex`'s (+0.0007 to +0.0012) because they're not the same
  estimand — worth a clear caption distinction if both are ever shown together.
- **Sign disagreement, `R1_welfare.tex` vs. `R2A_sign_contrast.tex`** — see Q4 above.
- **FE-spec mislabeling in the coefficient plot** — see Q1 above (plot calls its FE
  "Spec 3"; it structurally matches the tables' own "Spec 4").

No other numeric disagreement was found between committed `tables/*.tex` files and the
figure-generating scripts beyond what's listed above and in Q1–Q4.

## What to change in the paper

Prose/label edits only — nothing here implies a code or table-number change:

1. In the coefficient-plot caption/footnote (wherever `figures/coeff_plot_presentation.pdf`
   is discussed in the text), replace "Spec 3" with a description matching what the FE
   structure actually is (district + state×year), or relabel it "Spec 4" to match the
   tables' own taxonomy — as written it implies the wrong FE spec.
2. Same caption: note that the welfare point uses **raw EC employment**, not employment
   per capita, and that all three points use `incumbent_won_bin`/no `opposition_turnover`
   as controls, rather than letting readers assume the plot is "Table 3/4's Spec 3 shown
   graphically."
3. In `data.tex`'s infrastructure paragraph (the "six district-years in 2000, thirty-six
   in 2001" sentence), add one clause noting this describes the raw PMGSY district panel
   before DC-spell matching, not the ~2-and-7-row figures implicit in the estimation
   sample — otherwise a careful reader doing exactly this kind of reconciliation will
   flag it as a phantom discrepancy.
4. Fix `table1_summary.tex`'s footnote from "Census 2011" to "Census 2001" — the
   underlying numbers are already correct; only the printed round is wrong.
5. Wherever `R2A_sign_contrast.tex`'s welfare-arm Engineer coefficient and
   `R1_welfare.tex`'s standalone Engineer coefficient might be read side by side, add a
   sentence noting they differ in sign because one is a year≥2001-only, standardized
   interaction estimate and the other is a full-panel, raw-units estimate — not a
   contradiction, but will read as one without a note.
6. If `table3_infrastructure.tex`/`table4_welfare.tex` remain in the paper alongside
   `R1_infra.tex`/`R1_welfare.tex`, add a caption note that they come from a separate
   control/sample convention (incumbent-based controls; table4 additionally restricted
   to 2006–2008) so the two families of numbers aren't read as replications of each
   other.
