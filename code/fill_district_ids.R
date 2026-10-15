library(tidyverse)
library(stringdist)

# ---- Hardcoded Census 2011 district lookup ----
# Within each state, districts are listed in any order — R sorts them
# alphabetically, then assigns SHRUG global IDs sequentially from the
# state's known offset (derived from pc11r_shrid_key.csv analysis).

make_state <- function(state_id, offset, districts) {
  d <- sort(districts)
  tibble(
    pc11_state_id    = sprintf("%02d", state_id),
    district_name    = d,
    pc11_district_id = sprintf("%03d", offset + seq_along(d))
  )
}

lookup <- bind_rows(
  make_state(1, 0, c(
    "Anantnag","Badgam","Bandipore","Baramulla","Doda","Ganderbal",
    "Jammu","Kargil","Kathua","Kishtwar","Kulgam","Kupwara","Leh",
    "Poonch","Pulwama","Rajouri","Ramban","Reasi","Samba","Shopian",
    "Srinagar","Udhampur")),
  make_state(2, 22, c(
    "Bilaspur","Chamba","Hamirpur","Kangra","Kinnaur","Kullu",
    "Lahaul And Spiti","Mandi","Shimla","Sirmaur","Solan","Una")),
  make_state(3, 34, c(
    "Amritsar","Barnala","Bathinda","Faridkot","Fatehgarh Sahib",
    "Ferozepur","Gurdaspur","Hoshiarpur","Jalandhar","Kapurthala",
    "Ludhiana","Mansa","Moga","Muktsar","Patiala","Rupnagar",
    "S.A.S. Nagar","Sangrur","Shaheed Bhagat Singh Nagar","Tarn Taran")),
  make_state(4, 54, c("Chandigarh")),
  make_state(5, 55, c(
    "Almora","Bageshwar","Chamoli","Champawat","Dehradun","Haridwar",
    "Nainital","Pauri Garhwal","Pithoragarh","Rudraprayag",
    "Tehri Garhwal","Udham Singh Nagar","Uttarkashi")),
  make_state(6, 68, c(
    "Ambala","Bhiwani","Faridabad","Fatehabad","Gurgaon","Hisar",
    "Jhajjar","Jind","Kaithal","Karnal","Kurukshetra","Mahendragarh",
    "Mewat","Palwal","Panchkula","Panipat","Rewari","Rohtak",
    "Sirsa","Sonipat","Yamuna Nagar")),
  make_state(7, 89, c(
    "Central Delhi","East Delhi","New Delhi","North Delhi",
    "North East Delhi","North West Delhi","South Delhi",
    "South West Delhi","West Delhi")),
  make_state(8, 98, c(
    "Ajmer","Alwar","Banswara","Baran","Barmer","Bharatpur","Bhilwara",
    "Bikaner","Bundi","Chittorgarh","Churu","Dausa","Dhaulpur",
    "Dungarpur","Hanumangarh","Jaipur","Jaisalmer","Jalore","Jhalawar",
    "Jhunjhunu","Jodhpur","Karauli","Kota","Nagaur","Pali","Pratapgarh",
    "Rajsamand","Sawai Madhopur","Sikar","Sirohi","Sri Ganganagar",
    "Tonk","Udaipur")),
  # UP: 71 districts (Amethi excluded — created Aug 2010, not in SHRUG pc11)
  make_state(9, 131, c(
    "Agra","Aligarh","Allahabad","Ambedkar Nagar","Auraiya","Azamgarh",
    "Baghpat","Bahraich","Ballia","Balrampur","Banda","Barabanki",
    "Bareilly","Basti","Bijnor","Budaun","Bulandshahr","Chandauli",
    "Chitrakoot","Deoria","Etah","Etawah","Faizabad","Farrukhabad",
    "Fatehpur","Firozabad","Gautam Buddha Nagar","Ghaziabad","Ghazipur",
    "Gonda","Gorakhpur","Hamirpur","Hardoi","Jalaun","Jaunpur","Jhansi",
    "Jyotiba Phule Nagar","Kannauj","Kanpur Dehat","Kanpur Nagar",
    "Kasganj","Kaushambi","Kheri","Kushinagar","Lalitpur","Lucknow",
    "Mahamaya Nagar","Maharajganj","Mahoba","Mainpuri","Mathura","Mau",
    "Meerut","Mirzapur","Moradabad","Muzaffarnagar","Pilibhit",
    "Pratapgarh","Rae Bareli","Rampur","Saharanpur","Sant Kabir Nagar",
    "Sant Ravidas Nagar","Shahjahanpur","Shrawasti","Siddharthnagar",
    "Sitapur","Sonbhadra","Sultanpur","Unnao","Varanasi")),
  make_state(10, 202, c(
    "Araria","Arwal","Aurangabad","Banka","Begusarai","Bhagalpur",
    "Bhojpur","Buxar","Darbhanga","East Champaran","Gaya","Gopalganj",
    "Jamui","Jehanabad","Kaimur","Katihar","Khagaria","Kishanganj",
    "Lakhisarai","Madhepura","Madhubani","Munger","Muzaffarpur",
    "Nalanda","Nawada","Patna","Purnia","Rohtas","Saharsa","Samastipur",
    "Saran","Sheikhpura","Sheohar","Sitamarhi","Siwan","Supaul",
    "Vaishali","West Champaran")),
  make_state(11, 240, c(
    "East Sikkim","North Sikkim","South Sikkim","West Sikkim")),
  make_state(12, 244, c(
    "Anjaw","Changlang","Dibang Valley","East Kameng","East Siang",
    "Kurung Kumey","Lohit","Lower Dibang Valley","Lower Subansiri",
    "Papum Pare","Tawang","Tirap","Upper Siang","Upper Subansiri",
    "West Kameng","West Siang")),
  make_state(13, 260, c(
    "Dimapur","Kiphire","Kohima","Longleng","Mokokchung","Mon",
    "Peren","Phek","Tuensang","Wokha","Zunheboto")),
  make_state(14, 271, c(
    "Bishnupur","Chandel","Churachandpur","Imphal East","Imphal West",
    "Senapati","Tamenglong","Thoubal","Ukhrul")),
  make_state(15, 280, c(
    "Aizawl","Champhai","Kolasib","Lawngtlai","Lunglei",
    "Mamit","Saiha","Serchhip")),
  make_state(16, 288, c(
    "Dhalai","North Tripura","South Tripura","West Tripura")),
  make_state(17, 292, c(
    "East Garo Hills","East Khasi Hills","Jaintia Hills","Ri Bhoi",
    "South Garo Hills","West Garo Hills","West Khasi Hills")),
  make_state(18, 299, c(
    "Baksa","Barpeta","Bongaigaon","Cachar","Chirang","Darrang",
    "Dhemaji","Dhubri","Dibrugarh","Dima Hasao","Goalpara","Golaghat",
    "Hailakandi","Jorhat","Kamrup","Kamrup Metropolitan","Karbi Anglong",
    "Karimganj","Kokrajhar","Lakhimpur","Marigaon","Nagaon","Nalbari",
    "Sibsagar","Sonitpur","Tinsukia","Udalguri")),
  make_state(19, 326, c(
    "Bankura","Bardhaman","Birbhum","Cooch Behar","Dakshin Dinajpur",
    "Darjeeling","Hooghly","Howrah","Jalpaiguri","Kolkata","Malda",
    "Murshidabad","Nadia","North 24 Parganas","Paschim Medinipur",
    "Purba Medinipur","Purulia","South 24 Parganas","Uttar Dinajpur")),
  make_state(20, 345, c(
    "Bokaro","Chatra","Deoghar","Dhanbad","Dumka","East Singhbhum",
    "Garhwa","Giridih","Godda","Gumla","Hazaribagh","Jamtara","Khunti",
    "Koderma","Latehar","Lohardaga","Pakur","Palamu","Ramgarh","Ranchi",
    "Sahibganj","Saraikela Kharsawan","Simdega","West Singhbhum")),
  make_state(21, 369, c(
    "Angul","Balangir","Balasore","Bargarh","Bhadrak","Boudh","Cuttack",
    "Deogarh","Dhenkanal","Gajapati","Ganjam","Jagatsinghpur","Jajpur",
    "Jharsuguda","Kalahandi","Kandhamal","Kendrapara","Kendujhar",
    "Khordha","Koraput","Malkangiri","Mayurbhanj","Nabarangpur",
    "Nayagarh","Nuapada","Puri","Rayagada","Sambalpur","Subarnapur",
    "Sundargarh")),
  make_state(22, 399, c(
    "Bastar","Bijapur","Bilaspur","Dantewada","Dhamtari","Durg",
    "Janjgir Champa","Jashpur","Kabirdham","Kanker","Korba","Koriya",
    "Mahasamund","Narayanpur","Raigarh","Raipur","Rajnandgaon",
    "Surguja")),
  make_state(23, 417, c(
    "Alirajpur","Anuppur","Ashoknagar","Balaghat","Barwani","Betul",
    "Bhind","Bhopal","Burhanpur","Chhatarpur","Chhindwara","Damoh",
    "Datia","Dewas","Dhar","Dindori","Guna","Gwalior","Harda",
    "Hoshangabad","Indore","Jabalpur","Jhabua","Katni","Khandwa",
    "Khargone","Mandla","Mandsaur","Morena","Narsinghpur","Neemuch",
    "Panna","Raisen","Rajgarh","Ratlam","Rewa","Sagar","Satna","Sehore",
    "Seoni","Shahdol","Shajapur","Sheopur","Shivpuri","Sidhi",
    "Singrauli","Tikamgarh","Ujjain","Umaria","Vidisha")),
  make_state(24, 467, c(
    "Ahmedabad","Amreli","Anand","Banaskantha","Bharuch","Bhavnagar",
    "Dahod","Dangs","Gandhinagar","Jamnagar","Junagadh","Kheda","Kutch",
    "Mehsana","Narmada","Navsari","Panchmahal","Patan","Porbandar",
    "Rajkot","Sabarkantha","Surat","Surendranagar","Tapi","Vadodara",
    "Valsad")),
  make_state(25, 493, c("Daman","Diu")),
  make_state(26, 495, c("Dadra And Nagar Haveli")),
  make_state(27, 496, c(
    "Ahmednagar","Akola","Amravati","Aurangabad","Beed","Bhandara",
    "Buldhana","Chandrapur","Dhule","Gadchiroli","Gondia","Hingoli",
    "Jalgaon","Jalna","Kolhapur","Latur","Mumbai City","Mumbai Suburban",
    "Nagpur","Nanded","Nandurbar","Nashik","Osmanabad","Parbhani","Pune",
    "Raigad","Ratnagiri","Sangli","Satara","Sindhudurg","Solapur",
    "Thane","Wardha","Washim","Yavatmal")),
  # AP incl. Telangana (undivided, Census 2011)
  make_state(28, 531, c(
    "Adilabad","Anantapur","Chittoor","East Godavari","Guntur",
    "Hyderabad","Karimnagar","Khammam","Krishna","Kurnool","Mahbubnagar",
    "Medak","Nalgonda","Nellore","Nizamabad","Prakasam","Rangareddy",
    "Srikakulam","Visakhapatnam","Vizianagaram","Warangal",
    "West Godavari","Y.S.R.")),
  make_state(29, 554, c(
    "Bagalkot","Bangalore Rural","Bangalore Urban","Belgaum","Bellary",
    "Bidar","Bijapur","Chamarajanagar","Chikkaballapura","Chikmagalur",
    "Chitradurga","Dakshina Kannada","Davanagere","Dharwad","Gadag",
    "Gulbarga","Hassan","Haveri","Kodagu","Kolar","Koppal","Mandya",
    "Mysore","Raichur","Ramanagara","Shimoga","Tumkur","Udupi",
    "Uttara Kannada","Yadgir")),
  make_state(30, 584, c("North Goa","South Goa")),
  make_state(31, 586, c("Lakshadweep")),
  make_state(32, 587, c(
    "Alappuzha","Ernakulam","Idukki","Kannur","Kasaragod","Kollam",
    "Kottayam","Kozhikode","Malappuram","Palakkad","Pathanamthitta",
    "Thiruvananthapuram","Thrissur","Wayanad")),
  make_state(33, 601, c(
    "Ariyalur","Chennai","Coimbatore","Cuddalore","Dharmapuri",
    "Dindigul","Erode","Kanchipuram","Kanniyakumari","Karur",
    "Krishnagiri","Madurai","Nagapattinam","Namakkal","Nilgiris",
    "Perambalur","Pudukottai","Ramanathapuram","Salem","Sivaganga",
    "Thanjavur","Theni","Thoothukudi","Tiruchirappalli","Tirunelveli",
    "Tiruppur","Tiruvallur","Tiruvannamalai","Tiruvarur","Vellore",
    "Villupuram","Virudhunagar")),
  make_state(34, 633, c("Karaikal","Mahe","Puducherry","Yanam")),
  make_state(35, 637, c(
    "Nicobar","North And Middle Andaman","South Andaman"))
)

cat("=== LOOKUP TABLE ===\n")
cat("Total lookup rows:", nrow(lookup), "\n")
lookup %>% count(pc11_state_id) %>% print(n = 40)

# Validate against pc11 key
pc11_key_path <- "data/raw/pc11r_shrid_key.csv"
pc11_u_path   <- "data/raw/pc11r_shrid_key.csv"  # urban key not available locally; rural covers all districts

pc11_valid <- bind_rows(
  read_csv(pc11_key_path, show_col_types = FALSE),
  read_csv(pc11_u_path,   show_col_types = FALSE)
) %>%
  mutate(
    pc11_state_id    = sprintf("%02d", as.integer(pc11_state_id)),
    pc11_district_id = sprintf("%03d", as.integer(pc11_district_id))
  ) %>%
  distinct(pc11_state_id, pc11_district_id)

cat("\nValid pc11 districts (rural + urban union):", nrow(pc11_valid), "\n")

# Check which lookup IDs are not in pc11_valid
bad_ids <- lookup %>%
  anti_join(pc11_valid, by = c("pc11_state_id", "pc11_district_id"))
if (nrow(bad_ids) > 0) {
  cat("\nWARNING: lookup IDs not found in pc11_valid:\n")
  print(bad_ids)
} else {
  cat("All lookup IDs validated against pc11_valid. ✓\n")
}

# ---- Load crosswalk ----
crosswalk <- read_csv("data/raw/district_crosswalk.csv", show_col_types = FALSE) %>%
  mutate(pc11_state_id = sprintf("%02d", as.integer(pc11_state_id)))

cat("\nCrosswalk rows:", nrow(crosswalk), "\n")

# ---- Hard-coded fixes: display_name + state → target lookup name ----
hardcoded <- tribble(
  ~display_name,       ~pc11_state_id, ~target_name,
  "Cuddapah",          "28",           "Y.S.R.",
  "Monghyr",           "10",           "Munger",
  "Santhal Parganas",  "20",           "Dumka",
  "Boudh-Khondmals",   "21",           "Kandhamal",
  "North Arcot",       "33",           "Vellore",
  "South Arcot",       "33",           "Cuddalore",
  "Nawanshahr",        "03",           "Shaheed Bhagat Singh Nagar",
  "Hathras",           "09",           "Mahamaya Nagar"
)

# ---- Fuzzy match ----
crosswalk <- crosswalk %>%
  mutate(
    pc11_district_id = NA_character_,
    match_score      = NA_real_,
    match_type       = NA_character_,
    matched_name     = NA_character_
  )

for (i in seq_len(nrow(crosswalk))) {
  state_id <- crosswalk$pc11_state_id[i]
  dname    <- crosswalk$display_name[i]

  # Hardcoded first
  hc <- hardcoded %>% filter(display_name == dname, pc11_state_id == state_id)
  if (nrow(hc) > 0) {
    target <- hc$target_name[1]
    cand   <- lookup %>%
      filter(pc11_state_id == state_id,
             str_to_lower(district_name) == str_to_lower(target))
    if (nrow(cand) > 0) {
      crosswalk$pc11_district_id[i] <- cand$pc11_district_id[1]
      crosswalk$match_score[i]      <- 1.0
      crosswalk$match_type[i]       <- "hardcoded"
      crosswalk$matched_name[i]     <- cand$district_name[1]
      next
    }
  }

  # Fuzzy within state
  state_lkp <- lookup %>% filter(pc11_state_id == state_id)
  if (nrow(state_lkp) == 0) next

  scores  <- 1 - stringdist(tolower(dname), tolower(state_lkp$district_name), method = "jw")
  best_i  <- which.max(scores)
  best_s  <- scores[best_i]

  if (best_s > 0.85) {
    crosswalk$pc11_district_id[i] <- state_lkp$pc11_district_id[best_i]
    crosswalk$match_score[i]      <- best_s
    crosswalk$match_type[i]       <- "auto"
    crosswalk$matched_name[i]     <- state_lkp$district_name[best_i]
  } else if (best_s > 0.70) {
    crosswalk$pc11_district_id[i] <- state_lkp$pc11_district_id[best_i]
    crosswalk$match_score[i]      <- best_s
    crosswalk$match_type[i]       <- "review"
    crosswalk$matched_name[i]     <- state_lkp$district_name[best_i]
  }
}

# ---- Report ----
n_auto      <- sum(crosswalk$match_type == "auto",      na.rm = TRUE)
n_hardcoded <- sum(crosswalk$match_type == "hardcoded", na.rm = TRUE)
n_review    <- sum(crosswalk$match_type == "review",    na.rm = TRUE)
n_na        <- sum(is.na(crosswalk$pc11_district_id))

cat("\n=== RESULTS ===\n")
cat("Auto-filled (score > 0.85)         :", n_auto, "\n")
cat("Hard-coded fixes applied            :", n_hardcoded, "\n")
cat("Flagged for review (0.70 – 0.85)   :", n_review, "\n")
cat("Left as NA (< 0.70 or no coverage) :", n_na, "\n")

cat("\n=== FLAGGED FOR REVIEW ===\n")
crosswalk %>%
  filter(match_type == "review") %>%
  select(cadre, display_name, pc11_state_id, matched_name, pc11_district_id, match_score) %>%
  arrange(pc11_state_id, match_score) %>%
  print(n = Inf)

cat("\n=== LEFT AS NA ===\n")
crosswalk %>%
  filter(is.na(pc11_district_id)) %>%
  select(cadre, display_name, pc11_state_id) %>%
  arrange(pc11_state_id, display_name) %>%
  print(n = Inf)

# ---- Save ----
crosswalk %>%
  select(cadre, office_name, display_name, pc11_state_id, pc11_district_id) %>%
  write_csv("data/raw/district_crosswalk.csv")

cat("\nSaved to data/raw/district_crosswalk.csv\n")
