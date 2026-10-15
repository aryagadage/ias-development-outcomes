# Revision (Oct 2026): log re-estimation, state-level inference, recalibration

Produced by `code/10_log_and_inference.R`. Run it from the repo root with
`Rscript code/10_log_and_inference.R`; it takes about 5 seconds. No existing
script, table, figure or `.tex` file was modified.

**Conventions.**
- Controls everywhere are `allotment_year + tenure_months + opposition_turnover`,
  plus `Residual`.
- The stacked specs also include `Residual:infra_k`.
- 95% CIs use fixest's cluster t(G−1) critical values.
- "d" means clustered by district. "s" means clustered by state.
- G is the number of clusters, written as district / state.
- Bootstrap p-values are wild cluster restricted (WCR) by state: Webb
  weights, B = 9,999, null imposed, H0: coef = 0.
- Full records are in the CSVs listed at the end. Each row gives the coef, SE,
  p, CI, N, G, the FE and the cluster level.

---

## Exploration: what the paper's exhibits come from

| Paper exhibit | Source |
|---|---|
| Table 1 (`tab:r2a`, stacked sign contrast) | `code/run_full_analysis.R`, R2 "Version A" → `tables/R2A_sign_contrast.tex` |
| Table 2 (`tab:ideas_summary`): pooled signed OLS, junior/senior, IV, nightlights | `code/run_ideas.R` → `tables/ideas_summary.tex` |
| Table 4 (first stage, `R3_first_stage.tex`) | `code/run_full_analysis.R`, R3 |
| §6.1 "log ratio of standardised outcomes" (+0.063 to +0.086) | `code/run_full_analysis.R`, R6 |
| Figure `fig:coeffplot` | `code/coeff_plot_data.R` → `diagnostics/coeff_plot_spec3.csv` → `code/coeff_plot.py` |
| Appendix E worked example | **No code exists** in either repo. Re-implemented from the appendix text (see Task 3). |

| Concept | Variable |
|---|---|
| Roads | `roads_rate` = `roads_completed / road_length_km` (**not** km per 1,000 population; see Issues 1–2) |
| EC employment per capita | `emp_pc = ec_emp_all / tot_p` |
| Education | `Engineer`, `Residual` (social science is the omitted group) |
| Instrument | `QueueT_st`, from `data/analysis/QueueT_st.csv` |
| Controls | `allotment_year`, `tenure_months`, `opposition_turnover` |
| Identifiers | `district_id`, `state_id`, `year` / `year_fac`, `state_year` |

---

## Task 1. Sign contrast in logs

### 1a. Outcome diagnostics

| Item | Value |
|---|---|
| Roads estimation sample (yr ≥ 2001, non-missing) | 596 |
| Roads zeros / share of zeros | **0 / 0.0%** |
| `roads_rate` min / median / max | 0.0421 / 0.2872 / 2.000 |
| Mean of positive roads values | 0.35774 |
| c at 1% / 10% of that mean | 0.003577 / 0.035774 |
| District-years yr ≥ 2001 with roads missing | 634 |
| `emp_pc`, yr ≥ 2001: obs / missing / zeros / min | 1,230 / 1 / 0 / 6.76e-5 |
| `emp_pc`, full panel: missing / zeros | 25 / 0 |

Roads has no zeros: district-years with no completions are coded missing, not
zero. I ran the three requested transforms, and added a fourth, plain
`log(roads)`, which is feasible here.

### 1b. Stacked contrast (Table 1 spec, log outcomes)

- FE (1): `did_k + state_id + year_fac + infra_k`. N = 1,561; G = 361 / 27.
- FE (2): `did_k + state_year + infra_k`. N = 1,532; G = 352 / 21.
- The z-score rows reproduce Table 1 exactly.

**Engineer × infra_k (β^R − β^W, log points)**

| Roads version | FE | Coef | SE d | p d | 95% CI d | SE s | p s | 95% CI s |
|---|---|---|---|---|---|---|---|---|
| z-score (Table 1 replication) | (1) | 0.1412 | 0.1135 | 0.214 | [−0.082, 0.364] | 0.1206 | 0.252 | [−0.107, 0.389] |
| asinh | (1) | 0.0378 | 0.0334 | 0.259 | [−0.028, 0.104] | 0.0366 | 0.312 | [−0.038, 0.113] |
| log(+1%) | (1) | 0.0830 | 0.0680 | 0.223 | [−0.051, 0.217] | 0.0738 | 0.271 | [−0.069, 0.235] |
| log(+10%) | (1) | 0.0773 | 0.0617 | 0.211 | [−0.044, 0.199] | 0.0670 | 0.259 | [−0.060, 0.215] |
| log (no offset) | (1) | 0.0835 | 0.0688 | 0.226 | [−0.052, 0.219] | 0.0746 | 0.273 | [−0.070, 0.237] |
| z-score (Table 1 replication) | (2) | 0.1459 | 0.1075 | 0.176 | [−0.066, 0.357] | 0.0910 | 0.124 | [−0.044, 0.336] |
| asinh | (2) | 0.0426 | 0.0308 | 0.168 | [−0.018, 0.103] | 0.0265 | 0.124 | [−0.013, 0.098] |
| log(+1%) | (2) | 0.0948 | 0.0650 | 0.146 | [−0.033, 0.223] | 0.0562 | 0.107 | [−0.023, 0.212] |
| log(+10%) | (2) | 0.0876 | 0.0588 | 0.138 | [−0.028, 0.203] | 0.0509 | 0.101 | [−0.019, 0.194] |
| log (no offset) | (2) | 0.0956 | 0.0659 | 0.147 | [−0.034, 0.225] | 0.0569 | 0.108 | [−0.023, 0.214] |

**Engineer main effect (β^W, effect on log welfare)**

| Roads version | FE | Coef | SE d | p d | 95% CI d | SE s | p s | 95% CI s |
|---|---|---|---|---|---|---|---|---|
| z-score | (1) | −0.0252 | 0.0231 | 0.276 | [−0.071, 0.020] | 0.0225 | 0.272 | [−0.071, 0.021] |
| asinh | (1) | −0.0137 | 0.0158 | 0.388 | [−0.045, 0.018] | 0.0177 | 0.446 | [−0.050, 0.023] |
| log(+1%) | (1) | −0.0167 | 0.0164 | 0.309 | [−0.049, 0.016] | 0.0179 | 0.360 | [−0.054, 0.020] |
| log(+10%) | (1) | −0.0163 | 0.0163 | 0.317 | [−0.048, 0.016] | 0.0179 | 0.370 | [−0.053, 0.020] |
| log (no offset) | (1) | −0.0167 | 0.0164 | 0.308 | [−0.049, 0.016] | 0.0179 | 0.359 | [−0.054, 0.020] |
| z-score | (2) | −0.0317 | 0.0188 | 0.093 | [−0.069, 0.005] | 0.0122 | 0.017 | [−0.057, −0.006] |
| asinh | (2) | −0.0202 | 0.0109 | 0.065 | [−0.042, 0.001] | 0.0086 | 0.030 | [−0.038, −0.002] |
| log(+1%) | (2) | −0.0277 | 0.0137 | 0.043 | [−0.055, −0.001] | 0.0096 | 0.009 | [−0.048, −0.008] |
| log(+10%) | (2) | −0.0266 | 0.0130 | 0.042 | [−0.052, −0.001] | 0.0093 | 0.010 | [−0.046, −0.007] |
| log (no offset) | (2) | −0.0278 | 0.0138 | 0.044 | [−0.055, −0.001] | 0.0097 | 0.009 | [−0.048, −0.008] |

β^W moves with the roads transform because the controls are common across the
two classes.

### 1c. Direct log-ratio regression

`lr = roads_version − log(emp_pc)`, on district-years with both outcomes
observed. The wild bootstrap is clustered by state.

| Roads version | FE | N | G | Coef | SE d | p d | 95% CI d | SE s | p s | 95% CI s | Boot p | Boot 95% CI |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| asinh | district + state×year | 421 | 162 / 13 | 0.0356 | 0.0257 | 0.168 | [−0.015, 0.086] | 0.0245 | 0.172 | [−0.018, 0.089] | 0.184 | [−0.035, 0.101] |
| log(+1%) | district + state×year | 421 | 162 / 13 | 0.0781 | 0.0613 | 0.205 | [−0.043, 0.199] | 0.0667 | 0.265 | [−0.067, 0.224] | 0.333 | [−0.067, 0.279] |
| log(+10%) | district + state×year | 421 | 162 / 13 | 0.0702 | 0.0544 | 0.198 | [−0.037, 0.178] | 0.0593 | 0.259 | [−0.059, 0.199] | 0.325 | [−0.065, 0.246] |
| log (no offset) | district + state×year | 421 | 162 / 13 | 0.0791 | 0.0622 | 0.206 | [−0.044, 0.202] | 0.0677 | 0.266 | [−0.069, 0.227] | 0.332 | [−0.070, 0.281] |
| asinh | district + state + year | 453 | 174 / 17 | 0.0187 | 0.0280 | 0.506 | [−0.037, 0.074] | 0.0334 | 0.584 | [−0.052, 0.090] | 0.564 | [−0.054, 0.088] |
| log(+1%) | district + state + year | 453 | 174 / 17 | 0.0435 | 0.0648 | 0.503 | [−0.084, 0.171] | 0.0899 | 0.635 | [−0.147, 0.234] | 0.608 | [−0.098, 0.252] |
| log(+10%) | district + state + year | 453 | 174 / 17 | 0.0409 | 0.0579 | 0.481 | [−0.073, 0.155] | 0.0799 | 0.616 | [−0.128, 0.210] | 0.595 | [−0.090, 0.224] |
| log (no offset) | district + state + year | 453 | 174 / 17 | 0.0437 | 0.0657 | 0.507 | [−0.086, 0.173] | 0.0912 | 0.639 | [−0.150, 0.237] | 0.612 | [−0.097, 0.251] |

**1b vs 1c.**
- **State×year FE:** 1c is about 80% of 1b. For example, log(+1%) gives 0.078
  against 0.095, and asinh gives 0.036 against 0.043.
- **Additive FE:** 1c is about half of 1b. log(+1%) gives 0.043 against 0.083,
  and asinh gives 0.019 against 0.038. In relative terms this is a material
  difference, but it is well inside one SE.
- **Why they differ:**
  - The 1b welfare arm keeps all 1,108 welfare district-years, including ones
    with no roads observation.
  - In 1b the controls, and in col (1) the state and year FE, are common
    across classes, so they cancel out of the contrast. In 1c they act on the
    difference itself, which makes them effectively class-specific.
- The balanced stacked variant in 2b reproduces the 1c/2a structure exactly.

---

## Task 2. Instrumented contrast in logs; state-level inference

### 2a. IV on the log ratio

- FE: district + state + year (additive).
- N = 453; G = 174 / 17.
- The same first stage applies to every roads version.

| | Coef | SE d | p d | 95% CI d | KP-F d | SE s | p s | 95% CI s | KP-F s | Boot p (s) | Boot 95% CI |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **First stage** (Engineer on QueueT_st) | 0.3580 | 0.1994 | 0.074 | [−0.036, 0.752] | **3.22** | 0.1797 | 0.064 | [−0.023, 0.739] | **3.97** | 0.055 | [−0.009, 0.613] |
| 2SLS, asinh | 0.8889 | 0.6979 | 0.205 | [−0.489, 2.266] | | 0.5641 | 0.135 | [−0.307, 2.085] | | n/a | |
| 2SLS, log(+1%) | 1.2363 | 1.1313 | 0.276 | [−0.997, 3.469] | | 1.1365 | 0.293 | [−1.173, 3.646] | | n/a | |
| 2SLS, log(+10%) | 1.2153 | 1.0630 | 0.255 | [−0.883, 3.313] | | 1.0274 | 0.254 | [−0.963, 3.393] | | n/a | |
| 2SLS, log (no offset) | 1.2379 | 1.1404 | 0.279 | [−1.013, 3.489] | | 1.1516 | 0.298 | [−1.203, 3.679] | | n/a | |
| Reduced form, asinh | 0.3182 | 0.1708 | 0.064 | [−0.019, 0.655] | | 0.2426 | 0.208 | [−0.196, 0.833] | | 0.338 | [−0.357, 0.656] |
| Reduced form, log(+1%) | 0.4426 | 0.3235 | 0.173 | [−0.196, 1.081] | | 0.4862 | 0.376 | [−0.588, 1.473] | | 0.447 | [−0.891, 1.160] |
| Reduced form, log(+10%) | 0.4351 | 0.2943 | 0.141 | [−0.146, 1.016] | | 0.4421 | 0.340 | [−0.502, 1.372] | | 0.424 | [−0.779, 1.082] |
| Reduced form, log (no offset) | 0.4431 | 0.3275 | 0.178 | [−0.203, 1.090] | | 0.4922 | 0.381 | [−0.600, 1.487] | | 0.451 | [−0.870, 1.171] |

KP-F is fixest `ivwald1`: the first-stage Wald F computed with the stated
cluster vcov. For one endogenous regressor and one instrument, this is the
Kleibergen–Paap Wald F.

**The instrument is weak in this sample.** The first stage is 0.36 with a
KP-F of 3–4. It is not close to one. The 2SLS numbers should not be read as
point estimates. The weak-IV-robust test of β = 0 is the reduced-form
bootstrap, which gives p = 0.34 to 0.45.

### 2b. Stacked IV

The endogenous regressor is Engineer × infra_k and the instrument is
QueueT_st × infra_k. "As specified" means `did_k` plus common `state_year` FE.
In that spec, Engineer enters uninstrumented.

| Roads version | Spec | N | G | Coef | SE d | p d | 95% CI d | KP-F d | SE s | p s | 95% CI s | KP-F s |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| asinh | as specified | 1,532 | 352 / 21 | 0.8061 | 0.5000 | 0.108 | [−0.177, 1.790] | 7.86 | 0.4723 | 0.103 | [−0.179, 1.791] | 20.18 |
| log(+1%) | as specified | 1,532 | 352 / 21 | 1.0529 | 0.8702 | 0.227 | [−0.659, 2.764] | 7.86 | 0.8996 | 0.256 | [−0.824, 2.929] | 20.18 |
| log(+10%) | as specified | 1,532 | 352 / 21 | 1.0427 | 0.8053 | 0.196 | [−0.541, 2.627] | 7.86 | 0.8285 | 0.223 | [−0.686, 2.771] | 20.18 |
| log (no offset) | as specified | 1,532 | 352 / 21 | 1.0532 | 0.8791 | 0.232 | [−0.676, 2.782] | 7.86 | 0.9091 | 0.260 | [−0.843, 2.950] | 20.18 |
| asinh | variant† | 906 | 174 / 17 | 0.8889 | 0.7415 | 0.232 | [−0.575, 2.352] | 2.86 | 0.4394 | 0.060 | [−0.043, 1.820] | 6.54 |
| log(+1%) | variant† | 906 | 174 / 17 | 1.2363 | 1.2020 | 0.305 | [−1.136, 3.609] | 2.86 | 0.8853 | 0.182 | [−0.640, 3.113] | 6.54 |
| log(+10%) | variant† | 906 | 174 / 17 | 1.2153 | 1.1294 | 0.283 | [−1.014, 3.445] | 2.86 | 0.8004 | 0.148 | [−0.481, 2.912] | 6.54 |
| log (no offset) | variant† | 906 | 174 / 17 | 1.2379 | 1.2117 | 0.308 | [−1.154, 3.630] | 2.86 | 0.8971 | 0.187 | [−0.664, 3.140] | 6.54 |

† The variant uses the balanced stack (both outcomes observed), adds
state × k and year × k FE, and interacts the controls with k.

**Does it match 2a?**
- **As specified:** about 10–15% below 2a (0.81 against 0.89 for asinh; 1.05
  against 1.24 for the log versions). It is a different estimand: there are no
  class-specific state or year effects, the stack is unbalanced, and Engineer
  enters uninstrumented.
- **Variant:** reproduces the 2a point estimates exactly. Its SEs differ from
  2a's, and its state-clustered SE is smaller. I would not treat that as a
  gain in precision; 2a is the cleaner design.

### 2c. Existing Table 2, Panel B IV, re-clustered

- FE: `did_k + sid_k + yr_k`.
- N = 1,561; G = 361 / 27.

| | Coef | SE d | p d | 95% CI d | SE s | p s | 95% CI s | Boot p (s) | Boot 95% CI |
|---|---|---|---|---|---|---|---|---|---|
| 2SLS (original row 3) | 0.3365 | 0.2023 | **0.097** | [−0.061, 0.734] | 0.2692 | **0.223** | [−0.217, 0.890] | n/a | |
| KP-F | 34.54 (d) | | | | 58.15 (s) | | | | |
| First stage | 0.6860 | 0.1167 | <0.001 | [0.457, 0.916] | 0.0900 | <0.001 | [0.501, 0.871] | <0.0001 | [0.455, 0.898] |
| Reduced form | 0.2308 | 0.1285 | 0.073 | [−0.022, 0.484] | 0.1698 | 0.186 | [−0.118, 0.580] | **0.280** | [−0.183, 0.627] |

The district-clustered row reproduces the paper (0.337, SE 0.202, p = 0.097,
KP-F 34.5). Clustering by state, the IV is no longer significant at 10%. The
wild bootstrap of the reduced form gives p = 0.28.

### 2d. Few-cluster inference

The WCR results are in the 1c, 2a and 2c tables above.

**The 2SLS WRE bootstrap was not run.**
- `boottest()` does not accept fixest IV objects. The error was
  `invalid type (language) for variable 'lr_asinh ~ +1 | Engineer'`, and it
  occurs even after refitting with the FE as dummies.
- The route the package does support is an `ivreg` object. fwildclusterboot
  implements WRE only through Julia (WildBootTests.jl), and Julia is not
  installed, so that route failed with "Julia could not be found".
- I did not substitute another method.
- The reduced form is the fallback. With one instrument, the WCR test of the
  reduced-form coefficient is an Anderson–Rubin-type test of β = 0.
- The brief's reason for leaning on the reduced form ("the first stage is
  close to one") does not hold. The first stage is 0.36 in 2a and 0.69 in 2c.

---

## Task 3. Worked example recalibrated

The calculation is re-implemented from Appendix E.
- α = 1/2, so V = sqrt(S_j + D_j t_i).
- Five officers at m = 1; ω = 0.8 / 0.5 / 0.2.
- The queue is uniform over the 10 three-officer subsets and the 6 pairings.

**Reproduction checks: all pass.**
- β = 0.075 gives t_max = 0.03750, W(queue) = 2.3563, assortative +0.43%,
  full optimum +0.58% and placement share 75%.
- The illustrative case reproduces 2.3431 / 2.5597 / 2.6254, the one-draw
  2.4960 against 2.3520 (+6.1%), and the 77% placement share.

**Table columns.**
- "On education" means officers are sorted by education label (A = most
  technical goes to ω = 0.8). When β ≥ 0 this is the true assortative pairing.
- When β < 0 the label order is the reverse of the tilt order. These columns
  then show the result of sorting as if β were positive, which is a **loss**.
- "Full opt. on education" is the subset and pairing that would be optimal if
  label order were tilt order, evaluated at the true tilts.
- "True opt." is the actual optimum.

| β_comp source | β_comp | t_max | W(queue) | W(assort., on educ.) | % gain | W(full opt., on educ.) | % gain | % gain, true opt. | Placement share of loss |
|---|---|---|---|---|---|---|---|---|---|
| Paper, current | 0.0750 | 0.03750 | 2.35632 | 2.36654 | +0.434 | 2.36993 | +0.578 | +0.578 | 75.1% |
| 1c OLS, state×year, asinh: point | 0.0356 | 0.01782 | 2.35634 | 2.36120 | +0.206 | 2.36282 | +0.275 | +0.275 | 75.0% |
| … 95% CI low (state cl.) | −0.0178 | −0.00892 | 2.35635 | 2.35391 | **−0.103 (loss)** | 2.35310 | **−0.138 (loss)** | +0.138 | 75.0% |
| … 95% CI high (state cl.) | 0.0891 | 0.04456 | 2.35631 | 2.36845 | +0.515 | 2.37248 | +0.686 | +0.686 | 75.1% |
| … 95% CI low (district cl.) | −0.0151 | −0.00757 | 2.35635 | 2.35428 | **−0.088 (loss)** | 2.35359 | **−0.117 (loss)** | +0.117 | 75.0% |
| … 95% CI high (district cl.) | 0.0864 | 0.04321 | 2.35631 | 2.36809 | +0.500 | 2.37199 | +0.666 | +0.666 | 75.1% |
| 2a IV, asinh: point (weak IV) | 0.8889 | 0.43727 | 2.35247 | 2.47090 | +5.034 | 2.50842 | +6.629 | +6.629 | 75.9% |
| 2a IV, asinh: 95% CI high (state cl.) | 2.0846 | 0.95718 | 2.33701 | 2.59667 | +11.111 | 2.67399 | +14.419 | +14.419 | 77.1% |
| Zero | 0 | 0 | 2.35635 | 2.35635 | 0 | 2.35635 | 0 | 0 | n/a (0/0) |
| *Suppl.: 1c OLS, state×year, log(roads): point* | 0.0791 | 0.03955 | 2.35632 | 2.36710 | +0.457 | 2.37067 | +0.609 | +0.609 | 75.1% |
| *Suppl.: … 95% CI low (state cl.)* | −0.0685 | −0.03422 | 2.35633 | 2.34698 | **−0.397 (loss)** | 2.34385 | **−0.529 (loss)** | +0.527 | 75.1% |
| *Suppl.: … 95% CI high (state cl.)* | 0.2267 | 0.11321 | 2.35609 | 2.38690 | +1.308 | 2.39703 | +1.738 | +1.738 | 75.2% |
| *Suppl.: 2a IV, log(roads): point (weak IV)* | 1.2379 | 0.59992 | 2.34899 | 2.51134 | +6.912 | 2.56180 | +9.060 | +9.060 | 76.3% |
| *Suppl.: 2a IV, log(roads): 95% CI high (state cl.)* | 3.6792 | 1.45161 | 2.30817 | 2.70792 | +17.319 | 2.81944 | +22.150 | +22.150 | 78.2% |
| Illustrative tilts (0.8 … −0.8) | n/a | 0.8 | 2.34306 | 2.55969 | +9.2457 | 2.62544 | +12.052 | +12.052 | 76.7% |

**The 9.24% check.**
- The exact assortative gain is **9.2457%**.
- "9.24%" only comes out when you divide the rounded table entries
  (2.5597 / 2.3431). At one decimal place the exact figure is **9.2%**, so the
  paper's "9.3%" is wrong whichever way it is rounded.
- The same issue affects the full optimum. The exact gain is 12.052%, which
  rounds to 12.1%. The paper's "+12.0%" also comes from the rounded W's.

---

## Task 4. Sanity checks (report only)

**4.1 The Wald χ²(1) = 0.84.**
- **Source:** `run_full_analysis.R`, R2 "Version B", additive state + year spec.
- **What it tests:** whether the Engineer coefficient from a roads-only
  regression equals the Engineer coefficient from a separate welfare-only
  regression.
  - Roads: 0.0922 (SE 0.1169), N = 453.
  - Welfare: −0.0170 (SE 0.0231), N = 1,108.
- **How it differs from Table 1:**
  - Each regression has its own FE and control coefficients.
  - Each outcome is z-scored within its own arm.
  - χ² = (b1 − b2)² / (se1² + se2²), which sets the cross-equation covariance
    to zero.
  - Result: χ² = 0.839, p = 0.360.
- **Conclusion:** it is **not** a test of the Table 1 interaction. The paper
  prints it next to Table 1 anyway.
- **The state × year version** of the same Version B test gives
  χ² = 0.665 (p = 0.415).
- **The correct test of the Table 1 coefficient** (Wald on Engineer × infra_k,
  district-clustered):
  - Col (1): χ² = 1.549, p = 0.214.
  - Col (2): χ² = 1.843, p = 0.176.

**4.2 YOS and allotment year.**
- YOS = year − allotment_year exactly; the maximum deviation is 0.
- With year FE, or with any FE that absorbs year (state × year, year × k),
  YOS and allotment year are perfectly collinear.
- fixest drops YOS in Table 1 cols (1) and (2) and in 1c. It drops
  `allotment_year` in the Table 2 IV (`did_k + sid_k + yr_k`), because of
  formula order.
- **The YOS coefficient is not estimable** alongside allotment year in any of
  these specs.

**4.3 Opposition turnover.**
- `opposition_turnover` is constant within every state-year: 0 of 333
  state-years show any variation.
- It is **dropped as collinear** in every state × year spec: Table 1 col (2),
  1b col (2) and 1c with state × year FE.
- It is identified in the additive specs. In Table 1 col (1) the coefficient is
  −0.0055 (SE 0.0310).

**4.4 Figure 1 (`fig:coeffplot`).**
- `code/coeff_plot_data.R` uses:
  - FE: **district + additive state + year** (`district_id + state_id + year_fac`).
  - Controls: `Residual + allotment_year + tenure_months + opposition_turnover`.
  - District-clustered SEs and 90% CIs.
  - Outcomes standardised within each estimation sample: roads yr ≥ 2001
    (N = 453), lights (N = 2,339), `emp_pc` (N = 2,315).
- `code/coeff_plot.py` only plots the resulting CSV.
- The PDF in `../IAS-outcomes/figures/` is byte-identical to
  `figures/coeff_plot_presentation.pdf`.
- **The figure's subtitle is correct. The caption is wrong on two counts:** it
  says state-by-year FE, and it says "incumbency" where the control is
  opposition turnover.
- The roads point estimate is +0.0922 (SE 0.1169, p = 0.43). The appendix text
  says "roughly +0.07".
- `recon_memo.md` describes an older Python/PanelOLS version of this plot
  (state × year, `incumbent_won_bin`) that has since been replaced.

---

## Issues: failures, ambiguities, and decisions I made

1. **The roads variable differs from the brief.** `roads_rate` is roads
   completed per km completed, not km per 1,000 population. You chose to keep
   `roads_rate`, so it matches Table 1.
2. **No zeros in roads.** The zero-handling design (asinh, log + c) is
   therefore not needed. I added plain `log(roads)` as a fourth version.
3. **asinh is close to a level at this scale.** For x between 0.04 and 2,
   asinh(x) ≈ x, so the "preferred" asinh contrast (0.036) is roughly half the
   log-point contrast (0.078–0.079). Task 3 uses asinh as instructed. I added
   supplementary `log(roads)` rows, and I'd recommend calibrating from those.
4. **Few state clusters.** There are 13 (1c, state × year), 17 (1c additive and
   2a), 21 or 27 (stacked) and 27 (2c) state clusters, not about 31.
5. **The instrument is weak in the log-ratio sample.** The first stage is 0.358
   with KP-F 3.2 (d) / 4.0 (s). The 2a IV values in Task 3 rest on a weak
   instrument.
6. **WRE was not run** (see 2d): fixest IV is unsupported, and the ivreg route
   needs Julia. I did not install Julia.
7. **Bootstrap refits.** `boottest()` cannot parse fixest `|` FE formulas or
   fits with dropped singleton FE. Each bootstrapped model was refit with
   `factor()` dummies on the identical fixest sample, and the code checks that
   the coefficient matches to within 1e-8 before bootstrapping.
8. **Packages installed.** I installed `fwildclusterboot` 0.14.3 from
   r-universe, with dependencies `sitmo`, `collapse`, `dqrng`, `gtools`,
   `JuliaConnectoR` and `summclust`, as you approved.
9. **Script location.** The script is in `code/` rather than `scripts/`, to
   follow the repo's convention.
10. **Clustering for the Task 3 CI endpoints.** I used state clustering as
    primary and also show district clustering.
11. **2b.** The Engineer main effect enters uninstrumented, as the brief
    specifies. I added a balanced variant that reproduces 2a exactly.
12. **Negative β in Task 3.** These are handled as "sort on education labels"
    (a loss). The true optimum, which sorts the opposite way, is shown as well.
13. **Appendix E had no code.** I rebuilt it from the text and verified it
    against every published number before using it.
14. **File naming.** The Task 4 file uses `_log` only to satisfy the suffix
    rule; it contains neither log nor state-clustered estimates.

## New files

- `code/10_log_and_inference.R`
- `output/revision_oct2026/task1a_outcome_diagnostics_log.csv`
- `output/revision_oct2026/task1_sign_contrast_log.csv` (1b, 1c, both cluster levels)
- `output/revision_oct2026/task2ab_iv_log_stateclust.csv` (2a, 2b)
- `output/revision_oct2026/task2c_table2_iv_stateclust.csv`
- `output/revision_oct2026/task2d_wild_bootstrap_stateclust.csv`
- `output/revision_oct2026/task3_worked_example_recalibration_log.csv`
- `output/revision_oct2026/task4_sanity_checks_log.csv`
- `output/revision_oct2026/all_results_log_stateclust.rds` (all of the above in one R object)
- `output/revision_oct2026/SUMMARY.md`
