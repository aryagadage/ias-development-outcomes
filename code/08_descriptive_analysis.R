# =============================================================================
# 08_descriptive_analysis.R
# Project: IAS Officer Education & Infrastructure Outcomes
# Purpose: Descriptive figures and summary table on IAS officer education
#          groups, DC tenure, and posting patterns.
# Reads:   data/raw/ias-profile.csv
#          data/raw/ias-education.csv
#          data/raw/ias-experience.csv
# Outputs: output/figures/fig1_education_cohorts.pdf
#          output/figures/fig2_tenure_by_education.pdf
#          output/figures/fig3_posting_patterns.pdf
#          output/tables/table1_summary_stats.csv
# =============================================================================

source("code/00_config.R")

# Colour palette — consistent across all figures
edu_colours <- c(
  "Engineer"          = "#2166ac",
  "Social_Scientist"  = "#d6604d",
  "Residual"          = "#878787"
)
edu_levels <- c("Engineer", "Social_Scientist", "Residual")

# =============================================================================
# 1. Build officer-level education classification (identical to 07_merge_ias.R)
# =============================================================================
ed_raw <- read_csv(path_ias_education, show_col_types = FALSE)

eng_pattern <- "Engineering|Technology|Mathematics"
soc_pattern <- "Social Sci|Liberal Arts|Law|Governance|Management|Economics|Finance|Commerce"

ed_officer <- ed_raw %>%
  mutate(row_group = case_when(
    str_detect(Category_of_Subject, eng_pattern) ~ "Engineer",
    str_detect(Category_of_Subject, soc_pattern) ~ "Social_Scientist",
    TRUE                                          ~ "Residual"
  )) %>%
  group_by(ID) %>%
  summarise(
    education_group = case_when(
      any(row_group == "Engineer")         ~ "Engineer",
      any(row_group == "Social_Scientist") ~ "Social_Scientist",
      TRUE                                 ~ "Residual"
    ),
    .groups = "drop"
  ) %>%
  mutate(education_group = factor(education_group, levels = edu_levels))

# =============================================================================
# 2. Join profile → get allotment decade
# =============================================================================
profile <- read_csv(path_ias_profile, show_col_types = FALSE)

officer_data <- profile %>%
  select(ID, Allotment_Year, Cadre, Gender, Source_of_Recruitment) %>%
  left_join(ed_officer, by = "ID") %>%
  mutate(
    education_group = replace_na(as.character(education_group), "Residual"),
    education_group = factor(education_group, levels = edu_levels),
    decade = case_when(
      Allotment_Year < 1960 ~ "1950s",
      Allotment_Year < 1970 ~ "1960s",
      Allotment_Year < 1980 ~ "1970s",
      Allotment_Year < 1990 ~ "1980s",
      Allotment_Year < 2000 ~ "1990s",
      Allotment_Year < 2010 ~ "2000s",
      Allotment_Year < 2020 ~ "2010s",
      TRUE                  ~ NA_character_
    )
  ) %>%
  filter(!is.na(decade))

cat("\n--- Officer data ---\n")
cat("Officers with allotment decade:", nrow(officer_data), "\n")
cat("Education group distribution:\n")
print(count(officer_data, education_group) %>%
        mutate(pct = round(n / sum(n) * 100, 1)))

# =============================================================================
# 3. Extract DC spells and compute tenure
# =============================================================================
exp_raw <- read_csv(path_ias_experience, show_col_types = FALSE)

dc_pattern <- "^District Collector$|^District Collector and District Magistrate$|^District Magistrate$"

dc_spells <- exp_raw %>%
  filter(str_detect(Designation, dc_pattern),
         !is.na(Office), !is.na(Start_Date), !is.na(End_Date)) %>%
  mutate(
    start        = as.Date(Start_Date),
    end          = as.Date(End_Date),
    tenure_months = as.numeric(end - start) / 30.44
  ) %>%
  filter(tenure_months >= 0) %>%
  left_join(ed_officer, by = "ID")

cat("\n--- DC spells ---\n")
cat("Total spells:", nrow(dc_spells), "\n")
cat("Unique officers with DC posting:", n_distinct(dc_spells$ID), "\n")

# Officer-level DC summary
dc_by_officer <- dc_spells %>%
  group_by(ID) %>%
  summarise(
    n_dc_postings    = n(),
    total_dc_months  = sum(tenure_months, na.rm = TRUE),
    mean_dc_tenure   = mean(tenure_months, na.rm = TRUE),
    .groups = "drop"
  )

# =============================================================================
# FIGURE 1: Share of recruits by education_group × joining decade
# =============================================================================
fig1_data <- officer_data %>%
  count(decade, education_group) %>%
  group_by(decade) %>%
  mutate(share = n / sum(n)) %>%
  ungroup()

fig1 <- ggplot(fig1_data, aes(x = decade, y = share, fill = education_group)) +
  geom_col(position = "stack", width = 0.7) +
  scale_fill_manual(
    values = edu_colours,
    labels = c("Engineer", "Social Scientist", "Residual / Other"),
    name   = "Education group"
  ) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1),
                     expand = expansion(mult = c(0, 0.03))) +
  labs(
    title   = "IAS officer education background by joining cohort",
    x       = "Decade of allotment",
    y       = "Share of recruits"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    panel.grid.major.x = element_blank(),
    legend.position    = "bottom",
    plot.title         = element_text(face = "bold", size = 12)
  )

ggsave(file.path(path_figures, "fig1_education_cohorts.pdf"),
       fig1, width = 7, height = 4.5, device = "pdf")
cat("\nSaved fig1_education_cohorts.pdf\n")

# =============================================================================
# FIGURE 2: DC tenure (months) by education_group — violin + box overlay
# =============================================================================
fig2_data <- dc_spells %>%
  filter(!is.na(education_group), tenure_months <= 60)  # cap outliers at 5 years

fig2 <- ggplot(fig2_data,
               aes(x = education_group, y = tenure_months, fill = education_group)) +
  geom_violin(alpha = 0.6, colour = NA, trim = TRUE) +
  geom_boxplot(width = 0.15, outlier.shape = NA,
               colour = "grey30", fill = "white", alpha = 0.8) +
  scale_fill_manual(values = edu_colours, guide = "none") +
  scale_x_discrete(labels = c("Engineer", "Social\nScientist", "Residual /\nOther")) +
  scale_y_continuous(breaks = seq(0, 60, 12)) +
  labs(
    title = "District Collector tenure by officer education background",
    x     = "Education group",
    y     = "Tenure length (months)"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    panel.grid.major.x = element_blank(),
    plot.title         = element_text(face = "bold", size = 12)
  )

ggsave(file.path(path_figures, "fig2_tenure_by_education.pdf"),
       fig2, width = 6, height = 4.5, device = "pdf")
cat("Saved fig2_tenure_by_education.pdf\n")

# =============================================================================
# FIGURE 3: Share of DC postings by education_group, top 10 cadres
# =============================================================================
top10_cadres <- dc_spells %>%
  count(Cadre, sort = TRUE) %>%
  slice_head(n = 10) %>%
  pull(Cadre)

fig3_data <- dc_spells %>%
  filter(Cadre %in% top10_cadres, !is.na(education_group)) %>%
  count(Cadre, education_group) %>%
  group_by(Cadre) %>%
  mutate(share = n / sum(n)) %>%
  ungroup() %>%
  mutate(Cadre = fct_reorder(Cadre, -n, .fun = sum))

fig3 <- ggplot(fig3_data, aes(x = Cadre, y = share, fill = education_group)) +
  geom_col(position = "stack", width = 0.75) +
  scale_fill_manual(
    values = edu_colours,
    labels = c("Engineer", "Social Scientist", "Residual / Other"),
    name   = "Education group"
  ) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1),
                     expand = expansion(mult = c(0, 0.03))) +
  labs(
    title    = "Education background of DC officers by state cadre",
    subtitle = "Top 10 cadres by number of DC spells",
    x        = NULL,
    y        = "Share of DC spells"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    axis.text.x       = element_text(angle = 35, hjust = 1),
    panel.grid.major.x = element_blank(),
    legend.position   = "bottom",
    plot.title        = element_text(face = "bold", size = 12)
  )

ggsave(file.path(path_figures, "fig3_posting_patterns.pdf"),
       fig3, width = 8, height = 5, device = "pdf")
cat("Saved fig3_posting_patterns.pdf\n")

# =============================================================================
# TABLE 1: Summary statistics by education_group
# =============================================================================

# Officers who served as DC at least once
dc_ever <- dc_by_officer %>% pull(ID)

table1 <- officer_data %>%
  left_join(dc_by_officer, by = "ID") %>%
  group_by(education_group) %>%
  summarise(
    n_officers          = n(),
    n_served_as_dc      = sum(ID %in% dc_ever),
    share_served_as_dc  = round(mean(ID %in% dc_ever) * 100, 1),
    mean_dc_postings    = round(mean(n_dc_postings, na.rm = TRUE), 2),
    mean_tenure_months  = round(mean(mean_dc_tenure, na.rm = TRUE), 1),
    median_tenure_months = round(median(mean_dc_tenure, na.rm = TRUE), 1),
    .groups = "drop"
  )

cat("\n--- Table 1 ---\n")
print(table1)

write_csv(table1, file.path(path_tables, "table1_summary_stats.csv"))
cat("\nSaved table1_summary_stats.csv\n")

cat("\n=== All outputs saved ===\n")
cat("  output/figures/fig1_education_cohorts.pdf\n")
cat("  output/figures/fig2_tenure_by_education.pdf\n")
cat("  output/figures/fig3_posting_patterns.pdf\n")
cat("  output/tables/table1_summary_stats.csv\n")
