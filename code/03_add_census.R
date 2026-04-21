# =============================================================================
# 03_add_census.R
# Project: IAS Officer Education & Infrastructure Outcomes
# Purpose: Build district-level census baseline controls from 2001 and 2011
#          Population Census. Output is cross-sectional (one row per district).
#          2011: read district-level file directly (pc11 IDs).
#          2001: aggregate from shrid level to harmonise onto pc11 district IDs.
# Reads:   path_pca11_district   (pc11_pca_clean_pc11dist.csv -- pc11 district)
#          path_pca01_shrid      (pc01_pca_clean_shrid.csv    -- shrid level)
#          path_shrid_pc11dist   (shrid_pc11dist_key.csv      -- shrid -> pc11)
# Outputs: data/intermediate/census_baselines.csv
# =============================================================================

source("code/00_config.R")

# -----------------------------------------------------------------------------
# 1. Census 2011 -- already at pc11 district level
# -----------------------------------------------------------------------------
pca11_raw <- read_csv(path_pca11_district, show_col_types = FALSE)

pca11 <- pca11_raw %>%
  select(
    pc11_state_id, pc11_district_id,
    tot_p_11    = pc11_pca_tot_p,
    sc_p_11     = pc11_pca_p_sc,
    st_p_11     = pc11_pca_p_st,
    lit_p_11    = pc11_pca_p_lit,
    workers_p_11 = pc11_pca_tot_work_p
  ) %>%
  mutate(
    sc_share_11  = sc_p_11  / tot_p_11,
    st_share_11  = st_p_11  / tot_p_11,
    lit_rate_11  = lit_p_11 / tot_p_11,
    lfp_rate_11  = workers_p_11 / tot_p_11
  )

cat("\n--- Census 2011 loaded ---\n")
cat("Districts:", nrow(pca11), "\n")
cat("% missing tot_p:", round(mean(is.na(pca11$tot_p_11)) * 100, 1), "\n")

# -----------------------------------------------------------------------------
# 2. Census 2001 -- shrid level; aggregate to pc11 districts via crosswalk
# -----------------------------------------------------------------------------
pca01_raw <- read_csv(path_pca01_shrid,   show_col_types = FALSE)
key       <- read_csv(path_shrid_pc11dist, show_col_types = FALSE)

cat("\n--- Census 2001 raw ---\n")
cat("Shrid rows:", nrow(pca01_raw), "\n")

pca01_agg <- pca01_raw %>%
  select(
    shrid2,
    tot_p    = pc01_pca_tot_p,
    sc_p     = pc01_pca_p_sc,
    st_p     = pc01_pca_p_st,
    lit_p    = pc01_pca_p_lit,
    workers_p = pc01_pca_tot_work_p
  ) %>%
  inner_join(key, by = "shrid2") %>%
  group_by(pc11_state_id, pc11_district_id) %>%
  summarise(
    tot_p_01     = sum(tot_p,     na.rm = TRUE),
    sc_p_01      = sum(sc_p,      na.rm = TRUE),
    st_p_01      = sum(st_p,      na.rm = TRUE),
    lit_p_01     = sum(lit_p,     na.rm = TRUE),
    workers_p_01 = sum(workers_p, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    sc_share_01  = sc_p_01  / tot_p_01,
    st_share_01  = st_p_01  / tot_p_01,
    lit_rate_01  = lit_p_01 / tot_p_01,
    lfp_rate_01  = workers_p_01 / tot_p_01
  )

cat("\n--- Census 2001 aggregated to pc11 districts ---\n")
cat("Districts:", nrow(pca01_agg), "\n")
cat("% missing tot_p_01:", round(mean(is.na(pca01_agg$tot_p_01)) * 100, 1), "\n")

# -----------------------------------------------------------------------------
# 3. Join 2001 and 2011 into one cross-sectional file
# -----------------------------------------------------------------------------
out <- full_join(pca11, pca01_agg, by = c("pc11_state_id", "pc11_district_id")) %>%
  arrange(pc11_state_id, pc11_district_id)

# -----------------------------------------------------------------------------
# 4. Summary stats
# -----------------------------------------------------------------------------
cat("\n--- Output summary ---\n")
cat("Rows:", nrow(out), "\n")
cat("Unique state-district pairs:", n_distinct(paste(out$pc11_state_id, out$pc11_district_id)), "\n")
miss <- out %>%
  summarise(across(everything(), ~ round(mean(is.na(.)) * 100, 1))) %>%
  pivot_longer(everything(), names_to = "variable", values_to = "pct_missing") %>%
  filter(pct_missing > 0)
if (nrow(miss) > 0) { cat("Variables with missing values:\n"); print(miss) } else {
  cat("No missing values.\n")
}

# -----------------------------------------------------------------------------
# 5. Save
# -----------------------------------------------------------------------------
out_path <- file.path(path_intermediate, "census_baselines.csv")
write_csv(out, out_path)
cat("\nSaved:", out_path, "\n")
cat("Final dimensions:", nrow(out), "rows x", ncol(out), "cols\n")
