# Collector Vacancy and Officer Availability, State(-Cadre)-Month Panel, 1994-2008

Standalone read-only analysis of `data/raw/ias-experience.csv`, `data/raw/ias-profile.csv`, and `data/analysis/crosswalk_v2.csv`. No existing pipeline file was read for its *derived* columns and none was modified.

**Unit of analysis: cadre ("state cadre"), not `pc11_state_id`.** `crosswalk_v2.csv` maps several cadres to more than one `pc11_state_id` (office-name matching noise), so cadre is the clean, unambiguous grouping key -- and it is what the existing pipeline already uses for seniority/turnover variables. Joint cadres (A G M U T, Assam Meghalya, Manipur-Tripura) are genuinely multi-state/UT by institutional design, not a data artefact.

- Officers in profile file: 13,559; distinct cadres: 29
- Experience rows: 151,568; unparseable start date: 1194; unparseable (non-"N.A.") end date: 0; end-before-start dropped: 133
- Collector-designation spells (all years, same filter as `build_iv_v2.py`): 14,667; matched to a pc11 district via crosswalk: 11,073

**Five largest state cadres** (by officer headcount in `ias-profile.csv`), with their Collector-post roster size:

- Uttar Pradesh: 1,314 officers, 69 districts on roster
- Madhya Pradesh: 919 officers, 50 districts on roster
- Bihar: 876 officers, 56 districts on roster
- West Bengal: 850 officers, 19 districts on roster
- Maharashtra: 826 officers, 35 districts on roster

(2 officers' cadre values -- "Chhasttisgarh" (n=2), "Maharastra" (n=5), both misspellings of an existing cadre in `ias-profile.csv` -- do not match any crosswalk row and are therefore excluded from the panel entirely; 7 officers total, negligible relative to N=13,559.)

## Definitions

- **(a) Vacant** -- cadre-month count of districts on that cadre's roster (distinct `pc11_district_id` in the crosswalk for that cadre) with no Collector-spell interval covering the month.
- **(b) Available officers**, built from each officer's *entire* posting history (all designations), not just Collector spells:
  - *def1 (any)*: no posting interval of any kind covers the month.
  - *def3 (both-sided)*: as def1, and the specific gap covering the month has a recorded posting immediately before **and** after it (excludes gaps open at the start or end of the officer's known career).
  - *def2 (both-sided, <24mo)*: as def3, and that gap is under 24 months long.
  - By construction def2 &sube; def3 &sube; def1 in every cell.
- **(c) New spells** -- Collector-spell count by start month.

**Caveat on def1:** because it is built from the officer's full recorded history with no career-span restriction, def1 also counts officers who have not yet joined the service, have already retired, or otherwise have no record at all in a given month -- as "available" for every one of those months. It should be read as an upper bound / "not on record as posted anywhere," not a genuine standby pool; def2 and def3 are the readings closer to actual administrative availability.

## Distribution across cadre-months

### Pooled (all cadres, all months)

| group               | metric                                           |   mean |   median |   iqr |   p10 |   p90 |
|:--------------------|:-------------------------------------------------|-------:|---------:|------:|------:|------:|
| Pooled (all cadres) | (a) Vacant Collector posts                       |  13.5  |       10 |     9 |     4 |    33 |
| Pooled (all cadres) | (b1) Officers available -- any gap               | 256.99 |      267 |   244 |    48 |   495 |
| Pooled (all cadres) | (b2) Officers available -- both-sided gap, <24mo |   0.95 |        1 |     1 |     0 |     3 |
| Pooled (all cadres) | (b3) Officers available -- both-sided gap        |   1.37 |        1 |     2 |     0 |     3 |
| Pooled (all cadres) | (c) New Collector spells starting                |   0.95 |        0 |     1 |     0 |     3 |

### Five largest state cadres, separately

| group          | metric                                           |   mean |   median |   iqr |   p10 |   p90 |
|:---------------|:-------------------------------------------------|-------:|---------:|------:|------:|------:|
| Uttar Pradesh  | (a) Vacant Collector posts                       |  17.6  |     18   | 10.25 |   8   |  30   |
| Uttar Pradesh  | (b1) Officers available -- any gap               | 584.59 |    581   | 31.5  | 556   | 615.1 |
| Uttar Pradesh  | (b2) Officers available -- both-sided gap, <24mo |   2.26 |      2   |  2    |   0   |   4   |
| Uttar Pradesh  | (b3) Officers available -- both-sided gap        |   2.68 |      3   |  2.25 |   0   |   5   |
| Uttar Pradesh  | (c) New Collector spells starting                |   4.84 |      3   |  6    |   0   |  13   |
| Madhya Pradesh | (a) Vacant Collector posts                       |  15.73 |     11   | 14    |   7   |  29.1 |
| Madhya Pradesh | (b1) Officers available -- any gap               | 488.92 |    491   | 20.25 | 466.9 | 508   |
| Madhya Pradesh | (b2) Officers available -- both-sided gap, <24mo |   1.34 |      1   |  2    |   0   |   3   |
| Madhya Pradesh | (b3) Officers available -- both-sided gap        |   1.65 |      1   |  3    |   0   |   4   |
| Madhya Pradesh | (c) New Collector spells starting                |   2.26 |      1   |  3    |   0   |   6   |
| Bihar          | (a) Vacant Collector posts                       |  25.79 |     25   |  7    |  21   |  32   |
| Bihar          | (b1) Officers available -- any gap               | 554.47 |    555   | 22    | 535   | 572.3 |
| Bihar          | (b2) Officers available -- both-sided gap, <24mo |   1.03 |      1   |  2    |   0   |   2.1 |
| Bihar          | (b3) Officers available -- both-sided gap        |   3.01 |      2   |  4    |   1   |   6.1 |
| Bihar          | (c) New Collector spells starting                |   2.08 |      1   |  2    |   0   |   6   |
| West Bengal    | (a) Vacant Collector posts                       |   7.94 |      8   |  2    |   6   |  10   |
| West Bengal    | (b1) Officers available -- any gap               | 479.28 |    471   | 37.25 | 458   | 508.1 |
| West Bengal    | (b2) Officers available -- both-sided gap, <24mo |   2.04 |      2   |  2    |   0   |   5   |
| West Bengal    | (b3) Officers available -- both-sided gap        |   3.47 |      3   |  4.25 |   0   |   7.1 |
| West Bengal    | (c) New Collector spells starting                |   0.53 |      0   |  1    |   0   |   2   |
| Maharashtra    | (a) Vacant Collector posts                       |   7.56 |      7   |  4    |   4   |  12   |
| Maharashtra    | (b1) Officers available -- any gap               | 413.69 |    412.5 | 27.25 | 394   | 433   |
| Maharashtra    | (b2) Officers available -- both-sided gap, <24mo |   1.54 |      1   |  2    |   0   |   3   |
| Maharashtra    | (b3) Officers available -- both-sided gap        |   2.19 |      2   |  2    |   0   |   4   |
| Maharashtra    | (c) New Collector spells starting                |   1.39 |      1   |  2    |   0   |   4   |

## Correlation: vacancy count vs. available-officer count (cadre-month level)

| available_definition                             |   pooled_r |   Uttar Pradesh |   Madhya Pradesh |   Bihar |   West Bengal |   Maharashtra |
|:-------------------------------------------------|-----------:|----------------:|-----------------:|--------:|--------------:|--------------:|
| (b1) Officers available -- any gap               |      0.078 |          -0.134 |           -0.833 |   0.045 |        -0.467 |        -0.488 |
| (b2) Officers available -- both-sided gap, <24mo |     -0.028 |           0.438 |           -0.19  |   0.165 |        -0.242 |         0.157 |
| (b3) Officers available -- both-sided gap        |      0.021 |           0.499 |            0.107 |   0.451 |         0.025 |         0.402 |

## District succession gap (Collector spell ending -> next spell starting, same district)

- Succession pairs identified: 10,335 (district-cadre keys with &ge;2 Collector spells)
- Overlapping/negative-gap pairs: 2,560 (24.8%)
- **Mean gap, non-negative pairs only: 12.17 months** (median 0.89, IQR 15.44)
- Mean gap, all pairs including overlaps as negative values: 7.22 months (reported for transparency only; the non-negative figure above is the substantive one)

By state cadre (mean gap in months, all consecutive-spell pairs in that cadre's districts, non-negative only):

- Uttar Pradesh: 10.14 months (N pairs = 1,081)
- Madhya Pradesh: 9.36 months (N pairs = 826)
- Bihar: 11.54 months (N pairs = 671)
- West Bengal: 11.36 months (N pairs = 275)
- Maharashtra: 10.00 months (N pairs = 402)
