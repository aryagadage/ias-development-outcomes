#!/usr/bin/env Rscript
# ============================================================
#  code/12_worked_example.R
#  Standalone implementation of the Appendix E worked example
#  (5 officers, tilt t in {1, 1/2, 0, -1/2, -1} x t_max; 3 districts,
#  omega in {0.8, 0.5, 0.2}; alpha = 1/2, m_i = 1, N_j = 1).
#
#  Moved out of code/10_log_and_inference.R, which first re-implemented
#  Appendix E -- no other script in either repo computed it before that.
#
#  Usage:
#    Rscript code/12_worked_example.R                  # default betas
#    Rscript code/12_worked_example.R 0.0791 -0.0685 0.2267
#
#  Prints the illustrative table (tilts 0.8/0.4/0/-0.4/-0.8) and, for each
#  beta_comp supplied, the calibrated table exactly as reported in
#  Appendix E / Section 7.5.
# ============================================================

omega <- c(0.8, 0.5, 0.2)
S_j   <- omega^2 + (1 - omega)^2
D_j   <- (2 * omega - 1) / 2
perms3  <- rbind(c(1,2,3), c(1,3,2), c(2,1,3), c(2,3,1), c(3,1,2), c(3,2,1))
subsets <- combn(5, 3)

# V_ij = N_j sqrt(S_j m_i + D_j t_i), alpha = 1/2, m_i = 1, N_j = 1
V <- function(t) outer(t, seq_along(omega), function(tt, j) sqrt(S_j[j] + D_j[j] * tt))

# W of placing officers `who` (in district order 1..3) at their true tilts
W_of <- function(Vm, who) sum(Vm[cbind(who, 1:3)])

worked_example <- function(t) {
  Vm <- V(t)
  # Queue: uniform over which 3 of 5 officers are selected, uniform over
  # the 6 pairings of the selected 3 to the 3 districts.
  Wq <- mean(apply(subsets, 2, function(sub)
    mean(apply(perms3, 1, function(p) W_of(Vm, sub[p])))))
  # Assortative pairing BY EDUCATION LABEL: officer index 1 = most
  # technical education ("A") paired with the highest omega, etc. When the
  # true tilt order is reversed (beta < 0) this sorts "as if" beta were
  # positive, and the result is a loss relative to the queue.
  Wa_label <- mean(apply(subsets, 2, function(sub) W_of(Vm, sort(sub))))
  # Best pairing of the SAME selected officers, evaluated at true tilts.
  Wa_true  <- mean(apply(subsets, 2, function(sub)
    max(apply(perms3, 1, function(p) W_of(Vm, sub[p])))))
  # Full optimum under true tilts (free to re-select as well as re-pair).
  Wopt <- max(apply(subsets, 2, function(sub)
    max(apply(perms3, 1, function(p) W_of(Vm, sub[p])))))
  # Full optimum chosen AS IF label order were tilt order (i.e. using
  # |t| sorted descending to pick the subset/pairing), then evaluated at
  # the true tilts. Relevant only when beta < 0.
  t_asif <- sort(abs(t), decreasing = TRUE)
  Vas <- V(t_asif)
  best <- NULL; bestv <- -Inf
  for (s in seq_len(ncol(subsets))) for (r in seq_len(nrow(perms3))) {
    who <- subsets[, s][perms3[r, ]]
    v <- W_of(Vas, who)
    if (v > bestv + 1e-12) { bestv <- v; best <- who }
  }
  Wopt_label <- W_of(Vm, best)
  list(Wq = Wq, Wa_label = Wa_label, Wa_true = Wa_true,
       Wopt = Wopt, Wopt_label = Wopt_label)
}

tilts_for <- function(beta) {
  # t_i = log(e_i/s_i) is already in log space, so beta_comp (itself a log
  # ratio) identifies the tilt gap exactly: t_max = beta/2, no rho/exp
  # transform needed (that transform belonged to the retired linear-tilt
  # parametrization, t_i = e_i - s_i).
  tmax <- beta / 2
  list(tmax = tmax, t = tmax * c(1, 0.5, 0, -0.5, -1))
}

print_illustrative <- function() {
  cat("\n== Illustrative case (tilts 0.8, 0.4, 0, -0.4, -0.8) ==\n")
  ill <- worked_example(c(0.8, 0.4, 0, -0.4, -0.8))
  cat(sprintf(
    "  W(queue)=%.4f  W(assortative, same officers)=%.4f (%+.1f%%)  W(full optimum)=%.4f (%+.1f%%)\n",
    ill$Wq, ill$Wa_true, 100 * (ill$Wa_true / ill$Wq - 1),
    ill$Wopt, 100 * (ill$Wopt / ill$Wq - 1)))
  cat(sprintf("  Placement share of total loss: %.1f%%\n",
    100 * (ill$Wa_true - ill$Wq) / (ill$Wopt - ill$Wq)))

  Vi <- V(c(0.8, 0.4, 0, -0.4, -0.8))
  one_draw <- sapply(1:6, function(r) W_of(Vi, c(2, 3, 4)[perms3[r, ]]))
  cat(sprintf("  One draw (B,C,D): assortative=%.4f  mean over 6 pairings=%.4f  gain=%+.1f%%\n",
    max(one_draw), mean(one_draw), 100 * (max(one_draw) / mean(one_draw) - 1)))
  invisible(ill)
}

print_calibrated <- function(beta_comp) {
  for (b in beta_comp) {
    tt <- tilts_for(b)
    we <- worked_example(tt$t)
    Wa <- we$Wa_label
    Wo <- if (b >= 0) we$Wopt else we$Wopt_label
    cat(sprintf(
      "\n== Calibrated at beta_comp = %.4f (t_max = %.5f) ==\n", b, tt$tmax))
    cat(sprintf("  W(queue)=%.4f  W(assortative, same officers)=%.4f (%+.2f%%)  W(full optimum)=%.4f (%+.2f%%)\n",
      we$Wq, Wa, 100 * (Wa / we$Wq - 1), Wo, 100 * (Wo / we$Wq - 1)))
    loss <- we$Wopt - we$Wq
    if (abs(loss) > 1e-15) {
      cat(sprintf("  Placement share of total loss: %.1f%%\n",
        100 * (we$Wa_true - we$Wq) / loss))
    }
    if (b < 0) {
      cat("  NOTE: beta < 0 -- sorting on the education label is a LOSS relative to the queue;\n")
      cat("        the true optimum sorts the opposite way (shown as W_full_optimum above).\n")
    }
  }
}

args <- commandArgs(trailingOnly = TRUE)
# default: the paper's current calibration (0.075) and the three
# supplementary log(roads) calibration points (point estimate and the
# district-/state-clustered 95% CI bounds from task1_sign_contrast_log.csv)
betas <- if (length(args) > 0) as.numeric(args) else c(0.075, 0.0791, -0.0685, 0.2267)

print_illustrative()
print_calibrated(betas)
