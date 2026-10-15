#!/usr/bin/env Rscript
# code/run_ideas.R  —  IDEAS 1-3 + FALSIFICATION
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

# ── Stacked dataset ───────────────────────────────────────────────────────────
df_inf  <- df %>% filter(!is.na(roads_rate), year >= 2001) %>%
  mutate(k="infra",   infra_k=1L, y_z=z_roads, Y_signed=z_roads)
df_welf <- df %>% filter(!is.na(emp_pc),    year >= 2001) %>%
  mutate(k="welfare", infra_k=0L, y_z=z_emp,   Y_signed=-z_emp)
stk <- bind_rows(df_inf, df_welf)

stk$did_k  <- paste0(stk$district_id, "_", stk$infra_k)   # district×k
stk$sid_k  <- paste0(stk$state_id,    "_", stk$infra_k)   # state×k
stk$yr_k   <- paste0(stk$year_fac,    "_", stk$infra_k)   # year×k
med_ys     <- median(df$years_of_service, na.rm=TRUE)
stk$junior <- stk$years_of_service <= med_ys

cat(sprintf(
  "Stacked N=%d  (infra=%d, welfare=%d)  |  med YOS=%.1f  |  junior=%d senior=%d\n\n",
  nrow(stk), sum(stk$infra_k==1L), sum(stk$infra_k==0L),
  med_ys, sum(stk$junior, na.rm=TRUE), sum(!stk$junior, na.rm=TRUE)))

# KP-F for just-identified IV = t²(QueueT_st) in first stage
# (NOT the joint model F, which includes all controls)
safe_kp <- function(fit) {
  tryCatch({
    fs <- fit$iv_first_stage[["Engineer"]]
    t  <- as.numeric(coef(fs)["QueueT_st"] / se(fs)["QueueT_st"])
    t^2
  }, error = function(e) NA_real_)
}

fe_str   <- "did_k + sid_k + yr_k"
ctrl_str <- "allotment_year + tenure_months + opposition_turnover"

# ── IDEA 1: Pooled Signed OLS ─────────────────────────────────────────────────
cat("=== IDEA 1: Pooled Signed Outcome (OLS) ===\n")
# Y_signed = z(roads) for infra, -z(emp_pc) for welfare
# comparative advantage → one positive Engineer coefficient
fml1 <- as.formula(paste("Y_signed ~ Engineer + Residual +", ctrl_str, "|", fe_str))
fit1 <- feols(fml1, data=stk, cluster=~district_id)
b1 <- coef(fit1)["Engineer"]; se1 <- se(fit1)["Engineer"]
p1 <- pvalue(fit1)["Engineer"]; ci1 <- confint(fit1)["Engineer",]; n1 <- nobs(fit1)
cat(sprintf("  Engineer: b=%+.4f  SE=%.4f  p=%.3f  95%%CI=[%.4f, %.4f]  N=%d\n\n",
            b1, se1, p1, ci1[1], ci1[2], n1))

# ── IDEA 2: Junior / Senior split (sign-contrast form) ───────────────────────
cat("=== IDEA 2: Junior-DC Split (sign-contrast on each half) ===\n")
cat(sprintf("  Median years_of_service = %.1f; split is <=  vs  >\n", med_ys))
# Use unsigned z-scores + interaction so Eng:infra_k = beta_infra - beta_welfare
fml2 <- as.formula(paste(
  "y_z ~ Engineer + Engineer:infra_k + Residual + Residual:infra_k +",
  ctrl_str, "|", fe_str))

fit2j <- feols(fml2, data=filter(stk,  junior), cluster=~district_id)
fit2s <- feols(fml2, data=filter(stk, !junior), cluster=~district_id)

get_sc <- function(fit, lbl) {
  b  <- coef(fit)["Engineer:infra_k"];  se <- se(fit)["Engineer:infra_k"]
  p  <- pvalue(fit)["Engineer:infra_k"]; ci <- confint(fit)["Engineer:infra_k",]
  n  <- nobs(fit)
  cat(sprintf("  %s: Eng×infra_k=%+.4f  SE=%.4f  p=%.3f  CI=[%.4f,%.4f]  N=%d\n",
              lbl, b, se, p, ci[1], ci[2], n))
  list(b=b, se=se, p=p, ci=ci, n=n)
}
r2j <- get_sc(fit2j, sprintf("Junior  (YOS <= %.0f)", med_ys))
r2s <- get_sc(fit2s, sprintf("Senior  (YOS >  %.0f)", med_ys))
cat("\n")

# ── IDEA 3: IV Pooled Signed (2SLS) ──────────────────────────────────────────
cat("=== IDEA 3: IV Pooled Signed Outcome (2SLS) ===\n")

# First-stage check on stacked data
fml3_fs <- as.formula(paste("Engineer ~ QueueT_st + Residual +", ctrl_str, "|", fe_str))
fit3_fs  <- feols(fml3_fs, data=stk, cluster=~district_id)
kp_fs3 <- (as.numeric(coef(fit3_fs)["QueueT_st"] / se(fit3_fs)["QueueT_st"]))^2
cat(sprintf("  First stage (stacked N=%d): delta(QueueT_st)=%.4f  KP-F(t^2)=%.2f\n",
    nobs(fit3_fs), coef(fit3_fs)["QueueT_st"], kp_fs3))

fml3 <- as.formula(paste(
  "Y_signed ~ Residual +", ctrl_str, "|", fe_str, "| Engineer ~ QueueT_st"))
fit3 <- tryCatch(
  feols(fml3, data=stk, cluster=~district_id),
  error=function(e) tryCatch(
    feols(fml3, data=stk, vcov="hetero"),
    error=function(e2) NULL))

if (!is.null(fit3)) {
  b3  <- tryCatch(coef(fit3)["fit_Engineer"],    error=function(e) NA_real_)
  se3 <- tryCatch(se(fit3)["fit_Engineer"],      error=function(e) NA_real_)
  p3  <- tryCatch(pvalue(fit3)["fit_Engineer"],  error=function(e) NA_real_)
  ci3 <- tryCatch(confint(fit3)["fit_Engineer",],error=function(e) c(NA,NA))
  n3  <- nobs(fit3)
  kp3 <- safe_kp(fit3)
  cat(sprintf("  2SLS Engineer: b=%+.4f  SE=%.4f  p=%.3f  CI=[%.4f,%.4f]  N=%d  KP-F=%.2f\n",
              b3, se3, p3, ci3[1], ci3[2], n3, kp3))
  cat(sprintf("  OLS=%.4f vs 2SLS=%.4f → |2SLS| %s |OLS| (theory predicts >=)\n",
              b1, b3, ifelse(!is.na(b3) && abs(b3) >= abs(b1), ">=", "<")))
} else {
  cat("  2SLS failed to converge.\n")
  b3 <- se3 <- p3 <- kp3 <- NA_real_; ci3 <- c(NA,NA); n3 <- NA_integer_
}
cat("\n")

# ── FALSIFICATION: Nightlights ────────────────────────────────────────────────
cat("=== FALSIFICATION: Nightlights ===\n")
fml_f <- as.formula(paste(
  "lights_rural ~ Engineer + Residual +", ctrl_str,
  "| district_id + state_id + year_fac"))
fit_f <- feols(fml_f, data=df, cluster=~district_id)
bf  <- coef(fit_f)["Engineer"]; sef <- se(fit_f)["Engineer"]
pf  <- pvalue(fit_f)["Engineer"]; cif <- confint(fit_f)["Engineer",]; nf <- nobs(fit_f)
cat(sprintf("  Engineer on lights_rural: b=%+.4f  SE=%.4f  p=%.3f  CI=[%.4f,%.4f]  N=%d\n",
            bf, sef, pf, cif[1], cif[2], nf))
cat("  Note: null here is consistent-with, not confirmation-of, the theory.\n\n")

# ── SUMMARY TABLE (console) ───────────────────────────────────────────────────
star <- function(p) {
  if (is.na(p)) return("   ")
  if (p < 0.01) return("***")
  if (p < 0.05) return(" **")
  if (p < 0.10) return("  *")
  "   "
}

rows <- list(
  list(lab="1. Pooled signed OLS",
       b=b1, se=se1, p=p1, ci=ci1, n=n1),
  list(lab=sprintf("2a. Junior DCs (YOS<=%d) | Eng×infra_k", as.integer(med_ys)),
       b=r2j$b, se=r2j$se, p=r2j$p, ci=r2j$ci, n=r2j$n),
  list(lab=sprintf("2b. Senior DCs (YOS>%d)  | Eng×infra_k", as.integer(med_ys)),
       b=r2s$b, se=r2s$se, p=r2s$p, ci=r2s$ci, n=r2s$n),
  list(lab=sprintf("3. Pooled IV 2SLS [KP-F=%.2f]", kp3),
       b=b3,  se=se3, p=p3,  ci=ci3, n=n3),
  list(lab="Falsification: nightlights",
       b=bf,  se=sef, p=pf,  ci=cif, n=nf)
)

cat(strrep("=", 110), "\n SUMMARY\n", strrep("=", 110), "\n", sep="")
cat(sprintf("%-52s %9s %7s %5s  %-18s %6s\n",
            "Specification", "Coef.", "(SE)", "p", "95% CI", "N"))
cat(strrep("-", 106), "\n")
for (r in rows) {
  cat(sprintf("%-52s %+8.4f%s (%.4f) %.3f  [%+7.4f,%+7.4f] %6d\n",
      r$lab, r$b, star(r$p), r$se, r$p, r$ci[1], r$ci[2], r$n))
}

# ── LaTeX export ──────────────────────────────────────────────────────────────
ts <- function(p) {
  if (is.na(p)) return("")
  if (p < 0.01) return("$^{***}$")
  if (p < 0.05) return("$^{**}$")
  if (p < 0.10) return("$^{*}$")
  ""
}

tex_labs <- c(
  "\\quad 1.\\; Pooled signed OLS",
  sprintf("\\quad 2a.\\; Junior DCs (YOS $\\leq$ %d) \\hfill {\\small $\\hat{\\beta}_{\\text{Eng}\\times\\text{infra}}$}",
          as.integer(med_ys)),
  sprintf("\\quad 2b.\\; Senior DCs (YOS $>$ %d) \\hfill {\\small $\\hat{\\beta}_{\\text{Eng}\\times\\text{infra}}$}",
          as.integer(med_ys)),
  sprintf("\\quad 3.\\; Pooled IV 2SLS \\; [KP-$F$ $=$ %.2f]", kp3),
  "\\quad Falsification: nightlights"
)

sink("tables/ideas_summary.tex")
cat("\\begin{table}[htbp]\n\\centering\n")
cat("\\caption{Engineer Comparative Advantage --- Pooled and Split Tests}\n")
cat("\\label{tab:ideas_summary}\n")
cat("\\begin{tabular}{lrrrrc}\n\\toprule\n")
cat("Specification & Coef. & (SE) & $p$ & 95\\% CI & $N$ \\\\\n")
cat("\\midrule\n")
cat("\\multicolumn{6}{l}{\\textit{Panel A: Pooled Signed Outcome ($Y_{\\text{signed}}$)}} \\\\\n")
for (i in 1:3) {
  r <- rows[[i]]
  cat(sprintf("%s & $%+.4f$%s & $(%.4f)$ & $%.3f$ & $[%.4f,\\;%.4f]$ & $%d$ \\\\\n",
      tex_labs[i], r$b, ts(r$p), r$se, r$p, r$ci[1], r$ci[2], r$n))
}
cat("\\addlinespace\n")
cat("\\multicolumn{6}{l}{\\textit{Panel B: IV Estimate and Falsification}} \\\\\n")
for (i in 4:5) {
  r <- rows[[i]]
  cat(sprintf("%s & $%+.4f$%s & $(%.4f)$ & $%.3f$ & $[%.4f,\\;%.4f]$ & $%d$ \\\\\n",
      tex_labs[i], r$b, ts(r$p), r$se, r$p, r$ci[1], r$ci[2], r$n))
}
cat("\\bottomrule\n\\end{tabular}\n")
cat("\\par\\vspace{4pt}{\\footnotesize\n")
cat("\\textit{Notes:} All specifications include district$\\times k$, state$\\times k$, and year$\\times k$ fixed effects.\n")
cat("Controls: allotment cohort, tenure (months), opposition electoral turnover.\n")
cat("$Y_{\\text{signed}} = z(\\text{roads\\_rate})$ for $k=\\text{infra}$, $-z(\\text{emp\\_pc})$ for $k=\\text{welfare}$;\n")
cat("comparative advantage predicts a positive \\textit{Engineer} coefficient.\n")
cat("Rows 2a--2b report $\\hat{\\beta}_{\\text{Engineer}\\times\\mathbf{1}[k=\\text{infra}]}$ from the sign-contrast model\n")
cat("estimated on junior and senior DC subsamples separately.\n")
cat("Row 3: 2SLS instrument $= Q_{st}$ (engineer share of state-year DC pool); stacked sample doubles $N$.\n")
cat("Falsification: a near-zero nightlights coefficient is consistent with the theory\n")
cat("(infrastructure gain and welfare loss offsetting in aggregate light output).\n")
cat("SEs clustered at district level. $^{*}p<0.10$, $^{**}p<0.05$, $^{***}p<0.01$.}\n")
cat("\\end{table}\n")
sink()
cat("\nSaved tables/ideas_summary.tex\n")
