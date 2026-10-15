# Roads outcome rerun: roads_rate vs roads_km_pc vs roads_n_pc

Produced by `code/13_roads_km_rerun.R`. Run it from the repo root with
`Rscript code/13_roads_km_rerun.R`; it takes about 25 seconds.

Nothing outside `output/revision_oct2026/roads_km/` was written. No existing
table, output or `.tex` file was touched.

## Measures

| Measure | Definition | Role |
|---|---|---|
| `roads_rate` | roads_completed / road_length_km (existing) | old, for comparison |
| `roads_km_pc` | road_length_km / (tot_p / 1000) | new primary |
| `roads_n_pc` | roads_completed / (tot_p / 1000) | secondary check |

- `roads_completed` and `road_length_km` come from `data/final/panel_full.csv`.
- They are merged on the key `build_iv_v2.py` uses (state + district code, and
  year).
- The merge rebuilds `roads_rate` exactly: the missing pattern is identical,
  the maximum difference is 2e-16, and `tot_p` is identical.

## How the rerun keeps everything identical

**Script 10 is run unmodified.** `code/10_log_and_inference.R` is executed with
only two text substitutions: the input data frame and the output folder. The
`roads_rate` column is overwritten by each measure.

**Harness check.** The `roads_rate` pass reproduces all five existing CSVs in
`output/revision_oct2026/` with a maximum gap of **exactly 0**.

**Where each requested result comes from:**
- **Table 1, all four columns:** script 10's 1b section. Its z-score and
  `log (no offset)` rows are the same specifications as
  `code/11_tables_oct2026.R` cols (1)–(2) and (3)–(4).
- **Not run:** script 11 itself, because it writes into
  `../IAS-outcomes/figures/tables/`.
- **Table 2 row 1** (pooled signed OLS, from `run_ideas.R`) and the
  **Figure 1** roads coefficient (from `coeff_plot_data.R`) aren't in script
  10. They are refit with those scripts' exact specifications. Both reproduce
  their published values for `roads_rate`: 0.0373 and 0.0922.

**Sample (a decision I made).** The roads sample is held at the 596
district-years from 2001 on where `roads_rate` is observed, for all three
measures.
- 4 district-years have roads completed but 0 km of length.
- `roads_rate` already excludes them. Under `roads_km_pc` they would be zeros,
  which makes the unoffset log undefined.
- Holding the sample fixed means the comparison isolates the change of
  measure. A sensitivity check that adds the 4 rows back is at the end.

All p-values below are two-sided. d = clustered by district; s = clustered by
state; G = number of clusters.

---

## 1. Table 1, all four columns (district-clustered, as in the table)

- Cols (1)–(2) are standardised; cols (3)–(4) are logs (no offset).
- FE: (1)/(3) `did_k + state + year + k`, N = 1,561; (2)/(4)
  `did_k + state×year + k`, N = 1,532.

**Engineer × infra**

| Col | roads_rate | roads_km_pc | roads_n_pc |
|---|---|---|---|
| (1) std | 0.1412 (0.1135) p = 0.214 | −0.0109 (0.1343) p = 0.936 | 0.0383 (0.1520) p = 0.801 |
| (2) std | 0.1459 (0.1075) p = 0.176 | −0.0096 (0.1239) p = 0.938 | 0.0512 (0.1421) p = 0.719 |
| (3) log | 0.0835 (0.0688) p = 0.226 | −0.1425 (0.1950) p = 0.466 | −0.0709 (0.1789) p = 0.692 |
| (4) log | 0.0956 (0.0659) p = 0.147 | −0.1467 (0.1815) p = 0.419 | −0.0655 (0.1657) p = 0.693 |

**Engineer (welfare main effect)**

| Col | roads_rate | roads_km_pc | roads_n_pc |
|---|---|---|---|
| (1) std | −0.0252 (0.0231) p = 0.276 | −0.0169 (0.0237) p = 0.475 | −0.0188 (0.0245) p = 0.444 |
| (2) std | −0.0317 (0.0188) p = 0.093 | −0.0047 (0.0272) p = 0.864 | −0.0145 (0.0280) p = 0.605 |
| (3) log | −0.0167 (0.0164) p = 0.308 | −0.0078 (0.0206) p = 0.706 | −0.0123 (0.0194) p = 0.527 |
| (4) log | −0.0278 (0.0138) p = 0.044 | −0.0274 (0.0348) p = 0.432 | −0.0387 (0.0317) p = 0.224 |

The state-clustered versions of every cell are in
`<measure>/task1_sign_contrast_log.csv`.

## 2. Direct log-ratio regression (1c), log(roads) − log(emp_pc), no offset

- The bootstrap p-value is wild cluster restricted by state (Webb weights,
  9,999 replications).

| FE | Measure | Coef | SE d | p d | SE s | p s | 95% CI (s) | Boot p | N | G (d / s) |
|---|---|---|---|---|---|---|---|---|---|---|
| district + state×year | roads_rate | 0.0791 | 0.0622 | 0.206 | 0.0677 | 0.265 | [−0.069, 0.227] | 0.332 | 421 | 162 / 13 |
| | roads_km_pc | −0.1445 | 0.1642 | 0.380 | 0.1491 | 0.352 | [−0.469, 0.180] | 0.313 | 421 | 162 / 13 |
| | roads_n_pc | −0.0864 | 0.1493 | 0.564 | 0.1247 | 0.502 | [−0.358, 0.185] | 0.495 | 421 | 162 / 13 |
| district + state + year | roads_rate | 0.0437 | 0.0657 | 0.507 | 0.0912 | 0.639 | [−0.150, 0.237] | 0.612 | 453 | 174 / 17 |
| | roads_km_pc | −0.1340 | 0.1953 | 0.494 | 0.2171 | 0.546 | [−0.594, 0.326] | 0.433 | 453 | 174 / 17 |
| | roads_n_pc | −0.0914 | 0.1760 | 0.604 | 0.2065 | 0.664 | [−0.529, 0.346] | 0.606 | 453 | 174 / 17 |

## 3. Table 2

- Rows 3 and 3b use FE `did_k + sid_k + yr_k`; N = 1,561; G = 361 / 27.
- Row 1 also uses N = 1,561.

| | roads_rate | roads_km_pc | roads_n_pc |
|---|---|---|---|
| Row 1: pooled signed OLS (d) | 0.0373 (0.0333) p = 0.264 | 0.0074 (0.0389) p = 0.849 | 0.0158 (0.0423) p = 0.708 |
| Row 1, state-clustered (for reference) | (0.0312) p = 0.243 | (0.0290) p = 0.800 | (0.0327) p = 0.632 |
| Row 3: IV 2SLS (d) | 0.3365 (0.2023) p = 0.097 | 0.2673 (0.1544) p = 0.084 | 0.2976 (0.1842) p = 0.107 |
| Row 3b: IV 2SLS (s) | 0.3365 (0.2692) p = 0.222 | 0.2673 (0.2004) p = 0.194 | 0.2976 (0.2669) p = 0.275 |
| First-stage KP-F (d / s) | 34.54 / 58.15 | 34.54 / 58.15 | 34.54 / 58.15 |
| Reduced-form coef (s) | 0.2308 (0.1698) | 0.1834 (0.1252) | 0.2041 (0.1707) |
| Bootstrapped reduced-form p (WCR, state, Webb, 9,999) | 0.280 | 0.195 | 0.316 |

The first stage and KP-F are identical across measures. The instrument and the
held sample don't depend on the roads values; only the outcome changes.

## 4. Figure 1 roads coefficient

- Specification: standardised within the roads sample; district + additive
  state + year FE; controls; district-clustered; 90% CI. N = 453; G = 174.

| | roads_rate | roads_km_pc | roads_n_pc |
|---|---|---|---|
| Coef (SE) | 0.0922 (0.1169) | −0.0381 (0.1359) | −0.0025 (0.1509) |
| p | 0.431 | 0.780 | 0.987 |
| 90% CI | [−0.100, 0.284] | [−0.262, 0.186] | [−0.251, 0.246] |

## 5. Worked example (`code/12_worked_example.R`)

- Inputs: the 1c log estimate (district + state×year FE) and the endpoints of
  its state-clustered 95% CI.
- Full output is in `worked_example_<measure>_log.txt`.
- For β < 0, script 12 reports sorting on education as if β were positive,
  which is a **loss**.
- I added the "true optimum" column by running script 12 at |β|. Because ω is
  symmetric (0.8 ↔ 0.2), the queue and the true optimum are the same at −β
  and +β.

| Measure | β_comp | t_max | W(queue) | Assortative on education | Full optimum on education | True optimum gain | Placement share |
|---|---|---|---|---|---|---|---|
| roads_rate, point | 0.0791 | 0.0395 | 2.3563 | +0.46% | +0.61% | +0.61% | 75% |
| roads_rate, CI low | −0.0685 | −0.0342 | 2.3563 | −0.40% (loss) | −0.53% (loss) | +0.53% | 75% |
| roads_rate, CI high | 0.2267 | 0.1132 | 2.3561 | +1.31% | +1.74% | +1.74% | 75% |
| **roads_km_pc, point** | **−0.1445** | −0.0722 | 2.3562 | **−0.84% (loss)** | **−1.12% (loss)** | +1.11% | 75.2% |
| roads_km_pc, CI low | −0.4693 | −0.2336 | 2.3553 | −2.73% (loss) | −3.66% (loss) | +3.57% | 75.5% |
| roads_km_pc, CI high | 0.1803 | 0.0901 | 2.3562 | +1.04% | +1.38% | +1.38% | 75.2% |
| roads_n_pc, point | −0.0864 | −0.0432 | 2.3563 | −0.50% (loss) | −0.67% (loss) | +0.67% | 75.1% |
| roads_n_pc, CI low | −0.3582 | −0.1786 | 2.3557 | −2.08% (loss) | −2.79% (loss) | +2.73% | 75.4% |
| roads_n_pc, CI high | 0.1854 | 0.0926 | 2.3562 | +1.07% | +1.42% | +1.42% | 75.2% |

## 6. Zero and missing roads observations

| Window | Measure | N | Missing | Zero | Positive |
|---|---|---|---|---|---|
| All district-years, 1994–2008 | roads_rate | 2,390 | 1,792 | 0 | 598 |
| | roads_km_pc | 2,390 | 1,788 | **4** | 598 |
| | roads_n_pc | 2,390 | 1,788 | 0 | 602 |
| District-years, 2001–2008 | roads_rate | 1,230 | 634 | 0 | 596 |
| | roads_km_pc | 1,230 | 630 | **4** | 596 |
| | roads_n_pc | 1,230 | 630 | 0 | 600 |
| Held roads sample | all three | 596 | 0 | 0 | 596 |

- **Missing cases:** no PMGSY completion is recorded in that district-year.
  The panel records no completions as missing, not as zero.
- **The 4 extra cases** are district-years with roads_completed > 0 and
  road_length_km = 0. `roads_rate` is undefined there (divide by zero),
  `roads_km_pc` = 0, and `roads_n_pc` > 0.

---

## What to take from this

1. **The new measure is not a rescaling of the old one.** In the held sample,
   `roads_km_pc` correlates −0.35 with `roads_rate` in levels and −0.66 in
   logs. `roads_rate` is the reciprocal of mean completed-road length, so
   districts completing more km tend to have a *lower* `roads_rate`.
2. **The sign contrast does not survive the change of measure.** Under
   `roads_km_pc`, Engineer × infra is about 0 in the standardised columns
   (−0.011 and −0.010) and negative in logs (−0.14 to −0.15). The 1c log ratio
   is also negative: −0.14, state-clustered 95% CI [−0.47, 0.18].
   `roads_n_pc` is in between. Nothing is significant under any measure.
3. **Table 2's IV keeps its sign and size.** The estimates are 0.27 and 0.30
   against 0.34. With state clustering it is not significant (p = 0.19 to
   0.28; bootstrapped reduced form p = 0.20 to 0.32). Rows 1 and 3 are
   standardised, so this is a different specification from items 1–2. The IV
   and the log-contrast OLS point in opposite directions under the new
   measure.
4. **Calibration.** At the `roads_km_pc` point estimate, sorting on education
   would cost 0.84% of weighted output against the queue (1.12% for the
   education-based optimum). The CI spans −2.7% to +1.0% for assortative
   pairing. The placement share stays at about 75% throughout.

## Sensitivity: adding back the 4 zero-length district-years

Results are in `sensitivity_zero_length_rows/<measure>/`. This uses the same
script-10 harness; the roads sample is "measure non-missing", i.e. 600
district-years.
- **`roads_km_pc`:** the 4 rows are zeros.
  - The log (no offset) columns are unchanged, because fixest drops log(0)
    rows ("4 observations removed because of infinite values").
  - Table 1 z-score interaction: 0.0006 (col 1), −0.0010 (col 2).
  - 1c with log(+1% c): −0.079 under state×year FE, +0.017 under additive FE.
- **`roads_n_pc`:** the 4 rows have positive values.
  - Table 1 log interaction: 0.002 (col 3), 0.009 (col 4).
  - 1c log: −0.067 under state×year FE, 0.000 under additive FE (−0.091 with
    the held sample).
  - **These 4 rows move `roads_n_pc` estimates noticeably.** The roads arm
    sits on 421–453 district-years, so a handful of rows can shift a point
    estimate by about 0.1 log points. All p-values stay above 0.6.

## Decisions and caveats

1. **Sample held at the `roads_rate` sample** (596 district-years), as
   explained above. Sensitivity with the 4 rows is provided.
2. **Script 11 was not executed**, because it writes into the paper's tables
   folder. Its Table 1 specification is identical to script 10's 1b section,
   which was run. Its Table 2 rows 1 and 3 come from `run_ideas.R` and
   script 10's 2c section, both reproduced here.
3. **"Log version" means `log(roads)` with no offset.** That is what script 11
   uses for Table 1 cols (3)–(4) and what the current calibration uses. The
   asinh and log(+c) versions for each measure are in
   `<measure>/task1_sign_contrast_log.csv`.
4. **The 2SLS bootstrap (WRE) is still unavailable.** It needs Julia, which
   is not installed, so the same caveat as before applies.

## Files (all under `output/revision_oct2026/roads_km/`)

- `SUMMARY.md` (this file)
- `zero_missing_counts_log.csv`, `measure_descriptives_log.csv`
- `table2_row1_and_figure1_log.csv`
- `worked_example_inputs_log.csv`, `worked_example_roads_km_pc_log.txt`,
  `worked_example_roads_n_pc_log.txt`, `worked_example_roads_rate_log.txt`
- `roads_rate/`, `roads_km_pc/`, `roads_n_pc/`: each holds a full set of
  script-10 outputs (`task1_sign_contrast_log.csv`, `task1a_…`, `task2ab_…`,
  `task2c_…`, `task2d_…`, `task3_…`, `task4_…`, `all_results_log_stateclust.rds`)
- `sensitivity_zero_length_rows/roads_km_pc/`,
  `sensitivity_zero_length_rows/roads_n_pc/`: the same, on the 600-row sample
- New script: `code/13_roads_km_rerun.R`
