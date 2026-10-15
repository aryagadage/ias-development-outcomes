# Contrast figure, paper insert, and lab slides (Oct 2026)

Two things flagged before starting, resolved per your answers:
1. Part B's 4 new slides conflict with an earlier explicit instruction on this
   same deck ("keep to exactly 10 frames, no backup section") — **resolved:
   add them (14 frames total)**.
2. B2.4's bracketed bullet — **resolved: a 3-row table** comparing all three
   infrastructure measures on both estimates, sourced from the SUMMARY files
   (not the pasted check values).

**Task 0 was already done** — `output/revision_oct2026/roads_km/SUMMARY.md`
exists (from `code/13_roads_km_rerun.R`), so per the brief's own instruction
I skipped re-running it and used its numbers directly.

---

## Files created or changed

**New script**: `ias-development-outcomes/code/13_contrast_figure.R` — builds
the contrast figure from Table 1 columns (2)/(4) (refit, not read from a
cache), writes `output/revision_oct2026/contrast_figure_values.csv`.

**New figures** (`IAS-outcomes/figures/`), no backups needed (files didn't
exist before):
- `contrast_plot.pdf` (6.5in × 3in, for the paper)
- `contrast_plot_slides.png` (300dpi, 10in × 5.625in, for the slides)

**`IAS-outcomes/06_results.tex`**: inserted the exact figure block given in
A2, verbatim, after the paragraph beginning "Table~\ref{tab:r2a} gives the
two coefficients..."; inserted `(Figure~\ref{fig:contrast})` into the
"sign pattern of comparative advantage" sentence, exactly as specified.
**Nothing else in this file was touched.**

**`IAS-outcomes/09_Appendix.tex`**: **not touched.** A3 is conditional on a
`\paragraph{Quantity measures.}` paragraph with `[X]`/`[Y]`/`[ ]`
placeholders existing — it doesn't; there is no such paragraph anywhere in
the file. Skipping, as the task instructed.

**`IAS-outcomes/slides/model_talk.tex`**: backed up first to
`model_talk_pre_oct2026.tex`. Added `\usepackage{graphicx}` (not previously
loaded — the deck had used only TikZ until now). Updated the "Quantitative
value" slide's numbers (B1) and inserted 4 new slides before it (B2).
**Speaker notes were not updated** for the 4 new slides — `speaker_notes.md`
wasn't in scope for this task and I didn't touch it; flagging this as a gap
rather than assuming you want it filled.

---

## A1: contrast figure — plotted β^R values (new, not previously in the paper)

Refit directly (not read from a cache), on Table 1's exact column (2)/(4)
specification (`did_k + state_year + infra_k`, controls, district-clustered).
Contrast row reproduces the published 0.1459 / 0.0956 exactly (checked in the
script before writing any file).

| Panel | β^W (Welfare = Engineer) | β^R (Infrastructure = Engineer + Engineer:infra_k) | Contrast (Engineer:infra_k) |
|---|---|---|---|
| Standardised | −0.0317 (0.0188) | **0.1142 (0.1049)** | 0.1459 (0.1075) |
| Log | −0.0278 (0.0138) | **0.0678 (0.0647)** | 0.0956 (0.0659) |

β^R's SE is computed from the full vcov, including the Engineer /
Engineer:infra_k covariance term (not the naive sum of variances) — this
matters here since the two coefficients are negatively correlated enough
that ignoring the covariance would overstate β^R's SE by roughly 7–8%.

Full values (all three rows, both CIs) are in `contrast_figure_values.csv`.

---

## A4: compile report

`latexmk -pdf A_main.tex` — clean, exit 0.

- **No undefined references or citations**, including `fig:contrast` (checked
  explicitly — it resolves, page 26).
- **Figure vs. Table 1 placement**: the figure (page 26) lands on the page
  *before* Table 1 (page 27) — not "same" or "next," but adjacent and in a
  sensible reading order: the figure sits right where its paragraph puts it
  (same page as the discussion text that references it), while Table 1 (float
  input earlier in the source) migrates to the following page. Visually
  inspected both pages — nothing overlaps or looks out of order.
- **No new overfull boxes.** The same 6 pre-existing overfull hboxes from the
  table-revision task are still there, unchanged; none is on the new figure's
  page.

---

## Task 0 (already run) — roads outcome comparison

Pulled directly from `output/revision_oct2026/roads_km/SUMMARY.md`; not
recomputed. Full detail (zero/missing counts, Table 2, Figure 1, worked
example at every measure) is in that file. Headline comparison (Table 1 col
2 contrast, and the 1c log-ratio under district + state×year FE,
district-clustered — the same specification the paper already reports for
`roads_rate`):

| Infrastructure measure | Contrast, Table 1 col (2) | Log-ratio (1c, district-clustered) |
|---|---|---|
| Roads per km (paper's `roads_rate`) | +0.146 (p = 0.18) | +0.079 (p = 0.21) |
| Km per capita (`roads_km_pc`) | −0.010 (p = 0.94) | −0.145 (p = 0.38) |
| Roads per capita (`roads_n_pc`) | +0.051 (p = 0.72) | −0.086 (p = 0.56) |

**Flagging a mismatch with the numbers you pasted for checking**: you had
−0.14 (p=0.47) for km-per-capita's log-ratio and −0.07 (p=0.69) for
roads-per-capita's. My district-clustered, district+state×year-FE numbers
(the specification matching how the paper reports `roads_rate`'s own 1c
estimate) are −0.145 (p=0.38) and −0.086 (p=0.56) instead. I could not find
an FE/clustering combination in the SUMMARY file that reproduces your exact
checking values — the closest is the additive-FE, state-clustered row
(p=0.55 for km_pc), still not 0.47. You said those numbers were "only for
checking" and to pull from the SUMMARY files, which is what the slide and
this table use; flagging the gap in case your checking numbers came from a
different file version.

**What this means substantively** (already in the SUMMARY's own "what to
take from this" section, not my addition): the sign contrast does not
survive the switch from `roads_rate` to `roads_km_pc` — it goes negative in
both the standardised and log versions, though nothing is significant under
any of the three measures.

---

## Part B: slides

Deck is now **14 frames**. Inserted before "Quantitative value" (now frame
13): "The contrast" (9), "Sign contrast: estimates" (10), "Instrumenting
with the queue" (11), "The roads measure" (12). "Discussion" is now frame 14.

- **"The contrast"**: full-width `contrast_plot_slides.png`, one line beneath
  it, as specified.
- **"Sign contrast: estimates"**: Table 1's Engineer / Engineer×infra rows,
  4 columns, p-value row (0.21/0.18/0.23/0.15 — matches your check numbers
  exactly), one FE row (State×year), log-welfare cell (−0.028, p=0.04)
  shaded.
- **"Instrumenting with the queue"**: OLS (0.037) / IV district-clustered
  (0.337, KP-F 34.5) / IV state-clustered (0.337, KP-F 58.2).
- **"The roads measure"**: the two bullets as specified, then the 3-row
  table from the Task 0 section above (per your clarification), then the
  closing line.
- **"Quantitative value"**: illustrative table now reads +9.2% / +12.1%
  (was +9.2%/+12.0% — the +12.0% was the one remaining stale rounding from
  last session's fix, caught now); calibrated table now shows the β≈0.079
  log-ratio numbers (+0.46% / +0.61%) with a new third row for the 95% CI on
  assortative pairing ([−0.40%, +1.31%]); calibration line reworded exactly
  as specified; bottom line unchanged.

### B3: compile report

`./build_slides.sh` — clean, exit 0, **14 pages**.

- Had to fix one real build error: the image path was wrong on the first
  attempt (`figures/...` instead of `../figures/...`, since the deck compiles
  from inside `slides/`) — fixed, now resolves.
- Had to add `\usepackage{graphicx}` — the deck had never included an
  external image before (everything was TikZ), so this package wasn't
  loaded.
- Two small overfull vboxes appear (13.3pt on the pre-existing "Collector's
  problem" slide, 3.7pt on "Discussion") plus one new one (38.5pt on
  "Quantitative value", from the added CI row) and one pre-existing overfull
  hbox (2.0pt). All four rendered and inspected visually on the compiled
  PDF — **none is visible on the page**; no text is cut off, clipped, or
  overlapping anywhere I could see across all 14 slides.

---

## Open items for you

1. **The Task 0 checking-number mismatch** above (km_pc/n_pc log-ratio
   p-values) — couldn't resolve which spec your numbers came from.
2. **Speaker notes** for the 4 new slides don't exist yet — I didn't add them
   since it wasn't asked for here, but the deck now has 4 slides with no
   matching entry in `speaker_notes.md`.
3. Both repos still have the duplicate-content bug and the two orphaned
   references found in the previous task's compile report
   (`def:matchvalue`/`prop:vij`/`eq:vij`/`eq:SD` defined twice;
   `sec:collector` and `app:dynamic` undefined) — unchanged by this task,
   noting again since they'll keep showing up in every future compile until
   someone resolves them.
