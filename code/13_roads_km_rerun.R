#!/usr/bin/env Rscript
# ============================================================
#  code/13_roads_km_rerun.R
#  Reruns the Oct 2026 revision with alternative infrastructure outcomes
#  in place of roads_rate (roads completed / km completed):
#    roads_km_pc = road_length_km  / (tot_p / 1000)   [primary]
#    roads_n_pc  = roads_completed / (tot_p / 1000)   [secondary]
#  plus roads_rate itself as a harness check (must reproduce the existing
#  output/revision_oct2026/*.csv exactly).
#
#  How: code/10_log_and_inference.R is run UNMODIFIED except for two
#  textual substitutions (input data frame, output directory), with the
#  roads_rate column overwritten by the chosen measure. Every specification,
#  sample rule, control and clustering choice is therefore the same code.
#  Table 2 row 1 (run_ideas.R) and the Figure 1 roads coefficient
#  (coeff_plot_data.R) are not in script 10, so they are refit here with
#  the exact specs of those scripts. code/12_worked_example.R is called on
#  the new log-ratio estimates.
#
#  Sample: the roads sample is held at the district-years where roads_rate
#  is observed (road_length_km > 0). 4 district-years in 2001-2008 have
#  roads_completed > 0 but road_length_km == 0; they are excluded under
#  every measure in the main run and added back in a sensitivity block.
#
#  Writes only to output/revision_oct2026/roads_km/.
#  Run from repo root:  Rscript code/13_roads_km_rerun.R
# ============================================================
suppressPackageStartupMessages({
  library(fixest)
  library(dplyr)
})

OUT_KM <- "output/revision_oct2026/roads_km"
dir.create(OUT_KM, recursive = TRUE, showWarnings = FALSE)

# ── 0. Build the measures from the panel the build script merges from ────────

df0 <- read.csv("data/analysis/dc_analysis_v2.csv", stringsAsFactors = FALSE)
pan <- read.csv("data/final/panel_full.csv", stringsAsFactors = FALSE,
                colClasses = c(pc11_state_id = "character", pc11_district_id = "character"))
# build_iv_v2.py: district_id = pc11_state_id (2) + pc11_district_id (3); year = spell start year
pan$key <- paste0(formatC(as.integer(pan$pc11_state_id), width = 2, flag = "0"),
                  formatC(as.integer(pan$pc11_district_id), width = 3, flag = "0"))
df0$key <- sprintf("%05d", as.integer(df0$district_id))
df0 <- left_join(df0, pan[, c("key", "year", "roads_completed", "road_length_km")],
                 by = c("key", "year"))

# Merge check: must rebuild roads_rate exactly
rr <- ifelse(df0$road_length_km > 0, df0$roads_completed / df0$road_length_km, NA)
stopifnot(identical(is.na(rr), is.na(df0$roads_rate)),
          max(abs(rr - df0$roads_rate), na.rm = TRUE) < 1e-12)

df0$roads_km_pc <- df0$road_length_km  / (df0$tot_p / 1000)
df0$roads_n_pc  <- df0$roads_completed / (df0$tot_p / 1000)
df0$roads_rate_orig <- df0$roads_rate

MEASURES <- c("roads_rate", "roads_km_pc", "roads_n_pc")

# ── 6. Zero / missing counts ────────────────────────────────────────────────
cnt <- function(x, w) c(n = sum(w), missing = sum(is.na(x[w])), zero = sum(x[w] == 0, na.rm = TRUE),
                        positive = sum(x[w] > 0, na.rm = TRUE))
zm <- do.call(rbind, lapply(MEASURES, function(m) {
  x <- df0[[if (m == "roads_rate") "roads_rate_orig" else m]]
  rbind(
    data.frame(measure = m, window = "all district-years (1994-2008)", t(cnt(x, rep(TRUE, nrow(df0))))),
    data.frame(measure = m, window = "district-years 2001-2008",       t(cnt(x, df0$year >= 2001))),
    data.frame(measure = m, window = "held roads sample (roads_rate observed, 2001-2008)",
               t(cnt(x, df0$year >= 2001 & !is.na(df0$roads_rate_orig)))))
}))
rownames(zm) <- NULL
pos <- df0$year >= 2001 & !is.na(df0$roads_rate_orig)
desc <- do.call(rbind, lapply(MEASURES, function(m) {
  x <- df0[[if (m == "roads_rate") "roads_rate_orig" else m]][pos]
  data.frame(measure = m, min = min(x), median = median(x), mean = mean(x), max = max(x),
             cor_with_roads_rate = cor(x, df0$roads_rate_orig[pos]),
             cor_log_with_log_roads_rate = cor(log(x), log(df0$roads_rate_orig[pos])))
}))
write.csv(zm,   file.path(OUT_KM, "zero_missing_counts_log.csv"), row.names = FALSE)
write.csv(desc, file.path(OUT_KM, "measure_descriptives_log.csv"), row.names = FALSE)
print(zm); print(desc)

# ── Harness: run script 10 with roads_rate := measure ───────────────────────
src10 <- readLines("code/10_log_and_inference.R")
sub_once <- function(lines, old, new) {
  hit <- which(lines == old)
  if (length(hit) != 1) stop("pattern not found exactly once: ", old)
  lines[hit] <- new
  lines
}
src10 <- sub_once(src10, 'df <- read.csv("data/analysis/dc_analysis_v2.csv", stringsAsFactors = FALSE)',
                  'df <- .DF_IN')
src10 <- sub_once(src10, 'OUT <- "output/revision_oct2026"', 'OUT <- .OUT_IN')

make_input <- function(measure, keep_zero_length = FALSE) {
  d <- df0
  x <- d[[if (measure == "roads_rate") "roads_rate_orig" else measure]]
  keep <- if (keep_zero_length) !is.na(x) else !is.na(d$roads_rate_orig)
  d$roads_rate <- ifelse(keep, x, NA_real_)
  d[, setdiff(names(d), c("key", "roads_completed", "road_length_km",
                          "roads_km_pc", "roads_n_pc", "roads_rate_orig"))]
}

# Script 10 resolves model data via the formula environment (n_clust,
# boottest), so it must run in the global environment, as it does standalone.
# None of the names this script relies on afterwards are assigned by script 10.
run10 <- function(measure, out_dir, keep_zero_length = FALSE) {
  assign(".DF_IN",  make_input(measure, keep_zero_length), envir = globalenv())
  assign(".OUT_IN", out_dir, envir = globalenv())
  cat(sprintf("\n######## script 10 with roads := %s -> %s ########\n", measure, out_dir))
  eval(parse(text = src10), envir = globalenv())
}

for (m in MEASURES) run10(m, file.path(OUT_KM, m))

# Harness check: the roads_rate pass must equal the existing outputs
for (f in c("task1_sign_contrast_log.csv", "task2ab_iv_log_stateclust.csv",
            "task2c_table2_iv_stateclust.csv", "task2d_wild_bootstrap_stateclust.csv",
            "task3_worked_example_recalibration_log.csv")) {
  a <- read.csv(file.path("output/revision_oct2026", f), stringsAsFactors = FALSE)
  b <- read.csv(file.path(OUT_KM, "roads_rate", f), stringsAsFactors = FALSE)
  num <- intersect(names(a)[sapply(a, is.numeric)], c("coef", "se", "p", "ci95_lo", "ci95_hi",
                   "boot_p", "boot_ci95_lo", "boot_ci95_hi", "W_queue", "N", "n_clusters"))
  gap <- max(sapply(num, function(v) max(abs(a[[v]] - b[[v]]), na.rm = TRUE)))
  cat(sprintf("  harness check %-45s max abs gap = %.2e\n", f, gap))
  stopifnot(gap < 1e-8)
}

# ── Table 2 row 1 (run_ideas.R IDEA 1) and Figure 1 roads coefficient ──────
ctrl <- "allotment_year + tenure_months + opposition_turnover"
extra_rows <- list()
for (m in MEASURES) {
  df <- make_input(m)
  qt <- read.csv("data/analysis/QueueT_st.csv", colClasses = c(state_id = "character"))
  df$state_id <- formatC(as.integer(df$state_id), width = 2, flag = "0")
  df$emp_pc   <- df$ec_emp_all / df$tot_p
  df <- left_join(df, qt, by = c("state_id", "year"))
  df$year_fac <- as.character(df$year)

  # run_ideas.R: z-scores over the full panel, stacked 2001+
  zsc <- function(x) (x - mean(x, na.rm = TRUE)) / sd(x, na.rm = TRUE)
  df$z_roads <- zsc(df$roads_rate); df$z_emp <- zsc(df$emp_pc)
  stk <- bind_rows(
    df %>% filter(!is.na(roads_rate), year >= 2001) %>% mutate(infra_k = 1L, Y_signed = z_roads),
    df %>% filter(!is.na(emp_pc),     year >= 2001) %>% mutate(infra_k = 0L, Y_signed = -z_emp))
  stk$did_k <- paste0(stk$district_id, "_", stk$infra_k)
  stk$sid_k <- paste0(stk$state_id,    "_", stk$infra_k)
  stk$yr_k  <- paste0(stk$year_fac,    "_", stk$infra_k)
  f1 <- feols(as.formula(paste("Y_signed ~ Engineer + Residual +", ctrl, "| did_k + sid_k + yr_k")),
              data = stk, cluster = ~district_id)
  for (cl in c("district_id", "state_id")) {
    s <- summary(f1, cluster = as.formula(paste0("~", cl)))
    ci <- confint(s)["Engineer", ]
    extra_rows[[length(extra_rows) + 1]] <- data.frame(
      measure = m, item = "Table 2 row 1: pooled signed OLS", cluster = cl,
      coef = coef(s)["Engineer"], se = se(s)["Engineer"], p = pvalue(s)["Engineer"],
      ci_lo = ci[[1]], ci_hi = ci[[2]], ci_level = 0.95, N = nobs(f1),
      n_clusters = length(unique(stk[[cl]][obs(f1)])))
  }

  # coeff_plot_data.R: roads, yr>=2001, standardised in-sample, additive FE, 90% CI
  d <- df[!is.na(df$roads_rate) & df$year >= 2001, ]
  d$y_std <- (d$roads_rate - mean(d$roads_rate)) / sd(d$roads_rate)
  fg <- feols(as.formula(paste("y_std ~ Engineer + Residual +", ctrl,
                               "| district_id + state_id + year_fac")),
              data = d, cluster = ~district_id)
  b <- coef(fg)["Engineer"]; s <- se(fg)["Engineer"]
  extra_rows[[length(extra_rows) + 1]] <- data.frame(
    measure = m, item = "Figure 1 roads coefficient (spec 3, standardised)", cluster = "district_id",
    coef = b, se = s, p = pvalue(fg)["Engineer"], ci_lo = b - 1.645 * s, ci_hi = b + 1.645 * s,
    ci_level = 0.90, N = nobs(fg), n_clusters = length(unique(d$district_id[obs(fg)])))
}
extra <- do.call(rbind, extra_rows); rownames(extra) <- NULL
write.csv(extra, file.path(OUT_KM, "table2_row1_and_figure1_log.csv"), row.names = FALSE)
print(extra, digits = 4)

# ── 5. Worked example (code/12_worked_example.R) at the new estimates ───────
we_rows <- list()
for (m in MEASURES) {
  r <- read.csv(file.path(OUT_KM, m, "task1_sign_contrast_log.csv"), stringsAsFactors = FALSE)
  r <- r[r$task == "1c" & r$spec == "district + state x year" &
           grepl("log(roads) [no offset]", r$outcome, fixed = TRUE) & r$cluster == "state_id", ]
  stopifnot(nrow(r) == 1)
  betas <- c(r$coef, r$ci95_lo, r$ci95_hi)
  out <- system2("Rscript", c("code/12_worked_example.R", sprintf("%.10f", betas)),
                 stdout = TRUE, stderr = TRUE)
  writeLines(c(sprintf("# code/12_worked_example.R, measure = %s", m),
               sprintf("# beta_comp = 1c log(roads) - log(emp_pc), district + state x year FE: point, state-cl. 95%% CI low, high"),
               sprintf("# %s", paste(sprintf("%.6f", betas), collapse = ", ")), out),
             file.path(OUT_KM, sprintf("worked_example_%s_log.txt", m)))
  we_rows[[m]] <- data.frame(measure = m, which = c("point", "ci95_lo (state)", "ci95_hi (state)"),
                             beta_comp = betas)
}
write.csv(do.call(rbind, we_rows), file.path(OUT_KM, "worked_example_inputs_log.csv"), row.names = FALSE)

# ── Sensitivity: add back the 4 zero-length district-years ──────────────────
# roads_km_pc is 0 there (log undefined, so log(+c) and asinh only);
# roads_n_pc is positive there.
for (m in c("roads_km_pc", "roads_n_pc"))
  run10(m, file.path(OUT_KM, "sensitivity_zero_length_rows", m), keep_zero_length = TRUE)

cat("\nDone.\n")
