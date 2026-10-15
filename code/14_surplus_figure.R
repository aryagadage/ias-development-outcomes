#!/usr/bin/env Rscript
# ============================================================
#  code/14_surplus_figure.R
#  Two-panel surplus figure, alpha = 1/2, m = 1, N = 1 throughout.
#   (a) heatmap of the gain from tilt, sqrt(S(w) + D(w) t) - sqrt(S(w)),
#       over officer tilt t and district infrastructure share w, with the
#       calibrated tilt span shaded (point estimate and upper CI endpoint).
#   (b) expected % gain over the seniority queue against beta_comp, for
#       assortative pairing of the same officers and the full optimum,
#       computed with the functions in code/12_worked_example.R.
#
#  Outputs, one file per panel (existing files are backed up first):
#    figures/surplus_tilt_heatmap.pdf, figures/surplus_gain_beta.pdf   paper, 4.5in x 3.4in
#    figures/surplus_tilt_heatmap_slides.png, figures/surplus_gain_beta_slides.png
#                                                                      300 dpi, 16pt text
#
#  Run from repo root:  Rscript code/14_surplus_figure.R
# ============================================================
suppressPackageStartupMessages({
  library(ggplot2)
  })

# ── Worked-example functions from code/12_worked_example.R ───────────────────
# Evaluate its definitions only (skip the command-line block that prints).
we_exprs <- parse("code/12_worked_example.R")
is_def <- vapply(we_exprs, function(e) {
  is.call(e) && identical(e[[1]], as.name("<-")) &&
    !as.character(e[[2]]) %in% c("args", "betas")
}, logical(1))
for (e in we_exprs[is_def]) eval(e, envir = globalenv())
stopifnot(exists("worked_example"), exists("tilts_for"))

BETA_PT <- 0.0791
CI_LO   <- -0.0685
CI_HI   <- 0.2267
tmax_pt <- tilts_for(BETA_PT)$tmax
tmax_hi <- tilts_for(CI_HI)$tmax

# Same convention as script 12: assortative = sort on education label;
# full optimum = true optimum for beta >= 0, label-based optimum for beta < 0
# (sorting "as if" positive, which is a loss).
gains <- function(b) {
  we <- worked_example(tilts_for(b)$t)
  Wo <- if (b >= 0) we$Wopt else we$Wopt_label
  c(assortative = 100 * (we$Wa_label / we$Wq - 1),
    optimum     = 100 * (Wo / we$Wq - 1))
}

# Checks requested: +0.46% at 0.0791, -0.40% at -0.0685
g_pt <- gains(BETA_PT); g_lo <- gains(CI_LO); g_hi <- gains(CI_HI)
cat(sprintf("Assortative gain at %.4f: %+.4f%%  (full optimum %+.4f%%)\n", BETA_PT, g_pt[1], g_pt[2]))
cat(sprintf("Assortative gain at %.4f: %+.4f%%  (full optimum %+.4f%%)\n", CI_LO,  g_lo[1], g_lo[2]))
cat(sprintf("Assortative gain at %.4f: %+.4f%%  (full optimum %+.4f%%)\n", CI_HI,  g_hi[1], g_hi[2]))
stopifnot(round(g_pt[["assortative"]], 2) == 0.46,
          round(g_lo[["assortative"]], 2) == -0.40)

# ── Data ─────────────────────────────────────────────────────────────────────
S <- function(w) w^2 + (1 - w)^2
D <- function(w) (2 * w - 1) / 2
grid_a <- expand.grid(t = seq(-0.30, 0.30, length.out = 241),
                      w = seq(0.05, 0.95, length.out = 181))
grid_a$gain <- sqrt(S(grid_a$w) + D(grid_a$w) * grid_a$t) - sqrt(S(grid_a$w))
lim_a <- max(abs(grid_a$gain))

betas <- sort(unique(c(seq(-0.10, 0.30, by = 0.0025), BETA_PT, CI_LO, CI_HI)))
gb <- t(vapply(betas, gains, numeric(2)))
curve_b <- rbind(
  data.frame(beta = betas, gain = gb[, "assortative"], series = "Assortative pairing, same officers"),
  data.frame(beta = betas, gain = gb[, "optimum"],     series = "Full optimum"))
pts_b <- data.frame(beta = BETA_PT, gain = g_pt,
                    series = c("Assortative pairing, same officers", "Full optimum"))

# ── Plots: plain academic style, one file per panel ─────────────────────────
theme_paper <- function(base, family) {
  theme_classic(base_size = base, base_family = family) +
    theme(axis.text = element_text(colour = "black", size = base),
          axis.title = element_text(size = base),
          legend.text = element_text(size = base),
          legend.title = element_text(size = base),
          axis.line = element_line(linewidth = 0.3),
          axis.ticks = element_line(linewidth = 0.3),
          plot.margin = margin(5, 8, 5, 5))
}
fmt1 <- function(x) sprintf("%.1f", x)

# (a) Gain from tilt
plot_a <- function(base, family, lw) {
  ggplot(grid_a, aes(t, w)) +
    geom_raster(aes(fill = gain), interpolate = TRUE) +
    annotate("rect", xmin = -tmax_hi, xmax = tmax_hi, ymin = -Inf, ymax = Inf,
             fill = "grey40", alpha = 0.12) +
    annotate("rect", xmin = -tmax_pt, xmax = tmax_pt, ymin = -Inf, ymax = Inf,
             fill = "grey40", alpha = 0.25) +
    geom_contour(aes(z = gain), breaks = 0, colour = "black", linewidth = lw) +
    scale_fill_distiller(palette = "RdBu", direction = 1, limits = c(-lim_a, lim_a),
                         name = "Gain", labels = function(x) sprintf("%.2f", x)) +
    scale_x_continuous(expand = c(0, 0), breaks = seq(-0.3, 0.3, 0.1), labels = fmt1) +
    scale_y_continuous(expand = c(0, 0), breaks = seq(0.1, 0.9, 0.2), labels = fmt1) +
    labs(x = "Officer tilt (technical minus social)",
         y = expression("District infrastructure share, " * omega)) +
    theme_paper(base, family) +
    theme(legend.key.height = grid::unit(base * 2.5, "pt"),
          legend.key.width = grid::unit(base * 0.8, "pt"))
}

# (b) Expected gain over the queue
plot_b <- function(base, family, lw, pt) {
  ggplot(curve_b, aes(beta, gain, linetype = series)) +
    annotate("rect", xmin = CI_LO, xmax = CI_HI, ymin = -Inf, ymax = Inf,
             fill = "grey90") +
    geom_hline(yintercept = 0, linewidth = lw * 0.6, colour = "grey40") +
    geom_line(linewidth = lw) +
    geom_point(data = pts_b, size = pt) +
    scale_linetype_manual(values = c("Assortative pairing, same officers" = "solid",
                                     "Full optimum" = "dashed"),
                          labels = c("Assortative pairing", "Full optimum"), name = NULL) +
    scale_x_continuous(breaks = seq(-0.1, 0.3, 0.1), labels = fmt1) +
    labs(x = expression(beta^{comp}), y = "Gain over seniority queue (%)") +
    theme_paper(base, family) +
    theme(legend.position = "inside", legend.position.inside = c(0.03, 0.97),
          legend.justification = c(0, 1), legend.background = element_blank(),
          legend.key = element_blank(),
          legend.key.width = grid::unit(base * 2.2, "pt"))
}

# ── Save (back up any existing file first) ───────────────────────────────────
dir.create("figures", showWarnings = FALSE)
backup <- function(path) {
  if (file.exists(path)) {
    bak <- sub("(\\.[a-z]+)$", paste0("_bak_", format(Sys.time(), "%Y%m%d_%H%M%S"), "\\1"), path)
    stopifnot(file.copy(path, bak))
    cat(sprintf("Backed up %s -> %s\n", path, bak))
  }
}
save_both <- function(stem, p_paper, p_slides) {
  pdf_path <- sprintf("figures/%s.pdf", stem)
  png_path <- sprintf("figures/%s_slides.png", stem)
  backup(pdf_path); backup(png_path)
  ggsave(pdf_path, p_paper, width = 4.5, height = 3.4, units = "in", device = grDevices::pdf)
  ggsave(png_path, p_slides, width = 8, height = 6, units = "in", dpi = 300,
         device = ragg::agg_png, bg = "white")
  cat("Saved", pdf_path, "and", png_path, "\n")
}

save_both("surplus_tilt_heatmap", plot_a(10, "serif", 0.4), plot_a(16, "sans", 0.8))
save_both("surplus_gain_beta",    plot_b(10, "serif", 0.5, 1.6), plot_b(16, "sans", 1.0, 3.2))
cat(sprintf("Bands: t_max(%.4f) = %.5f, t_max(%.4f) = %.5f\n", BETA_PT, tmax_pt, CI_HI, tmax_hi))
