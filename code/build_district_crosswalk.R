# =============================================================================
# build_district_crosswalk.R
# Purpose: Apply all crosswalk rules to district_crosswalk_todo.csv:
#   1. Drop departmental/non-geographic office_names
#   2. Fix pc11_state_id for cross-cadre postings (use 2011 boundaries)
#   3. Standardise old/alternate district names → canonical 2011 Census names
#   4. Disambiguate parenthetical names (e.g. "Hamirpur (UP)" → UP)
#   5. Handle AGMUT multi-state cadre (keep only genuine districts)
# pc11_district_id is left NA — fill from Census 2011 district code book
# and save as data/raw/district_crosswalk.csv.
# =============================================================================

suppressPackageStartupMessages(library(tidyverse))
path_raw <- "~/Documents/Github/ias-development-outcomes/data/raw"

todo <- read_csv(file.path(path_raw, "district_crosswalk_todo.csv"),
                 show_col_types = FALSE)
cat("Rows in todo:", nrow(todo), "\n")

# =============================================================================
# STEP 1: Flag and drop departmental / non-geographic office_names
# Rule: drop if name contains any of these keywords (case-insensitive)
# =============================================================================
dept_keywords <- paste(c(
  "Deptt", "Dept\\b", "Division\\b", "Authority", "\\bBoard\\b",
  "Corporation", "Corpn", "Secretariat", "Collectorate",
  "\\bRevenue\\b", "Supply", "Supplies", "\\bCivil\\b",
  "General Admin", "\\bAdministration\\b", "\\bAdmn\\b",
  "\\bD/o\\b", "\\bO/o\\b", "\\bM/o\\b", "\\bIndustries\\b",
  "\\bTourism\\b", "\\bPersonnel\\b", "\\bPlanning\\b",
  "\\bFinance\\b", "\\bAgriculture\\b", "\\bCooperation\\b",
  "\\bHome\\b", "\\bLabour\\b", "\\bLaw\\b(?!\\s+[A-Z])",
  "\\bLand\\b.*\\bReforms\\b", "\\bLand\\b.*\\bAcquisition\\b",
  "\\bLand\\b.*\\bBuildings\\b", "\\bLand\\b.*\\bLand\\b",
  "Disaster Mgmt", "Mgmt Auth", "GRIDCO", "OPTCL",
  "Bhavan", "Stamp", "\\bCommerce\\b", "Ppm\\b",
  "Drugs Pharma", "UP Drugs", "State.*Corpn", "Dev.*Corpn",
  "Govt\\.\\s*of", "Govt of", "Government of",
  "\\bDeptt$", "Reforms Deptt", "Admn,$",
  "^Administration$", "^Collectorate$", "^Commissioner$",
  "^Revenue$", "^Revenue & Finance", "^Revenue & Forest",
  "^Revenue Admn", "^Rev\\. Admn",
  "Stamp Revenue", "Social Justice.*Deptt",
  "Public Health", "Urban Dev", "Urban Housing",
  "Agri Production", "Appointments.*Deptt",
  "Panchayats Deptt", "Public Admin$",
  "Personnel.*Deptt", "Land Revenue & Disaster",
  "Revenue.*Disaster", "Revenue.*Forest",
  "Revenue.*Finance", "Land & Land Reforms",
  "Revenue Administration", "Civil Supplies"
), collapse = "|")

cw <- todo %>%
  mutate(is_dept = str_detect(office_name,
                               regex(dept_keywords, ignore_case = TRUE)))

n_dept   <- sum(cw$is_dept)
cw_clean <- filter(cw, !is_dept) %>% select(-is_dept)

cat("Dropped as departmental:", n_dept, "\n")
cat("Remaining genuine district rows:", nrow(cw_clean), "\n\n")

# =============================================================================
# STEP 2: Standardise old / alternate district names → canonical 2011 name
# Sources: user instructions + known Census 2011 name changes
# =============================================================================
name_fixes <- tribble(
  ~office_name,                       ~canonical_name,          ~note,
  # User-specified old → new
  "Cuddapah",                         "Kadapa",                 "renamed 2005",
  "Cuddapah(AP)",                     "Kadapa",                 "renamed 2005",
  "Monghyr",                          "Munger",                 "renamed",
  "Santhal Parganas",                 "Dumka",                  "HQ district post-split",
  "Boudh-Khondmals",                  "Kandhamal",              "renamed 2001",
  "North Arcot",                       "Vellore",               "split → Vellore is HQ",
  "South Arcot",                       "Cuddalore",             "split → Cuddalore is HQ",
  # Other common alternate names
  "Bhabhua",                           "Kaimur",                "HQ name → district name",
  "Chapra",                            "Saran",                 "HQ name → district name",
  "Motihari",                          "East Champaran",        "HQ name → district name",
  "Kodrama",                           "Koderma",               "spelling variant",
  "Nawadah",                           "Nawada",                "spelling variant",
  "Hazaribag",                         "Hazaribagh",            "spelling variant",
  "Gumala",                            "Gumla",                 "spelling variant",
  "Dindore",                           "Dindori",               "spelling variant",
  "Umeria",                            "Umaria",                "spelling variant",
  "Vishakapatnam",                     "Visakhapatnam",         "spelling variant",
  "Khordha / Khurda",                  "Khordha",               "slash variant",
  "Baleswar / Balasore",               "Balasore",              "slash variant",
  "Subarnapur / Sonepur",              "Subarnapur",            "slash variant",
  "Sonepur",                           "Subarnapur",            "old name",
  "Phulbani",                          "Kandhamal",             "renamed 2001",
  "Deogarh (OR)",                      "Deogarh",               "state disambig removed",
  "Bardhaman / Burdwan",               "Bardhaman",             "slash variant",
  "Medimipur(East)",                   "East Midnapore",        "variant",
  "Midnapore",                         "Paschim Medinipur",     "split → West Midnapore is default",
  "West Midnapore",                    "Paschim Medinipur",     "canonical name",
  "East Midnapore",                    "Purba Medinipur",       "canonical name",
  "Pashchim Medinipur",                "Paschim Medinipur",     "spelling variant",
  "West Dinajpur",                     "Dakshin Dinajpur",      "split → South Dinajpur",
  "North Dinajpur",                    "Uttar Dinajpur",        "canonical name",
  "South Dinajpur",                    "Dakshin Dinajpur",      "canonical name",
  "Alappuzha",                         "Alappuzha",             "correct",
  "Alleppey",                          "Alappuzha",             "old name",
  "Quilon",                            "Kollam",                "old name",
  "Palakkad/Palghat",                  "Palakkad",              "slash variant",
  "Thiruvananthapuram / Trivandrum",   "Thiruvananthapuram",    "slash variant",
  "Thrissoor",                         "Thrissur",              "spelling variant",
  "Thoothukudi / Tutukorin",           "Thoothukudi",           "slash variant",
  "Tiruchirapalli",                    "Tiruchirappalli",       "spelling variant",
  "Kancheepuram",                      "Kanchipuram",           "spelling variant",
  "Thiruvannamalai",                   "Tiruvannamalai",        "spelling variant",
  "Kakinada",                          "East Godavari",         "HQ→district (East Godavari HQ)",
  "Ariyalur(TN)",                      "Ariyalur",              "state suffix removed",
  "Aurangabad (MH)",                   "Aurangabad",            "state suffix removed",
  "Bijapur (CG)",                      "Bijapur",               "state suffix removed",
  "Bilaspur (CG)",                     "Bilaspur",              "CG = Chhattisgarh",
  "Pratapgarh (RJ)",                   "Pratapgarh",            "RJ = Rajasthan",
  "Hamirpur (UP)",                     "Hamirpur",              "UP version",
  "Kadapa(AP)",                        "Kadapa",                "state suffix removed",
  "Dhalai (Tripura)",                  "Dhalai",                "state suffix removed",
  "Ukhrul (Manipur)",                  "Ukhrul",                "state suffix removed",
  "West Garo Hills (Meghalaya)",       "West Garo Hills",       "state suffix removed",
  "Singhbhum East",                    "East Singhbhum",        "name order variant",
  "West Singhbhum(Chaibassa)",         "West Singhbhum",        "HQ appended",
  "Seraikela Kharaswan",               "Saraikela Kharsawan",   "spelling variant",
  "North Bastar & Kanker",             "Kanker",                "Kanker is the 2011 district name",
  "North Bastar (Kanker)",             "Kanker",                "Kanker is the 2011 district name",
  "South Bastar (Dantewara)",          "Dantewada",             "Dantewada is the 2011 name",
  "Kabeerdham",                        "Kabirdham",             "spelling variant",
  "Kawardha",                          "Kabirdham",             "HQ name (district renamed Kabirdham)",
  "Surguja",                           "Surguja",               "correct",
  "Sarguja",                           "Surguja",               "spelling variant",
  "Janjgir-Champa",                    "Janjgir-Champa",        "correct",
  "Janjgir",                           "Janjgir-Champa",        "full name",
  "Kanpur Dehat (Rural)",              "Kanpur Dehat",          "parenthetical removed",
  "Jyotiba Phule Nagar (JP Nagar)",    "Amroha",                "renamed 2012",
  "Kashiram Nagar",                    "Kasganj",               "renamed 2008",
  "Mahamaya Nagar",                    "Hathras",               "renamed 2012",
  "Prayagraj",                         "Allahabad",             "renamed 2018; use 2011 name",
  "Kanoj",                             "Kannauj",               "spelling variant",
  "Kaushambi",                         "Kaushambi",             "correct",
  "Kaushambhi",                        "Kaushambi",             "spelling variant",
  "Sant Ravidas Nagar",                "Bhadohi",               "also known as Bhadohi",
  "Sidharth Nagar",                    "Siddharthnagar",        "spelling variant",
  "Padrauna",                          "Kushinagar",            "HQ name (Padrauna→Kushinagar dist)",
  "Ambedkar Nagar",                    "Ambedkar Nagar",        "correct",
  "Shrawasti",                         "Shravasti",             "spelling variant",
  "Tehri-Garhwal",                     "Tehri Garhwal",         "hyphen variant",
  "Uttaranchal",                       "Uttarakhand",           "old state name; skip district",
  "Dakshina Kannada",                  "Dakshina Kannada",      "correct (Karnataka)",
  "Cachar (Assam)",                    "Cachar",                "state suffix removed",
  "Lakhimpur (Assam)",                 "Lakhimpur",             "state suffix removed",
  "Leh ( Ladakh)",                     "Leh",                   "parenthetical removed",
  "Raigad / Raigarh (MH)",             "Raigad",                "MH = Maharashtra (Raigad, not Raigarh)",
  "Dakshin Dinajpur",                  "Dakshin Dinajpur",      "correct",
  "Aruppukkottai",                     "Virudhunagar",          "HQ subdistrict; district is Virudhunagar",
  "Hosur",                             "Krishnagiri",           "Hosur is in Krishnagiri dist",
  "Tirumalai",                         "Tirunelveli",           "Tirumalai is in Tirunelveli dist",
  "Dharampur",                         "Valsad",                "Dharampur is in Valsad dist (GJ)",
  "Himatnagar",                        "Sabarkantha",           "Himatnagar is HQ of Sabarkantha",
  "Dohad",                             "Dahod",                 "spelling variant",
  "Mahesana",                          "Mehsana",               "spelling variant",
  "Godhra",                            "Panchmahal",            "Godhra is HQ of Panchmahal",
  "Tapi-Vyara",                        "Tapi",                  "Vyara is HQ; district is Tapi",
  "Kachchha",                          "Kutch",                 "variant spelling of Kutch",
  "Bhuj",                              "Kutch",                 "Bhuj is HQ of Kutch",
  "Greater Bombay",                    "Mumbai City",           "old name",
  "Greater Mumbai",                    "Mumbai City",           "variant",
  "Mumbai city",                       "Mumbai City",           "case variant",
  "Atnagiri",                          "Ratnagiri",             "likely typo",
  "Osmanabad",                         "Osmanabad",             "correct (use as-is; renamed Dharashiv 2023)",
  "Chnaglang (Aru. Pradesh)",          "Changlang",             "spelling fix",
  "Noida",                             "Gautam Buddha Nagar",   "Noida is in GBN dist",
  "Gautam Budh Nagar",                 "Gautam Buddha Nagar",   "spelling variant",
  "Sri Ganganagar",                    "Ganganagar",            "Census uses Ganganagar",
  "Durgapur",                          "Bardhaman",             "Durgapur is in Bardhaman dist (WB)",
  "Kolkata",                           "Kolkata",               "correct",
  "Sakaleshapur",                      "Hassan",                "Sakleshpur is in Hassan dist (KA)",
  "Chittorgarh",                       "Chittorgarh",           "correct (Rajasthan)",
  "Latur",                             "Latur",                 "correct (Maharashtra)",
  "Ambassa",                           "Khowai",                "Ambassa is in Khowai dist (Tripura 2011 boundary)",
  "Dharma Nagar",                      "North Tripura",         "Dharmanagar is in North Tripura",
  "Kailashahar",                       "Unakoti",               "Kailashahar is in Unakoti dist (Tripura)",
  "Udaipur",                           "Gomati",                "Udaipur (Tripura) is HQ of Gomati dist — NOT Rajasthan Udaipur",
  "Dhalai",                            "Dhalai",                "correct (Tripura)",
  "Khowai",                            "Khowai",                "correct (Tripura)"
)

# Apply name fixes
cw_clean <- cw_clean %>%
  left_join(name_fixes %>% distinct(office_name, .keep_all = TRUE) %>%
              select(office_name, canonical_name),
            by = "office_name") %>%
  mutate(
    display_name = coalesce(canonical_name, office_name),
    name_changed = !is.na(canonical_name)
  ) %>%
  select(-canonical_name)

cat("District names standardised:", sum(cw_clean$name_changed), "\n\n")

# =============================================================================
# STEP 3: Fix pc11_state_id using cadre + disambiguated name rules
# Covers: cross-cadre districts (2011 boundaries), disambiguated parentheticals,
# multi-state cadres (AGMUT, Assam Meghalya, Manipur-Tripura), Telangana→28
# =============================================================================

# State override table: when cadre cadre_val has office_name matching pattern,
# set pc11_state_id to override_state. Ordered: first match wins.
state_overrides <- tribble(
  ~cadre,            ~name_pattern,                 ~override_state, ~note,
  # Disambiguated parentheticals — user's rules
  "Uttar Pradesh",   "Hamirpur",                    "09",  "Hamirpur (UP) not HP",
  "Chhattisgarh",    "Bilaspur",                    "22",  "CG Bilaspur not HP",
  "Rajasthan",       "Pratapgarh",                  "08",  "RJ not UP",
  "Maharashtra",     "Aurangabad",                  "27",  "MH not Bihar",
  "Rajasthan",       "Udaipur",                     "08",  "Rajasthan Udaipur",
  # Tripura-cadre Udaipur must be Gomati/Tripura (handled via name_fixes)
  # Cross-cadre: Jharkhand districts appearing under Bihar cadre → state 20
  "Bihar",           "Bokaro",                      "20",  "Jharkhand 2011",
  "Bihar",           "Chatra",                      "20",  "Jharkhand 2011",
  "Bihar",           "Deoghar",                     "20",  "Jharkhand 2011",
  "Bihar",           "Dhanbad",                     "20",  "Jharkhand 2011",
  "Bihar",           "Dumka",                       "20",  "Jharkhand 2011",
  "Bihar",           "East Singhbhum",              "20",  "Jharkhand 2011",
  "Bihar",           "Garhwa",                      "20",  "Jharkhand 2011",
  "Bihar",           "Giridih",                     "20",  "Jharkhand 2011",
  "Bihar",           "Godda",                       "20",  "Jharkhand 2011",
  "Bihar",           "Gumla",                       "20",  "Jharkhand 2011",
  "Bihar",           "Hazaribagh",                  "20",  "Jharkhand 2011",
  "Bihar",           "Jamtara",                     "20",  "Jharkhand 2011",
  "Bihar",           "Khunti",                      "20",  "Jharkhand 2011",
  "Bihar",           "Koderma",                     "20",  "Jharkhand 2011",
  "Bihar",           "Latehar",                     "20",  "Jharkhand 2011",
  "Bihar",           "Lohardaga",                   "20",  "Jharkhand 2011",
  "Bihar",           "Pakur",                       "20",  "Jharkhand 2011",
  "Bihar",           "Palamu",                      "20",  "Jharkhand 2011",
  "Bihar",           "Ramgarh",                     "20",  "Jharkhand 2011",
  "Bihar",           "Ranchi",                      "20",  "Jharkhand 2011",
  "Bihar",           "Sahebganj",                   "20",  "Jharkhand 2011",
  "Bihar",           "Sahibganj",                   "20",  "Jharkhand 2011",
  "Bihar",           "Saraikela Kharsawan",         "20",  "Jharkhand 2011",
  "Bihar",           "Simdega",                     "20",  "Jharkhand 2011",
  "Bihar",           "West Singhbhum",              "20",  "Jharkhand 2011",
  "Bihar",           "Santhal Parganas",            "20",  "Dumka, Jharkhand",
  # Cross-cadre: Bihar/UP districts appearing under Jharkhand cadre → correct state
  "Jharkhand",       "Patna",                       "10",  "Bihar",
  "Jharkhand",       "Gaya",                        "10",  "Bihar",
  "Jharkhand",       "Bhagalpur",                   "10",  "Bihar",
  "Jharkhand",       "Muzaffarpur",                 "10",  "Bihar",
  "Jharkhand",       "Darbhanga",                   "10",  "Bihar",
  "Jharkhand",       "Nalanda",                     "10",  "Bihar",
  "Jharkhand",       "Araria",                      "10",  "Bihar",
  "Jharkhand",       "Banka",                       "10",  "Bihar",
  "Jharkhand",       "Begusarai",                   "10",  "Bihar",
  "Jharkhand",       "Buxar",                       "10",  "Bihar",
  "Jharkhand",       "East Champaran",              "10",  "Bihar",
  "Jharkhand",       "Gopalganj",                   "10",  "Bihar",
  "Jharkhand",       "Jamui",                       "10",  "Bihar",
  "Jharkhand",       "Katihar",                     "10",  "Bihar",
  "Jharkhand",       "Khagaria",                    "10",  "Bihar",
  "Jharkhand",       "Kishanganj",                  "10",  "Bihar",
  "Jharkhand",       "Madhepura",                   "10",  "Bihar",
  "Jharkhand",       "Madhubani",                   "10",  "Bihar",
  "Jharkhand",       "Munger",                      "10",  "Bihar",
  "Jharkhand",       "Nawada",                      "10",  "Bihar",
  "Jharkhand",       "Purnia",                      "10",  "Bihar",
  "Jharkhand",       "Rohtas",                      "10",  "Bihar",
  "Jharkhand",       "Saharsa",                     "10",  "Bihar",
  "Jharkhand",       "Samastipur",                  "10",  "Bihar",
  "Jharkhand",       "Saran",                       "10",  "Bihar",
  "Jharkhand",       "Sitamarhi",                   "10",  "Bihar",
  "Jharkhand",       "Siwan",                       "10",  "Bihar",
  "Jharkhand",       "Supaul",                      "10",  "Bihar",
  "Jharkhand",       "Vaishali",                    "10",  "Bihar",
  "Jharkhand",       "West Champaran",              "10",  "Bihar",
  "Jharkhand",       "Odisha",                      "21",  "drop — state name not district",
  # Cross-cadre: Uttarakhand cadre officers in UP districts → UP (09)
  "Uttarakhand",     "Agra",                        "09",  "UP not UK",
  "Uttarakhand",     "Aligarh",                     "09",  "UP not UK",
  "Uttarakhand",     "Allahabad",                   "09",  "UP not UK",
  "Uttarakhand",     "Ambedkar Nagar",              "09",  "UP not UK",
  "Uttarakhand",     "Auraiya",                     "09",  "UP not UK",
  "Uttarakhand",     "Azamgarh",                    "09",  "UP not UK",
  "Uttarakhand",     "Badaun",                      "09",  "UP not UK",
  "Uttarakhand",     "Bahraich",                    "09",  "UP not UK",
  "Uttarakhand",     "Ballia",                      "09",  "UP not UK",
  "Uttarakhand",     "Banda",                       "09",  "UP not UK",
  "Uttarakhand",     "Barabanki",                   "09",  "UP not UK",
  "Uttarakhand",     "Bareilly",                    "09",  "UP not UK",
  "Uttarakhand",     "Basti",                       "09",  "UP not UK",
  "Uttarakhand",     "Bijnor",                      "09",  "UP not UK",
  "Uttarakhand",     "Bulandshahr",                 "09",  "UP not UK",
  "Uttarakhand",     "Etah",                        "09",  "UP not UK",
  "Uttarakhand",     "Etawah",                      "09",  "UP not UK",
  "Uttarakhand",     "Faizabad",                    "09",  "UP not UK",
  "Uttarakhand",     "Farukhabad",                  "09",  "UP not UK",
  "Uttarakhand",     "Fatehpur",                    "09",  "UP not UK",
  "Uttarakhand",     "Ghazipur",                    "09",  "UP not UK",
  "Uttarakhand",     "Gautam Buddha Nagar",         "09",  "UP not UK",
  "Uttarakhand",     "Gorakhpur",                   "09",  "UP not UK",
  "Uttarakhand",     "Jhansi",                      "09",  "UP not UK",
  "Uttarakhand",     "Kaushambi",                   "09",  "UP not UK",
  "Uttarakhand",     "Kheri",                       "09",  "UP not UK",
  "Uttarakhand",     "Lalitpur",                    "09",  "UP not UK",
  "Uttarakhand",     "Lakhimpur Kheri",             "09",  "UP not UK",
  "Uttarakhand",     "Maharajganj",                 "09",  "UP not UK",
  "Uttarakhand",     "Mahoba",                      "09",  "UP not UK",
  "Uttarakhand",     "Mainpuri",                    "09",  "UP not UK",
  "Uttarakhand",     "Mirzapur",                    "09",  "UP not UK",
  "Uttarakhand",     "Moradabad",                   "09",  "UP not UK",
  "Uttarakhand",     "Muzaffarnagar",               "09",  "UP not UK",
  "Uttarakhand",     "Pilibhit",                    "09",  "UP not UK",
  "Uttarakhand",     "Rae Bareli",                  "09",  "UP not UK",
  "Uttarakhand",     "Rampur",                      "09",  "UP not UK",
  "Uttarakhand",     "Saharanpur",                  "09",  "UP not UK",
  "Uttarakhand",     "Shahjahanpur",                "09",  "UP not UK",
  "Uttarakhand",     "Siddharthnagar",              "09",  "UP not UK",
  "Uttarakhand",     "Sitapur",                     "09",  "UP not UK",
  "Uttarakhand",     "Sultanpur",                   "09",  "UP not UK",
  "Uttarakhand",     "Unnao",                       "09",  "UP not UK",
  "Uttarakhand",     "Varanasi",                    "09",  "UP not UK",
  # UK-proper districts (stay in 05) are handled by cadre default
  # Multi-state cadres: AGMUT → assign by district geography
  "A G M U T",      "Karaikal",                    "34",  "Puducherry",
  "A G M U T",      "Mahe",                        "34",  "Puducherry",
  "A G M U T",      "Yanam",                       "34",  "Puducherry",
  "A G M U T",      "Pondicherry",                 "34",  "Puducherry",
  "A G M U T",      "Puducherry",                  "34",  "Puducherry",
  "A G M U T",      "N C T of Delhi",              "07",  "Delhi",
  "A G M U T",      "New Delhi",                   "07",  "Delhi",
  "A G M U T",      "South Delhi",                 "07",  "Delhi",
  "A G M U T",      "North Delhi",                 "07",  "Delhi",
  "A G M U T",      "Changlang",                   "12",  "Arunachal Pradesh",
  "A G M U T",      "Lohit",                       "12",  "Arunachal Pradesh",
  "A G M U T",      "East Siang",                  "12",  "Arunachal Pradesh",
  "A G M U T",      "North Goa",                   "30",  "Goa",
  "A G M U T",      "South Goa",                   "30",  "Goa",
  "A G M U T",      "Goa",                         "30",  "Goa (whole state)",
  "A G M U T",      "Aizawl",                      "15",  "Mizoram",
  "A G M U T",      "Lunglei",                     "15",  "Mizoram",
  "A G M U T",      "Daman",                       "25",  "Daman & Diu",
  "A G M U T",      "Diu",                         "25",  "Daman & Diu",
  "A G M U T",      "Dadra Nagar Haveli",          "26",  "Dadra & Nagar Haveli",
  "A G M U T",      "Haveli",                      "26",  "Dadra & Nagar Haveli",
  "A G M U T",      "Lakshadweep",                 "31",  "Lakshadweep",
  "A G M U T",      "L M Islands",                 "31",  "Lakshadweep",
  "A G M U T",      "Alipurduar",                  "19",  "West Bengal (inter-cadre)",
  # Manipur-Tripura cadre
  "Manipur-Tripura", "Dhalai",                     "16",  "Tripura",
  "Manipur-Tripura", "North Tripura",              "16",  "Tripura",
  "Manipur-Tripura", "South Tripura",              "16",  "Tripura",
  "Manipur-Tripura", "West Tripura",               "16",  "Tripura",
  "Manipur-Tripura", "Ambassa",                    "16",  "Tripura (Khowai)",
  "Manipur-Tripura", "Kailashahar",                "16",  "Tripura (Unakoti)",
  "Manipur-Tripura", "Azamgarh",                   "09",  "UP (inter-cadre)",
  "Manipur-Tripura", "Gumla",                      "20",  "Jharkhand (inter-cadre)",
  "Manipur-Tripura", "Tripura",                    "16",  "Tripura (state name used as district)",
  "Manipur-Tripura", "Chhattisgarh",               "22",  "CG (inter-cadre)",
  # Assam Meghalaya cadre
  "Assam Meghalya",  "West Garo Hills",            "17",  "Meghalaya",
  "Assam Meghalya",  "Darjeeling",                 "19",  "West Bengal (inter-cadre)",
  "Assam Meghalya",  "Kanpur",                     "09",  "UP (inter-cadre)",
  "Assam Meghalya",  "Sabarkantha",                "24",  "Gujarat (inter-cadre)",
  "Assam Meghalya",  "Uttaranchal",                NA,    "state name, not district — drop",
  # Manipur cadre cross-postings
  "Manipur",         "Giridih",                    "20",  "Jharkhand",
  "Manipur",         "Nalanda",                    "10",  "Bihar",
  "Manipur",         "Raipur",                     "22",  "Chhattisgarh",
  "Manipur",         "Sheopurkala",                "23",  "MP",
  "Manipur",         "South Tripura",              "16",  "Tripura",
  "Manipur",         "Surguja",                    "22",  "Chhattisgarh",
  "Manipur",         "Washim",                     "27",  "Maharashtra",
  "Manipur",         "Madhya Pradesh",             NA,    "state name, not district",
  "Manipur",         "Jharkhand",                  NA,    "state name, not district",
  # Karnataka cross-postings
  "Karnataka",       "Murshidabad",                "19",  "West Bengal",
  # Kerala cross-postings
  "Kerala",          "Korba",                      "22",  "Chhattisgarh",
  "Kerala",          "Raipur",                     "22",  "Chhattisgarh",
  "Kerala",          "Rajnandgaon",                "22",  "Chhattisgarh",
  "Kerala",          "Vaishali",                   "10",  "Bihar",
  # Punjab cross-postings
  "Punjab",          "Bastar",                     "22",  "Chhattisgarh",
  "Punjab",          "Bilaspur",                   "22",  "Chhattisgarh CG",
  "Punjab",          "Buldhana",                   "27",  "Maharashtra",
  "Punjab",          "Dumka",                      "20",  "Jharkhand",
  "Punjab",          "Gopalganj",                  "10",  "Bihar",
  "Punjab",          "Jharkhand",                  NA,    "state name",
  "Punjab",          "Raigarh",                    "22",  "Chhattisgarh",
  # Sikkim cross-postings
  "Sikkim",          "Bulandshahr",                "09",  "UP",
  "Sikkim",          "Fatehpur",                   "09",  "UP",
  "Sikkim",          "Maharajganj",                "09",  "UP",
  "Sikkim",          "Pakur",                      "20",  "Jharkhand",
  "Sikkim",          "Rampur",                     "09",  "UP",
  "Sikkim",          "Sonbhadra",                  "09",  "UP",
  # Nagaland cross-postings
  "Nagaland",        "Rae Bareli",                 "09",  "UP",
  # Tripura cross-postings
  "Tripura",         "Amravati",                   "27",  "Maharashtra",
  "Tripura",         "Bhojpur",                    "10",  "Bihar",
  "Tripura",         "Gaya",                       "10",  "Bihar",
  "Tripura",         "Giridih",                    "20",  "Jharkhand",
  "Tripura",         "Jharkhand",                  NA,    "state name",
  "Tripura",         "Patna",                      "10",  "Bihar",
  # Andhra Pradesh: Lohardaga appears — cross-cadre to Jharkhand
  "Andhra Pradesh",  "Lohardaga",                  "20",  "Jharkhand",
  "Andhra Pradesh",  "Chittorgarh",                "08",  "Rajasthan (not AP Chittoor)",
  "Andhra Pradesh",  "Dakshina Kannada",           "29",  "Karnataka",
  "Andhra Pradesh",  "Changlang",                  "12",  "Arunachal Pradesh",
  "Andhra Pradesh",  "Uttaranchal",                NA,    "state name, not district",
  "Andhra Pradesh",  "West Bengal Bhavan",         NA,    "not a district",
  "Andhra Pradesh",  "Revenue Deptt",              NA,    "departmental",
  "Andhra Pradesh",  "General Admin Deptt",        NA,    "departmental",
  # Rajasthan cross-postings
  "Rajasthan",       "Nagpur",                     "27",  "Maharashtra",
  "Rajasthan",       "Ranchi",                     "20",  "Jharkhand",
  "Rajasthan",       "Cachar",                     "18",  "Assam",
  "Rajasthan",       "Durgapur",                   "19",  "West Bengal",
  "Rajasthan",       "Baleswar / Balasore",        "21",  "Odisha",
  # Odisha: some MP districts appear
  "Odisha",          "Badwani",                    "23",  "MP",
  "Odisha",          "Morena",                     "23",  "MP",
  "Odisha",          "Jaipur",                     "08",  "Rajasthan",
  "Odisha",          "Deoghar",                    "20",  "Jharkhand (not Odisha)",
  # Chhattisgarh: many are actually MP/CG border districts
  "Chhattisgarh",    "Agra",                       "09",  "UP",
  "Chhattisgarh",    "Bhind",                      "23",  "MP",
  "Chhattisgarh",    "Bhopal",                     "23",  "MP",
  "Chhattisgarh",    "Balaghat",                   "23",  "MP",
  "Chhattisgarh",    "Betul",                      "23",  "MP",
  "Chhattisgarh",    "Chhatarpur",                 "23",  "MP",
  "Chhattisgarh",    "Datia",                      "23",  "MP",
  "Chhattisgarh",    "Dhar",                       "23",  "MP",
  "Chhattisgarh",    "Guna",                       "23",  "MP",
  "Chhattisgarh",    "Gwalior",                    "23",  "MP",
  "Chhattisgarh",    "Hoshangabad",                "23",  "MP",
  "Chhattisgarh",    "Jabalpur",                   "23",  "MP",
  "Chhattisgarh",    "Jhabua",                     "23",  "MP",
  "Chhattisgarh",    "Mandla",                     "23",  "MP",
  "Chhattisgarh",    "Mandsaur",                   "23",  "MP",
  "Chhattisgarh",    "Munger",                     "10",  "Bihar",
  "Chhattisgarh",    "Narsinghpur",                "23",  "MP",
  "Chhattisgarh",    "Sagar",                      "23",  "MP",
  "Chhattisgarh",    "Sant Kabir Nagar",           "09",  "UP",
  "Chhattisgarh",    "Satna",                      "23",  "MP",
  "Chhattisgarh",    "Sehore",                     "23",  "MP",
  "Chhattisgarh",    "Shahdol",                    "23",  "MP",
  "Chhattisgarh",    "Shajapur",                   "23",  "MP",
  "Chhattisgarh",    "Shivpuri",                   "23",  "MP",
  "Chhattisgarh",    "Sidhi",                      "23",  "MP",
  "Chhattisgarh",    "Tikamgarh",                  "23",  "MP",
  "Chhattisgarh",    "Ujjain",                     "23",  "MP",
  "Chhattisgarh",    "Vidisha",                    "23",  "MP",
  "Chhattisgarh",    "Ghaziabad",                  "09",  "UP",
  "Chhattisgarh",    "Kodagu",                     "29",  "Karnataka",
  # AGMUT: remaining district names with state suffix
  "A G M U T",      "Karaikal",                    "34",  "Puducherry",
  "A G M U T",      "Karaikal (Pondi)",             "34",  "Puducherry",
  "A G M U T",      "Saiha",                        "15",  "Mizoram",
  "A G M U T",      "Saiha (Mizoram)",              "15",  "Mizoram",
  "A G M U T",      "West Siang",                   "12",  "Arunachal Pradesh",
  "A G M U T",      "West Siang (Aru. Pradesh)",    "12",  "Arunachal Pradesh",
  "A G M U T",      "Daman Diu / Dadra Nagar Haveli", "25", "Daman & Diu (primary)",
  "A G M U T",      "Goa, Daman, Diu",              "30",  "Goa (primary in combined entry)",
  "A G M U T",      "(UT)",                         NA,    "not a district",
  # Manipur-Tripura: after name canonicalisation, match on canonical name
  "Manipur-Tripura", "Khowai",                      "16",  "Tripura (Ambassa→Khowai)",
  "Manipur-Tripura", "Unakoti",                     "16",  "Tripura (Kailashahar→Unakoti)"
)

# Apply state overrides: match on cadre + display_name (canonical)
cw_clean <- cw_clean %>%
  left_join(
    state_overrides %>%
      distinct(cadre, name_pattern, .keep_all = TRUE) %>%
      select(cadre, name_pattern, override_state),
    by = c("cadre", "display_name" = "name_pattern")
  ) %>%
  mutate(
    pc11_state_id = coalesce(override_state, pc11_state_id)
  ) %>%
  select(-override_state)

# Drop rows where override_state was explicitly set to NA (state-name entries, non-districts)
cw_clean <- cw_clean %>%
  filter(!(cadre %in% state_overrides$cadre &
           display_name %in% state_overrides$name_pattern &
           is.na(pc11_state_id) &
           state_overrides$override_state[match(
             paste(cadre, display_name),
             paste(state_overrides$cadre, state_overrides$name_pattern)
           )] %>% is.na()))

# Also drop "Uttarakhand" as office_name (it's a state name used as posting label)
cw_clean <- cw_clean %>%
  filter(!str_detect(display_name,
    regex("^Uttar Pradesh$|^Jharkhand$|^Odisha$|^Bihar$|^Madhya Pradesh$|^Chhattisgarh$|^Tripura$|^Manipur$|^Sikkim$|^Uttaranchal$|^Uttarakhand$",
          ignore_case = TRUE)))

# =============================================================================
# STEP 4: pc11_district_id — left blank; report names for manual entry
# Without an authoritative Census 2011 district code list on this machine,
# assigning numeric IDs risks introducing errors. Fill from Census 2011
# Primary Census Abstract district list (available at censusindia.gov.in).
# =============================================================================
cw_out <- cw_clean %>%
  mutate(pc11_district_id = NA_character_) %>%
  select(cadre, office_name, display_name, pc11_state_id, pc11_district_id, name_changed)

# =============================================================================
# STEP 5: Report
# =============================================================================
n_filled  <- sum(!is.na(cw_out$pc11_state_id) & !is.na(cw_out$pc11_district_id))
n_state_only <- sum(!is.na(cw_out$pc11_state_id) & is.na(cw_out$pc11_district_id))
n_no_state   <- sum(is.na(cw_out$pc11_state_id))

cat("=== CROSSWALK BUILD SUMMARY ===\n")
cat("Original todo rows:              ", nrow(todo), "\n")
cat("Dropped as departmental:         ", n_dept, "\n")
cat("Remaining after filter:          ", nrow(cw_out), "\n")
cat("Names standardised:              ", sum(cw_out$name_changed), "\n")
cat("Rows with pc11_state_id filled:  ", sum(!is.na(cw_out$pc11_state_id)), "\n")
cat("Rows with pc11_district_id filled:", n_filled, "\n\n")
cat("ACTION NEEDED — pc11_district_id missing for",
    nrow(cw_out), "rows.\n")
cat("Fill using Census 2011 district code list, grouped by state:\n\n")

cw_out %>%
  filter(is.na(pc11_district_id)) %>%
  count(pc11_state_id, name = "n_districts_to_fill") %>%
  arrange(pc11_state_id) %>%
  print(n = Inf)

cat("\nRows with no pc11_state_id (genuine ambiguity — check manually):\n")
print(cw_out %>% filter(is.na(pc11_state_id)) %>%
        select(cadre, office_name, display_name))

# Save
write_csv(cw_out %>% select(cadre, office_name, display_name,
                              pc11_state_id, pc11_district_id),
          file.path(path_raw, "district_crosswalk.csv"))
cat("\nSaved: data/raw/district_crosswalk.csv\n")
cat("Next step: fill pc11_district_id column using Census 2011 district codes,\n")
cat("then re-run 07_merge_ias.R to complete the panel merge.\n")
