##############################################################################
# run_iv_v2.R — Refined IV: Queue_refined = opposition_turnover × cadre_queue_pct
#
# SPEC:  feols(Engineer ~ Queue_refined | district_id + year, cluster = ~state_id)
# 2SLS:  feols(outcome ~ 1 | district_id + year | Engineer ~ Queue_refined,
#              cluster = ~district_id)  [roads_rate + lights_rural only]
##############################################################################

suppressPackageStartupMessages({
  library(fixest)
  library(data.table)
})

dir.create("tables", showWarnings = FALSE)

# ─────────────────────────────────────────────────────────────────────────────
# 1. LOAD
# ─────────────────────────────────────────────────────────────────────────────

df <- fread("data/analysis/dc_analysis_v2.csv",
            colClasses = list(character = c("district_id","state_id")))
df[, district_id := factor(district_id)]
df[, state_id    := factor(state_id)]
df[, year_fac   := factor(year)]

cat(sprintf("Dataset: %d obs | %d districts | %d states\n",
    nrow(df), uniqueN(df$district_id), uniqueN(df$state_id)))
cat(sprintf("Engineer mean : %.3f\n", mean(df$Engineer)))
cat(sprintf("opposition_turnover==1: %d obs (%.1f%%)\n",
    sum(df$opposition_turnover==1), 100*mean(df$opposition_turnover==1)))
cat(sprintf("Queue_refined: mean=%.4f, SD=%.4f, max=%.4f\n\n",
    mean(df$Queue_refined, na.rm=TRUE),
    sd(df$Queue_refined, na.rm=TRUE),
    max(df$Queue_refined, na.rm=TRUE)))

# ─────────────────────────────────────────────────────────────────────────────
# 2. FIRST STAGE  (cluster at state level as requested)
#
# feols(Engineer ~ Queue_refined | district_id + year, cluster = ~state_id)
# ─────────────────────────────────────────────────────────────────────────────

cat("══════════════════════════════════════════════════════\n")
cat("FIRST STAGE\n")
cat("══════════════════════════════════════════════════════\n")

fs_full <- feols(Engineer ~ Queue_refined | district_id + year_fac,
                 data = df, cluster = ~state_id)

fs_roads <- feols(Engineer ~ Queue_refined | district_id + year_fac,
                  data = df[year >= 2001 & !is.na(roads_rate)],
                  cluster = ~state_id)

fs_lights <- feols(Engineer ~ Queue_refined | district_id + year_fac,
                   data = df[!is.na(lights_rural)],
                   cluster = ~state_id)

print_fs <- function(m, label) {
  cf  <- coef(m)["Queue_refined"]
  se  <- se(m)["Queue_refined"]
  pv  <- pvalue(m)["Queue_refined"]
  f   <- fitstat(m, "f")[[1]]$stat  # F-stat on all regressors; use Wald F below
  # Wald F on instrument (= t^2 for single instrument)
  f_wald <- (cf / se)^2
  pass <- ifelse(f_wald > 10, "PASS ✓", "FAIL ✗")
  cat(sprintf("  %-30s  coef=%+.4f  SE=%.4f  p=%.3f  F(Wald)=%.2f  [%s]\n",
              label, cf, se, pv, f_wald, pass))
}

print_fs(fs_full,   "Full sample (N=all)")
print_fs(fs_roads,  "Roads subsample (yr>=2001)")
print_fs(fs_lights, "Lights subsample (full)")

cat("\nDetailed first stage (full sample):\n")
print(summary(fs_full))

# ─────────────────────────────────────────────────────────────────────────────
# 3. FIRST STAGE TABLE  →  tables/first_stage_v2.tex
# ─────────────────────────────────────────────────────────────────────────────

etable(fs_full, fs_roads, fs_lights,
       headers   = c("Full","Roads subset","Lights subset"),
       keep      = "Queue_refined",
       fitstat   = ~ f + n,
       tex       = TRUE,
       title     = "First Stage: Queue\\_refined Predicts Engineer",
       label     = "tab:first_stage_v2",
       notes     = paste("Queue\\_refined = opposition\\_turnover",
                         "\\$\\times\\$ cadre\\_queue\\_pct.",
                         "Opposition\\_turnover = 1 if winning party changed",
                         "vs previous year in state s in year t.",
                         "cadre\\_queue\\_pct = percentile rank of officer",
                         "within cadre-year active DC pool (0=most senior,",
                         "1=most junior). Clustered at state level.",
                         "F\\$(Wald)\\$ = squared t-ratio (single instrument)."),
       file      = "tables/first_stage_v2.tex")
cat("Saved tables/first_stage_v2.tex\n\n")

# ─────────────────────────────────────────────────────────────────────────────
# 4. CHECK FIRST STAGE STRENGTH — decide whether to proceed with 2SLS
# ─────────────────────────────────────────────────────────────────────────────

f_roads  <- (coef(fs_roads)["Queue_refined"]  / se(fs_roads)["Queue_refined"])^2
f_lights <- (coef(fs_lights)["Queue_refined"] / se(fs_lights)["Queue_refined"])^2

cat("══════════════════════════════════════════════════════\n")
cat("INSTRUMENT STRENGTH CHECK (F > 10 threshold)\n")
cat("══════════════════════════════════════════════════════\n")
cat(sprintf("  roads_rate  subsample: F(Wald) = %.2f  [%s]\n",
    f_roads,  ifelse(f_roads  > 10, "PASS", "FAIL")))
cat(sprintf("  lights_rural full :    F(Wald) = %.2f  [%s]\n",
    f_lights, ifelse(f_lights > 10, "PASS", "FAIL")))
cat("\n")

# Always run 2SLS and report regardless, but flag weak-instrument results
cat("══════════════════════════════════════════════════════\n")
cat("2SLS ESTIMATES\n")
cat("══════════════════════════════════════════════════════\n")

# ─────────────────────────────────────────────────────────────────────────────
# 5. 2SLS
# ─────────────────────────────────────────────────────────────────────────────

## ROADS RATE (year >= 2001)
sub_roads <- df[year >= 2001 & !is.na(roads_rate) & !is.na(Queue_refined)]
iv_roads  <- feols(roads_rate ~ 1 | district_id + year_fac | Engineer ~ Queue_refined,
                   data = sub_roads, cluster = ~district_id)

## LIGHTS PER CAPITA (full panel)
sub_lights <- df[!is.na(lights_rural) & !is.na(Queue_refined)]
iv_lights  <- feols(lights_rural ~ 1 | district_id + year_fac | Engineer ~ Queue_refined,
                    data = sub_lights, cluster = ~district_id)

## OLS equivalents for comparison
ols_roads  <- feols(roads_rate  ~ Engineer | district_id + year_fac,
                    data = sub_roads,  cluster = ~district_id)
ols_lights <- feols(lights_rural ~ Engineer | district_id + year_fac,
                    data = sub_lights, cluster = ~district_id)

# Extract and print
print_iv <- function(m_iv, m_ols, outcome_label, f_val) {
  cf_iv  <- coef(m_iv)["fit_Engineer"]
  se_iv  <- se(m_iv)["fit_Engineer"]
  pv_iv  <- pvalue(m_iv)["fit_Engineer"]
  cf_ols <- coef(m_ols)["Engineer"]
  se_ols <- se(m_ols)["Engineer"]
  pv_ols <- pvalue(m_ols)["Engineer"]
  weak   <- ifelse(f_val < 10, "  ⚠ WEAK INSTRUMENT", "")

  cat(sprintf("  %s%s\n", outcome_label, weak))
  cat(sprintf("    OLS  : Engineer = %+.4f (SE %.4f, p=%.3f)  N=%d\n",
      cf_ols, se_ols, pv_ols, nobs(m_ols)))
  cat(sprintf("    2SLS : Engineer = %+.4f (SE %.4f, p=%.3f)  N=%d  F=%.2f\n",
      cf_iv, se_iv, pv_iv, nobs(m_iv), f_val))
  cat(sprintf("    Ratio (IV/OLS)  = %.2f\n\n",
      ifelse(abs(cf_ols) > 1e-8, cf_iv / cf_ols, NA)))
}

print_iv(iv_roads,  ols_roads,  "ROADS RATE (year>=2001)", f_roads)
print_iv(iv_lights, ols_lights, "LIGHTS PER CAPITA",       f_lights)

# ─────────────────────────────────────────────────────────────────────────────
# 6. 2SLS TABLE  →  tables/iv_main_v2.tex
# Manual construction for clean OLS | IV side-by-side layout
# ─────────────────────────────────────────────────────────────────────────────

fmt_coef <- function(cf, se, pv) {
  stars <- ifelse(pv < 0.01, "***", ifelse(pv < 0.05, "**",
           ifelse(pv < 0.10, "*", "")))
  sprintf("%.4f%s", cf, stars)
}
fmt_se <- function(se) sprintf("(%.4f)", se)
fmt_f  <- function(f)  {
  flag <- ifelse(f > 10, "\\checkmark", "\\times")
  sprintf("%.2f~$%s$", f, flag)
}

cf_ols_r  <- coef(ols_roads)["Engineer"]
se_ols_r  <- se(ols_roads)["Engineer"]
pv_ols_r  <- pvalue(ols_roads)["Engineer"]
cf_iv_r   <- coef(iv_roads)["fit_Engineer"]
se_iv_r   <- se(iv_roads)["fit_Engineer"]
pv_iv_r   <- pvalue(iv_roads)["fit_Engineer"]
n_r       <- nobs(iv_roads)

cf_ols_l  <- coef(ols_lights)["Engineer"]
se_ols_l  <- se(ols_lights)["Engineer"]
pv_ols_l  <- pvalue(ols_lights)["Engineer"]
cf_iv_l   <- coef(iv_lights)["fit_Engineer"]
se_iv_l   <- se(iv_lights)["fit_Engineer"]
pv_iv_l   <- pvalue(iv_lights)["fit_Engineer"]
n_l       <- nobs(iv_lights)

tex <- c(
  "\\begin{table}[htbp]",
  "\\centering",
  "\\caption{OLS vs 2SLS: Effect of Engineer DC on Infrastructure Outcomes}",
  "\\label{tab:iv_main_v2}",
  "\\begin{tabular}{lcccc}",
  "\\hline\\hline",
  " & \\multicolumn{2}{c}{Road completion rate} & \\multicolumn{2}{c}{Nightlights per capita} \\\\",
  "\\cmidrule(lr){2-3}\\cmidrule(lr){4-5}",
  " & OLS & 2SLS & OLS & 2SLS \\\\",
  " & (1) & (2) & (3) & (4) \\\\",
  "\\hline",
  sprintf("Engineer & %s & %s & %s & %s \\\\",
          fmt_coef(cf_ols_r, se_ols_r, pv_ols_r),
          fmt_coef(cf_iv_r,  se_iv_r,  pv_iv_r),
          fmt_coef(cf_ols_l, se_ols_l, pv_ols_l),
          fmt_coef(cf_iv_l,  se_iv_l,  pv_iv_l)),
  sprintf("          & %s & %s & %s & %s \\\\[4pt]",
          fmt_se(se_ols_r), fmt_se(se_iv_r),
          fmt_se(se_ols_l), fmt_se(se_iv_l)),
  sprintf("First-stage $F$ & --- & %s & --- & %s \\\\",
          fmt_f(f_roads), fmt_f(f_lights)),
  sprintf("Observations & %s & %s & %s & %s \\\\",
          format(nobs(ols_roads),  big.mark=","),
          format(n_r, big.mark=","),
          format(nobs(ols_lights), big.mark=","),
          format(n_l, big.mark=",")),
  "\\hline",
  "District FE  & \\checkmark & \\checkmark & \\checkmark & \\checkmark \\\\",
  "Year FE      & \\checkmark & \\checkmark & \\checkmark & \\checkmark \\\\",
  "\\hline\\hline",
  "\\multicolumn{5}{p{0.90\\textwidth}}{\\footnotesize",
  "\\textit{Notes:} Baseline category: SocialScientist.",
  "Instrument (2SLS): Queue\\_refined $=$ opposition\\_turnover $\\times$",
  "cadre\\_queue\\_pct, where opposition\\_turnover $=1$ when incoming",
  "state government is from a different party than outgoing,",
  "and cadre\\_queue\\_pct $\\in[0,1]$ is officer's percentile position",
  "in the cadre's seniority queue in that year (0 = most senior).",
  "Cols (1)--(2): roads subsample, year $\\geq 2001$.",
  "Cols (3)--(4): full panel, 1994--2008.",
  "Clustered SEs at district level. $\\checkmark$: $F>10$; $\\times$: $F\\leq10$.",
  "Stars: *** $p<0.01$, ** $p<0.05$, * $p<0.10$.}",
  "\\end{tabular}",
  "\\end{table}"
)
writeLines(tex, "tables/iv_main_v2.tex")
cat("Saved tables/iv_main_v2.tex\n")
cat("Done.\n")
