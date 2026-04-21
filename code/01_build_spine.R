# =============================================================================
# 01_build_spine.R
# Project: IAS Officer Education & Infrastructure Outcomes
# Purpose: Build the district-year panel spine from DMSP nightlights data.
#          This is the backbone all other datasets join onto.
# Reads:   path_dmsp_district  (dmsp_pc11dist.csv)
# Outputs: data/intermediate/panel_spine.csv
# =============================================================================

source("code/00_config.R")

# -----------------------------------------------------------------------------
# 1. Load DMSP district nightlights
# -----------------------------------------------------------------------------
raw <- read_csv(path_dmsp_district, show_col_types = FALSE)

cat("\n--- Raw file loaded ---\n")
cat("Rows:", nrow(raw), "\n")
cat("Columns:", paste(names(raw), collapse = ", "), "\n")

# -----------------------------------------------------------------------------
# 2. Keep only the columns we need and collapse multiple satellites per year
#    12 years (1994, 1997-2007) have 2 simultaneous DMSP satellites. dmsp_total_light_cal
#    is already inter-calibrated across sensors, so we average across satellites
#    within each district-year to produce one row per district-year.
# -----------------------------------------------------------------------------
spine <- raw %>%
  select(pc11_state_id, pc11_district_id, year, dmsp_total_light_cal) %>%
  group_by(pc11_state_id, pc11_district_id, year) %>%
  summarise(dmsp_total_light_cal = mean(dmsp_total_light_cal, na.rm = TRUE),
            n_satellites         = n(),
            .groups = "drop") %>%
  arrange(pc11_state_id, pc11_district_id, year)

cat("\n--- After collapsing satellites (mean within district-year) ---\n")
cat("Years with 2 satellites:", sum(spine$n_satellites == 2) / n_distinct(paste(spine$pc11_state_id, spine$pc11_district_id)), "\n")
spine <- select(spine, -n_satellites)   # drop helper column before saving

cat("\n--- After column selection ---\n")
cat("Rows:", nrow(spine), "\n")
cat("Unique districts:", n_distinct(spine$pc11_district_id), "\n")
cat("Unique state-district pairs:",
    n_distinct(paste(spine$pc11_state_id, spine$pc11_district_id)), "\n")
cat("Year range:", min(spine$year), "to", max(spine$year), "\n")
cat("Years present:", paste(sort(unique(spine$year)), collapse = ", "), "\n")

# -----------------------------------------------------------------------------
# 3. Check for missing values
# -----------------------------------------------------------------------------
miss <- spine %>%
  summarise(across(everything(), ~ mean(is.na(.)) * 100)) %>%
  pivot_longer(everything(), names_to = "variable", values_to = "pct_missing")

cat("\n--- Missing values (%) ---\n")
print(miss)

# -----------------------------------------------------------------------------
# 4. Check balance: is every district observed in every year?
# -----------------------------------------------------------------------------
n_years     <- n_distinct(spine$year)
n_dist      <- n_distinct(paste(spine$pc11_state_id, spine$pc11_district_id))
n_expected  <- n_years * n_dist
n_actual    <- nrow(spine)

cat("\n--- Panel balance ---\n")
cat("Districts x Years (expected):", n_expected, "\n")
cat("Actual rows:", n_actual, "\n")
cat("Unbalanced rows missing:", n_expected - n_actual, "\n")

# -----------------------------------------------------------------------------
# 5. Save
# -----------------------------------------------------------------------------
out_path <- file.path(path_intermediate, "panel_spine.csv")
write_csv(spine, out_path)

cat("\n--- Saved ---\n")
cat("Output:", out_path, "\n")
cat("Final dimensions:", nrow(spine), "rows x", ncol(spine), "cols\n")
