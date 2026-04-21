# =============================================================================
# 04_add_econ_census.R
# Project: IAS Officer Education & Infrastructure Outcomes
# Purpose: Build a stacked district × EC-round panel of employment totals.
#          EC13: district-level file used directly (pc11 IDs).
#          EC90, EC98, EC05: shrid-level files aggregated via pc11 district key.
#          Output stacks all four rounds with a census_year column.
# Reads:   path_ec13_district    (ec13_pc11dist.csv)
#          path_ec05_shrid       (ec05_shrid.csv)
#          path_ec98_shrid       (ec98_shrid.csv)
#          path_ec90_shrid       (ec90_shrid.csv)
#          path_shrid_pc11dist   (shrid_pc11dist_key.csv -- shrid -> pc11)
# Outputs: data/intermediate/econ_census_district.csv
# =============================================================================

source("code/00_config.R")

key <- read_csv(path_shrid_pc11dist, show_col_types = FALSE)

# helper: aggregate shrid-level EC file to pc11 district, return renamed cols
agg_ec_shrid <- function(path, prefix, yr) {
  raw <- read_csv(path, show_col_types = FALSE)
  raw %>%
    select(shrid2,
           emp_all     = paste0(prefix, "_emp_all"),
           count_all   = paste0(prefix, "_count_all"),
           emp_manuf   = paste0(prefix, "_emp_manuf"),
           emp_services = paste0(prefix, "_emp_services")) %>%
    inner_join(key, by = "shrid2") %>%
    group_by(pc11_state_id, pc11_district_id) %>%
    summarise(across(c(emp_all, count_all, emp_manuf, emp_services),
                     ~ sum(.x, na.rm = TRUE)),
              .groups = "drop") %>%
    mutate(census_year = yr)
}

# -----------------------------------------------------------------------------
# 1. EC 2013 -- district-level file (pc11 IDs, use directly)
# -----------------------------------------------------------------------------
ec13_raw <- read_csv(path_ec13_district, show_col_types = FALSE)

ec13 <- ec13_raw %>%
  select(pc11_state_id, pc11_district_id,
         emp_all      = ec13_emp_all,
         count_all    = ec13_count_all,
         emp_manuf    = ec13_emp_manuf,
         emp_services = ec13_emp_services) %>%
  mutate(census_year = 2013)

cat("\n--- EC 2013 (district file) ---\n")
cat("Districts:", nrow(ec13), "\n")

# -----------------------------------------------------------------------------
# 2. EC 2005, 1998, 1990 -- aggregate from shrid
# -----------------------------------------------------------------------------
ec05 <- agg_ec_shrid(path_ec05_shrid, "ec05", 2005)
cat("\n--- EC 2005 (from shrid) ---\n")
cat("Districts:", nrow(ec05), "\n")

ec98 <- agg_ec_shrid(path_ec98_shrid, "ec98", 1998)
cat("\n--- EC 1998 (from shrid) ---\n")
cat("Districts:", nrow(ec98), "\n")

ec90 <- agg_ec_shrid(path_ec90_shrid, "ec90", 1990)
cat("\n--- EC 1990 (from shrid) ---\n")
cat("Districts:", nrow(ec90), "\n")

# -----------------------------------------------------------------------------
# 3. Stack all rounds
# -----------------------------------------------------------------------------
out <- bind_rows(ec90, ec98, ec05, ec13) %>%
  arrange(pc11_state_id, pc11_district_id, census_year)

# -----------------------------------------------------------------------------
# 4. Summary stats
# -----------------------------------------------------------------------------
cat("\n--- Stacked output ---\n")
cat("Rows:", nrow(out), "\n")
cat("Unique state-district pairs:", n_distinct(paste(out$pc11_state_id, out$pc11_district_id)), "\n")
cat("Census years:", paste(sort(unique(out$census_year)), collapse = ", "), "\n")
cat("Rows per census year:\n")
print(count(out, census_year))
miss <- out %>%
  summarise(across(c(emp_all, count_all, emp_manuf, emp_services),
                   ~ round(mean(is.na(.)) * 100, 1))) %>%
  pivot_longer(everything(), names_to = "variable", values_to = "pct_missing")
cat("Missing values (%):\n")
print(miss)

# -----------------------------------------------------------------------------
# 5. Save
# -----------------------------------------------------------------------------
out_path <- file.path(path_intermediate, "econ_census_district.csv")
write_csv(out, out_path)
cat("\nSaved:", out_path, "\n")
cat("Final dimensions:", nrow(out), "rows x", ncol(out), "cols\n")
