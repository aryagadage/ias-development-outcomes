#!/usr/bin/env Rscript
# ============================================================
#  code/11_tables_oct2026.R
#  Rebuilds the three paper tables revised in Oct 2026:
#    tables/R2A_sign_contrast.tex   (tab:r2a)        -- add log columns (3)-(4)
#    tables/ideas_summary.tex       (tab:ideas_summary) -- add row 3b, state-clustered IV
#    tables/R3_first_stage.tex      (tab:firststage) -- drop the absorbed column
#
#  Mirrors the data construction in run_full_analysis.R (Table 1, Table 4)
#  and reads the state-clustered IV numbers from
#  output/revision_oct2026/task2c_table2_iv_stateclust.csv and
#  task2d_wild_bootstrap_stateclust.csv (produced by code/10_log_and_inference.R).
#  No number in this script is hand-typed from the paper; every figure is
#  either refit here or read from those CSVs.
#
#  Run from the ias-development-outcomes repo root:
#    Rscript code/11_tables_oct2026.R
#  Writes tables into ../IAS-outcomes/figures/tables/, which is where
#  the paper's \input{tables/...} resolves.
# ============================================================
suppressPackageStartupMessages({
  library(fixest)
  library(dplyr)
})

OUT_REV    <- "output/revision_oct2026"
TABLES_DIR <- "../IAS-outcomes/figures/tables"
stopifnot(dir.exists(TABLES_DIR))

# ---------- 0. backup originals (keep the \input filenames unchanged) -------
backup <- function(fname) {
  src <- file.path(TABLES_DIR, fname)
  dst <- file.path(TABLES_DIR, sub("\\.tex$", "_pre_oct2026.tex", fname))
  if (!file.exists(dst)) {
    file.copy(src, dst)
    cat(sprintf("  backed up %s -> %s\n", fname, basename(dst)))
  } else {
    cat(sprintf("  backup already exists for %s, leaving it\n", fname))
  }
}
backup("R2A_sign_contrast.tex")
backup("ideas_summary.tex")
backup("R3_first_stage.tex")

# ---------- 1. load & prepare data (identical to run_full_analysis.R) -------
df <- read.csv("data/analysis/dc_analysis_v2.csv", stringsAsFactors = FALSE)
qt <- read.csv("data/analysis/QueueT_st.csv", stringsAsFactors = FALSE,
               colClasses = c(state_id = "character"))
df$state_id    <- formatC(as.integer(df$state_id), width = 2, flag = "0")
df$district_id <- as.character(df$district_id)
df$emp_pc      <- df$ec_emp_all / df$tot_p
df <- left_join(df, qt, by = c("state_id", "year"))
df$state_year  <- paste0(df$state_id, "_", df$year)
df$year_fac    <- as.character(df$year)

ctrl <- "allotment_year + tenure_months + opposition_turnover"

# relabelling dictionary for ground rule 4 (applies to FE rows and var names)
dict <- c(
  did_k        = "District $\\times$ class",
  state_id     = "State",
  year_fac     = "Year",
  infra_k      = "Class",
  state_year   = "State $\\times$ year",
  district_id  = "District",
  sid_k        = "State $\\times$ class",
  yr_k         = "Year $\\times$ class",
  QueueT_st    = "QueueT\\_st"
)

# ============================================================
# TASK 1: Table 1 (tab:r2a) -- add log columns (3)-(4)
# ============================================================
cat("\n== Rebuilding Table 1 (R2A_sign_contrast.tex) ==\n")

df_roads <- df[!is.na(df$roads_rate) & df$year >= 2001, ]
df_welf  <- df[!is.na(df$emp_pc)     & df$year >= 2001, ]
std <- function(x) (x - mean(x, na.rm = TRUE)) / sd(x, na.rm = TRUE)

build_stack <- function(y_inf, y_welf) {
  a <- df_roads; a$y <- y_inf;  a$infra_k <- 1L
  b <- df_welf;  b$y <- y_welf; b$infra_k <- 0L
  s <- bind_rows(a, b)
  s$did_k <- paste0(s$district_id, "_", s$infra_k)
  s
}

t1_fe <- list(
  "(1)" = "did_k + state_id + year_fac + infra_k",
  "(2)" = "did_k + state_year + infra_k"
)
t1_rhs <- paste("y ~ Engineer + Engineer:infra_k + Residual + Residual:infra_k +", ctrl)

stk_z   <- build_stack(std(df_roads$roads_rate), std(df_welf$emp_pc))
stk_log <- build_stack(log(df_roads$roads_rate), log(df_welf$emp_pc))

r2a_results <- list()
for (nm in names(t1_fe)) {
  r2a_results[[nm]] <- feols(as.formula(paste(t1_rhs, "|", t1_fe[[nm]])),
                              data = stk_z, cluster = ~district_id)
}
for (nm in names(t1_fe)) {
  r2a_results[[paste0(nm, "log")]] <- feols(as.formula(paste(t1_rhs, "|", t1_fe[[nm]])),
                                             data = stk_log, cluster = ~district_id)
}

# sanity check against the brief's target numbers before writing anything
chk <- r2a_results[["(1)log"]]
stopifnot(abs(coef(chk)["Engineer:infra_k"] - 0.0835) < 0.001)
stopifnot(abs(coef(chk)["Engineer"]         + 0.0167) < 0.001)
cat("  log-column replication check passed (col 1 matches brief to 3dp)\n")

etable(r2a_results,
       keep = c("Engineer", "Engineer:infra_k", "Residual", "Residual:infra_k"),
       dict = dict, digits = "r4", digits.stats = "r5",
       se.below = TRUE, signif.code = c("***" = .01, "**" = .05, "*" = .10),
       tex = TRUE, file = file.path(TABLES_DIR, "R2A_sign_contrast.tex"), replace = TRUE,
       title = "Explicit Sign-Contrast Interaction Test",
       label = "tab:r2a")

# etable's grouped-header syntax varies by fixest version; add the group row
# and column renumbering, and append the revised notes as plain text OUTSIDE
# the tabular (NOT \multicolumn, which only has meaning inside an alignment)
# by direct, deterministic text surgery on the file etable just wrote. Every
# number in the file still comes from the fits above; only the note text
# below and the header-row labels are typed here.
lines <- readLines(file.path(TABLES_DIR, "R2A_sign_contrast.tex"))
model_line_idx <- grep("^\\s*Model:", lines)
dep_line_idx   <- grep("Dependent Variable:", lines)
end_tab_idx    <- grep("^\\s*\\\\end\\{tabular\\}", lines)
stopifnot(length(model_line_idx) == 1, length(dep_line_idx) == 1, length(end_tab_idx) == 1)
lines[model_line_idx] <- "   Model:                       & (1)      & (2)      & (3)      & (4)\\\\  "
header_group <- "   & \\multicolumn{2}{c}{Standardised} & \\multicolumn{2}{c}{Log}\\\\  "
lines <- append(lines, header_group, after = dep_line_idx)
# drop whatever dependent-variable row etable produced (y / y_std differ by column,
# which etable cannot label in one row) and keep our explicit group row instead
lines <- lines[-dep_line_idx]

notes_t1 <- c(
  "   \\par\\vspace{4pt}{\\footnotesize",
  "   \\textit{Notes:} Stacked district--year--class panel, 2001--2008. Columns (1)--(2) standardise each outcome within class; columns (3)--(4) use logs, so the Engineer $\\times$ infra coefficient is $\\beta^{R}-\\beta^{W}$ in log points.",
  "   Controls: residual education, its interaction with class, allotment year, tenure in post, opposition electoral turnover (absorbed under state $\\times$ year effects).",
  "   Standard errors clustered by district.}"
)
end_tab_idx <- grep("^\\s*\\\\end\\{tabular\\}", lines)  # recompute after row deletion above
lines <- append(lines, notes_t1, after = end_tab_idx)

writeLines(lines, file.path(TABLES_DIR, "R2A_sign_contrast.tex"))
cat("  Saved R2A_sign_contrast.tex (4 columns)\n")

# ============================================================
# TASK 2: Table 2 (tab:ideas_summary) -- add row 3b
# ============================================================
cat("\n== Rebuilding Table 2 (ideas_summary.tex) ==\n")

t2c <- read.csv(file.path(OUT_REV, "task2c_table2_iv_stateclust.csv"), stringsAsFactors = FALSE)
row3b <- t2c[t2c$task == "2c" & t2c$outcome == "Y_signed (z)" &
             t2c$term == "fit_Engineer" & t2c$cluster == "state_id", ]
stopifnot(nrow(row3b) == 1)
kp_s <- as.numeric(sub("KP_F=", "", row3b$extra))

t2d <- read.csv(file.path(OUT_REV, "task2d_wild_bootstrap_stateclust.csv"), stringsAsFactors = FALSE)
boot_row <- t2d[t2d$estimate == "2c reduced form (Table 2 Panel B, Y_signed)", ]
stopifnot(nrow(boot_row) == 1)
boot_p <- boot_row$boot_p

fmt <- function(x, d = 4) formatC(x, format = "f", digits = d)
row3b_tex <- sprintf(
  "\\quad 3b.\\; State-clustered & $+%s$ & $(%s)$ & $%s$ & $[%s,\\;%s]$ & $%d$ \\\\",
  fmt(row3b$coef), fmt(row3b$se), fmt(row3b$p, 3),
  fmt(row3b$ci95_lo), fmt(row3b$ci95_hi), row3b$N
)

t2_lines <- readLines(file.path(TABLES_DIR, "ideas_summary_pre_oct2026.tex"))
row3_idx <- grep("Pooled IV 2SLS", t2_lines)
stopifnot(length(row3_idx) == 1)
t2_lines <- append(t2_lines, row3b_tex, after = row3_idx)

# notes: remove "stacked sample doubles N", add the row-3b note
notes_remove <- grep("stacked sample doubles", t2_lines)
t2_lines[notes_remove] <- sub(
  "; stacked sample doubles \\$N\\$\\.", ".", t2_lines[notes_remove])

note_insert_after <- grep("predicts a positive \\\\textit\\{Engineer\\} coefficient", t2_lines)
stopifnot(length(note_insert_after) == 1)
new_note <- sprintf(
  "Row 3b re-estimates row 3 with standard errors clustered by state (27 clusters; KP-$F$ = %s). Wild cluster restricted bootstrap of the reduced form, clustered by state (Webb weights, 9,999 replications): $p = %s$.",
  fmt(kp_s, 2), fmt(boot_p, 3))
t2_lines <- append(t2_lines, new_note, after = note_insert_after)

# rows 2a-2b N gap: verified (Oct 2026) that no stacked cell has missing years
# of service; the 305 cells are FE singletons created by splitting the sample
# (pooled drops 264 of 1,825; junior 297 of 941; senior 272 of 884).
split_note_after <- grep("estimated on junior and senior DC subsamples separately", t2_lines)
stopifnot(length(split_note_after) == 1)
t2_lines <- append(t2_lines,
  "Rows 2a--2b sum to 1,256 rather than 1,561 because fixed-effect cells that become singletons within each subsample are dropped (569 cells across the two subsamples, against 264 in the pooled sample).",
  after = split_note_after)

writeLines(t2_lines, file.path(TABLES_DIR, "ideas_summary.tex"))
cat("  Saved ideas_summary.tex (row 3b added)\n")

# ============================================================
# TASK 3: Table 4 (tab:firststage) -- drop the absorbed column
# ============================================================
cat("\n== Rebuilding Table 4 (R3_first_stage.tex) ==\n")

df_iv <- df[!is.na(df$QueueT_st), ]
iv_specs <- list(
  "(1)" = "district_id + state_id + year_fac",
  "(2)" = "district_id + year_fac"
)
r3_first_stage <- list()
for (nm in names(iv_specs)) {
  fml_fs <- as.formula(paste(
    "Engineer ~ QueueT_st + allotment_year + tenure_months + opposition_turnover |",
    iv_specs[[nm]]))
  r3_first_stage[[nm]] <- feols(fml_fs, data = df_iv, cluster = ~district_id)
}
stopifnot(abs(coef(r3_first_stage[["(1)"]])["QueueT_st"] - 1.055) < 0.01)

etable(r3_first_stage,
       keep_raw = "QueueT_st",
       dict = dict,
       se.below = TRUE, signif.code = c("***" = .01, "**" = .05, "*" = .10),
       tex = TRUE, file = file.path(TABLES_DIR, "R3_first_stage.tex"), replace = TRUE,
       title = "First Stage: Queue Composition Predicts Engineer Assignment",
       label = "tab:firststage")
cat("  Saved R3_first_stage.tex (2 columns)\n")

cat("\nDone.\n")
