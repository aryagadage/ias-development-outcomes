# Collector Vacancy-and-Availability Panel, Cadre-Month, 1994-2008 (v2)

Standalone, read-only analysis of `data/raw/ias-experience.csv`, `data/raw/ias-profile.csv`, `data/analysis/crosswalk_v2.csv`. No existing pipeline file was modified or used as a source.

**Unit of analysis: cadre ("state cadre"), same choice and same reasoning as the earlier `diagnostics/collector_availability/` pass** -- crosswalk cadre->pc11_state_id is many-to-many due to office-name matching noise, so cadre is the unambiguous key. "District" = (cadre, pc11_district_id).

- Officers with usable cadre + allotment year: 13,559 across 29 cadres
- Experience rows: 151,568 -> 145,120 usable posting intervals (bad start date 1194, bad non-"N.A." end date 0, true end-before-start anomaly 133, and 5121 further rows dropped because they are "N.A."-ended (ongoing) but start after the 2008 study window closes -- not a data error, just out of scope)
- Collector-designation spells (all years): 14,667; matched to a pc11 district via crosswalk: 11,073

**Five largest state cadres** (by officer headcount):

- Uttar Pradesh: 1,314 officers, 69 districts on roster
- Madhya Pradesh: 919 officers, 50 districts on roster
- Bihar: 876 officers, 56 districts on roster
- West Bengal: 850 officers, 19 districts on roster
- Maharashtra: 826 officers, 35 districts on roster

## Step 6 -- Post classifier

**Built on `Designation` (job title), not literally `Office` (department/place name).** Office holds strings like "M/o Education" or a district name and carries no DC / sub-district / secretariat / deputation / training role information; Designation is where that information lives, and it is the same field the existing pipeline's own DC filter already uses. This is a deliberate, flagged substitution for the task's "free-text office names" phrasing, not a silent one.

Priority order: DC/DM/Collector (exact reuse of the existing pipeline filter) &rarr; training (Designation or Organisation) &rarr; deputation (Organisation indicates away from home cadre: Centre, inter-cadre, foreign posting, PSU, ex-cadre, non-AIS) &rarr; sub-district (SDM/SDO/sub-collector/additional collector/joint collector/etc., keyword list in code) &rarr; secretariat (broad HQ/board/leadership keyword list) &rarr; unclassified.

Share of experience rows (N=145,120) per bucket:

| bucket          |   n_rows |   share |
|:----------------|---------:|--------:|
| secretariat     |    84053 |  0.5792 |
| deputation      |    18423 |  0.127  |
| dc_dm_collector |    14667 |  0.1011 |
| unclassified    |    13481 |  0.0929 |
| subdistrict     |    10470 |  0.0721 |
| training        |     4026 |  0.0277 |

Top 20 most frequent **unclassified** designation strings (candidates for extending the ruleset):

| designation                  |    n |
|:-----------------------------|-----:|
| N.A.                         | 6112 |
| On Leave                     |  821 |
| District Dev Officer         |  558 |
| Project Officer              |  504 |
| Chief Executive Officer      |  479 |
| Settlement Officer           |  288 |
| Chief Dev Officer            |  283 |
| Chief Electoral Officer      |  234 |
| On Compulsory Wait           |  182 |
| Vice Chairperson             |  170 |
| Under Suspension             |  166 |
| Executive Magistrate         |  158 |
| Assistant Magistrate         |  132 |
| Magistrate (City)            |  126 |
| Inspector General            |  104 |
| Additional Executive Officer |   98 |
| Charge Officer               |   91 |
| Revenue Divisional Officer   |   89 |
| District Revenue Officer     |   87 |
| District Planning Officer    |   73 |

## Step 1 -- Gap taxonomy and spell duration

Consecutive-spell-pair gaps computed within each district-cadre roster slot, ordered by start date: 10,335 pairs.

### Pooled

| bucket             |    n |   share |
|:-------------------|-----:|--------:|
| negative (overlap) | 6078 |  0.5881 |
| 0-3mo              | 1318 |  0.1275 |
| 4-12mo             |  851 |  0.0823 |
| 13-36mo            | 1349 |  0.1305 |
| >36mo              |  739 |  0.0715 |

### Five largest cadres

| group          | bucket             |    n |   share |
|:---------------|:-------------------|-----:|--------:|
| Uttar Pradesh  | negative (overlap) | 1006 |  0.6284 |
| Uttar Pradesh  | 0-3mo              |  163 |  0.1018 |
| Uttar Pradesh  | 4-12mo             |  165 |  0.1031 |
| Uttar Pradesh  | 13-36mo            |  202 |  0.1262 |
| Uttar Pradesh  | >36mo              |   65 |  0.0406 |
| Madhya Pradesh | negative (overlap) |  643 |  0.6095 |
| Madhya Pradesh | 0-3mo              |  157 |  0.1488 |
| Madhya Pradesh | 4-12mo             |   77 |  0.073  |
| Madhya Pradesh | 13-36mo            |  122 |  0.1156 |
| Madhya Pradesh | >36mo              |   56 |  0.0531 |
| Bihar          | negative (overlap) |  506 |  0.5803 |
| Bihar          | 0-3mo              |  106 |  0.1216 |
| Bihar          | 4-12mo             |   80 |  0.0917 |
| Bihar          | 13-36mo            |  114 |  0.1307 |
| Bihar          | >36mo              |   66 |  0.0757 |
| West Bengal    | negative (overlap) |  194 |  0.5575 |
| West Bengal    | 0-3mo              |   64 |  0.1839 |
| West Bengal    | 4-12mo             |   23 |  0.0661 |
| West Bengal    | 13-36mo            |   37 |  0.1063 |
| West Bengal    | >36mo              |   30 |  0.0862 |
| Maharashtra    | negative (overlap) |  408 |  0.6755 |
| Maharashtra    | 0-3mo              |   68 |  0.1126 |
| Maharashtra    | 4-12mo             |   37 |  0.0613 |
| Maharashtra    | 13-36mo            |   55 |  0.0911 |
| Maharashtra    | >36mo              |   36 |  0.0596 |

### DC spell duration (months)

**Pooled:**

| group               |   mean |   median |   iqr |   p10 |   p90 |
|:--------------------|-------:|---------:|------:|------:|------:|
| Pooled (all cadres) |  18.99 |       17 |    15 |     6 |    34 |

**Five largest cadres:**

| group          |   mean |   median |   iqr |   p10 |   p90 |
|:---------------|-------:|---------:|------:|------:|------:|
| Uttar Pradesh  |  16.93 |       14 |    14 |     5 |  29.1 |
| Madhya Pradesh |  19.21 |       17 |    14 |     6 |  36   |
| Bihar          |  17.5  |       15 |    15 |     5 |  32   |
| West Bengal    |  21.71 |       22 |    13 |     9 |  34   |
| Maharashtra    |  24.39 |       23 |    17 |     9 |  39.2 |

**All cadres** (for completeness, not requested as a headline table):

| group            |   mean |   median |   iqr |   p10 |   p90 |
|:-----------------|-------:|---------:|------:|------:|------:|
| A G M U T        |  21.5  |     20   | 17    |   6.4 |  37.6 |
| Andhra Pradesh   |  19.22 |     18   | 15    |   6.8 |  33   |
| Assam Meghalya   |  21.64 |     19   | 17.5  |   6   |  39   |
| Bihar            |  17.5  |     15   | 15    |   5   |  32   |
| Chhattisgarh     |  17.56 |     16   | 16    |   4   |  31   |
| Gujarat          |  21.28 |     19   | 15    |   7   |  39   |
| Haryana          |  19.13 |     14   | 14    |   5   |  31.4 |
| Himachal Pradesh |  20.62 |     19   | 16    |   6   |  36   |
| Jammu & Kashmir  |  20.88 |     18   | 14    |  10   |  38   |
| Jharkhand        |  16.16 |     13   | 13    |   5   |  30   |
| Karnataka        |  17.36 |     16   | 15    |   5   |  31.3 |
| Kerala           |  18.33 |     16   | 14    |   6.6 |  32   |
| Madhya Pradesh   |  19.21 |     17   | 14    |   6   |  36   |
| Maharashtra      |  24.39 |     23   | 17    |   9   |  39.2 |
| Manipur          |  15.12 |     14   | 15.75 |   4.5 |  28.5 |
| Manipur-Tripura  |  18.32 |     18   |  9    |   7   |  29.3 |
| Nagaland         |  23.5  |     23.5 | 15.5  |  11.1 |  35.9 |
| Odisha           |  19.25 |     18   | 14    |   6   |  33.9 |
| Punjab           |  18.24 |     16   | 15.5  |   5   |  34.5 |
| Rajasthan        |  18.53 |     17   | 12    |   8   |  30.8 |
| Sikkim           |  23.54 |     21   | 23.5  |   6.1 |  47.8 |
| Tamil Nadu       |  19.29 |     17   | 16    |   6   |  34   |
| Telangana        |  19.28 |     18   | 14.25 |   6.9 |  33.2 |
| Tripura          |  19.28 |     16   | 12.5  |   6.6 |  33.4 |
| Uttar Pradesh    |  16.93 |     14   | 14    |   5   |  29.1 |
| Uttarakhand      |  18.03 |     14   | 14    |   6   |  32   |
| West Bengal      |  21.71 |     22   | 13    |   9   |  34   |

## Step 2 -- Vacancy vs. record failure

**Rule:** a district-month with no spell covering it counts as a **genuine vacancy** only if the enclosing gap (Step 1's consecutive-pair gap) is bounded on both sides and <=3 months. Everything else uncovered -- a bounded gap >3 months, or an open-ended gap before a district's first-ever recorded spell or after its last -- is a **record failure**, not a vacancy: we cannot verify "no administrator" for an unbounded stretch, and a district cannot plausibly run headless for a year.

Reconciliation against the raw occupancy sweep (independent check, not silently trusted): 987 of 132,840 district-month cells (0.743%) disagreed before reconciliation; disagreements are resolved conservatively (trust a directly observed covering spell over the pair-gap inference; anything left uncovered and unclassified is folded into record failure).

### Distribution across cadre-months, pooled

| metric                                             | group   |   mean |   median |   iqr |   p10 |   p90 |
|:---------------------------------------------------|:--------|-------:|---------:|------:|------:|------:|
| Genuine vacancies (no spell, gap <=3mo both-sided) | Pooled  |   0.06 |        0 |     0 |     0 |     0 |
| Record failures (no spell, gap >3mo or open-ended) | Pooled  |  13.43 |       10 |     9 |     4 |    33 |

### Five largest cadres

| metric                                             | group          |   mean |   median |   iqr |   p10 |   p90 |
|:---------------------------------------------------|:---------------|-------:|---------:|------:|------:|------:|
| Genuine vacancies (no spell, gap <=3mo both-sided) | Uttar Pradesh  |   0.53 |        0 |  1    |   0   |   2   |
| Genuine vacancies (no spell, gap <=3mo both-sided) | Madhya Pradesh |   0.1  |        0 |  0    |   0   |   0   |
| Genuine vacancies (no spell, gap <=3mo both-sided) | Bihar          |   0.21 |        0 |  0    |   0   |   1   |
| Genuine vacancies (no spell, gap <=3mo both-sided) | West Bengal    |   0.04 |        0 |  0    |   0   |   0   |
| Genuine vacancies (no spell, gap <=3mo both-sided) | Maharashtra    |   0.03 |        0 |  0    |   0   |   0   |
| Record failures (no spell, gap >3mo or open-ended) | Uttar Pradesh  |  17.07 |       17 | 10.25 |   7.9 |  28   |
| Record failures (no spell, gap >3mo or open-ended) | Madhya Pradesh |  15.63 |       11 | 14    |   7   |  29.1 |
| Record failures (no spell, gap >3mo or open-ended) | Bihar          |  25.58 |       25 |  6    |  21   |  32   |
| Record failures (no spell, gap >3mo or open-ended) | West Bengal    |   7.9  |        8 |  2    |   6   |  10   |
| Record failures (no spell, gap >3mo or open-ended) | Maharashtra    |   7.52 |        7 |  4    |   4   |  11.1 |

## Step 3 -- Eligibility band (5-15 years of service)

Distribution of officers in-band, cadre-months:

| metric                              | group   |   mean |   median |   iqr |   p10 |   p90 |
|:------------------------------------|:--------|-------:|---------:|------:|------:|------:|
| Officers in 5-15yr eligibility band | Pooled  | 102.83 |       95 |    96 |    32 |   182 |

| metric                              | group          |   mean |   median |   iqr |   p10 |   p90 |
|:------------------------------------|:---------------|-------:|---------:|------:|------:|------:|
| Officers in 5-15yr eligibility band | Uttar Pradesh  | 246.73 |      236 |   131 |   160 |   329 |
| Officers in 5-15yr eligibility band | Madhya Pradesh | 163.47 |      160 |    28 |   149 |   186 |
| Officers in 5-15yr eligibility band | Bihar          | 211.27 |      212 |    42 |   171 |   242 |
| Officers in 5-15yr eligibility band | West Bengal    | 184.93 |      178 |    38 |   165 |   212 |
| Officers in 5-15yr eligibility band | Maharashtra    | 176.13 |      176 |    25 |   156 |   196 |

**Observed years-of-service at actual DC-spell start** (the reality check against the 5-15yr band):

Pooled: mean=9.33, median=9.00, iqr=4.00, p10=6.00, p90=13.00


Five largest cadres:

| group          |   mean |   median |   iqr |   p10 |   p90 |
|:---------------|-------:|---------:|------:|------:|------:|
| Uttar Pradesh  |   9.98 |       10 |  5    |     5 |    14 |
| Madhya Pradesh |   9.18 |        9 |  4    |     6 |    13 |
| Bihar          |   9.12 |        9 |  4.75 |     5 |    14 |
| West Bengal    |   9.91 |       10 |  4    |     7 |    13 |
| Maharashtra    |   9.56 |        9 |  3    |     6 |    13 |

Observed p10/p90 sit reasonably within the 5-15yr band; no revision flagged.

## Step 4 -- Availability, Definitions A / B / C

- **Def A**: in eligibility band, not currently in a DC spell, and either currently in a recorded non-DC post, or in a both-sided gap of <=3 months.
- **Def B**: as A, gap tolerance widened to <=12 months.
- **Def C**: Def A, restricted to officers with >=1 recorded posting (any designation) before the current month.

**Caveat, not silently resolved:** "currently in a recorded non-DC post" counts *any* non-DC classified posting, including deputation and training postings (Step 6's finer categories). An officer on central deputation or in training is arguably not truly available for state DC posting; this reading of the definition as given will overstate availability under condition (a) to that extent. Restricting (a) to exclude deputation/training is a one-line change (`post_class not in {'deputation','training'}`) if a stricter reading is wanted.

### Distribution across cadre-months, pooled

| definition                                  | group   |   mean |   median |   iqr |   p10 |   p90 |
|:--------------------------------------------|:--------|-------:|---------:|------:|------:|------:|
| Def A (currently non-DC post, or gap <=3mo) | Pooled  |  49.88 |       48 |    45 |    14 |    93 |
| Def B (as A, gap widened to <=12mo)         | Pooled  |  50.09 |       48 |    44 |    14 |    93 |
| Def C (Def A + >=1 prior post in cadre)     | Pooled  |  48.84 |       47 |    44 |    13 |    91 |

### Five largest cadres

| definition                                  | group          |   mean |   median |   iqr |   p10 |   p90 |
|:--------------------------------------------|:---------------|-------:|---------:|------:|------:|------:|
| Def A (currently non-DC post, or gap <=3mo) | Uttar Pradesh  | 101.42 |     93   | 62.75 |  55   | 178   |
| Def A (currently non-DC post, or gap <=3mo) | Madhya Pradesh |  77.36 |     72   | 30.5  |  60   | 104   |
| Def A (currently non-DC post, or gap <=3mo) | Bihar          |  58.92 |     55   | 22    |  42   |  84.1 |
| Def A (currently non-DC post, or gap <=3mo) | West Bengal    |  85.84 |     81   | 37.25 |  63   | 115   |
| Def A (currently non-DC post, or gap <=3mo) | Maharashtra    | 103.7  |    103   |  7    |  95.9 | 113.1 |
| Def B (as A, gap widened to <=12mo)         | Uttar Pradesh  | 102.13 |     93.5 | 62.75 |  56   | 178.1 |
| Def B (as A, gap widened to <=12mo)         | Madhya Pradesh |  77.56 |     72   | 29.5  |  60.9 | 104   |
| Def B (as A, gap widened to <=12mo)         | Bihar          |  59.13 |     55   | 22    |  42   |  85.1 |
| Def B (as A, gap widened to <=12mo)         | West Bengal    |  86.14 |     81   | 38.25 |  63   | 115   |
| Def B (as A, gap widened to <=12mo)         | Maharashtra    | 104.06 |    103   |  8    |  95.9 | 114   |
| Def C (Def A + >=1 prior post in cadre)     | Uttar Pradesh  |  97.99 |     92   | 66.5  |  48.9 | 173   |
| Def C (Def A + >=1 prior post in cadre)     | Madhya Pradesh |  76.32 |     71   | 29.25 |  60   | 102   |
| Def C (Def A + >=1 prior post in cadre)     | Bihar          |  55.73 |     52   | 22.25 |  39   |  82   |
| Def C (Def A + >=1 prior post in cadre)     | West Bengal    |  84.13 |     81   | 37    |  60.9 | 111.1 |
| Def C (Def A + >=1 prior post in cadre)     | Maharashtra    | 102.76 |    102   |  9    |  94.9 | 112   |

## Step 5 -- The ratio that matters (available / genuine vacancies)

Computed only for the 245 of 4,860 cadre-months with >=1 genuine vacancy (ratio undefined at zero vacancies; those months are excluded from the distribution below, not silently treated as 0 or infinite).

| definition                                  |   mean |   median |   iqr |   p10 |   p90 |
|:--------------------------------------------|-------:|---------:|------:|------:|------:|
| Def A (currently non-DC post, or gap <=3mo) | 60.615 |       59 |  47.5 |  21   |   102 |
| Def B (as A, gap widened to <=12mo)         | 60.934 |       59 |  48   |  21.4 |   103 |
| Def C (Def A + >=1 prior post in cadre)     | 59.114 |       58 |  47   |  19.4 |   101 |

**Share of (vacancy>0) cadre-months where the ratio falls below threshold:**

| definition                                  |   n_cadre_months_with_vacancy |   share_lt_1 |   share_lt_2 |   share_lt_5 |
|:--------------------------------------------|------------------------------:|-------------:|-------------:|-------------:|
| Def A (currently non-DC post, or gap <=3mo) |                           245 |            0 |            0 |            0 |
| Def B (as A, gap widened to <=12mo)         |                           245 |            0 |            0 |            0 |
| Def C (Def A + >=1 prior post in cadre)     |                           245 |            0 |            0 |            0 |

**Correlation, genuine vacancies vs. available officers (cadre-month level):**

| definition                                  |   pooled_r |   Uttar Pradesh |   Madhya Pradesh |   Bihar |   West Bengal |   Maharashtra |
|:--------------------------------------------|-----------:|----------------:|-----------------:|--------:|--------------:|--------------:|
| Def A (currently non-DC post, or gap <=3mo) |      0.138 |          -0.107 |           -0.095 |   0.131 |         0.102 |         0.096 |
| Def B (as A, gap widened to <=12mo)         |      0.139 |          -0.104 |           -0.095 |   0.13  |         0.098 |         0.094 |
| Def C (Def A + >=1 prior post in cadre)     |      0.132 |          -0.109 |           -0.118 |   0.119 |         0.106 |         0.1   |

## Sanity check -- officers must exceed roster size

| cadre            |   n_officers |   n_districts_roster | officers_exceed_roster   |
|:-----------------|-------------:|---------------------:|:-------------------------|
| A G M U T        |          696 |                   17 | True                     |
| Andhra Pradesh   |          604 |                   27 | True                     |
| Assam Meghalya   |          555 |                   29 | True                     |
| Bihar            |          876 |                   56 | True                     |
| Chhattisgarh     |          257 |                   47 | True                     |
| Gujarat          |          639 |                   26 | True                     |
| Haryana          |          472 |                   21 | True                     |
| Himachal Pradesh |          303 |                   12 | True                     |
| Jammu & Kashmir  |          305 |                    5 | True                     |
| Jharkhand        |          335 |                   51 | True                     |
| Karnataka        |          618 |                   30 | True                     |
| Kerala           |          398 |                   18 | True                     |
| Madhya Pradesh   |          919 |                   50 | True                     |
| Maharashtra      |          826 |                   35 | True                     |
| Manipur          |          122 |                    8 | True                     |
| Manipur-Tripura  |          183 |                    6 | True                     |
| Nagaland         |          180 |                    2 | True                     |
| Odisha           |          602 |                   34 | True                     |
| Punjab           |          509 |                   26 | True                     |
| Rajasthan        |          649 |                   34 | True                     |
| Sikkim           |          118 |                   10 | True                     |
| Tamil Nadu       |          722 |                   32 | True                     |
| Telangana        |          213 |                   23 | True                     |
| Tripura          |           94 |                    9 | True                     |
| Uttar Pradesh    |         1314 |                   69 | True                     |
| Uttarakhand      |          196 |                   42 | True                     |
| West Bengal      |          850 |                   19 | True                     |

PASS for every cadre with a matched district roster: officer headcount exceeds Collector-post roster size in all cases, as expected.
