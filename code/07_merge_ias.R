# =============================================================================
# 07_merge_ias.R
# Project: IAS Officer Education & Infrastructure Outcomes
# Purpose: Classify IAS officers by education group, extract District Collector
#          spells, and merge onto the district-year panel.
# Reads:   path_ias_education    (ias-education.csv)
#          path_ias_experience   (ias-experience.csv)
#          data/final/panel_full.csv
# Outputs: data/final/panel_with_ias.csv
# =============================================================================

source("code/00_config.R")

# =============================================================================
# PART 1: Education classification
# Stopping point: confirm frequency table before proceeding to spell extraction.
# =============================================================================

ed_raw <- read_csv(path_ias_education, show_col_types = FALSE)

cat("\n--- Raw education file ---\n")
cat("Rows:", nrow(ed_raw), "| Unique officer IDs:", n_distinct(ed_raw$ID), "\n")
cat("Avg qualifications per officer:", round(nrow(ed_raw) / n_distinct(ed_raw$ID), 2), "\n")

# -----------------------------------------------------------------------------
# Classify each qualification row by Category_of_Subject
# Using str_detect so partial matches work across compound category strings.
# Engineer keywords:         "Engineering", "Technology", "Mathematics"
# Social_Scientist keywords: "Social Sci", "Liberal Arts", "Law",
#                            "Governance", "Management", "Economics",
#                            "Finance", "Commerce"
# Note: "Social Sci" (not "Social Sciences") matches "Social Science and Liberal Arts"
# -----------------------------------------------------------------------------
eng_pattern <- "Engineering|Technology|Mathematics"
soc_pattern <- "Social Sci|Liberal Arts|Law|Governance|Management|Economics|Finance|Commerce"

ed_classified <- ed_raw %>%
  mutate(
    row_group = case_when(
      str_detect(Category_of_Subject, eng_pattern) ~ "Engineer",
      str_detect(Category_of_Subject, soc_pattern) ~ "Social_Scientist",
      TRUE                                          ~ "Residual"
    )
  )

# -----------------------------------------------------------------------------
# Collapse to one row per officer.
# Priority rule: if an officer has ANY Engineering qualification → Engineer;
# else if ANY Social_Scientist qualification → Social_Scientist;
# else → Residual.
# Rationale: captures officers who hold an engineering degree alongside others.
# -----------------------------------------------------------------------------
ed_officer <- ed_classified %>%
  group_by(ID) %>%
  summarise(
    education_group = case_when(
      any(row_group == "Engineer")          ~ "Engineer",
      any(row_group == "Social_Scientist")  ~ "Social_Scientist",
      TRUE                                  ~ "Residual"
    ),
    .groups = "drop"
  ) %>%
  mutate(
    is_engineer          = as.integer(education_group == "Engineer"),
    is_social_scientist  = as.integer(education_group == "Social_Scientist")
  )

# -----------------------------------------------------------------------------
# Frequency table -- STOP HERE and confirm before proceeding
# -----------------------------------------------------------------------------
cat("\n--- Education group classification (priority: Engineer > Social_Scientist > Residual) ---\n")
cat("Note: officer classified as Engineer if ANY qualification is in Engineering/Tech/Maths\n\n")

freq <- ed_officer %>%
  count(education_group) %>%
  mutate(pct = round(n / sum(n) * 100, 1)) %>%
  arrange(desc(n))

print(freq)

cat("\nOmitted base category in regressions: Residual\n")

# =============================================================================
# PART 2: DC spell extraction and year expansion
# Designations treated as District Collector: "District Collector",
# "District Collector and District Magistrate", "District Magistrate"
# (DM = DC in most Indian states; subordinate roles excluded)
# =============================================================================

exp_raw <- read_csv(path_ias_experience, show_col_types = FALSE)

cat("\n--- Raw experience file ---\n")
cat("Rows:", nrow(exp_raw), "| Unique officer IDs:", n_distinct(exp_raw$ID), "\n")

# -----------------------------------------------------------------------------
# 2a. Filter to DC-level postings and parse dates
# -----------------------------------------------------------------------------
dc_pattern <- "^District Collector$|^District Collector and District Magistrate$|^District Magistrate$"

dc_spells <- exp_raw %>%
  filter(str_detect(Designation, dc_pattern)) %>%
  mutate(
    start_date = as.Date(Start_Date),
    end_date   = as.Date(End_Date),
    start_year = year(start_date),
    end_year   = year(end_date)
  ) %>%
  filter(
    !is.na(Office),          # drop spells with no district name
    !is.na(start_date),
    !is.na(end_date),
    end_date >= start_date,  # drop negative-length spells (data errors)
    start_year >= 1985       # panel-relevant years only
  ) %>%
  select(ID, Cadre, office_name = Office, start_year, end_year)

cat("\n--- DC spells after filtering ---\n")
cat("Spells:", nrow(dc_spells), "| Unique officers:", n_distinct(dc_spells$ID), "\n")
cat("Spells with missing Office (dropped):", sum(is.na(exp_raw %>%
  filter(str_detect(Designation, dc_pattern)) %>% pull(Office))), "\n")
cat("Year range:", min(dc_spells$start_year), "to", max(dc_spells$end_year), "\n")

# -----------------------------------------------------------------------------
# 2b. Expand each spell to one row per year
# An officer is counted as DC in year Y if start_year <= Y <= end_year.
# -----------------------------------------------------------------------------
dc_officer_year <- dc_spells %>%
  rowwise() %>%
  mutate(year = list(seq(start_year, end_year))) %>%
  unnest(year) %>%
  ungroup() %>%
  select(ID, Cadre, office_name, year)

cat("\n--- After year expansion ---\n")
cat("Officer-district-year rows:", nrow(dc_officer_year), "\n")

# If officer served in multiple districts in the same year (mid-year transfer),
# keep the spell that started later (most recent posting in that year).
dc_officer_year <- dc_spells %>%
  rowwise() %>%
  mutate(year = list(seq(start_year, end_year))) %>%
  unnest(year) %>%
  ungroup() %>%
  group_by(ID, year) %>%
  slice_max(start_year, n = 1, with_ties = FALSE) %>%  # latest spell wins
  ungroup() %>%
  select(ID, Cadre, office_name, year)

cat("After dedup (one district per officer-year):", nrow(dc_officer_year), "\n")

# -----------------------------------------------------------------------------
# 2c. Map IAS cadre → pc11_state_id
# Single-state cadres mapped directly. Multi-state cadres (AGMUT,
# Manipur-Tripura, Assam Meghalya) left as NA — state will be resolved
# via the district crosswalk in step 2d.
# Telangana mapped to "28" (Andhra Pradesh in 2011 Census boundaries).
# -----------------------------------------------------------------------------
cadre_state_map <- tribble(
  ~Cadre,                ~pc11_state_id,
  "Andhra Pradesh",      "28",
  "Bihar",               "10",
  "Chhattisgarh",        "22",
  "Gujarat",             "24",
  "Haryana",             "06",
  "Himachal Pradesh",    "02",
  "Jammu & Kashmir",     "01",
  "Jharkhand",           "20",
  "Karnataka",           "29",
  "Kerala",              "32",
  "Madhya Pradesh",      "23",
  "Maharashtra",         "27",
  "Manipur",             "14",
  "Meghalaya",           "17",
  "Mizoram",             "15",
  "Nagaland",            "13",
  "Odisha",              "21",
  "Punjab",              "03",
  "Rajasthan",           "08",
  "Sikkim",              "11",
  "Tamil Nadu",          "33",
  "Telangana",           "28",   # 2011 Census: part of Andhra Pradesh
  "Tripura",             "16",
  "Uttar Pradesh",       "09",
  "Uttarakhand",         "05",
  "West Bengal",         "19",
  # Multi-state cadres: state inferred from district crosswalk
  "A G M U T",          NA_character_,
  "Assam Meghalya",      NA_character_,
  "Manipur-Tripura",     NA_character_
)

dc_officer_year <- dc_officer_year %>%
  left_join(cadre_state_map, by = "Cadre")

cat("\n--- Cadre → pc11_state_id mapping ---\n")
cat("Rows with state ID resolved:  ",
    sum(!is.na(dc_officer_year$pc11_state_id)), "\n")
cat("Rows needing crosswalk (multi-state cadre):",
    sum(is.na(dc_officer_year$pc11_state_id)), "\n")

# =============================================================================
# PART 3: District name crosswalk → pc11_district_id
#
# SHRUG district files contain only numeric pc11_district_id; no name field.
# A crosswalk file must map (Cadre, office_name) → pc11_district_id.
#
# If data/raw/district_crosswalk.csv exists, the merge proceeds fully.
# If not, this script writes data/raw/district_crosswalk_todo.csv listing
# all unique (Cadre, office_name) pairs that need to be filled in, then stops.
#
# Crosswalk file format (fill in pc11_state_id and pc11_district_id columns):
#   cadre | office_name | pc11_state_id | pc11_district_id
# =============================================================================

crosswalk_path <- file.path(path_raw, "district_crosswalk.csv")
todo_path      <- file.path(path_raw, "district_crosswalk_todo.csv")

if (!file.exists(crosswalk_path)) {

  todo <- dc_officer_year %>%
    distinct(Cadre, office_name) %>%
    left_join(cadre_state_map, by = "Cadre") %>%
    arrange(Cadre, office_name) %>%
    mutate(pc11_district_id = NA_character_) %>%
    rename(cadre = Cadre)

  write_csv(todo, todo_path)

  cat("\n")
  cat("=================================================================\n")
  cat("District crosswalk not found at:\n  ", crosswalk_path, "\n\n")
  cat("Generated district_crosswalk_todo.csv with", nrow(todo), "unique\n")
  cat("(cadre, office_name) pairs at:\n  ", todo_path, "\n\n")
  cat("Fill in pc11_state_id and pc11_district_id for each row,\n")
  cat("save as data/raw/district_crosswalk.csv, then re-run.\n")
  cat("=================================================================\n")
  stop("Stopping: district crosswalk required to proceed.", call. = FALSE)

}

# =============================================================================
# PART 4: Full merge onto panel (runs once crosswalk exists)
# =============================================================================

crosswalk <- read_csv(crosswalk_path, show_col_types = FALSE) %>%
  mutate(across(c(pc11_state_id, pc11_district_id), as.character))

# Attach pc11_district_id to DC officer-year via crosswalk
dc_panel <- dc_officer_year %>%
  rename(cadre = Cadre) %>%
  left_join(crosswalk %>% select(cadre, office_name, pc11_district_id),
            by = c("cadre", "office_name")) %>%
  # For single-state cadres, pc11_state_id already set; crosswalk can also
  # supply/override it for multi-state cadres
  left_join(crosswalk %>% select(cadre, office_name,
                                  pc11_state_id_cw = pc11_state_id),
            by = c("cadre", "office_name")) %>%
  mutate(pc11_state_id = coalesce(pc11_state_id, pc11_state_id_cw)) %>%
  select(-pc11_state_id_cw) %>%
  filter(!is.na(pc11_district_id), !is.na(pc11_state_id)) %>%
  select(ID, pc11_state_id, pc11_district_id, year)

cat("\n--- DC panel after crosswalk join ---\n")
cat("District-year-officer rows:", nrow(dc_panel), "\n")

# If multiple officers matched to same district-year, keep one
# (data quality issue; flag count)
n_multi <- dc_panel %>% count(pc11_state_id, pc11_district_id, year) %>%
  filter(n > 1) %>% nrow()
cat("District-years with >1 officer matched:", n_multi, "\n")

dc_panel <- dc_panel %>%
  group_by(pc11_state_id, pc11_district_id, year) %>%
  slice(1) %>%
  ungroup()

# -----------------------------------------------------------------------------
# 4a. Join education group onto DC panel, then merge onto main panel
# -----------------------------------------------------------------------------
dc_panel <- dc_panel %>%
  left_join(ed_officer, by = "ID")

panel <- read_csv(file.path(path_final, "panel_full.csv"), show_col_types = FALSE)

panel_ias <- panel %>%
  left_join(dc_panel, by = c("pc11_state_id", "pc11_district_id", "year"))

# -----------------------------------------------------------------------------
# 4b. Final scorecard
# -----------------------------------------------------------------------------
cat("\n=== MERGE SCORECARD ===\n")
cat("Panel rows:", nrow(panel_ias), "\n")
cat("District-years with a matched DC officer:",
    sum(!is.na(panel_ias$ID)), "\n")
cat("Match rate:", round(mean(!is.na(panel_ias$ID)) * 100, 1), "%\n\n")
cat("Education group among matched district-years:\n")
print(panel_ias %>% filter(!is.na(education_group)) %>%
        count(education_group) %>%
        mutate(pct = round(n / sum(n) * 100, 1)))

out_path <- file.path(path_final, "panel_with_ias.csv")
write_csv(panel_ias, out_path)
cat("\nSaved:", out_path, "\n")
cat("Final dimensions:", nrow(panel_ias), "rows x", ncol(panel_ias), "cols\n")
