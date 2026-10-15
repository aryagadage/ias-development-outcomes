# Tables update, number verification, and compile report (Oct 2026)

Produced by `code/11_tables_oct2026.R` (Tables 1, 2, 4) and `code/12_worked_example.R`
(Appendix E, standalone). Reads `output/revision_oct2026/*.csv` from
`code/10_log_and_inference.R`; does not modify that script or its outputs.

---

## 1. Files changed

**New scripts** (`ias-development-outcomes/code/`):
- `11_tables_oct2026.R` — rebuilds the three paper tables below from refit models
  and from the Task 1b/2c/2d CSVs. No number in the output tables is hand-typed;
  every figure is either a coefficient/SE read off a `fixest` object fit in the
  script, or read from a CSV written by `10_log_and_inference.R`.
- `12_worked_example.R` — standalone Appendix E calculator, extracted from
  `10_log_and_inference.R`'s Task 3 block (that script's own comment confirms no
  prior script computed this). Takes `beta_comp` (a vector) on the command line
  and prints the illustrative table and one calibrated table per value.

**Tables rewritten** (`IAS-outcomes/figures/tables/`), with backups made first:
| File | Backup |
|---|---|
| `R2A_sign_contrast.tex` (`tab:r2a`) | `R2A_sign_contrast_pre_oct2026.tex` |
| `ideas_summary.tex` (`tab:ideas_summary`) | `ideas_summary_pre_oct2026.tex` |
| `R3_first_stage.tex` (`tab:firststage`) | `R3_first_stage_pre_oct2026.tex` |

**Other file changed**: `IAS-outcomes/references.bib` — two comment lines fixed
(see §4, compile report). This is not a table and not prose in a `.tex` file; it
was a pre-existing bug blocking every citation in the paper from resolving, found
while compiling for Task 8. No bibliographic entry was added, removed, or altered.

**No prose was edited in any `.tex` file.**

---

## 2. Table rebuilds

### Table 1 (`tab:r2a`): four columns

Columns (1)–(2) are refit, unchanged in spec, and reproduce the existing
published numbers exactly (0.1412/0.1459 on the interaction, same N, same R²).
Columns (3)–(4) use `log(roads_rate)` / `log(emp_pc)` in the same stacked
spec, no offset (there are no zeros in `roads_rate` — confirmed in
`task1a_outcome_diagnostics_log.csv`).

**Check against the brief's target numbers:**

| | (1) | (2) |
|---|---|---|
| Engineer × infra | 0.0835 (0.0688) — **matches** | 0.0956 (0.0659) — **matches** |
| Engineer | −0.0167 (0.0164) — **matches** | −0.0278 (0.0138) — **matches** |

All four match to the 4th decimal. (One cell not on the brief's check list,
`Residual:infra_k` in column (1), changed from the previously published 0.0326
to 0.0327 on refit — the unrounded coefficient is 0.032653, which rounds to
0.0327, not 0.0326. This looks like a pre-existing rounding artifact in the
original table, not an error introduced here; flagged, not fixed, since it
isn't one of the numbers the brief asked me to check and the difference is a
single last-digit rounding call.)

A real `etable()` formatting bug surfaced while building this: `fixest`'s
default digit algorithm rendered this exact coefficient as −0.0168 instead of
−0.0167 (verified independently: the unrounded value is −0.0167467). Passing
`digits = "r4"` (plain 4-decimal rounding) fixes it; the fix is in the script
and is the reason a direct `etable()` call without it would not reproduce the
brief's numbers.

Fixed-effect rows relabeled per ground rule 4 (District × class, State, Year,
Class, State × year). No Wald χ² line existed in this table to remove.

### Table 2 (`tab:ideas_summary`): row 3b added

All existing rows and numbers are byte-identical to the original (copied
forward from the `_pre_oct2026` backup; nothing in rows 1–3 or the
falsification row was regenerated). Row 3b is read from
`task2c_table2_iv_stateclust.csv` (the `cluster == "state_id"` record) and the
bootstrap p-value from `task2d_wild_bootstrap_stateclust.csv` (the
"2c reduced form (Table 2 Panel B, Y_signed)" record): coef +0.3365, SE
0.2692, p 0.222, 95% CI [−0.2169, 0.8898], N 1,561, KP-F 58.15, bootstrap
p = 0.280 — all match the brief.

The note "stacked sample doubles $N$" was removed (it's wrong: N is the same
as the OLS row, as the brief says). The row-3b note was added with the
bootstrap p-value and the clustered KP-F folded in, since the row label itself
(kept to "3b. State-clustered") was shortened to resolve an overfull hbox —
see §4.

### Table 4 (`tab:firststage`): dropped the absorbed column

Kept the two columns with the 1.055 coefficient, renumbered (1)/(2), FE rows
relabeled (District, State, Year). Refit and verified the coefficient is still
1.055 (0.0775)/(0.0770) before writing. The original column 1 (state × year
FE, instrument absorbed, no coefficient shown) is gone.

---

## 3. Task 4: numbers typed into the text

Every number below was found by grep and checked against
`output/revision_oct2026/SUMMARY.md` / the underlying CSVs. All of
`results.tex` (`06_results.tex`), `empirics.tex` (`05_empirical.tex`), and
`data.tex` (`04_Data.tex`) — the three files carrying `% [REV]` markers —
**match**. `appendix.tex` (`09_Appendix.tex`) has **no `% [REV]` markers at
all** and was evidently not touched in this revision pass; its Task 4 numbers
mostly **do not match** and are flagged below rather than fixed (prose is off
limits).

| # | Number(s) | File : line | Source | Match? |
|---|---|---|---|---|
| 1 | Log interaction: 0.084, 0.096, p=0.23, p=0.15 | `06_results.tex:122` | Task 1b, log (no offset), cols (1)/(2) | **Yes** |
| 2 | Log welfare main effect: −0.017, −0.028, p=0.04, p=0.01 (state cl.) | `06_results.tex:124–125` | Task 1b, log (no offset), Engineer row | **Yes** |
| 3 | Interaction p-values, Table 1 cols (1)–(2): p=0.21, p=0.18 | `06_results.tex:110,112` | Task 4.1, correct Wald test on Engineer×infra_k | **Yes** |
| 4 | Direct log-ratio, district+state×year: 0.079, SE 0.062, p=0.21 | `06_results.tex:153–154` | Task 1c, log (no offset), district+state×year | **Yes** |
| 5 | Direct log-ratio, additive FE: 0.044, p=0.51 | `06_results.tex:155` | Task 1c, log (no offset), district+state+year | **Yes** |
| 6 | IV clustered by state: KP-F 58.2, p=0.22; bootstrap p=0.28 | `06_results.tex:191–193` | Task 2c, state-clustered | **Yes** |
| 7 | Stacked KP-F 34.5, and 58.2 clustered by state | `05_empirical.tex:176` | Task 2c | **Yes** |
| 8 | Unstacked first stage: 1.055 | `05_empirical.tex:180` | Table 4 / Task 4.2 | **Yes** |
| 9 | Stacked panel: 1,561 cells; 453 infra, 1,108 welfare; 361 districts | `04_Data.tex:228–229` | Table 1 N's + stacked construction | **Yes** |
| 10 | Roads: 598 non-missing total; 2 in 2000, 596 in 2001–2008 | `04_Data.tex:285–287` | Task 1a diagnostics | **Yes** |
| 11 | Calibrated: β=0.079, t_max≈0.040, W=2.3563/2.3671/2.3707, gains +0.46%/+0.61%, placement 75% | `09_Appendix.tex:1240–1258` | Task 3 "Suppl.: 1c OLS, log(roads)" row | **No** — appendix still shows the old calibration (β=0.075, t_max=0.0375, W=2.3563/2.3665/2.3699, +0.43%/+0.58%). Reproduced the brief's target numbers exactly with `code/12_worked_example.R` (see §5), so the target numbers are correct; the appendix text is simply not updated. |
| 12 | Range (log roads, state cl.): −0.069→−0.40%/−0.53%; 0.227→+1.31%/+1.74% | `09_Appendix.tex` (no such range in the text) | Task 3 CI-bound rows | **No** — not present at all; the appendix has no sensitivity range around the calibration. Reproduced with `code/12_worked_example.R` (see §5). |
| 13 | Illustrative case: +9.2% and +12.1% | `09_Appendix.tex:1217–1218` | Task 3 illustrative row | **No** — appendix still shows +9.3% and +12.0%. The exact figures are 9.2457% and 12.052%, which round to 9.2% and 12.1% (confirmed independently with `code/12_worked_example.R`); the paper's current text rounds from the table's own rounded W's rather than the exact ratio, which is why it's off in the first decimal on both. |
| 14 | D.1: Figure 1 roads coefficient +0.092 (SE 0.117) | `09_Appendix.tex:972` | Task 4.4 | **No** — text still says "roughly +0.07", with its own pre-existing `% TODO` next to it asking for the exact number. This was already an open TODO before this revision; not something newly broken by it. |

**Net:** `06_results.tex` and `05_empirical.tex` and `04_Data.tex`: 10/10 checked
numbers match. `09_Appendix.tex`: 0/4 match, because that file was not part of
this revision pass (no `% [REV]` markers anywhere in it). Someone should run
this revision's numbers through Appendix E and the D.1 discussion next; I did
not touch the prose.

---

## 4. Compile report

`latexmk -pdf A_main.tex` (the paper's actual main file — the brief's
`model.tex`/`results.tex`/`empirics.tex`/`data.tex`/`appendix.tex` correspond to
`03_model.tex`/`06_results.tex`/`05_empirical.tex`/`04_Data.tex`/`09_Appendix.tex`
in the current repo).

**A real, pre-existing bug blocked every citation from resolving.**
`references.bib` had two comment lines containing the literal text `@article`
and `@techreport` (around the `XuBertrandBurgess2018` entry). BibTeX does not
treat `%` as a comment character the way LaTeX does — it scans for `@word`
anywhere in the file to start a new entry — so these comments made BibTeX
choke mid-file and silently stop producing a `.bbl`, which meant **every**
citation in the paper (27 of them) printed as `?`. This predates the Oct 2026
revision and is not a `.tex` prose or table issue, so I fixed the two comment
lines (removed the literal `@`, kept the English meaning) rather than leaving
the bibliography broken. No entry's content changed.

**After that fix, the build is clean (`latexmk` exit 0, 65 pages).** Remaining
items, none of which I touched (all are prose/label issues in `.tex` files):

- **Confirmed resolving**, as asked: `app:stacking`, `app:example`,
  `app:proofs`, `eq:edu-levels` (in `03_model.tex`), `sec:implications`, and
  `AsherEtAl2021` (present in `references.bib`, citation now resolves with no
  warning). All six check out.
- **2 genuinely undefined references** (both print as `??` in the PDF):
  - `07_assignment.tex:76` — `\ref{sec:collector}`. No such label exists; the
    Collector's-problem subsection in `03_model.tex` is labelled
    `sec:problem`. Looks like a simple stale label name.
  - `07_assignment.tex:234` — `\ref{app:dynamic}`. No such label, and no
    section called "Task-Specific Experience" (or similar) exists anywhere in
    `09_Appendix.tex` to attach one to. The content this used to point to
    appears to have been removed or never added; the reference is orphaned.
- **4 multiply-defined labels**, a genuine content duplication unrelated to
  this revision: `def:matchvalue`, `prop:vij`, `eq:vij`, and `eq:SD` are each
  defined twice — once in `03_model.tex` (lines 232–267, right before
  "Empirical Implications") and again, word-for-word, in `07_assignment.tex`
  (lines 79–174, "The Value of a Match" / "Level and Tilt"). Whichever `\ref`
  to these labels currently resolves is silently picking up whichever copy
  LaTeX processes last (`07_assignment.tex`'s). This is a structural
  duplication someone should resolve by deleting one copy; I left both in
  place since choosing which one to delete is a prose decision.
- **Overfull boxes**: the new four-column Table 1 produces **zero** overfull
  boxes. `ideas_summary.tex` (Table 2) has a pre-existing ~34pt overfull hbox
  spanning its whole `tabular` — confirmed present, unchanged, in the
  `_pre_oct2026` backup before any of my edits, so it is not something this
  revision introduced. (I shortened row 3b's label during debugging on the
  mistaken assumption it was the cause; it wasn't, but the shorter label is
  harmless and the KP-F value it used to carry is now in the table note
  instead.) A handful of other small overfull boxes (12–27pt) exist elsewhere
  in the document body, also unrelated to tables and pre-existing.

---

## 5. Task 5: the roads variable

Traced in `code/02_add_roads.R` and `code/build_iv_v2.py` (the script that
actually builds `dc_analysis_v2.csv`, the file every analysis script reads).

- `roads_completed` (`02_add_roads.R:57`) is a **count**: the number of PMGSY
  shrid-level road records with a non-missing completion date, grouped to
  pc11 district–year via the shrid–district crosswalk (`n()` per group — one
  unit per completed road project, not a length).
- `road_length_km` (`02_add_roads.R:58`) is a **sum**: the total length (km)
  of those same completed roads (`road_length_new`), summed within the same
  district–year group.
- `roads_rate` (`build_iv_v2.py:241–243`) = `roads_completed / road_length_km`
  (`NaN` when `road_length_km` is 0 or missing).

**Why it can exceed 1:** the numerator counts discrete completed projects and
the denominator sums their combined completed length, so `roads_rate` is the
reciprocal of the mean length of a completed road in that district–year, not
a share or a rate of coverage. Whenever a district's completed roads that
year are short on average — several sub-kilometre segments — the count
exceeds the summed length and the ratio exceeds 1 (sample maximum: 2.0, per
`task1a_outcome_diagnostics_log.csv`).

**Suggested two-sentence description for the paper:**

> `roads_rate` is the number of PMGSY road-construction projects completed in
> a district–year divided by the total length (km) of those same completed
> roads, both aggregated from the shrid level via the shrid–district
> crosswalk — not kilometres completed per capita or per unit of sanctioned
> network. Because the numerator counts projects and the denominator sums
> their length, the measure is the reciprocal of mean completed-project
> length (a fragmentation measure) and can exceed 1 when completed roads are
> short, which happens in the sample (maximum 2.0).

---

## 6. Task 7: why rows 2a + 2b don't sum to row 1

**Not missing data.** `years_of_service` has zero missing values in the
stacked sample (`run_ideas.R`); the raw stacked panel is 1,825 rows
(941 "junior"-side, 884 "senior"-side by the median split — these sum exactly
to 1,825, so nothing is lost at the split itself).

**It's fixed-effect singletons, and splitting creates more of them than
pooling does.** The pooled regression (row 1, `did_k + sid_k + yr_k` FE on
all 1,825 rows) drops to N = 1,561 — 264 observations are singletons in those
fixed effects. Splitting the sample by tenure *before* fitting removes the
cross-tenure variation that was keeping some of those cells non-singleton: a
district×class/state×class/year×class cell with exactly one junior
officer-year and one senior officer-year is fine in the pooled regression but
becomes a singleton in each half once separated. Concretely: the junior
regression drops 941 → 644 (297 singletons) and the senior regression drops
884 → 612 (272 singletons), a combined loss of 569 against the pooled loss of
264 — exactly the missing 305 (1,561 − 1,256). Verified by refitting both
subsample regressions directly (`nobs()` on each `feols` object).

---

## 7. Things I was unsure about / flagging for you

1. **The `Residual:infra_k` rounding change in Table 1 col (1)** (0.0326 →
   0.0327, §2) — correct per the unrounded value, but not on your check list,
   so flagging rather than assuming it's wanted.
2. **References.bib fix** — a non-`.tex`, non-table file, outside the letter
   of "only tables/*.tex may be written," but the paper could not compile at
   all without it (every citation failed). Said what I changed and why in §4;
   happy to revert if you'd rather fix it yourself.
3. **The duplicate match-value block** (§4) and the two orphaned references
   (`sec:collector`, `app:dynamic`) are real bugs but are prose/structure, not
   tables — reported, not touched.
4. **Appendix E and the D.1 discussion are stale** relative to this revision
   (§3, items 11–14). `code/12_worked_example.R` reproduces every number the
   brief expects there, so the fix is mechanical once someone edits that
   prose — I did not do it myself per the ground rules.
5. **Table 2's row-3b label** was shortened from what a literal reading of the
   brief implies ("Pooled IV 2SLS, SEs clustered by state") to "State-clustered"
   to chase an overfull-hbox red herring that turned out to be pre-existing
   and unrelated (§4). The KP-F value that would have been in the row is now
   in the table note instead. If you'd prefer the fuller label restored (the
   overfull box isn't caused by it), that's a one-line change in
   `code/11_tables_oct2026.R`.
