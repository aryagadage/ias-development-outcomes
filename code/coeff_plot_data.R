# ============================================================
#  code/coeff_plot_data.R
#  Computes the Engineer coefficient (Spec 3: district + additive
#  state + year FE, controls, cluster district) on the standardised
#  outcome, for the three headline outcomes -- using the exact same
#  data, sample, control set, FE structure, and estimator (fixest)
#  as tables/R1_infra.tex, tables/R1_lights.tex, tables/R1_welfare.tex.
#  Written so code/coeff_plot.py can plot table-consistent numbers
#  instead of recomputing them under a different spec.
#  Output: diagnostics/coeff_plot_spec3.csv
# ============================================================
suppressPackageStartupMessages({ library(fixest); library(dplyr) })

dir.create("diagnostics", showWarnings = FALSE)

df <- read.csv("data/analysis/dc_analysis_v2.csv", stringsAsFactors = FALSE)
df$state_id    <- formatC(as.integer(df$state_id), width = 2, flag = "0")
df$district_id <- as.character(df$district_id)
df$emp_pc      <- df$ec_emp_all / df$tot_p
df$year_fac    <- as.character(df$year)

outcomes <- list(
  list(var = "roads_rate",   label = "Road completion rate\n(PMGSY, 2001-2008)",
       data = df[!is.na(df$roads_rate) & df$year >= 2001, ]),
  list(var = "lights_rural", label = "Nightlights per capita\n(DMSP, 1994-2008)",
       data = df[!is.na(df$lights_rural), ]),
  list(var = "emp_pc",       label = "EC employment per capita\n(1994-2008)",
       data = df[!is.na(df$emp_pc), ])
)

fe_spec3 <- "district_id + state_id + year_fac"
ctrl     <- "Residual + allotment_year + tenure_months + opposition_turnover"
CI_Z     <- 1.645  # 90% two-sided

rows <- list()
for (oc in outcomes) {
  d  <- oc$data
  sd_y <- sd(d[[oc$var]], na.rm = TRUE)
  d$y_std <- (d[[oc$var]] - mean(d[[oc$var]], na.rm = TRUE)) / sd_y

  fml <- as.formula(paste("y_std ~ Engineer +", ctrl, "|", fe_spec3))
  fit <- feols(fml, data = d, cluster = ~district_id)

  b  <- coef(fit)["Engineer"]; se <- se(fit)["Engineer"]; p <- pvalue(fit)["Engineer"]
  n  <- nobs(fit)
  cat(sprintf("%-32s beta=%+.4f  SE=%.4f  p=%.4f  N=%d\n", oc$var, b, se, p, n))

  rows[[length(rows) + 1]] <- data.frame(
    var = oc$var, label = oc$label,
    coef = as.numeric(b), se = as.numeric(se), pval = as.numeric(p), n = n,
    ci_lo = as.numeric(b - CI_Z * se), ci_hi = as.numeric(b + CI_Z * se),
    stringsAsFactors = FALSE
  )
}

out <- do.call(rbind, rows)
write.csv(out, "diagnostics/coeff_plot_spec3.csv", row.names = FALSE)
cat("\nSaved diagnostics/coeff_plot_spec3.csv\n")
