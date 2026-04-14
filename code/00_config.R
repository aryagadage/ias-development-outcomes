# =============================================================================
# 00_config.R
# Project: IAS Officer Education & Infrastructure Outcomes
# Purpose: Define all file paths and load shared packages.
#          Every other script sources this file first.
# =============================================================================

library(tidyverse)

# -----------------------------------------------------------------------------
# BASE PATHS  (edit these two lines if the project moves machines)
# -----------------------------------------------------------------------------
path_repo  <- "~/Documents/Github/ias-development-outcomes"
path_shrug <- "/Users/ag5276/Library/CloudStorage/GoogleDrive-ag5276@columbia.edu/My Drive/IAS Outcomes"

# -----------------------------------------------------------------------------
# REPO SUB-PATHS
# -----------------------------------------------------------------------------
path_raw          <- file.path(path_repo, "data/raw")
path_intermediate <- file.path(path_repo, "data/intermediate")
path_final        <- file.path(path_repo, "data/final")
path_code         <- file.path(path_repo, "code")
path_tables       <- file.path(path_repo, "output/tables")
path_figures      <- file.path(path_repo, "output/figures")

# -----------------------------------------------------------------------------
# SHRUG SOURCE DATA PATHS
# -----------------------------------------------------------------------------

# Nightlights (DMSP, 1992-2013) -- district level
path_dmsp_dir      <- file.path(path_shrug, "Nightlights/DMSP Night Lights (1992 - 2013)/shrug-dmsp-csv")
path_dmsp_district <- file.path(path_dmsp_dir, "dmsp_pc11dist.csv")

# Roads (PMGSY)
path_pmgsy_dir   <- file.path(path_shrug, "Roads/shrug-pmgsy-csv")
path_pmgsy_shrid <- file.path(path_pmgsy_dir, "pmgsy_2015_shrid.csv")

# Population Census
path_pc_keys_dir <- file.path(path_shrug, "Population Census/shrug-pc-keys-csv")
path_pca11_dir   <- file.path(path_shrug, "Population Census/shrug-pca11-csv 6.02.23 PM")
path_pc11r_key   <- file.path(path_pc_keys_dir, "pc11r_shrid_key.csv")

# Economic Census
path_ec_dir        <- file.path(path_shrug, "Economic Census")
path_ec13_district <- file.path(path_ec_dir, "shrug-ec13-csv/ec13_pc11dist.csv")

# Elections
path_elections_dir <- file.path(path_shrug, "Elections")
path_elections_xl  <- file.path(path_elections_dir, "Elections_Master.xlsx")
path_triv_cand_dir <- file.path(path_elections_dir, "shrug-triv-cand-csv")

# IAS officer data (already in data/raw/)
path_ias_profile    <- file.path(path_raw, "ias-profile.csv")
path_ias_education  <- file.path(path_raw, "ias-education.csv")
path_ias_experience <- file.path(path_raw, "ias-experience.csv")
