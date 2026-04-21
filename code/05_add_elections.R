# =============================================================================
# 05_add_elections.R
# Project: IAS Officer Education & Infrastructure Outcomes
# Purpose: Clean Elections_Master.xlsx (state × year political controls).
#          No merging here -- just read, inspect, clean, and save.
# Reads:   path_elections_xl     (Elections_Master.xlsx)
# Outputs: data/intermediate/elections_state_year.csv
# =============================================================================

source("code/00_config.R")

# -----------------------------------------------------------------------------
# 1. Load
# -----------------------------------------------------------------------------
raw <- read_excel(path_elections_xl)

cat("\n--- Raw Elections_Master ---\n")
cat("Rows:", nrow(raw), "\n")
cat("Columns:", ncol(raw), "\n")
cat("Column names:\n")
print(names(raw))

# -----------------------------------------------------------------------------
# 2. Inspect structure
# -----------------------------------------------------------------------------
cat("\n--- First few rows ---\n")
print(head(raw, 3))

cat("\n--- Column types ---\n")
print(glimpse(raw))

# -----------------------------------------------------------------------------
# 3. Clean: standardise names, drop all-NA columns, coerce obvious types
# -----------------------------------------------------------------------------
out <- raw %>%
  rename_with(~ str_to_lower(str_replace_all(., "\\s+", "_"))) %>%   # snake_case
  select(where(~ !all(is.na(.)))) %>%                                  # drop empty cols
  mutate(across(where(is.character), str_trim))                        # trim whitespace

# Coerce year column to integer if it looks numeric
if ("year" %in% names(out)) {
  out <- out %>% mutate(year = as.integer(year))
}

cat("\n--- After cleaning ---\n")
cat("Rows:", nrow(out), "\n")
cat("Columns:", ncol(out), "\n")

# -----------------------------------------------------------------------------
# 4. Summary stats
# -----------------------------------------------------------------------------
if ("year" %in% names(out)) {
  cat("Year range:", min(out$year, na.rm = TRUE), "to", max(out$year, na.rm = TRUE), "\n")
}

# Identify the state ID / name column and report unique states
state_cols <- names(out)[str_detect(names(out), "state")]
if (length(state_cols) > 0) {
  cat("Unique states (", state_cols[1], "):",
      n_distinct(out[[state_cols[1]]]), "\n")
}

miss <- out %>%
  summarise(across(everything(), ~ round(mean(is.na(.)) * 100, 1))) %>%
  pivot_longer(everything(), names_to = "variable", values_to = "pct_missing") %>%
  filter(pct_missing > 0)
if (nrow(miss) > 0) {
  cat("Variables with missing values:\n")
  print(miss)
} else {
  cat("No missing values.\n")
}

# -----------------------------------------------------------------------------
# 5. Save
# -----------------------------------------------------------------------------
out_path <- file.path(path_intermediate, "elections_state_year.csv")
write_csv(out, out_path)
cat("\nSaved:", out_path, "\n")
cat("Final dimensions:", nrow(out), "rows x", ncol(out), "cols\n")
