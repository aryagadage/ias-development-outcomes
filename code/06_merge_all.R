# =============================================================================
# 06_merge_all.R
# Project: IAS Officer Education & Infrastructure Outcomes
# Purpose: Merge all intermediate datasets onto the panel spine to produce
#          the analysis-ready district-year panel (excluding IAS data).
#          Join logic:
#            roads        -- district x year (left join; sparse)
#            census       -- district only; 2001 cols for year<2011, 2011 cols for year>=2011
#            econ census  -- district x nearest EC round
#                           (1990: year<1998 | 1998: 1998-2004 | 2005: 2005-2012 | 2013: year>=2013)
#            elections    -- state x year (forward-filled from most recent election)
# Reads:   data/intermediate/panel_spine.csv
#          data/intermediate/roads_district_year.csv
#          data/intermediate/census_baselines.csv
#          data/intermediate/econ_census_district.csv
#          data/intermediate/elections_state_year.csv
# Outputs: data/final/panel_full.csv
# =============================================================================

source("code/00_config.R")

# -----------------------------------------------------------------------------
# 1. Load all intermediate files
# -----------------------------------------------------------------------------
spine     <- read_csv(file.path(path_intermediate, "panel_spine.csv"),      show_col_types = FALSE)
roads     <- read_csv(file.path(path_intermediate, "roads_district_year.csv"), show_col_types = FALSE)
census    <- read_csv(file.path(path_intermediate, "census_baselines.csv"), show_col_types = FALSE)
econ      <- read_csv(file.path(path_intermediate, "econ_census_district.csv"), show_col_types = FALSE)
elections <- read_csv(file.path(path_intermediate, "elections_state_year.csv"), show_col_types = FALSE)

cat("\n--- Spine:", nrow(spine), "rows |",
    n_distinct(paste(spine$pc11_state_id, spine$pc11_district_id)), "districts |",
    n_distinct(spine$year), "years ---\n")

# -----------------------------------------------------------------------------
# 2. Roads -- left join on district x year (sparse; missing years = no completions)
# -----------------------------------------------------------------------------
panel <- spine %>%
  left_join(roads, by = c("pc11_state_id", "pc11_district_id", "year"))

cat("After roads join:", nrow(panel), "rows |",
    round(mean(!is.na(panel$roads_completed)) * 100, 1), "% of district-years have road completions\n")

# -----------------------------------------------------------------------------
# 3. Census -- join all columns then select time-appropriate values
# -----------------------------------------------------------------------------
panel <- panel %>%
  left_join(census, by = c("pc11_state_id", "pc11_district_id")) %>%
  mutate(
    # Pick 2001 values for years before 2011, 2011 values from 2011 onwards
    tot_p    = if_else(year < 2011, tot_p_01,    tot_p_11),
    sc_share = if_else(year < 2011, sc_share_01, sc_share_11),
    st_share = if_else(year < 2011, st_share_01, st_share_11),
    lit_rate = if_else(year < 2011, lit_rate_01, lit_rate_11),
    lfp_rate = if_else(year < 2011, lfp_rate_01, lfp_rate_11)
  ) %>%
  select(-ends_with("_01"), -ends_with("_11"))   # drop raw suffix cols

cat("After census join:", nrow(panel), "rows |",
    round(mean(!is.na(panel$tot_p)) * 100, 1), "% non-missing tot_p\n")

# -----------------------------------------------------------------------------
# 4. Economic census -- assign nearest EC round then join
# -----------------------------------------------------------------------------
econ_wide <- econ %>%
  rename(ec_year = census_year,
         ec_emp_all      = emp_all,
         ec_count_all    = count_all,
         ec_emp_manuf    = emp_manuf,
         ec_emp_services = emp_services)

panel <- panel %>%
  mutate(ec_year = case_when(
    year < 1998               ~ 1990,
    year >= 1998 & year < 2005 ~ 1998,
    year >= 2005 & year < 2013 ~ 2005,
    year >= 2013              ~ 2013
  )) %>%
  left_join(econ_wide, by = c("pc11_state_id", "pc11_district_id", "ec_year")) %>%
  select(-ec_year)   # drop helper after join

cat("After econ census join:", nrow(panel), "rows |",
    round(mean(!is.na(panel$ec_emp_all)) * 100, 1), "% non-missing ec_emp_all\n")

# -----------------------------------------------------------------------------
# 5. Elections -- forward-fill each state's most recent election into every year
# -----------------------------------------------------------------------------

# Map election state names to pc11_state_id (zero-padded, 2011 Census codes)
# Telangana (formed 2014) maps to "28" (AP) since panel uses 2011 boundaries
state_id_map <- tribble(
  ~state,              ~pc11_state_id,
  "Andhra Pradesh",    "28",
  "Arunachal Pradesh", "12",
  "Assam",             "18",
  "Bihar",             "10",
  "Chhattisgarh",      "22",
  "Delhi",             "07",
  "Goa",               "30",
  "Gujarat",           "24",
  "Haryana",           "06",
  "Himachal Pradesh",  "02",
  "Jammu & Kashmir",   "01",
  "Jharkhand",         "20",
  "Karnataka",         "29",
  "Kerala",            "32",
  "Madhya Pradesh",    "23",
  "Maharashtra",       "27",
  "Manipur",           "14",
  "Meghalaya",         "17",
  "Mizoram",           "15",
  "Nagaland",          "13",
  "Odisha",            "21",
  "Puducherry",        "34",
  "Punjab",            "03",
  "Rajasthan",         "08",
  "Sikkim",            "11",
  "Tamil Nadu",        "33",
  "Telangana",         "28",
  "Tripura",           "16",
  "Uttar Pradesh",     "09",
  "Uttarakhand",       "05",
  "West Bengal",       "19"
)

panel_years <- sort(unique(panel$year))   # 1994:2013

# For each state x panel-year, assign the most recent election result
elections_panel <- elections %>%
  inner_join(state_id_map, by = "state") %>%
  select(pc11_state_id, election_year, winning_party, incumbent_won) %>%
  filter(election_year <= max(panel_years)) %>%
  # Cross with all panel years, keep only rows where election_year <= panel year,
  # then take the most recent election for each state-year
  crossing(year = panel_years) %>%
  filter(election_year <= year) %>%
  group_by(pc11_state_id, year) %>%
  slice_max(election_year, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  select(pc11_state_id, year, winning_party, incumbent_won)

panel <- panel %>%
  left_join(elections_panel, by = c("pc11_state_id", "year"))

cat("After elections join:", nrow(panel), "rows |",
    round(mean(!is.na(panel$winning_party)) * 100, 1), "% non-missing winning_party\n")

# -----------------------------------------------------------------------------
# 6. Save
# -----------------------------------------------------------------------------
out_path <- file.path(path_final, "panel_full.csv")
write_csv(panel, out_path)
cat("\nSaved:", out_path, "\n")

# -----------------------------------------------------------------------------
# 7. Final scorecard
# -----------------------------------------------------------------------------
key_vars <- c("dmsp_total_light_cal", "roads_completed", "road_length_km",
              "tot_p", "sc_share", "st_share", "lit_rate", "lfp_rate",
              "ec_emp_all", "ec_count_all", "ec_emp_manuf", "ec_emp_services",
              "winning_party", "incumbent_won")

scorecard <- tibble(variable = key_vars) %>%
  mutate(pct_nonmissing = map_dbl(variable,
    ~ round(mean(!is.na(panel[[.x]])) * 100, 1)))

cat("\n=== FINAL SCORECARD ===\n")
cat("Total rows:      ", nrow(panel), "\n")
cat("Unique districts:", n_distinct(paste(panel$pc11_state_id, panel$pc11_district_id)), "\n")
cat("Years:           ", min(panel$year), "to", max(panel$year), "\n")
cat("Columns:         ", ncol(panel), "\n\n")
cat("% non-missing by variable:\n")
print(scorecard, n = Inf)
