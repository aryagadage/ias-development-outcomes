##############################################################################
# run_iv.R  —  IV estimation: Engineer ~ Queue_st (CM_turnover × seniority)
# Three FE specs × four outcomes. Saves per-outcome comparison tables and
# a single summary table.
##############################################################################

suppressPackageStartupMessages({
  library(fixest)
  library(data.table)
})

dir.create("tables", showWarnings = FALSE)

# ─────────────────────────────────────────────────────────────────────────────
# 1. LOAD DATA
# ─────────────────────────────────────────────────────────────────────────────

df <- fread("data/analysis/dc_analysis_balanced.csv",
            colClasses = list(character = c("district_id","state_id")))

# Ensure FE variables are factors
df[, district_id := factor(district_id)]
df[, state_id    := factor(state_id)]
df[, year        := as.integer(year)]
df[, year_fac    := factor(year)]
df[, state_year  := paste0(state_id, "_", year)]   # for state×year FE

cat(sprintf("Dataset: %d obs | %d districts | %d states | years %d-%d\n",
    nrow(df), uniqueN(df$district_id), uniqueN(df$state_id),
    min(df$year), max(df$year)))
cat(sprintf("Engineer mean: %.3f  |  Queue_st mean: %.4f  SD: %.4f\n",
    mean(df$Engineer), mean(df$Queue_st, na.rm=TRUE),
    sd(df$Queue_st, na.rm=TRUE)))
cat(sprintf("CM_turnover==1: %d obs (%.1f%%)\n\n",
    sum(df$CM_turnover==1, na.rm=TRUE),
    100*mean(df$CM_turnover==1, na.rm=TRUE)))

# ─────────────────────────────────────────────────────────────────────────────
# 2. HELPER: extract IV result row
# ─────────────────────────────────────────────────────────────────────────────

extract_iv <- function(m, spec_label) {
  if (inherits(m, "try-error") || is.null(m)) {
    return(data.frame(spec = spec_label, coef = NA, se = NA, pval = NA,
                      fstat = NA, n = NA, stringsAsFactors = FALSE))
  }
  cf  <- coef(m)["fit_Engineer"]
  se  <- sqrt(diag(vcov(m)))["fit_Engineer"]
  pv  <- 2 * pnorm(-abs(cf / se))

  # First-stage F-stat on the instrument
  fs <- tryCatch({
    fitstat(m, "ivf")[[1]]$stat
  }, error = function(e) NA_real_)

  data.frame(spec  = spec_label,
             coef  = round(cf,  4),
             se    = round(se,  4),
             pval  = round(pv,  4),
             fstat = round(fs,  2),
             n     = nobs(m),
             stringsAsFactors = FALSE)
}

# ─────────────────────────────────────────────────────────────────────────────
# 3. RUN IV FOR EACH OUTCOME × SPEC
# ─────────────────────────────────────────────────────────────────────────────

outcomes <- list(
  list(var = "roads_rate",   label = "Road completion rate",      year_min = 2001),
  list(var = "lights_rural", label = "Nightlights per capita",    year_min = 1994),
  list(var = "ec_emp_all",   label = "EC employment (all)",       year_min = 1994),
  list(var = "lit_rate",     label = "Literacy rate",             year_min = 1994)
)

spec_labels <- c(
  "Spec1" = "District + Year FE",
  "Spec2" = "District + State + Year FE",
  "Spec3" = "District + State\\texttimes{}Year FE  [\\textit{instrument absorbed}]"
)

# Collect all results for summary table
all_results <- list()

for (oc in outcomes) {
  var     <- oc$var
  label   <- oc$label
  yr_min  <- oc$year_min

  sub <- df[year >= yr_min & !is.na(get(var)) & !is.na(Queue_st)]
  cat(sprintf("═══ Outcome: %s  (N=%d, year>=%d) ═══\n", label, nrow(sub), yr_min))

  fml_base <- as.formula(paste0(var, " ~ 1 | district_id + year_fac | Engineer ~ Queue_st"))
  fml_sep  <- as.formula(paste0(var, " ~ 1 | district_id + state_id + year_fac | Engineer ~ Queue_st"))
  fml_sxyr <- as.formula(paste0(var, " ~ 1 | district_id + state_year | Engineer ~ Queue_st"))

  m1 <- try(feols(fml_base, data = sub, cluster = ~district_id), silent = TRUE)
  m2 <- try(feols(fml_sep,  data = sub, cluster = ~district_id), silent = TRUE)
  m3 <- try(feols(fml_sxyr, data = sub, cluster = ~district_id), silent = TRUE)

  r1 <- extract_iv(m1, "Spec 1: District+Year")
  r2 <- extract_iv(m2, "Spec 2: District+State+Year")
  r3 <- extract_iv(m3, "Spec 3: District+StateYear")

  for (r in list(r1, r2, r3)) {
    fpass <- ifelse(!is.na(r$fstat) & r$fstat > 10, "PASS", "FAIL")
    cat(sprintf("  %-35s  Engineer=%+.4f (SE=%.4f, p=%.3f)  F=%-6s  [F>10: %s]\n",
        r$spec, r$coef, r$se, r$pval,
        ifelse(is.na(r$fstat), "NA", sprintf("%.2f", r$fstat)),
        fpass))
  }
  cat("\n")

  # Store for summary
  res <- rbind(r1, r2, r3)
  res$outcome <- label
  all_results[[var]] <- res

  # ── Per-outcome LaTeX table ──────────────────────────────────────────────
  write_outcome_tex <- function(r1, r2, r3, out_label, filename) {
    fmt_coef <- function(r) {
      if (is.na(r$coef)) return("---")
      stars <- ifelse(r$pval < 0.01, "***", ifelse(r$pval < 0.05, "**",
               ifelse(r$pval < 0.10, "*", "")))
      sprintf("%.4f%s", r$coef, stars)
    }
    fmt_se <- function(r) {
      if (is.na(r$se)) return("") else sprintf("(%.4f)", r$se)
    }
    fmt_f <- function(r) {
      if (is.na(r$fstat)) return("---")
      flag <- ifelse(r$fstat > 10, " \\checkmark", " \\texttimes{}")
      sprintf("%.2f%s", r$fstat, flag)
    }

    rows <- c(
      sprintf("Engineer (2SLS)   & %s & %s & %s \\\\",
              fmt_coef(r1), fmt_coef(r2), fmt_coef(r3)),
      sprintf("                  & %s & %s & %s \\\\[4pt]",
              fmt_se(r1), fmt_se(r2), fmt_se(r3)),
      sprintf("First-stage $F$   & %s & %s & %s \\\\",
              fmt_f(r1), fmt_f(r2), fmt_f(r3)),
      sprintf("Observations      & %s & %s & %s \\\\",
              format(r1$n, big.mark=","), format(r2$n, big.mark=","),
              format(r3$n, big.mark=","))
    )

    tex <- c(
      "\\begin{table}[htbp]",
      "\\centering",
      sprintf("\\caption{IV Estimates: %s}", out_label),
      "\\label{tab:iv_spec_comparison}",
      "\\begin{tabular}{lccc}",
      "\\hline\\hline",
      paste0("& Spec 1 & Spec 2 & Spec 3 \\\\"),
      paste0("& Dist+Year & Dist+State+Year & Dist+State$\\times$Year \\\\"),
      "\\hline",
      rows,
      "\\hline",
      "District FE       & \\checkmark & \\checkmark & \\checkmark \\\\",
      "Year FE           & \\checkmark & \\checkmark &             \\\\",
      "State FE          &             & \\checkmark &             \\\\",
      "State$\\times$Year FE &        &             & \\checkmark \\\\",
      "\\hline\\hline",
      "\\multicolumn{4}{p{0.75\\textwidth}}{\\footnotesize",
      "\\textit{Notes:} Outcome is instrumented for Engineer (=1 if officer has engineering background) using",
      "Queue\\_st = CM\\_turnover $\\times$ seniority\\_rank\\_std. CM\\_turnover = 1 when incumbent party lost",
      "most recent state election. Seniority rank standardised within cadre (allotment year, ascending).",
      "Clustered SEs at district level. Stars: *** $p<0.01$, ** $p<0.05$, * $p<0.10$.",
      "Spec 3 state$\\times$year FE may absorb CM\\_turnover variation --- see F-statistic.}",
      "\\end{tabular}",
      "\\end{table}"
    )
    writeLines(tex, filename)
    cat(sprintf("  Saved %s\n", filename))
  }

  write_outcome_tex(r1, r2, r3, label,
    sprintf("tables/iv_spec_comparison_%s.tex", gsub("[^a-z]", "_", tolower(var))))
}

cat("\n")

# ─────────────────────────────────────────────────────────────────────────────
# 4. SUMMARY TABLE (one row per outcome × spec)
# ─────────────────────────────────────────────────────────────────────────────

cat("═══ IV SUMMARY TABLE ═══\n")
cat(sprintf("%-30s %-28s  %8s  %8s  %8s  %6s\n",
    "Outcome", "Spec", "Enginr", "SE", "p", "F-stat"))
cat(strrep("-", 90), "\n")

summary_rows <- list()
for (var in names(all_results)) {
  for (i in 1:nrow(all_results[[var]])) {
    r <- all_results[[var]][i,]
    fpass <- ifelse(!is.na(r$fstat) & r$fstat > 10, "PASS", "FAIL")
    cat(sprintf("%-30s %-28s  %+8.4f  %8.4f  %8.3f  %5s [%s]\n",
        r$outcome, r$spec, r$coef, r$se, r$pval,
        ifelse(is.na(r$fstat), "NA", sprintf("%.2f", r$fstat)), fpass))
    summary_rows[[length(summary_rows)+1]] <- r
  }
}

# Write summary LaTeX
write_summary_tex <- function(all_results, filename) {
  outcome_order <- c("Road completion rate","Nightlights per capita",
                     "EC employment (all)","Literacy rate")
  spec_short <- c(
    "Spec 1: District+Year"     = "Dist.+Yr",
    "Spec 2: District+State+Year" = "Dist.+St.+Yr",
    "Spec 3: District+StateYear"  = "Dist.+St.$\\times$Yr"
  )

  fmt_cell <- function(r) {
    if (is.na(r$coef)) return("\\multicolumn{2}{c}{---}")
    stars <- ifelse(r$pval < 0.01, "***", ifelse(r$pval < 0.05, "**",
             ifelse(r$pval < 0.10, "*", "")))
    fpass <- ifelse(!is.na(r$fstat) & r$fstat > 10,
                    sprintf("[F=%.1f\\checkmark]", r$fstat),
                    sprintf("[F=%.1f\\texttimes]", ifelse(is.na(r$fstat), 0, r$fstat)))
    sprintf("%.4f%s \\\\ & (%s) \\\\ & {\\tiny %s}", r$coef, stars,
            sprintf("%.4f", r$se), fpass)
  }

  # Build rows: one block per spec (3 rows: coef, se, F-note), columns = outcomes
  tex_rows <- character(0)
  for (skey in names(spec_short)) {
    slabel <- spec_short[[skey]]
    coef_cells <- se_cells <- f_cells <- character(0)
    for (ocl in outcome_order) {
      rd <- all_results[[which(sapply(all_results, function(x) x$outcome[1]) == ocl)]]
      r  <- rd[rd$spec == skey, ]
      if (nrow(r)==0 || is.na(r$coef)) {
        coef_cells <- c(coef_cells, "---"); se_cells <- c(se_cells, "")
        f_cells    <- c(f_cells,    "---")
      } else {
        stars <- ifelse(r$pval < 0.01,"***",ifelse(r$pval<0.05,"**",ifelse(r$pval<0.10,"*","")))
        coef_cells <- c(coef_cells, sprintf("%.4f%s", r$coef, stars))
        se_cells   <- c(se_cells,   sprintf("(%.4f)", r$se))
        fv <- ifelse(is.na(r$fstat), "NA",
                     sprintf("%.2f%s", r$fstat, ifelse(r$fstat>10," \\ding{51}"," \\ding{55}")))
        f_cells <- c(f_cells, fv)
      }
    }
    tex_rows <- c(tex_rows,
      sprintf("\\multirow{3}{*}{\\textit{%s}}", slabel),
      paste0("& Engineer  & ", paste(coef_cells, collapse=" & "), " \\\\"),
      paste0("&            & ", paste(se_cells,   collapse=" & "), " \\\\"),
      paste0("& 1st-Stg $F$ & ", paste(f_cells,  collapse=" & "), " \\\\[6pt]")
    )
  }

  # Simpler version: one row per outcome per spec, outcomes as columns
  # Columns: spec | roads_rate | lights_rural | ec_emp_all | lit_rate
  header_labs <- c("Roads Rate","Nightlights pc","EC Employment","Literacy")

  rows <- c()
  for (skey in names(spec_short)) {
    slabel <- spec_short[[skey]]
    coef_parts <- character(0)
    n_parts    <- character(0)
    f_parts    <- character(0)
    for (ocl in outcome_order) {
      rd_list <- all_results[sapply(all_results, function(x) x$outcome[1]) == ocl]
      if (length(rd_list)==0) {
        coef_parts <- c(coef_parts, "---"); f_parts <- c(f_parts, "---")
        n_parts <- c(n_parts, "---"); next
      }
      rd <- rd_list[[1]]
      r  <- rd[rd$spec == skey, ]
      if (nrow(r)==0 || is.na(r$coef)) {
        coef_parts <- c(coef_parts, "---"); f_parts <- c(f_parts, "---")
        n_parts <- c(n_parts, "---"); next
      }
      stars <- ifelse(r$pval<0.01,"***",ifelse(r$pval<0.05,"**",ifelse(r$pval<0.10,"*","")))
      coef_parts <- c(coef_parts,
        sprintf("\\makecell{%.4f%s\\\\(%.4f)}", r$coef, stars, r$se))
      fv <- ifelse(is.na(r$fstat),"---",
              sprintf("%.2f%s", r$fstat, ifelse(r$fstat>10," \\checkmark"," \\times")))
      f_parts <- c(f_parts, fv)
      n_parts <- c(n_parts, format(r$n, big.mark=","))
    }
    rows <- c(rows,
      sprintf("\\midrule\n\\multicolumn{5}{l}{\\textit{%s}} \\\\", slabel),
      paste0("Engineer (IV) & ", paste(coef_parts, collapse=" & "), " \\\\"),
      paste0("First-stage $F$ & ", paste(f_parts, collapse=" & "), " \\\\"),
      paste0("$N$ & ", paste(n_parts, collapse=" & "), " \\\\")
    )
  }

  tex <- c(
    "\\begin{table}[htbp]",
    "\\centering",
    "\\caption{IV Summary: Engineer Effect Under Three FE Specifications}",
    "\\label{tab:iv_summary}",
    "\\begin{tabular}{lcccc}",
    "\\toprule",
    paste0("& ", paste(header_labs, collapse=" & "), " \\\\"),
    rows,
    "\\bottomrule",
    "\\multicolumn{5}{p{\\linewidth}}{\\footnotesize",
    "\\textit{Notes:} IV estimates using Queue\\_st $=$ CM\\_turnover $\\times$ seniority\\_rank\\_std as instrument",
    "for Engineer dummy. Baseline: SocialScientist. Clustered SEs at district level in parentheses.",
    "\\checkmark: $F>10$ (instrument strong); $\\times$: $F\\leq 10$ (weak instrument).",
    "Spec 3 state$\\times$year FE absorbs CM\\_turnover state-year variation, reducing instrument power.}",
    "\\end{tabular}",
    "\\end{table}"
  )
  writeLines(tex, filename)
  cat(sprintf("\nSaved %s\n", filename))
}

write_summary_tex(all_results, "tables/iv_summary.tex")
cat("\nDone. All IV tables written to tables/\n")
