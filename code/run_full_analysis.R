# ============================================================
#  run_full_analysis.R
#  Comprehensive analysis: R0–R6 as specified.
#  Input : data/analysis/dc_analysis_v2.csv
#           data/analysis/QueueT_st.csv
#  Output: tables/ (multiple .tex), diagnostics/ (summary prints)
# ============================================================
suppressPackageStartupMessages({
  library(fixest)
  library(dplyr)
})

dir.create("tables",      showWarnings = FALSE)
dir.create("diagnostics", showWarnings = FALSE)

# ── 0. LOAD & PREPARE ────────────────────────────────────────────────────────

df <- read.csv("data/analysis/dc_analysis_v2.csv", stringsAsFactors = FALSE)
qt <- read.csv("data/analysis/QueueT_st.csv",      stringsAsFactors = FALSE,
               colClasses = c(state_id = "character"))

# state_id padding
df$state_id <- formatC(as.integer(df$state_id), width = 2, flag = "0")
df$district_id <- as.character(df$district_id)

# Derived variables
df$years_of_service <- df$year - df$allotment_year
df$emp_pc           <- df$ec_emp_all / df$tot_p

# Merge QueueT_st
df <- left_join(df, qt, by = c("state_id", "year"))

# State-year factor for FEs
df$state_year <- paste0(df$state_id, "_", df$year)
df$year_fac   <- as.character(df$year)

# For roads: restrict to year >= 2001 sub-sample
df_roads <- df[!is.na(df$roads_rate) & df$year >= 2001, ]
df_lights <- df[!is.na(df$lights_rural), ]
df_emp    <- df[!is.na(df$emp_pc), ]

# Control sets
ctrl_base <- ~ allotment_year + tenure_months + opposition_turnover


# ============================================================
# R0  DIAGNOSTICS
# ============================================================

cat("\n", strrep("=", 60), "\n")
cat("R0  DIAGNOSTICS\n")
cat(strrep("=", 60), "\n")

## (a) years_of_service distribution
ys <- df$years_of_service[!is.na(df$years_of_service)]
iqr_ys <- quantile(ys, .75) - quantile(ys, .25)

cat("\n(a) years_of_service (= year - allotment_year, proxy for IAS career seniority)\n")
cat(sprintf("  Mean   = %5.1f\n",                 mean(ys)))
cat(sprintf("  Median = %5.1f\n",               median(ys)))
cat(sprintf("  SD     = %5.1f\n",                   sd(ys)))
cat(sprintf("  p10    = %5.1f   p25 = %5.1f\n",
            quantile(ys,.10), quantile(ys,.25)))
cat(sprintf("  p75    = %5.1f   p90 = %5.1f\n",
            quantile(ys,.75), quantile(ys,.90)))
cat(sprintf("  IQR    = %5.1f years\n", iqr_ys))

prop4_runnable <- iqr_ys >= 4
if (!prop4_runnable) {
  cat("  FLAG: IQR < 4 — Proposition 4 (tenure interaction) UNDERPOWERED\n")
} else {
  cat("  IQR >= 4 — Proposition 4 runnable\n")
}

## (b) match rate by education category — reported from analysis sample
cat("\n(b) Education distribution in analytic sample (all rows are matched DC-years)\n")
edu_tab <- df %>%
  mutate(group = case_when(Engineer == 1 ~ "Engineer",
                           Residual == 1 ~ "Residual",
                           TRUE ~ "Social Scientist")) %>%
  group_by(group) %>%
  summarise(n = n(), pct = n() / nrow(df) * 100) %>%
  arrange(desc(n))
print(as.data.frame(edu_tab))

# Differential missingness check: roads by group
miss_roads <- df %>%
  mutate(group = case_when(Engineer==1~"Engineer", Residual==1~"Residual",
                            TRUE~"SocialSci")) %>%
  group_by(group) %>%
  summarise(roads_obs  = sum(!is.na(roads_rate)),
            lights_obs = sum(!is.na(lights_rural)),
            emp_obs    = sum(!is.na(emp_pc)),
            total      = n()) %>%
  mutate(roads_rate_obs = roads_obs / total)
cat("\n  Outcome missingness by education group:\n")
print(as.data.frame(miss_roads))

## (c) Engineer share by year
cat("\n(c) Engineer share of DC pool by year:\n")
eng_by_yr <- df %>%
  group_by(year) %>%
  summarise(Engineer_share = mean(Engineer), n = n())
print(as.data.frame(eng_by_yr))

# Save Figure 1 data
write.csv(eng_by_yr, "diagnostics/R0c_engineer_share_by_year.csv", row.names=FALSE)

## (d) Sample counts
cat("\n(d) Sample size summary:\n")
cat(sprintf("  N obs (obs)                : %d\n",  nrow(df)))
cat(sprintf("  N districts                : %d\n",  n_distinct(df$district_id)))
cat(sprintf("  N state-years              : %d\n",  n_distinct(df$state_year)))
cat(sprintf("  N officer-district-years   : %d\n",  nrow(df)))  # 1 DC per d-t
cat(sprintf("  Mean obs per district      : %.1f\n", nrow(df)/n_distinct(df$district_id)))
cat(sprintf("  N roads-sample obs         : %d\n",  nrow(df_roads)))
cat(sprintf("  N lights-sample obs        : %d\n",  nrow(df_lights)))
cat(sprintf("  N employment-sample obs    : %d\n",  nrow(df_emp)))
cat(sprintf("  QueueT_st matched          : %d (%.1f%%)\n",
            sum(!is.na(df$QueueT_st)), 100*mean(!is.na(df$QueueT_st))))


# ============================================================
# R1  FE LADDER — OLS
# ============================================================

cat("\n", strrep("=", 60), "\n")
cat("R1  FE LADDER (OLS)\n")
cat(strrep("=", 60), "\n")

fe_specs <- list(
  "(1) dist"            = ~ district_id,
  "(2) dist+yr"         = ~ district_id + year_fac,
  "(3) dist+state+yr"   = ~ district_id + state_id + year_fac,
  "(4) dist+state×yr"   = ~ district_id + state_year
)

rhs <- ~ Engineer + Residual + allotment_year + tenure_months + opposition_turnover

outcomes <- list(
  infra  = list(y = "roads_rate",  data = df_roads,  label = "Roads rate"),
  lights = list(y = "lights_rural", data = df_lights, label = "Nightlights"),
  welfare= list(y = "emp_pc",      data = df_emp,    label = "Emp/capita")
)

r1_coefs <- list()  # collect for master table

for (out_nm in names(outcomes)) {
  oc <- outcomes[[out_nm]]
  cat(sprintf("\n  %s\n", oc$label))
  cat(sprintf("  %-25s %8s %8s %8s %8s\n",
              "", "(1)", "(2)", "(3)", "(4)"))
  cat(sprintf("  %-25s %s\n", "", strrep("-", 35)))
  for (grp in c("Engineer","Residual")) {
    row_vals <- character(4)
    for (i in seq_along(fe_specs)) {
      fml <- as.formula(paste(oc$y, "~",
                               paste(c("Engineer","Residual",
                                       "allotment_year","tenure_months",
                                       "opposition_turnover"),
                                     collapse = " + "),
                               "| 0 +", deparse(fe_specs[[i]][[2]])))
      fit <- tryCatch(
        feols(fml, data = oc$data, cluster = ~district_id),
        error = function(e) NULL)
      if (is.null(fit)) { row_vals[i] <- "  err "; next }
      b  <- coef(fit)[grp]
      se <- se(fit)[grp]
      p  <- pvalue(fit)[grp]
      stars <- ifelse(is.na(p), "", ifelse(p < .01, "***", ifelse(p < .05, "**", ifelse(p < .10, "*", ""))))
      row_vals[i] <- sprintf("%6.4f%s", b, stars)
      # store for master table
      r1_coefs[[paste(out_nm, names(fe_specs)[i], grp, sep="|")]] <-
        c(b=b, se=se, p=p)
    }
    cat(sprintf("  %-25s %s\n", grp,
                paste(sprintf("%8s", row_vals), collapse="")))
  }
}

cat("\n  Note: *** p<0.01, ** p<0.05, * p<0.10; SE clustered at district.\n")
cat("  PURPOSE: show whether coefficient is present at (1)-(2) and absorbed at (4).\n")


# ============================================================
# R2  JOINT SIGN-CONTRAST TEST
# ============================================================

cat("\n", strrep("=", 60), "\n")
cat("R2  JOINT SIGN-CONTRAST TEST\n")
cat(strrep("=", 60), "\n")

# Build stacked dataset: roads (infra) vs emp_pc (welfare), 2001-2008
df_inf <- df_roads %>%
  filter(!is.na(roads_rate)) %>%
  mutate(y_raw = roads_rate, k = "infra", infra_k = 1L)

df_welf <- df %>%
  filter(!is.na(emp_pc), year >= 2001) %>%
  mutate(y_raw = emp_pc, k = "welfare", infra_k = 0L)

# Standardise within k
std <- function(x) (x - mean(x, na.rm=TRUE)) / sd(x, na.rm=TRUE)
df_inf$y_std  <- std(df_inf$y_raw)
df_welf$y_std <- std(df_welf$y_raw)

stk <- bind_rows(df_inf, df_welf)
stk$infra_k   <- as.integer(stk$infra_k)
stk$did_k     <- paste0(stk$district_id, "_", stk$infra_k)  # district × k FE
stk$styr_k    <- paste0(stk$state_year, "_", stk$infra_k)   # state×yr × k

cat("\n  Stacked sample:\n")
cat(sprintf("  k=infra  (roads):   %d obs, %d districts\n",
            nrow(df_inf), n_distinct(df_inf$district_id)))
cat(sprintf("  k=welfare (emp_pc): %d obs, %d districts\n",
            nrow(df_welf), n_distinct(df_welf$district_id)))
cat(sprintf("  Combined:           %d obs\n", nrow(stk)))

## Version A — stacked regression, two FE specs
# Spec (3): district×k + state + year + k FEs
# Spec (4): district×k + state×year + k FEs

r2a_results <- list()

for (spec_nm in c("(3) add-state","(4) state×yr")) {
  fe_part <- if (spec_nm == "(3) add-state")
    "did_k + state_id + year_fac + infra_k"
  else
    "did_k + state_year + infra_k"

  fml <- as.formula(paste(
    "y_std ~ Engineer + Engineer:infra_k + Residual + Residual:infra_k",
    "+ allotment_year + tenure_months + opposition_turnover |", fe_part))

  fit <- tryCatch(
    feols(fml, data = stk, cluster = ~district_id),
    error = function(e) { cat("  R2A error:", conditionMessage(e), "\n"); NULL })

  if (!is.null(fit)) {
    b_int   <- coef(fit)["Engineer:infra_k"]
    se_int  <- se(fit)["Engineer:infra_k"]
    p_int   <- pvalue(fit)["Engineer:infra_k"]
    b_eng   <- coef(fit)["Engineer"]
    se_eng  <- se(fit)["Engineer"]
    p_eng   <- pvalue(fit)["Engineer"]
    r2a_results[[spec_nm]] <- fit
    cat(sprintf("\n  Version A  %s\n", spec_nm))
    cat(sprintf("  Engineer (welfare baseline)    : %7.5f  SE=%7.5f  p=%.3f\n",
                b_eng, se_eng, p_eng))
    cat(sprintf("  Engineer×infra_k (COMP. ADV.)  : %7.5f  SE=%7.5f  p=%.3f  %s\n",
                b_int, se_int, p_int,
                if (!is.na(p_int) && p_int < .10) "***HEADLINE***" else ""))
  }
}

## Version B — separate OLS + Wald chi2 (cross-equation equality test)
cat("\n  Version B  Wald test H0: beta_Eng^infra = beta_Eng^welfare\n")

for (spec_nm in c("(3) add-state","(4) state×yr")) {
  fe_i <- if (spec_nm == "(3) add-state") "district_id + state_id + year_fac"
          else "district_id + state_year"

  fit_inf  <- tryCatch(
    feols(as.formula(paste("y_std ~ Engineer + Residual + allotment_year +",
                           "tenure_months + opposition_turnover |", fe_i)),
          data = df_inf,  cluster = ~district_id), error = function(e) NULL)
  fit_welf <- tryCatch(
    feols(as.formula(paste("y_std ~ Engineer + Residual + allotment_year +",
                           "tenure_months + opposition_turnover |", fe_i)),
          data = df_welf, cluster = ~district_id), error = function(e) NULL)

  if (!is.null(fit_inf) && !is.null(fit_welf)) {
    b1 <- coef(fit_inf)["Engineer"];  se1 <- se(fit_inf)["Engineer"]
    b2 <- coef(fit_welf)["Engineer"]; se2 <- se(fit_welf)["Engineer"]
    chi2 <- (b1 - b2)^2 / (se1^2 + se2^2)
    p_wald <- pchisq(chi2, df = 1, lower.tail = FALSE)
    cat(sprintf("  %s\n", spec_nm))
    cat(sprintf("    beta_Eng^infra  = %7.5f (SE=%7.5f)\n", b1, se1))
    cat(sprintf("    beta_Eng^welfare= %7.5f (SE=%7.5f)\n", b2, se2))
    cat(sprintf("    Wald chi2(1)    = %6.3f   p = %.4f  %s\n",
                chi2, p_wald,
                if (!is.na(p_wald) && p_wald < .10) "** sign contrast **" else ""))
  }
}


# ============================================================
# R3  IV / 2SLS
# ============================================================

cat("\n", strrep("=", 60), "\n")
cat("R3  IV / 2SLS (instrument = QueueT_st)\n")
cat(strrep("=", 60), "\n")

cat("
  NOTE: QueueT_st varies at state×year level.
  Under state×year FEs (spec a), ALL state-year variation is absorbed
  — including QueueT_st. This is mechanical, not a researcher choice.
  Specs (b) district+state+year and (c) district+year allow identification.\n")

df_iv   <- df[!is.na(df$QueueT_st), ]
df_iv_r <- df_iv[!is.na(df_iv$roads_rate) & df_iv$year >= 2001, ]
df_iv_l <- df_iv[!is.na(df_iv$lights_rural), ]
df_iv_e <- df_iv[!is.na(df_iv$emp_pc), ]

iv_specs <- list(
  "(a) dist+state×yr [ABSORBED]"  = "district_id + state_year",
  "(b) dist+state+yr [USE THIS]"  = "district_id + state_id + year_fac",
  "(c) dist+yr"                   = "district_id + year_fac"
)

r3_first_stage <- list()

cat("\n  First stage: Engineer ~ QueueT_st + controls | [FE]\n")
cat(sprintf("  %-35s %10s %10s %10s\n", "FE spec", "delta", "KP-F", "N"))
cat(sprintf("  %-35s %s\n", "", strrep("-",32)))

for (spec_nm in names(iv_specs)) {
  fe_str <- iv_specs[[spec_nm]]
  fml_fs <- as.formula(paste(
    "Engineer ~ QueueT_st + allotment_year + tenure_months + opposition_turnover |",
    fe_str))
  fit_fs <- tryCatch(
    feols(fml_fs, data = df_iv, cluster = ~district_id),
    error = function(e) NULL)
  if (is.null(fit_fs)) { cat(sprintf("  %-35s  ERROR\n", spec_nm)); next }

  delta  <- coef(fit_fs)["QueueT_st"]
  f_stat <- fitstat(fit_fs, "f")[[1]]$stat   # robust F on first-stage instrument
  r3_first_stage[[spec_nm]] <- fit_fs
  cat(sprintf("  %-35s %10.4f %10.3f %10d\n",
              spec_nm, delta, f_stat, nobs(fit_fs)))
}

cat("\n  2SLS results for specs with usable first stage:\n")

r3_2sls <- list()

safe_kp <- function(fit) {
  # For just-identified IV, KP-F = first-stage F (clustered)
  tryCatch(
    fitstat(fit$iv_first_stage[["Engineer"]], "f")$f$stat,
    error = function(e) NA_real_)
}

for (spec_nm in c("(b) dist+state+yr [USE THIS]","(c) dist+yr")) {
  fe_str <- iv_specs[[spec_nm]]
  for (out_nm in names(outcomes)) {
    oc    <- outcomes[[out_nm]]
    dat_s <- switch(out_nm,
                    infra  = df_iv_r,
                    lights = df_iv_l,
                    welfare= df_iv_e)
    if (nrow(dat_s) == 0) next
    # Include Residual in exogenous controls
    fml_2s <- as.formula(paste(
      oc$y, "~ Residual + allotment_year + tenure_months + opposition_turnover |",
      fe_str, "| Engineer ~ QueueT_st"))
    # Try district clustering; fall back to HC1 if vcov fails
    fit_2s <- tryCatch(
      feols(fml_2s, data = dat_s, cluster = ~district_id),
      error = function(e) tryCatch(
        feols(fml_2s, data = dat_s, vcov = "hetero"),
        error = function(e2) NULL))
    if (is.null(fit_2s)) next
    b  <- tryCatch(coef(fit_2s)["fit_Engineer"],   error = function(e) NA_real_)
    se <- tryCatch(se(fit_2s)["fit_Engineer"],     error = function(e) NA_real_)
    p  <- tryCatch(pvalue(fit_2s)["fit_Engineer"], error = function(e) NA_real_)
    kp <- safe_kp(fit_2s)
    r3_2sls[[paste(spec_nm, out_nm, sep="|")]] <- fit_2s
    cat(sprintf("  2SLS %s | %-10s : beta=%8.5f SE=%8.5f p=%.3f  KP-F=%.2f  N=%d\n",
                spec_nm, oc$label, b, se, p, kp, nobs(fit_2s)))
  }
}


# ============================================================
# R4  ELECTION-CONTROL SENSITIVITY
# ============================================================

cat("\n", strrep("=", 60), "\n")
cat("R4  ELECTION-CONTROL SENSITIVITY\n")
cat(strrep("=", 60), "\n")

cat("
  Concern: opposition_turnover is both a control and correlated with
  the instrument (QueueT_st varies after political turnover). Dropping
  the election control tests whether IV power and sign-contrast are
  driven by this variable.\n")

# R2A spec (3) with and without election control
for (with_elec in c(TRUE, FALSE)) {
  ctrl_str <- if (with_elec) "allotment_year + tenure_months + opposition_turnover"
              else            "allotment_year + tenure_months"
  fe_str <- "did_k + state_id + year_fac + infra_k"
  fml <- as.formula(paste(
    "y_std ~ Engineer + Engineer:infra_k + Residual + Residual:infra_k +",
    ctrl_str, "|", fe_str))
  fit <- tryCatch(feols(fml, data=stk, cluster=~district_id), error=function(e) NULL)
  if (is.null(fit)) next
  b  <- coef(fit)["Engineer:infra_k"]
  se <- se(fit)["Engineer:infra_k"]
  p  <- pvalue(fit)["Engineer:infra_k"]
  cat(sprintf("  R2A spec(3) %-20s: Eng×infra_k = %7.5f (SE=%7.5f, p=%.3f)\n",
              if (with_elec) "WITH election ctrl" else "WITHOUT election ctrl",
              b, se, p))
}

cat("\n")

# R3 first stage with and without election control
for (with_elec in c(TRUE, FALSE)) {
  ctrl_str <- if (with_elec) "allotment_year + tenure_months + opposition_turnover"
              else            "allotment_year + tenure_months"
  fml_fs <- as.formula(paste(
    "Engineer ~ QueueT_st +", ctrl_str, "| district_id + state_id + year_fac"))
  fit_fs <- tryCatch(feols(fml_fs, data=df_iv, cluster=~district_id), error=function(e) NULL)
  if (is.null(fit_fs)) next
  delta  <- coef(fit_fs)["QueueT_st"]
  f_stat <- fitstat(fit_fs, "f")[[1]]$stat
  cat(sprintf("  R3 first-stage %-20s: delta=%7.4f  F=%.3f  N=%d\n",
              if (with_elec) "WITH election ctrl" else "WITHOUT election ctrl",
              delta, f_stat, nobs(fit_fs)))
}


# ============================================================
# R5  TENURE INTERACTION (Prop 4) — conditional on R0
# ============================================================

cat("\n", strrep("=", 60), "\n")
cat("R5  TENURE INTERACTION\n")
cat(strrep("=", 60), "\n")

if (!prop4_runnable) {
  cat("  SKIP: R0(a) flagged IQR < 4 years — underpowered.\n")
} else {
  df$tenure_years <- df$tenure_months / 12

  for (out_nm in c("infra","welfare")) {
    oc  <- outcomes[[out_nm]]
    dat <- switch(out_nm, infra = df_roads, welfare = df_emp)
    if (!"tenure_years" %in% names(dat)) dat$tenure_years <- dat$tenure_months / 12

    # Continuous interaction
    fml_c <- as.formula(paste(
      oc$y, "~ Engineer + Engineer:tenure_years +",
      "Residual + Residual:tenure_years +",
      "allotment_year + opposition_turnover | district_id + state_year"))
    fit_c <- tryCatch(feols(fml_c, data=dat, cluster=~district_id), error=function(e) NULL)

    if (!is.null(fit_c)) {
      b_eng  <- coef(fit_c)["Engineer"]
      b_int  <- coef(fit_c)["Engineer:tenure_years"]
      se_int <- se(fit_c)["Engineer:tenure_years"]
      p_int  <- pvalue(fit_c)["Engineer:tenure_years"]
      cat(sprintf("\n  %s  (continuous tenure interaction)\n", oc$label))
      cat(sprintf("  Engineer main       : %8.5f\n", b_eng))
      cat(sprintf("  Engineer:tenure_yrs : %8.5f  SE=%8.5f  p=%.3f\n",
                  b_int, se_int, p_int))
      cat(sprintf("  Prediction: infra main>0, interaction<0 (effect fades): %s\n",
                  if (out_nm == "infra")
                    ifelse(b_eng > 0 && b_int < 0, "CONFIRMED", "NOT CONFIRMED")
                  else "welfare check (no directional prediction)"))
    }

    # Tercile (non-parametric)
    dat$tenure_tercile <- ntile(dat$tenure_years, 3)
    fml_t <- as.formula(paste(
      oc$y, "~ Engineer:factor(tenure_tercile) +",
      "Residual:factor(tenure_tercile) +",
      "allotment_year + opposition_turnover | district_id + state_year"))
    fit_t <- tryCatch(feols(fml_t, data=dat, cluster=~district_id), error=function(e) NULL)
    if (!is.null(fit_t)) {
      coefs_t <- coef(fit_t)[grep("Engineer:factor", names(coef(fit_t)))]
      cat(sprintf("  Tercile Engineer coefficients: %s\n",
                  paste(sprintf("T%d=%.4f", 1:3, coefs_t), collapse="  ")))
    }
  }
}


# ============================================================
# R6  RATIO OUTCOME (Prop 1 direct composition test)
# ============================================================

cat("\n", strrep("=", 60), "\n")
cat("R6  RATIO OUTCOME (log-infra minus log-welfare)\n")
cat(strrep("=", 60), "\n")

# Restrict to districts with BOTH infra and welfare observed, 2001-2008
df_both <- df %>%
  filter(!is.na(roads_rate), !is.na(emp_pc), year >= 2001)

cat(sprintf("  N obs with BOTH infra & welfare: %d (vs %d infra-only)\n",
            nrow(df_both), nrow(df_roads)))

for (c_val in c(1e-4, 1e-3, 1e-2)) {
  inf_std  <- std(df_both$roads_rate)
  welf_std <- std(df_both$emp_pc)
  df_both$ratio_log <- log(inf_std - min(inf_std) + c_val) -
                       log(welf_std - min(welf_std) + c_val)
  fit_r <- tryCatch(
    feols(ratio_log ~ Engineer + Residual + allotment_year + tenure_months +
            opposition_turnover | district_id + state_year,
          data = df_both, cluster = ~district_id),
    error = function(e) NULL)
  if (!is.null(fit_r)) {
    b  <- coef(fit_r)["Engineer"]
    se <- se(fit_r)["Engineer"]
    p  <- pvalue(fit_r)["Engineer"]
    cat(sprintf("  c = %.0e  : Engineer = %8.5f (SE=%8.5f, p=%.3f)  N=%d  %s\n",
                c_val, b, se, p, nobs(fit_r),
                if (!is.na(b) && b > 0) "+ [expected]" else ""))
  }
}


# ============================================================
# MASTER TABLE — LaTeX output
# ============================================================

cat("\n", strrep("=", 60), "\n")
cat("MASTER TABLE (LaTeX)\n")
cat(strrep("=", 60), "\n")

# Collect key results
collect <- function(fit, var, label, spec, outcome) {
  if (is.null(fit)) return(NULL)
  b  <- tryCatch(coef(fit)[var],   error=function(e) NA)
  se <- tryCatch(se(fit)[var],     error=function(e) NA)
  p  <- tryCatch(pvalue(fit)[var], error=function(e) NA)
  n  <- tryCatch(nobs(fit),        error=function(e) NA)
  data.frame(label=label, spec=spec, outcome=outcome, b=b, se=se, p=p, n=n,
             stringsAsFactors=FALSE)
}

stars <- function(p) ifelse(is.na(p), "", ifelse(p<.01,"^{***}", ifelse(p<.05,"^{**}", ifelse(p<.10,"^{*}",""))))
fmt   <- function(b, se, p) sprintf("$%s%.5f%s$ \\\\ $(%0.5f)$", ifelse(!is.na(b)&b<0,"",""), b, stars(p), se)

# R1: spectrum across FE specs, infra + welfare + lights (spec 3 only for master)
# R2: comparative advantage parameter
# R3: 2SLS Engineer, spec (b), infra
# Save etable outputs for individual blocks

# ── Individual block tables via etable ────────────────────────────────────────

# R1 per outcome
for (out_nm in names(outcomes)) {
  oc <- outcomes[[out_nm]]
  fits_r1 <- list()
  for (i in seq_along(fe_specs)) {
    fe_str <- deparse(fe_specs[[i]][[2]])
    fml <- as.formula(paste(oc$y, "~",
                             "Engineer + Residual + allotment_year + tenure_months +",
                             "opposition_turnover | 0 +", fe_str))
    fits_r1[[names(fe_specs)[i]]] <- tryCatch(
      feols(fml, data = oc$data, cluster = ~district_id),
      error = function(e) NULL)
  }
  valid <- fits_r1[!sapply(fits_r1, is.null)]
  if (length(valid) > 0) {
    sink_file <- paste0("tables/R1_", out_nm, ".tex")
    etable(valid,
           keep = c("Engineer","Residual"),
           se.below = TRUE, signif.code = c("***"=.01,"**"=.05,"*"=.10),
           tex = TRUE, file = sink_file, replace = TRUE,
           title = paste("R1 FE Ladder —", oc$label))
    cat(sprintf("  Saved %s\n", sink_file))
  }
}

# R2A stacked: comparative advantage
if (length(r2a_results) > 0) {
  etable(r2a_results,
         keep = c("Engineer","Engineer:infra_k","Residual","Residual:infra_k"),
         se.below = TRUE, signif.code = c("***"=.01,"**"=.05,"*"=.10),
         tex = TRUE, file = "tables/R2A_sign_contrast.tex", replace = TRUE,
         title = "R2A Joint Sign-Contrast (Comparative Advantage Test)")
  cat("  Saved tables/R2A_sign_contrast.tex\n")
}

# R3 first stage
if (length(r3_first_stage) > 0) {
  valid_fs <- r3_first_stage[!sapply(r3_first_stage, is.null)]
  if (length(valid_fs) > 0) {
    etable(valid_fs,
           keep = "QueueT_st",
           se.below = TRUE, signif.code = c("***"=.01,"**"=.05,"*"=.10),
           tex = TRUE, file = "tables/R3_first_stage.tex", replace = TRUE,
           title = "R3 First Stage: QueueT\\_st Predicts Engineer")
    cat("  Saved tables/R3_first_stage.tex\n")
  }
}

# ── MASTER TABLE (manual LaTeX) ───────────────────────────────────────────────

# Collect headline rows: R1 spec(3), R2A, R3 2SLS
master_rows <- list()

for (out_nm in names(outcomes)) {
  oc  <- outcomes[[out_nm]]
  dat <- switch(out_nm, infra=df_roads, lights=df_lights, welfare=df_emp)
  fe_str <- "district_id + state_id + year_fac"
  fml <- as.formula(paste(oc$y,
    "~ Engineer + Residual + allotment_year + tenure_months +",
    "opposition_turnover | 0 +", fe_str))
  fit <- tryCatch(feols(fml, data=dat, cluster=~district_id), error=function(e) NULL)
  if (!is.null(fit)) {
    b  <- coef(fit)["Engineer"]
    se <- se(fit)["Engineer"]
    p  <- pvalue(fit)["Engineer"]
    master_rows[[length(master_rows)+1]] <- list(
      row = out_nm, spec = "R1 Spec(3)",
      b=b, se=se, p=p, n=nobs(fit))
  }
}

# R2A sign contrast (spec 3)
if ("(3) add-state" %in% names(r2a_results)) {
  fit <- r2a_results[["(3) add-state"]]
  b  <- coef(fit)["Engineer:infra_k"]
  se <- se(fit)["Engineer:infra_k"]
  p  <- pvalue(fit)["Engineer:infra_k"]
  master_rows[[length(master_rows)+1]] <- list(
    row="Comparative advantage (Eng×infra_k)", spec="R2A",
    b=b, se=se, p=p, n=nrow(stk))
}

# R3 2SLS, infra, spec (b)
key_2sls <- "(b) dist+state+yr [USE THIS]|infra"
if (key_2sls %in% names(r3_2sls)) {
  fit <- r3_2sls[[key_2sls]]
  b  <- coef(fit)["fit_Engineer"]
  se <- se(fit)["fit_Engineer"]
  p  <- pvalue(fit)["fit_Engineer"]
  master_rows[[length(master_rows)+1]] <- list(
    row="roads_rate (2SLS)", spec="R3 Spec(b)",
    b=b, se=se, p=p, n=nobs(fit))
}

# Write master LaTeX table
tex_lines <- c(
  "\\begin{table}[htbp]",
  "\\centering",
  "\\caption{Master Results: Engineer Coefficient (Social Scientist Baseline)}",
  "\\label{tab:master}",
  "\\begin{tabular}{llccc}",
  "\\toprule",
  "Analysis & Spec & $\\hat\\beta_{\\text{Eng}}$ & SE & $p$ \\\\",
  "\\midrule"
)

for (rw in master_rows) {
  st <- ifelse(!is.na(rw$p) & rw$p < .01, "^{***}",
         ifelse(!is.na(rw$p) & rw$p < .05, "^{**}",
          ifelse(!is.na(rw$p) & rw$p < .10, "^{*}", "")))
  b_fmt  <- if (!is.na(rw$b))  sprintf("$%.5f%s$", rw$b, st) else "---"
  se_fmt <- if (!is.na(rw$se)) sprintf("$(%.5f)$", rw$se)    else ""
  p_fmt  <- if (!is.na(rw$p))  sprintf("%.3f", rw$p)          else "---"
  tex_lines <- c(tex_lines,
    sprintf("%s & %s & %s & %s & %s \\\\",
            rw$row, rw$spec, b_fmt, se_fmt, p_fmt))
}

tex_lines <- c(tex_lines,
  "\\bottomrule",
  "\\end{tabular}",
  "\\par\\vspace{4pt}{\\footnotesize",
  "Baseline: Social Scientist DCs. Controls: allotment year, tenure (months),",
  "election indicator (opposition turnover). SE clustered at district.",
  "R1: OLS with district + additive state + year FEs.",
  "R2A: stacked infra/welfare with district$\\times$k + state + year + k FEs;",
  "  coefficient shown is Engineer$\\times$infra\\_k (comparative-advantage parameter).",
  "R3: 2SLS; instrument = QueueT\\_st (Engineer share of state-year DC pool);",
  "  state$\\times$year FE mechanically absorbs QueueT\\_st --- uses additive FEs.",
  "$^{*}p<0.10$, $^{**}p<0.05$, $^{***}p<0.01$.}",
  "\\end{table}"
)

writeLines(tex_lines, "tables/master_results.tex")
cat("  Saved tables/master_results.tex\n")

cat("\n", strrep("=", 60), "\n")
cat("DONE. Tables written to tables/\n")
cat(strrep("=", 60), "\n")
