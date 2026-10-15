#!/usr/bin/env Rscript
# ============================================================
#  code/13_contrast_figure.R
#  Builds the welfare / infrastructure / contrast coefficient plot from
#  Table 1 (tab:r2a) columns (2) and (4): district x class + state x year
#  FE, district-clustered SEs, standardised (col 2) and log (col 4)
#  outcomes. Mirrors the model construction in code/11_tables_oct2026.R
#  exactly so the plotted Contrast row equals the published Table 1
#  Engineer:infra_k coefficients (0.1459 / 0.0956).
#
#  Outputs:
#    ../IAS-outcomes/figures/contrast_plot.pdf        (6.5in x 3in)
#    ../IAS-outcomes/figures/contrast_plot_slides.png (300dpi, 16:9-ish)
#
#  Run from the ias-development-outcomes repo root:
#    Rscript code/13_contrast_figure.R
# ============================================================
suppressPackageStartupMessages({
  library(fixest)
  library(dplyr)
  library(ggplot2)
  library(patchwork)
})

FIG_DIR <- "../IAS-outcomes/figures"
stopifnot(dir.exists(FIG_DIR))

if (file.exists(file.path(FIG_DIR, "contrast_plot.pdf"))) {
  file.copy(file.path(FIG_DIR, "contrast_plot.pdf"),
            file.path(FIG_DIR, "contrast_plot_pre_oct2026.pdf"), overwrite = FALSE)
}
if (file.exists(file.path(FIG_DIR, "contrast_plot_slides.png"))) {
  file.copy(file.path(FIG_DIR, "contrast_plot_slides.png"),
            file.path(FIG_DIR, "contrast_plot_slides_pre_oct2026.png"), overwrite = FALSE)
}

# ---------- 1. data + models (identical construction to code/11) -----------
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

fe2 <- "did_k + state_year + infra_k"
rhs <- paste("y ~ Engineer + Engineer:infra_k + Residual + Residual:infra_k +", ctrl)

stk_z   <- build_stack(std(df_roads$roads_rate), std(df_welf$emp_pc))
stk_log <- build_stack(log(df_roads$roads_rate), log(df_welf$emp_pc))

fit_std <- feols(as.formula(paste(rhs, "|", fe2)), data = stk_z,   cluster = ~district_id)
fit_log <- feols(as.formula(paste(rhs, "|", fe2)), data = stk_log, cluster = ~district_id)

stopifnot(abs(coef(fit_std)["Engineer:infra_k"] - 0.1459) < 1e-3)
stopifnot(abs(coef(fit_log)["Engineer:infra_k"] - 0.0956) < 1e-3)
cat("Replication check passed: contrast = 0.1459 (std), 0.0956 (log)\n")

# ---------- 2. coefficients, SEs (combined via vcov), CIs -------------------
coef_rows <- function(fit, label) {
  V <- vcov(fit)
  b <- coef(fit)
  bW <- b["Engineer"]
  seW <- sqrt(V["Engineer", "Engineer"])
  bC <- b["Engineer:infra_k"]
  seC <- sqrt(V["Engineer:infra_k", "Engineer:infra_k"])
  bR <- bW + bC
  seR <- sqrt(V["Engineer", "Engineer"] + V["Engineer:infra_k", "Engineer:infra_k"] +
                2 * V["Engineer", "Engineer:infra_k"])
  df_t <- degrees_freedom(fit, type = "t")
  z90 <- qt(0.95, df_t); z95 <- qt(0.975, df_t)
  data.frame(
    panel = label,
    row = factor(c("Welfare", "Infrastructure", "Contrast"),
                 levels = c("Contrast", "Infrastructure", "Welfare")),
    estimate = c(bW, bR, bC),
    se       = c(seW, seR, seC),
    stringsAsFactors = FALSE
  ) %>%
    mutate(lo90 = estimate - z90 * se, hi90 = estimate + z90 * se,
           lo95 = estimate - z95 * se, hi95 = estimate + z95 * se)
}

rows <- bind_rows(
  coef_rows(fit_std, "Standardised outcomes"),
  coef_rows(fit_log, "Log outcomes")
)
rows$panel <- factor(rows$panel, levels = c("Standardised outcomes", "Log outcomes"))

cat("\nPlotted beta^R (infrastructure effect, Engineer + Engineer:infra_k):\n")
print(rows[rows$row == "Infrastructure", c("panel", "estimate", "se")], row.names = FALSE)
write.csv(rows, "output/revision_oct2026/contrast_figure_values.csv", row.names = FALSE)

# ---------- 3. plot ----------------------------------------------------------
pal <- c(Welfare = "#4C72B0", Infrastructure = "#4C72B0", Contrast = "#C44E52")

make_panel <- function(d, title) {
  ggplot(d, aes(x = estimate, y = row, colour = row)) +
    geom_vline(xintercept = 0, linetype = "dashed", colour = "grey50") +
    geom_errorbarh(aes(xmin = lo95, xmax = hi95), height = 0, linewidth = 0.5) +
    geom_errorbarh(aes(xmin = lo90, xmax = hi90), height = 0, linewidth = 1.6) +
    geom_point(size = 2.6) +
    scale_colour_manual(values = pal, guide = "none") +
    labs(title = title, x = "Engineer coefficient", y = NULL) +
    theme_minimal(base_size = 11) +
    theme(panel.grid.minor = element_blank(),
          plot.title = element_text(size = 11, hjust = 0.5))
}

p1 <- make_panel(rows[rows$panel == "Standardised outcomes", ], "Standardised outcomes")
p2 <- make_panel(rows[rows$panel == "Log outcomes", ], "Log outcomes")

note <- "District x class and state x year fixed effects. 90% and 95% CIs, SEs clustered by district."

combined <- (p1 | p2) +
  plot_annotation(caption = note) &
  theme(plot.caption = element_text(size = 7, colour = "grey40", hjust = 0))

ggsave(file.path(FIG_DIR, "contrast_plot.pdf"), combined, width = 6.5, height = 3, units = "in")
cat("Saved", file.path(FIG_DIR, "contrast_plot.pdf"), "\n")

p1s <- make_panel(rows[rows$panel == "Standardised outcomes", ], "Standardised outcomes") +
  theme_minimal(base_size = 15) + theme(panel.grid.minor = element_blank(),
                                         plot.title = element_text(size = 15, hjust = 0.5))
p2s <- make_panel(rows[rows$panel == "Log outcomes", ], "Log outcomes") +
  theme_minimal(base_size = 15) + theme(panel.grid.minor = element_blank(),
                                         plot.title = element_text(size = 15, hjust = 0.5))
combined_s <- (p1s | p2s) +
  plot_annotation(caption = note) &
  theme(plot.caption = element_text(size = 10, colour = "grey40", hjust = 0))

ggsave(file.path(FIG_DIR, "contrast_plot_slides.png"), combined_s,
       width = 10, height = 5.625, units = "in", dpi = 300)
cat("Saved", file.path(FIG_DIR, "contrast_plot_slides.png"), "\n")
