# =============================================================================
# 02_add_roads.R
# Project: IAS Officer Education & Infrastructure Outcomes
# Purpose: Aggregate PMGSY road completion data from shrid to district × year.
#          Counts roads completed and sums road length per district per year.
# Reads:   path_pmgsy_shrid      (pmgsy_2015_shrid.csv   -- shrid level)
#          path_pc11r_key        (pc11r_shrid_key.csv     -- shrid -> district)
# Outputs: data/intermediate/roads_district_year.csv
# =============================================================================

source("code/00_config.R")

# -----------------------------------------------------------------------------
# 1. Load PMGSY roads (shrid level) and shrid-district key
# -----------------------------------------------------------------------------
roads_raw <- read_csv(path_pmgsy_shrid, show_col_types = FALSE)
key       <- read_csv(path_pc11r_key,   show_col_types = FALSE) %>%
  select(shrid2, pc11_state_id, pc11_district_id)

cat("\n--- Raw PMGSY rows:", nrow(roads_raw), "---\n")
cat("Unique shrids in roads:", n_distinct(roads_raw$shrid2), "\n")

# -----------------------------------------------------------------------------
# 2. Keep new-road variables only; extract completion year
# -----------------------------------------------------------------------------
roads <- roads_raw %>%
  select(shrid2, road_comp_date_new, road_length_new) %>%
  filter(!is.na(road_comp_date_new)) %>%
  mutate(
    # dates arrive as strings like "31/03/2006" or "2006-03-31" -- parse both
    comp_date = parse_date_time(road_comp_date_new, orders = c("dmy", "ymd"),
                                quiet = TRUE),
    year      = year(comp_date)
  ) %>%
  filter(!is.na(year))

cat("\n--- After parsing completion dates ---\n")
cat("Roads with valid completion date:", nrow(roads), "\n")
cat("Year range:", min(roads$year), "to", max(roads$year), "\n")

# -----------------------------------------------------------------------------
# 3. Join shrid -> pc11 district
# -----------------------------------------------------------------------------
roads_dist <- roads %>%
  inner_join(key, by = "shrid2")

cat("\n--- After joining shrid key ---\n")
cat("Rows retained:", nrow(roads_dist),
    "(dropped", nrow(roads) - nrow(roads_dist), "unmatched shrids)\n")

# -----------------------------------------------------------------------------
# 4. Aggregate to district × year
# -----------------------------------------------------------------------------
out <- roads_dist %>%
  group_by(pc11_state_id, pc11_district_id, year) %>%
  summarise(
    roads_completed = n(),
    road_length_km  = sum(road_length_new, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(pc11_state_id, pc11_district_id, year)

# -----------------------------------------------------------------------------
# 5. Summary stats
# -----------------------------------------------------------------------------
cat("\n--- Output summary ---\n")
cat("Rows:", nrow(out), "\n")
cat("Unique state-district pairs:", n_distinct(paste(out$pc11_state_id, out$pc11_district_id)), "\n")
cat("Year range:", min(out$year), "to", max(out$year), "\n")
cat("% missing road_length_km:", round(mean(is.na(out$road_length_km)) * 100, 1), "\n")
cat("Roads per district-year (median):", median(out$roads_completed), "\n")

# -----------------------------------------------------------------------------
# 6. Save
# -----------------------------------------------------------------------------
out_path <- file.path(path_intermediate, "roads_district_year.csv")
write_csv(out, out_path)
cat("\nSaved:", out_path, "\n")
cat("Final dimensions:", nrow(out), "rows x", ncol(out), "cols\n")
