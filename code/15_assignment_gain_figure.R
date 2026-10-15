#!/usr/bin/env Rscript
# ============================================================
#  code/15_assignment_gain_figure.R
#  Single-panel figure for Appendix E ("Calibrated tilts"): expected %
#  gain over the seniority queue as a function of the composition
#  estimate beta_comp, for (a) pairing the same selected officers by
#  education and (b) re-selecting and pairing by education. Point
#  estimate and 95% CI are read from the log-ratio regression
#  (district + state x year FE, clustered by district) that
#  06_results.tex Section~\ref{sec:results-contrast} reports.
#
#  Output: figures/assignment_gain.pdf (existing file backed up first).
#
#  Run from repo root:  Rscript code/15_assignment_gain_figure.R
# ============================================================
suppressPackageStartupMessages(library(ggplot2))

# ── Worked-example functions from code/12_worked_example.R ───────────────────
we_exprs <- parse("code/12_worked_example.R")
is_def <- vapply(we_exprs, function(e) {
  is.call(e) && identical(e[[1]], as.name("<-")) &&
    !as.character(e[[2]]) %in% c("args", "betas")
}, logical(1))
for (e in we_exprs[is_def]) eval(e, envir = globalenv())
stopifnot(exists("worked_example"), exists("tilts_for"))

# ── Point estimate and 95% CI: log-ratio regression, district + state x year
#    FE, clustered by district -- the "first of these estimates" that
#    06_results.tex says Appendix E uses (Section~\ref{sec:results-contrast}).
log_fits <- read.csv("output/revision_oct2026/task1_sign_contrast_log.csv",
                      stringsAsFactors = FALSE)
row <- subset(log_fits, task == "1c" & spec == "district + state x year" &
              grepl("no offset", outcome, fixed = TRUE) &
              cluster == "district_id")
stopifnot(nrow(row) == 1)
stopifnot(round(row$coef, 3) == 0.079, round(row$se, 3) == 0.062)
cat(sprintf("Log-ratio estimate: beta=%.4f  SE=%.4f  95%% CI=[%.4f, %.4f]  (p=%.3f)\n",
            row$coef, row$se, row$ci95_lo, row$ci95_hi, row$p))

BETA_PT <- 0.079
CI_LO   <- row$ci95_lo
CI_HI   <- row$ci95_hi

# ── Gain over the queue, same convention as the Appendix E table: assortative
#    = sort on education label; full optimum = true optimum for beta >= 0,
#    label-based optimum for beta < 0 (sorting "as if" positive, a loss there).
gains <- function(b) {
  we <- worked_example(tilts_for(b)$t)
  Wo <- if (b >= 0) we$Wopt else we$Wopt_label
  c(pair = 100 * (we$Wa_label / we$Wq - 1),
    select_pair = 100 * (Wo / we$Wq - 1))
}

g_pt <- gains(BETA_PT)
cat(sprintf("At beta_comp = %.3f: pair by education %+.2f%%, select and pair %+.2f%%\n",
            BETA_PT, g_pt["pair"], g_pt["select_pair"]))

betas <- sort(unique(c(seq(-0.08, 0.25, by = 0.0025), BETA_PT, CI_LO, CI_HI)))
gb <- t(vapply(betas, gains, numeric(2)))
curve <- rbind(
  data.frame(beta = betas, gain = gb[, "pair"],        series = "Pair by education"),
  data.frame(beta = betas, gain = gb[, "select_pair"], series = "Select and pair by education"))
pts <- data.frame(beta = BETA_PT, gain = g_pt,
                   series = c("Pair by education", "Select and pair by education"))

# ── Plot ──────────────────────────────────────────────────────────────────────
plot_gain <- function(base, family, lw, pt) {
  ggplot(curve, aes(beta, gain, linetype = series)) +
    annotate("rect", xmin = CI_LO, xmax = CI_HI, ymin = -Inf, ymax = Inf,
             fill = "grey85") +
    geom_hline(yintercept = 0, linewidth = lw * 0.6, colour = "grey40") +
    geom_line(linewidth = lw) +
    geom_point(data = pts, size = pt) +
    scale_linetype_manual(values = c("Pair by education" = "solid",
                                     "Select and pair by education" = "dashed"),
                          name = NULL) +
    scale_x_continuous(breaks = seq(-0.05, 0.25, 0.05),
                       labels = function(x) sprintf("%.2f", x)) +
    labs(x = expression(beta^{comp}), y = "Gain over seniority queue (%)") +
    theme_classic(base_size = base, base_family = family) +
    theme(axis.text = element_text(colour = "black", size = base),
          axis.title = element_text(size = base),
          legend.text = element_text(size = base),
          axis.line = element_line(linewidth = 0.3),
          axis.ticks = element_line(linewidth = 0.3),
          legend.position = "inside", legend.position.inside = c(0.03, 0.97),
          legend.justification = c(0, 1), legend.background = element_blank(),
          legend.key = element_blank(),
          legend.key.width = grid::unit(base * 2.2, "pt"),
          plot.margin = margin(5, 8, 5, 5))
}

dir.create("figures", showWarnings = FALSE)
path <- "figures/assignment_gain.pdf"
if (file.exists(path)) {
  bak <- sub("(\\.[a-z]+)$", paste0("_bak_", format(Sys.time(), "%Y%m%d_%H%M%S"), "\\1"), path)
  stopifnot(file.copy(path, bak))
  cat(sprintf("Backed up %s -> %s\n", path, bak))
}
ggsave(path, plot_gain(10, "serif", 0.6, 1.8), width = 5.5, height = 3.6,
       units = "in", device = grDevices::pdf)
cat("Saved", path, "\n")
