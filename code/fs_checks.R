#!/usr/bin/env Rscript
# code/fs_checks.R — First-stage strengthening checks (KP-F diagnostic)
suppressPackageStartupMessages({ library(fixest); library(dplyr) })

# ── Data ─────────────────────────────────────────────────────────────────────
df <- read.csv("data/analysis/dc_analysis_v2.csv")
qt <- read.csv("data/analysis/QueueT_st.csv",
               colClasses = c(state_id = "character"))
df$state_id         <- formatC(as.integer(df$state_id), width=2, flag="0")
df$years_of_service <- df$year - df$allotment_year
df$emp_pc           <- df$ec_emp_all / df$tot_p
df                  <- left_join(df, qt, by=c("state_id","year"))
df$year_fac         <- as.character(df$year)

zsc <- function(x) (x - mean(x, na.rm=TRUE)) / sd(x, na.rm=TRUE)
df$z_roads <- zsc(df$roads_rate)
df$z_emp   <- zsc(df$emp_pc)

# Stacked dataset (mirror of run_ideas.R)
df_inf  <- df %>% filter(!is.na(roads_rate), year >= 2001) %>%
  mutate(infra_k = 1L, y_z = z_roads, Y_signed = z_roads)
df_welf <- df %>% filter(!is.na(emp_pc),    year >= 2001) %>%
  mutate(infra_k = 0L, y_z = z_emp,   Y_signed = -z_emp)
stk <- bind_rows(df_inf, df_welf)
stk$did_k <- paste0(stk$district_id, "_", stk$infra_k)
stk$sid_k <- paste0(stk$state_id,    "_", stk$infra_k)
stk$yr_k  <- paste0(stk$year_fac,    "_", stk$infra_k)

# Unstacked year>=2001 panel
df_21 <- df[df$year >= 2001, ]

# KP-F for just-identified IV = t² on QueueT_st (clustered)
fs_kp <- function(fit) {
  t <- as.numeric(coef(fit)["QueueT_st"] / se(fit)["QueueT_st"])
  t^2
}

row_fmt <- "  %-58s  delta=%+.4f  KP-F=%6.2f  N=%d%s\n"
flag10  <- function(f) if (!is.na(f) && f >= 10) "  *** F>=10" else ""

all_rows <- list()
add_row <- function(label, fit) {
  d   <- as.numeric(coef(fit)["QueueT_st"])
  kpf <- fs_kp(fit)
  n   <- nobs(fit)
  cat(sprintf(row_fmt, label, d, kpf, n, flag10(kpf)))
  all_rows[[length(all_rows)+1]] <<- list(label=label, delta=d, kpf=kpf, n=n)
}

# ── CHECK 1: Trim controls (FE held at current: did_k + sid_k + yr_k) ────────
cat("\n=== CHECK 1: Control trimming | FE = did_k + sid_k + yr_k ===\n")
fe_curr <- "| did_k + sid_k + yr_k"

add_row("Full controls (baseline)",
  feols(as.formula(paste("Engineer ~ QueueT_st + Residual + allotment_year + tenure_months + opposition_turnover", fe_curr)),
        data=stk, cluster=~district_id))

add_row("Drop opposition_turnover",
  feols(as.formula(paste("Engineer ~ QueueT_st + Residual + allotment_year + tenure_months", fe_curr)),
        data=stk, cluster=~district_id))

add_row("Drop tenure_months",
  feols(as.formula(paste("Engineer ~ QueueT_st + Residual + allotment_year + opposition_turnover", fe_curr)),
        data=stk, cluster=~district_id))

add_row("Drop both (allotment_year + Residual only)",
  feols(as.formula(paste("Engineer ~ QueueT_st + Residual + allotment_year", fe_curr)),
        data=stk, cluster=~district_id))

# ── CHECK 2: FE structure (full controls held fixed) ─────────────────────────
cat("\n=== CHECK 2: FE structure | controls = full ===\n")
ctrl <- "QueueT_st + Residual + allotment_year + tenure_months + opposition_turnover"

# (a) current
add_row("(a) did_k + sid_k + yr_k  [current]",
  feols(as.formula(paste("Engineer ~", ctrl, "| did_k + sid_k + yr_k")),
        data=stk, cluster=~district_id))

# (b) drop state×k — keep district×k + year×k
add_row("(b) did_k + yr_k  [drop state×k]",
  feols(as.formula(paste("Engineer ~", ctrl, "| did_k + yr_k")),
        data=stk, cluster=~district_id))

# (c) common district + year (no k-interaction); add infra_k to absorb level shift
add_row("(c) district + year + infra_k  [no k-interaction on FE]",
  feols(as.formula(paste("Engineer ~", ctrl, "+ factor(infra_k) | district_id + year_fac")),
        data=stk, cluster=~district_id))

# (d) state×year FE — expected to absorb instrument (sanity check)
add_row("(d) district + state×year  [SHOULD ABSORB, sanity]",
  feols(as.formula(paste("Engineer ~", ctrl, "| district_id + state_id^year_fac")),
        data=stk, cluster=~district_id))

# ── CHECK 3: Non-stacked first stage ─────────────────────────────────────────
cat("\n=== CHECK 3: Non-stacked first stage | dist + state + year FE ===\n")

# Full panel (1994-2008, N=2390)
add_row("Unstacked: full panel (1994-2008)",
  feols(as.formula(paste("Engineer ~", ctrl, "| district_id + state_id + year_fac")),
        data=df, cluster=~district_id))

# Year>=2001 panel (matches stacked period)
add_row("Unstacked: year>=2001",
  feols(as.formula(paste("Engineer ~", ctrl, "| district_id + state_id + year_fac")),
        data=df_21, cluster=~district_id))

# Roads sample only (smallest, hardest)
df_rds <- df[!is.na(df$roads_rate) & df$year >= 2001, ]
add_row("Unstacked: roads sample only (year>=2001)",
  feols(as.formula(paste("Engineer ~", ctrl, "| district_id + state_id + year_fac")),
        data=df_rds, cluster=~district_id))

# ── SUMMARY ──────────────────────────────────────────────────────────────────
cat("\n", strrep("=",85), "\n COMBINED SUMMARY\n", strrep("=",85), "\n", sep="")
cat(sprintf("  %-58s  %6s  %5s  %s\n", "Specification", "KP-F", "N", ""))
cat(strrep("-",82), "\n")
for (r in all_rows) {
  fl <- flag10(r$kpf)
  cat(sprintf("  %-58s  %6.2f  %5d%s\n", r$label, r$kpf, r$n, fl))
}
cat("\nRule of thumb: KP-F >= 10 → instrument passes weak-IV test.\n")
cat("Stacked N is ~2x the native panel (each officer-district-year appears for both k).\n")
