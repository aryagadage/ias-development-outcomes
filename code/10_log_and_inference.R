#!/usr/bin/env Rscript
# ============================================================
#  code/10_log_and_inference.R
#  Revision (Oct 2026): log re-estimation of the sign contrast,
#  state-level / few-cluster inference, recalibration of the
#  Appendix E worked example, and sanity checks.
#
#  Mirrors the data prep in run_full_analysis.R (Table 1 = R2A)
#  and run_ideas.R (Table 2). Does NOT modify or overwrite any
#  existing script, table, or figure. All outputs go to
#  output/revision_oct2026/.
#
#  Run from repo root:  Rscript code/10_log_and_inference.R
# ============================================================
suppressPackageStartupMessages({
  library(fixest)
  library(dplyr)
  library(fwildclusterboot)
})

OUT <- "output/revision_oct2026"
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

B_BOOT <- 9999
set.seed(20261006)
dqrng::dqset.seed(20261006)

# ── 0. LOAD & PREPARE (identical to run_full_analysis.R) ─────────────────────

df <- read.csv("data/analysis/dc_analysis_v2.csv", stringsAsFactors = FALSE)
qt <- read.csv("data/analysis/QueueT_st.csv", stringsAsFactors = FALSE,
               colClasses = c(state_id = "character"))

df$state_id         <- formatC(as.integer(df$state_id), width = 2, flag = "0")
df$district_id      <- as.character(df$district_id)
df$years_of_service <- df$year - df$allotment_year
df$emp_pc           <- df$ec_emp_all / df$tot_p
df                  <- left_join(df, qt, by = c("state_id", "year"))
df$state_year       <- paste0(df$state_id, "_", df$year)
df$year_fac         <- as.character(df$year)

ctrl     <- "allotment_year + tenure_months + opposition_turnover"
FE_ADD   <- "district_id + state_id + year_fac"
FE_STYR  <- "district_id + state_year"

# ── Helpers ──────────────────────────────────────────────────────────────────

n_clust <- function(fit, cl) {
  d <- eval(fit$call$data, envir = environment(formula(fit)))
  length(unique(d[[cl]][obs(fit)]))
}

# One tidy row per (fit, coefficient, cluster level)
tidy_row <- function(fit, var, task, spec, outcome, fe_desc, cl, extra = list()) {
  s  <- summary(fit, cluster = as.formula(paste0("~", cl)))
  ct <- coeftable(s)
  if (!var %in% rownames(ct)) {
    b <- se <- p <- lo <- hi <- NA_real_
  } else {
    b  <- ct[var, 1]; se <- ct[var, 2]; p <- ct[var, 4]
    ci <- confint(s, parm = var, level = 0.95)
    lo <- ci[1, 1]; hi <- ci[1, 2]
  }
  data.frame(task = task, spec = spec, outcome = outcome, term = var,
             coef = b, se = se, p = p, ci95_lo = lo, ci95_hi = hi,
             N = nobs(fit), n_clusters = n_clust(fit, cl),
             fixed_effects = fe_desc, cluster = cl,
             extra = if (length(extra)) paste(names(extra), unlist(extra), sep = "=", collapse = "; ") else "",
             stringsAsFactors = FALSE)
}

both_clusters <- function(fit, var, task, spec, outcome, fe_desc, ...) {
  rbind(tidy_row(fit, var, task, spec, outcome, fe_desc, "district_id", ...),
        tidy_row(fit, var, task, spec, outcome, fe_desc, "state_id", ...))
}

# Kleibergen–Paap Wald F for a just-identified IV under a given cluster:
# fixest "ivwald1" = Wald F on the excluded instrument in the first stage
# using the requested (cluster-robust) vcov, i.e. the KP rk Wald F here.
kp_f <- function(fit_iv, cl) {
  s <- summary(fit_iv, cluster = as.formula(paste0("~", cl)))
  as.numeric(fitstat(s, "ivwald1")[[1]]$stat)
}

results <- list()
add <- function(x) results[[length(results) + 1]] <<- x

# ============================================================
# TASK 1a  OUTCOME TRANSFORMATIONS
# ============================================================
cat("\n== TASK 1a: outcome diagnostics ==\n")

df_roads <- df[!is.na(df$roads_rate) & df$year >= 2001, ]
df_welf  <- df[!is.na(df$emp_pc)     & df$year >= 2001, ]

pos_mean <- mean(df_roads$roads_rate[df_roads$roads_rate > 0])
c01      <- 0.01 * pos_mean
c10      <- 0.10 * pos_mean

roads_tf <- list(
  asinh   = function(x) asinh(x),
  logc01  = function(x) log(x + c01),
  logc10  = function(x) log(x + c10),
  log     = function(x) log(x)          # added: feasible because no zeros
)
roads_lbl <- c(asinh = "asinh(roads)", logc01 = "log(roads + 1% mean)",
               logc10 = "log(roads + 10% mean)", log = "log(roads) [no offset]")

w_all <- df$emp_pc[df$year >= 2001]
diag1a <- data.frame(
  item = c("roads_rate: obs in roads estimation sample (yr>=2001, non-missing)",
           "roads_rate: number of zeros", "roads_rate: share zeros",
           "roads_rate: min", "roads_rate: median", "roads_rate: max",
           "roads_rate: mean of positive values",
           "c (1% of positive mean)", "c (10% of positive mean)",
           "roads_rate: district-years yr>=2001 with roads missing",
           "emp_pc: district-years yr>=2001", "emp_pc: missing (yr>=2001)",
           "emp_pc: zeros (yr>=2001)", "emp_pc: min (yr>=2001)",
           "emp_pc: missing (full panel)", "emp_pc: zeros (full panel)"),
  value = c(nrow(df_roads), sum(df_roads$roads_rate == 0),
            mean(df_roads$roads_rate == 0),
            min(df_roads$roads_rate), median(df_roads$roads_rate),
            max(df_roads$roads_rate), pos_mean, c01, c10,
            sum(is.na(df$roads_rate[df$year >= 2001])),
            length(w_all), sum(is.na(w_all)), sum(w_all == 0, na.rm = TRUE),
            min(w_all, na.rm = TRUE),
            sum(is.na(df$emp_pc)), sum(df$emp_pc == 0, na.rm = TRUE)))
print(diag1a, row.names = FALSE)
write.csv(diag1a, file.path(OUT, "task1a_outcome_diagnostics_log.csv"), row.names = FALSE)

# ============================================================
# TASK 1b  STACKED CONTRAST IN LOGS (Table 1 spec, log outcome)
# ============================================================
cat("\n== TASK 1b: stacked contrast in logs ==\n")

build_stack <- function(y_inf, y_welf) {
  a <- df_roads; a$y <- y_inf;  a$infra_k <- 1L
  b <- df_welf;  b$y <- y_welf; b$infra_k <- 0L
  s <- bind_rows(a, b)
  s$did_k  <- paste0(s$district_id, "_", s$infra_k)
  s$styr_k <- paste0(s$state_year,  "_", s$infra_k)
  s
}

t1_fe <- list(
  "(1) did_k + state + year + k" = "did_k + state_id + year_fac + infra_k",
  "(2) did_k + state x year + k" = "did_k + state_year + infra_k")
t1_rhs <- paste("y ~ Engineer + Engineer:infra_k + Residual + Residual:infra_k +", ctrl)

# Replication check: z-scored stack must reproduce Table 1 (0.1412 / 0.1459)
std <- function(x) (x - mean(x, na.rm = TRUE)) / sd(x, na.rm = TRUE)
stk_z <- build_stack(std(df_roads$roads_rate), std(df_welf$emp_pc))
for (nm in names(t1_fe)) {
  f <- feols(as.formula(paste(t1_rhs, "|", t1_fe[[nm]])), data = stk_z)
  add(both_clusters(f, "Engineer:infra_k", "1b", nm, "z-score (Table 1 replication)", t1_fe[[nm]]))
  add(both_clusters(f, "Engineer",         "1b", nm, "z-score (Table 1 replication)", t1_fe[[nm]]))
}

stk_log <- list()
for (rv in names(roads_tf)) {
  stk_log[[rv]] <- build_stack(roads_tf[[rv]](df_roads$roads_rate), log(df_welf$emp_pc))
  stk_cur <- stk_log[[rv]]
  for (nm in names(t1_fe)) {
    f <- feols(as.formula(paste(t1_rhs, "|", t1_fe[[nm]])), data = stk_cur)
    lab <- paste0(roads_lbl[[rv]], " vs log(emp_pc)")
    add(both_clusters(f, "Engineer:infra_k", "1b", nm, lab, t1_fe[[nm]]))
    add(both_clusters(f, "Engineer",         "1b", nm, lab, t1_fe[[nm]]))
  }
}

# ============================================================
# TASK 1c  DIRECT LOG-RATIO REGRESSION (district-year level)
# ============================================================
cat("\n== TASK 1c: direct log-ratio regression ==\n")

df_both <- df[!is.na(df$roads_rate) & !is.na(df$emp_pc) & df$year >= 2001, ]
for (rv in names(roads_tf))
  df_both[[paste0("lr_", rv)]] <- roads_tf[[rv]](df_both$roads_rate) - log(df_both$emp_pc)

lr_fe <- list("district + state x year" = FE_STYR,
              "district + state + year" = FE_ADD)
fits_1c <- list()
for (rv in names(roads_tf)) {
  for (nm in names(lr_fe)) {
    f <- feols(as.formula(paste0("lr_", rv, " ~ Engineer + Residual + ", ctrl, " | ", lr_fe[[nm]])),
               data = df_both)
    fits_1c[[paste(rv, nm, sep = "|")]] <- f
    add(both_clusters(f, "Engineer", "1c", nm, paste0(roads_lbl[[rv]], " - log(emp_pc)"), lr_fe[[nm]]))
  }
}

# ============================================================
# TASK 2a  IV ON THE LOG RATIO (district + additive state + year FE)
# ============================================================
cat("\n== TASK 2a: IV on log ratio ==\n")

df_both_iv <- df_both[!is.na(df_both$QueueT_st), ]
iv_info <- list()
for (rv in names(roads_tf)) {
  y <- paste0("lr_", rv)
  lab <- paste0(roads_lbl[[rv]], " - log(emp_pc)")
  fs <- feols(as.formula(paste("Engineer ~ QueueT_st + Residual +", ctrl, "|", FE_ADD)),
              data = df_both_iv)
  rf <- feols(as.formula(paste(y, "~ QueueT_st + Residual +", ctrl, "|", FE_ADD)),
              data = df_both_iv)
  iv <- feols(as.formula(paste(y, "~ Residual +", ctrl, "|", FE_ADD, "| Engineer ~ QueueT_st")),
              data = df_both_iv)
  for (cl in c("district_id", "state_id")) {
    kp <- kp_f(iv, cl)
    add(tidy_row(fs, "QueueT_st",    "2a", "first stage",  "Engineer", FE_ADD, cl,
                 list(KP_F = round(kp, 2))))
    add(tidy_row(iv, "fit_Engineer", "2a", "2SLS",         lab,        FE_ADD, cl,
                 list(KP_F = round(kp, 2))))
    add(tidy_row(rf, "QueueT_st",    "2a", "reduced form", lab,        FE_ADD, cl))
  }
  iv_info[[rv]] <- list(fs = fs, rf = rf, iv = iv)
}

# ============================================================
# TASK 2b  STACKED IV EQUIVALENT
# ============================================================
cat("\n== TASK 2b: stacked IV ==\n")
# Endogenous: Engineer x infra_k; instrument: QueueT_st x infra_k.
# FE: district-by-class + COMMON state-by-year (absorbs QueueT_st main effect,
# so Engineer main effect enters as an uninstrumented regressor, as instructed).
FE_2B  <- "did_k + state_year"
# Variant: the exact stacked analogue of 2a's FE structure (class-interacted
# additive state and year FE, both-outcome district-years only).
FE_2B2 <- "did_k + state_year + sid_k + yr_k"

for (rv in names(roads_tf)) {
  s <- stk_log[[rv]]
  s$eng_inf <- s$Engineer * s$infra_k
  s$q_inf   <- s$QueueT_st * s$infra_k
  s$res_inf <- s$Residual * s$infra_k
  s$sid_k   <- paste0(s$state_id, "_", s$infra_k)
  s$yr_k    <- paste0(s$year_fac, "_", s$infra_k)
  s <- s[!is.na(s$QueueT_st), ]
  stk_iv <- s
  lab <- paste0(roads_lbl[[rv]], " vs log(emp_pc)")

  iv_b <- feols(as.formula(paste("y ~ Engineer + Residual + res_inf +", ctrl, "|", FE_2B,
                                 "| eng_inf ~ q_inf")), data = stk_iv)
  for (cl in c("district_id", "state_id"))
    add(tidy_row(iv_b, "fit_eng_inf", "2b", "stacked IV: did_k + state_year (as specified)",
                 lab, FE_2B, cl, list(KP_F = round(kp_f(iv_b, cl), 2))))

  # Variant on the balanced (both-observed) stack with interacted controls
  key <- paste(stk_iv$district_id, stk_iv$year)
  both_keys <- paste(df_both_iv$district_id, df_both_iv$year)
  stk_bal <- stk_iv[key %in% both_keys, ]
  for (v in c("allotment_year", "tenure_months", "opposition_turnover"))
    stk_bal[[paste0(v, "_k")]] <- stk_bal[[v]] * stk_bal$infra_k
  iv_b2 <- feols(as.formula(paste(
    "y ~ Engineer + Residual + res_inf +", ctrl,
    "+ allotment_year_k + tenure_months_k + opposition_turnover_k |", FE_2B2,
    "| eng_inf ~ q_inf")), data = stk_bal)
  for (cl in c("district_id", "state_id"))
    add(tidy_row(iv_b2, "fit_eng_inf", "2b",
                 "stacked IV variant: balanced stack, + state x k + year x k FE, controls x k",
                 lab, FE_2B2, cl, list(KP_F = round(kp_f(iv_b2, cl), 2))))
}

# ============================================================
# TASK 2c  RE-CLUSTER THE EXISTING TABLE 2 PANEL B IV (run_ideas.R)
# ============================================================
cat("\n== TASK 2c: existing IV re-clustered ==\n")

zsc <- function(x) (x - mean(x, na.rm = TRUE)) / sd(x, na.rm = TRUE)
d2 <- df
d2$z_roads <- zsc(d2$roads_rate)
d2$z_emp   <- zsc(d2$emp_pc)
i_inf  <- d2 %>% filter(!is.na(roads_rate), year >= 2001) %>%
  mutate(infra_k = 1L, Y_signed = z_roads)
i_welf <- d2 %>% filter(!is.na(emp_pc), year >= 2001) %>%
  mutate(infra_k = 0L, Y_signed = -z_emp)
stk_ideas <- bind_rows(i_inf, i_welf)
stk_ideas$did_k <- paste0(stk_ideas$district_id, "_", stk_ideas$infra_k)
stk_ideas$sid_k <- paste0(stk_ideas$state_id,    "_", stk_ideas$infra_k)
stk_ideas$yr_k  <- paste0(stk_ideas$year_fac,    "_", stk_ideas$infra_k)
FE_IDEAS <- "did_k + sid_k + yr_k"

iv_2c <- feols(as.formula(paste("Y_signed ~ Residual +", ctrl, "|", FE_IDEAS,
                                "| Engineer ~ QueueT_st")), data = stk_ideas)
rf_2c <- feols(as.formula(paste("Y_signed ~ QueueT_st + Residual +", ctrl, "|", FE_IDEAS)),
               data = stk_ideas)
fs_2c <- feols(as.formula(paste("Engineer ~ QueueT_st + Residual +", ctrl, "|", FE_IDEAS)),
               data = stk_ideas)
for (cl in c("district_id", "state_id")) {
  kp <- kp_f(iv_2c, cl)
  add(tidy_row(iv_2c, "fit_Engineer", "2c", "Table 2 Panel B 2SLS", "Y_signed (z)", FE_IDEAS, cl,
               list(KP_F = round(kp, 2))))
  add(tidy_row(fs_2c, "QueueT_st", "2c", "first stage", "Engineer", FE_IDEAS, cl))
  add(tidy_row(rf_2c, "QueueT_st", "2c", "reduced form", "Y_signed (z)", FE_IDEAS, cl))
}

# ============================================================
# TASK 2d  WILD CLUSTER BOOTSTRAP BY STATE (Webb, 9,999, H0: 0)
# ============================================================
cat("\n== TASK 2d: wild cluster bootstrap ==\n")
# boottest() cannot (i) parse fixest formulas with a `|` fixed-effects part
# (error in get_cluster) nor (ii) accept fits from which feols removed
# singleton FE levels. Each bootstrapped model is therefore refit with
# every FE as explicit factor() dummies, on exactly the fixest estimation
# sample (data[obs(fit), ]), dropping the regressors fixest found collinear.
# The refit is checked to reproduce the fixest coefficient before bootstrapping.
boot_rows <- list()
do_boot <- function(fit, data, param, yvar, rhs, fes, label) {
  rhs  <- setdiff(rhs, fit$collin.var)
  dsub <- data[obs(fit), ]
  fml  <- as.formula(paste(yvar, "~", paste(c(rhs, paste0("factor(", fes, ")")), collapse = " + ")))
  refit <- feols(fml, data = dsub)
  gap <- abs(coef(refit)[param] - coef(fit)[param])
  ok  <- is.finite(gap) && gap < 1e-8
  bt <- if (!ok) simpleError(sprintf("dummy refit does not reproduce fixest coef (gap=%g)", gap)) else
    tryCatch(boottest(refit, param = param, clustid = "state_id", B = B_BOOT, type = "webb",
                      r = 0, impose_null = TRUE, sign_level = 0.05),
             error = function(e) e)
  G <- length(unique(dsub$state_id))
  if (inherits(bt, "error")) {
    cat("  BOOT FAILED:", label, "--", conditionMessage(bt), "\n")
    boot_rows[[length(boot_rows) + 1]] <<- data.frame(
      estimate = label, term = param, coef = as.numeric(coef(fit)[param]), boot_p = NA,
      boot_ci95_lo = NA, boot_ci95_hi = NA, t_stat = NA, N = nobs(fit), n_clusters = G,
      B = B_BOOT, weights = "webb", method = "WCR", note = paste("FAILED:", conditionMessage(bt)))
    return(invisible(NULL))
  }
  ci <- tryCatch(as.numeric(confint(bt)), error = function(e) c(NA, NA))
  boot_rows[[length(boot_rows) + 1]] <<- data.frame(
    estimate = label, term = param, coef = as.numeric(coef(fit)[param]),
    boot_p = pval(bt), boot_ci95_lo = ci[1], boot_ci95_hi = ci[2],
    t_stat = teststat(bt), N = nobs(fit), n_clusters = G,
    B = B_BOOT, weights = "webb", method = "WCR",
    note = "null imposed; FE as dummies on fixest sample")
  cat(sprintf("  %-62s p=%.4f  G=%d\n", label, pval(bt), G))
}

ctrl_v <- c("allotment_year", "tenure_months", "opposition_turnover")
fe_vars <- list("district + state x year" = c("district_id", "state_year"),
                "district + state + year" = c("district_id", "state_id", "year_fac"))

# 1c OLS contrasts (all roads versions, both FE structures)
for (k in names(fits_1c)) {
  rv <- strsplit(k, "\\|")[[1]]
  do_boot(fits_1c[[k]], df_both, "Engineer", paste0("lr_", rv[1]),
          c("Engineer", "Residual", ctrl_v), fe_vars[[rv[2]]],
          sprintf("1c OLS, %s, %s", roads_lbl[[rv[1]]], rv[2]))
}
# 2a reduced forms and first stage
for (rv in names(roads_tf))
  do_boot(iv_info[[rv]]$rf, df_both_iv, "QueueT_st", paste0("lr_", rv),
          c("QueueT_st", "Residual", ctrl_v), fe_vars[["district + state + year"]],
          sprintf("2a reduced form, %s", roads_lbl[[rv]]))
do_boot(iv_info[["asinh"]]$fs, df_both_iv, "QueueT_st", "Engineer",
        c("QueueT_st", "Residual", ctrl_v), fe_vars[["district + state + year"]],
        "2a first stage (Engineer on QueueT_st)")
# 2c reduced form and first stage
do_boot(rf_2c, stk_ideas, "QueueT_st", "Y_signed", c("QueueT_st", "Residual", ctrl_v),
        c("did_k", "sid_k", "yr_k"), "2c reduced form (Table 2 Panel B, Y_signed)")
do_boot(fs_2c, stk_ideas, "QueueT_st", "Engineer", c("QueueT_st", "Residual", ctrl_v),
        c("did_k", "sid_k", "yr_k"), "2c first stage (stacked)")

# 2SLS (WRE). First: does boottest() accept the fixest IV object directly?
# Probe on a refit with FE as dummies on the fixest sample, so the singleton
# problem above cannot be the reason for failure.
iv_probe_dat <- df_both_iv[obs(iv_info[["asinh"]]$iv), ]
iv_probe <- feols(lr_asinh ~ Residual + allotment_year + tenure_months + opposition_turnover +
                    factor(district_id) + factor(year_fac) | Engineer ~ QueueT_st,
                  data = iv_probe_dat)
iv_try <- tryCatch(
  boottest(iv_probe, param = "fit_Engineer", clustid = "state_id",
           B = B_BOOT, type = "webb"),
  error = function(e) e)
wre_note <- if (inherits(iv_try, "error")) paste("fixest IV not accepted:", conditionMessage(iv_try)) else "fixest IV accepted"
cat("  WRE on fixest IV object:", wre_note, "\n")

# Supplementary: WRE via an ivreg::ivreg refit of the same 2SLS (dummies for
# district and year; state is nested in district), the IV class boottest supports.
do_wre <- function(fit_iv, data, yvar, label) {
  dsub <- data[obs(fit_iv), ]
  exo  <- setdiff(c("Residual", ctrl_v), fit_iv$collin.var)
  fes  <- "factor(district_id) + factor(year_fac)"
  fml  <- as.formula(paste(yvar, "~ Engineer +", paste(exo, collapse = " + "), "+", fes,
                           "|", "QueueT_st +", paste(exo, collapse = " + "), "+", fes))
  ivr  <- ivreg::ivreg(fml, data = dsub)
  gap  <- abs(coef(ivr)["Engineer"] - coef(fit_iv)["fit_Engineer"])
  bt <- if (!is.finite(gap) || gap > 1e-6) simpleError(sprintf("ivreg refit gap %g", gap)) else
    tryCatch(boottest(ivr, param = "Engineer", clustid = "state_id", B = B_BOOT,
                      type = "webb", r = 0, sign_level = 0.05),
             error = function(e) e)
  G <- length(unique(dsub$state_id))
  if (inherits(bt, "error")) {
    cat("  WRE FAILED:", label, "--", conditionMessage(bt), "\n")
    boot_rows[[length(boot_rows) + 1]] <<- data.frame(
      estimate = label, term = "Engineer (2SLS)", coef = as.numeric(coef(fit_iv)["fit_Engineer"]),
      boot_p = NA, boot_ci95_lo = NA, boot_ci95_hi = NA, t_stat = NA, N = nobs(fit_iv),
      n_clusters = G, B = B_BOOT, weights = "webb", method = "WRE",
      note = paste("FAILED:", conditionMessage(bt)))
    return(invisible(NULL))
  }
  ci <- tryCatch(as.numeric(confint(bt)), error = function(e) c(NA, NA))
  boot_rows[[length(boot_rows) + 1]] <<- data.frame(
    estimate = label, term = "Engineer (2SLS)", coef = as.numeric(coef(fit_iv)["fit_Engineer"]),
    boot_p = pval(bt), boot_ci95_lo = ci[1], boot_ci95_hi = ci[2], t_stat = teststat(bt),
    N = nobs(fit_iv), n_clusters = G, B = B_BOOT, weights = "webb", method = "WRE",
    note = "ivreg refit of the fixest 2SLS (same coef), FE as dummies")
  cat(sprintf("  %-62s p=%.4f  G=%d\n", label, pval(bt), G))
}
for (rv in names(roads_tf))
  do_wre(iv_info[[rv]]$iv, df_both_iv, paste0("lr_", rv), sprintf("2a 2SLS (WRE), %s", roads_lbl[[rv]]))

boot_df <- do.call(rbind, boot_rows)
boot_df$wre_on_fixest_iv <- wre_note
write.csv(boot_df, file.path(OUT, "task2d_wild_bootstrap_stateclust.csv"), row.names = FALSE)

# ============================================================
# WRITE ESTIMATE TABLES
# ============================================================
res <- do.call(rbind, results)
write.csv(res[res$task %in% c("1b", "1c"), ],
          file.path(OUT, "task1_sign_contrast_log.csv"), row.names = FALSE)
write.csv(res[res$task %in% c("2a", "2b"), ],
          file.path(OUT, "task2ab_iv_log_stateclust.csv"), row.names = FALSE)
write.csv(res[res$task == "2c", ],
          file.path(OUT, "task2c_table2_iv_stateclust.csv"), row.names = FALSE)

# ============================================================
# TASK 3  RECALIBRATE THE WORKED EXAMPLE (Appendix E)
# ============================================================
cat("\n== TASK 3: worked example ==\n")

omega <- c(0.8, 0.5, 0.2)
S_j   <- omega^2 + (1 - omega)^2
D_j   <- (2 * omega - 1) / 2
perms3 <- rbind(c(1,2,3), c(1,3,2), c(2,1,3), c(2,3,1), c(3,1,2), c(3,2,1))
subsets <- combn(5, 3)

# V_ij = N_j sqrt(S_j m_i + D_j t_i), alpha = 1/2, m_i = 1, N_j = 1
V <- function(t) outer(t, seq_along(omega), function(tt, j) sqrt(S_j[j] + D_j[j] * tt))

# W of placing officers `who` (in district order 1..3) at true tilts
W_of <- function(Vm, who) sum(Vm[cbind(who, 1:3)])

worked_example <- function(t) {
  Vm <- V(t)
  # Queue: uniform over 3-subsets, uniform over bijections
  Wq <- mean(apply(subsets, 2, function(sub) mean(apply(perms3, 1, function(p) W_of(Vm, sub[p])))))
  # Assortative on education labels (officer index 1 = most technical
  # education = A). Pair highest-labelled with highest omega. When the true
  # tilt ordering is reversed (beta < 0) this is sorting "as if" positive.
  Wa_label <- mean(apply(subsets, 2, function(sub) W_of(Vm, sort(sub))))
  # Best pairing of the same officers under TRUE tilts
  Wa_true  <- mean(apply(subsets, 2, function(sub) max(apply(perms3, 1, function(p) W_of(Vm, sub[p])))))
  # Full optimum under true tilts
  Wopt <- max(apply(subsets, 2, function(sub) max(apply(perms3, 1, function(p) W_of(Vm, sub[p])))))
  # Full optimum chosen as if the label ordering were the tilt ordering:
  # pick the (subset, pairing) that is optimal under |t| in label order, then
  # evaluate it at true tilts
  t_asif <- sort(abs(t), decreasing = TRUE)
  Vas <- V(t_asif)
  best <- NULL; bestv <- -Inf
  for (s in seq_len(ncol(subsets))) for (r in seq_len(nrow(perms3))) {
    who <- subsets[, s][perms3[r, ]]
    v <- W_of(Vas, who)
    if (v > bestv + 1e-12) { bestv <- v; best <- who }
  }
  Wopt_label <- W_of(Vm, best)
  list(Wq = Wq, Wa_label = Wa_label, Wa_true = Wa_true, Wopt = Wopt, Wopt_label = Wopt_label)
}

# Check 1: illustrative case
ill <- worked_example(c(0.8, 0.4, 0, -0.4, -0.8))
cat(sprintf("  Illustrative: queue=%.4f assort=%.4f (%.2f%%) opt=%.4f (%.2f%%) placement share=%.1f%%\n",
            ill$Wq, ill$Wa_true, 100 * (ill$Wa_true / ill$Wq - 1), ill$Wopt,
            100 * (ill$Wopt / ill$Wq - 1), 100 * (ill$Wa_true - ill$Wq) / (ill$Wopt - ill$Wq)))
# One draw check (B, C, D)
Vi <- V(c(0.8, 0.4, 0, -0.4, -0.8))
one_draw <- sapply(1:6, function(r) W_of(Vi, c(2, 3, 4)[perms3[r, ]]))
cat(sprintf("  One draw (B,C,D): assortative=%.4f mean=%.4f gain=%.2f%%\n",
            max(one_draw), mean(one_draw), 100 * (max(one_draw) / mean(one_draw) - 1)))

tilts_for <- function(beta) {
  rho  <- exp(beta / 2)
  tmax <- 2 * (rho - 1) / (rho + 1)
  list(tmax = tmax, t = tmax * c(1, 0.5, 0, -0.5, -1))
}

# Reproduction check at 0.075
chk <- worked_example(tilts_for(0.075)$t)
repro_ok <- abs(chk$Wq - 2.3563) < 5e-5 &&
  abs(round(100 * (chk$Wa_true / chk$Wq - 1), 2) - 0.43) < 1e-9 &&
  abs(round(100 * (chk$Wopt / chk$Wq - 1), 2) - 0.58) < 1e-9
cat(sprintf("  0.075 check: queue=%.4f assort=+%.2f%% opt=+%.2f%%  REPRODUCES=%s\n",
            chk$Wq, 100 * (chk$Wa_true / chk$Wq - 1), 100 * (chk$Wopt / chk$Wq - 1), repro_ok))
if (!repro_ok) stop("Worked example does not reproduce the 0.075 table; stopping before Task 3 output.")

pick <- function(task, spec, outcome_pat, term, cl) {
  r <- res[res$task == task & res$spec == spec & grepl(outcome_pat, res$outcome, fixed = TRUE) &
             res$term == term & res$cluster == cl, ]
  stopifnot(nrow(r) == 1); r
}
ols_st <- pick("1c", "district + state x year", "asinh(roads)", "Engineer", "state_id")
ols_di <- pick("1c", "district + state x year", "asinh(roads)", "Engineer", "district_id")
iv_st  <- pick("2a", "2SLS", "asinh(roads)", "fit_Engineer", "state_id")
# Supplementary: roads_rate lies in [0.04, 2], where asinh(x) ~ x, so the
# asinh version is close to a level. log(roads) is feasible (no zeros).
ols_lg <- pick("1c", "district + state x year", "log(roads) [no offset]", "Engineer", "state_id")
iv_lg  <- pick("2a", "2SLS", "log(roads) [no offset]", "fit_Engineer", "state_id")

cal_in <- data.frame(
  source = c("Paper (current, midpoint of z-score log ratio)",
             "1c OLS, state x year FE, asinh: point",
             "1c OLS, state x year FE, asinh: 95% CI low (state cl.)",
             "1c OLS, state x year FE, asinh: 95% CI high (state cl.)",
             "1c OLS, state x year FE, asinh: 95% CI low (district cl.)",
             "1c OLS, state x year FE, asinh: 95% CI high (district cl.)",
             "2a IV, asinh: point",
             "2a IV, asinh: 95% CI high (state cl.)",
             "Zero",
             "[suppl.] 1c OLS, state x year FE, log(roads): point",
             "[suppl.] 1c OLS, state x year FE, log(roads): 95% CI low (state cl.)",
             "[suppl.] 1c OLS, state x year FE, log(roads): 95% CI high (state cl.)",
             "[suppl.] 2a IV, log(roads): point",
             "[suppl.] 2a IV, log(roads): 95% CI high (state cl.)"),
  beta_comp = c(0.075, ols_st$coef, ols_st$ci95_lo, ols_st$ci95_hi,
                ols_di$ci95_lo, ols_di$ci95_hi, iv_st$coef, iv_st$ci95_hi, 0,
                ols_lg$coef, ols_lg$ci95_lo, ols_lg$ci95_hi, iv_lg$coef, iv_lg$ci95_hi),
  stringsAsFactors = FALSE)

cal_rows <- lapply(seq_len(nrow(cal_in)), function(i) {
  b  <- cal_in$beta_comp[i]
  tt <- tilts_for(b)
  we <- worked_example(tt$t)
  # For beta >= 0 the label sort is the true assortative sort.
  Wa  <- we$Wa_label
  Wo  <- if (b >= 0) we$Wopt else we$Wopt_label
  loss <- we$Wopt - we$Wq
  data.frame(
    source = cal_in$source[i], beta_comp = b, t_max = tt$tmax,
    W_queue = we$Wq,
    W_assortative_on_education = Wa,
    pct_gain_assortative = 100 * (Wa / we$Wq - 1),
    W_full_optimum_on_education = Wo,
    pct_gain_full_optimum = 100 * (Wo / we$Wq - 1),
    W_true_full_optimum = we$Wopt,
    pct_gain_true_full_optimum = 100 * (we$Wopt / we$Wq - 1),
    placement_share_of_total_loss = if (abs(loss) < 1e-15) NA_real_ else
      (we$Wa_true - we$Wq) / loss,
    note = if (b < 0) "beta<0: education-sorted rules are LOSSES vs queue; true optimum sorts the other way" else "",
    stringsAsFactors = FALSE)
})
cal <- do.call(rbind, cal_rows)
ill_row <- data.frame(
  source = "Illustrative tilts {0.8,0.4,0,-0.4,-0.8}", beta_comp = NA, t_max = 0.8,
  W_queue = ill$Wq, W_assortative_on_education = ill$Wa_label,
  pct_gain_assortative = 100 * (ill$Wa_label / ill$Wq - 1),
  W_full_optimum_on_education = ill$Wopt, pct_gain_full_optimum = 100 * (ill$Wopt / ill$Wq - 1),
  W_true_full_optimum = ill$Wopt, pct_gain_true_full_optimum = 100 * (ill$Wopt / ill$Wq - 1),
  placement_share_of_total_loss = (ill$Wa_true - ill$Wq) / (ill$Wopt - ill$Wq), note = "")
cal <- rbind(cal, ill_row)
print(cal[, 1:9], digits = 6)
write.csv(cal, file.path(OUT, "task3_worked_example_recalibration_log.csv"), row.names = FALSE)

# ============================================================
# TASK 4  SANITY CHECKS (report only)
# ============================================================
cat("\n== TASK 4: sanity checks ==\n")
chk_rows <- list()
addc <- function(check, item, value) chk_rows[[length(chk_rows) + 1]] <<-
  data.frame(check = check, item = item, value = as.character(value), stringsAsFactors = FALSE)

# 4.1  Version B Wald (run_full_analysis.R lines ~228-256), recomputed here
df_inf_z  <- df_roads; df_inf_z$y_std  <- std(df_inf_z$roads_rate)
df_welf_z <- df_welf;  df_welf_z$y_std <- std(df_welf_z$emp_pc)
for (nm in c("(3) add-state", "(4) state x yr")) {
  fe_i <- if (nm == "(3) add-state") FE_ADD else FE_STYR
  fml  <- as.formula(paste("y_std ~ Engineer + Residual +", ctrl, "|", fe_i))
  f1 <- feols(fml, data = df_inf_z,  cluster = ~district_id)
  f2 <- feols(fml, data = df_welf_z, cluster = ~district_id)
  b1 <- coef(f1)["Engineer"]; s1 <- se(f1)["Engineer"]
  b2 <- coef(f2)["Engineer"]; s2 <- se(f2)["Engineer"]
  chi2 <- as.numeric((b1 - b2)^2 / (s1^2 + s2^2))
  addc("4.1", paste(nm, "separate-regression beta_infra (SE)"), sprintf("%.4f (%.4f), N=%d", b1, s1, nobs(f1)))
  addc("4.1", paste(nm, "separate-regression beta_welfare (SE)"), sprintf("%.4f (%.4f), N=%d", b2, s2, nobs(f2)))
  addc("4.1", paste(nm, "Version B chi2(1), p (zero cross-eq. covariance)"),
       sprintf("%.3f, p=%.4f", chi2, pchisq(chi2, 1, lower.tail = FALSE)))
}
for (nm in names(t1_fe)) {
  f <- feols(as.formula(paste(t1_rhs, "|", t1_fe[[nm]])), data = stk_z, cluster = ~district_id)
  w <- wald(f, keep = "^Engineer:infra_k$", print = FALSE)
  addc("4.1", paste("Stacked", nm, "Wald on Engineer:infra_k (F = chi2(1))"),
       sprintf("%.3f, p=%.4f", w$stat, w$p))
}

# 4.2  YOS vs allotment year
for (nm in names(t1_fe)) {
  f <- feols(as.formula(paste(t1_rhs, "+ years_of_service |", t1_fe[[nm]])),
             data = stk_z, cluster = ~district_id)
  addc("4.2", paste("Table 1", nm, "+ years_of_service: collinear vars dropped"),
       paste(f$collin.var, collapse = ", "))
  addc("4.2", paste("Table 1", nm, "years_of_service coef"),
       if ("years_of_service" %in% names(coef(f))) sprintf("%.5f (SE %.5f)", coef(f)["years_of_service"], se(f)["years_of_service"]) else "not estimable (dropped)")
}
f <- feols(as.formula(paste("lr_asinh ~ Engineer + Residual +", ctrl, "+ years_of_service |", FE_STYR)),
           data = df_both, cluster = ~district_id)
addc("4.2", "1c lr (state x year) + years_of_service: collinear vars dropped", paste(f$collin.var, collapse = ", "))
f <- feols(as.formula(paste("Y_signed ~ Residual + years_of_service +", ctrl, "|", FE_IDEAS,
                            "| Engineer ~ QueueT_st")), data = stk_ideas, cluster = ~district_id)
addc("4.2", "Table 2 IV (did_k+sid_k+yr_k) + years_of_service: collinear vars dropped",
     paste(f$collin.var, collapse = ", "))
addc("4.2", "Max |year - allotment_year - years_of_service| in data",
     max(abs(df$year - df$allotment_year - df$years_of_service), na.rm = TRUE))

# 4.3  Opposition turnover under state-by-year FE
for (nm in names(t1_fe)) {
  f <- feols(as.formula(paste(t1_rhs, "|", t1_fe[[nm]])), data = stk_z, cluster = ~district_id)
  addc("4.3", paste("Table 1", nm, "collinear vars dropped"),
       if (length(f$collin.var)) paste(f$collin.var, collapse = ", ") else "none")
  addc("4.3", paste("Table 1", nm, "opposition_turnover coef (SE)"),
       sprintf("%.4f (%.4f)", coef(f)["opposition_turnover"], se(f)["opposition_turnover"]))
}
wsy <- df %>% group_by(state_year) %>%
  summarise(v = n_distinct(opposition_turnover), .groups = "drop")
addc("4.3", "State-years (all) with >1 distinct opposition_turnover value",
     sprintf("%d of %d", sum(wsy$v > 1), nrow(wsy)))
addc("4.3", "Share of obs with opposition_turnover = 1", sprintf("%.3f", mean(df$opposition_turnover)))

chk <- do.call(rbind, chk_rows)
print(chk, row.names = FALSE)
write.csv(chk, file.path(OUT, "task4_sanity_checks_log.csv"), row.names = FALSE)

# Console dump of the main estimates
cat("\n== ALL ESTIMATES ==\n")
print(res[, c("task", "spec", "outcome", "term", "cluster", "coef", "se", "p",
              "ci95_lo", "ci95_hi", "N", "n_clusters", "extra")], digits = 4, row.names = FALSE)
print(boot_df, digits = 4, row.names = FALSE)
saveRDS(list(res = res, boot = boot_df, cal = cal, chk = chk, diag = diag1a),
        file.path(OUT, "all_results_log_stateclust.rds"))
cat("\nDone.\n")
