# ============================================================
# 01c_filter_fl.R — derive the Florida subset from the cached
#                   national pulls (no API calls)
# Author: Yuanyuan Wen (with Claude Code)
# Purpose: Read the national raw caches written by 01b_nass_explore.R
#          (data/raw/nass/all_*.rds), keep only Florida rows, tidy,
#          and write the FL dump + an availability inventory.
#          Decoupled from the (slow) pull so you can re-filter FL
#          without re-downloading.
# Inputs:  data/raw/nass/all_*.rds   (from 01b_nass_explore.R)
# Outputs: scripts/R/_outputs/nass_citrus_fl.rds / .csv
#          scripts/R/_outputs/nass_inventory.csv   (what's available in FL)
# Notes:   Filters state_alpha == "FL" before tidying (memory-light).
#          Value codes "(D)"/"(Z)"/"(X)" -> NA. No seed (INV-9 n/a).
# ============================================================

# 0. Setup ----
library(tidyverse)
library(here)

raw_dir <- here("data", "raw", "nass")
out_dir <- here("scripts", "R", "_outputs")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

parse_value <- function(x) {
  if (is.numeric(x)) return(x)
  suppressWarnings(readr::parse_number(as.character(x),
                                       na = c("(D)", "(Z)", "(NA)", "(X)", "")))
}

# 1. Read each national cache, keep Florida rows only ----
files <- list.files(raw_dir, pattern = "^all_.*\\.rds$", full.names = TRUE)
stopifnot("No national caches found (data/raw/nass/all_*.rds). Run 01b_nass_explore.R first." =
            length(files) > 0)
message("Reading ", length(files), " national cache file(s)...")

fl_raw <- map(files, function(f) {
  d <- readRDS(f)
  if (!"state_alpha" %in% names(d)) return(NULL)
  d |> filter(state_alpha == "FL")
}) |>
  compact() |>
  bind_rows()

stopifnot("No Florida rows found across the caches." = nrow(fl_raw) > 0)
message("Florida raw rows: ", format(nrow(fl_raw), big.mark = ","),
        " | commodities: ", paste(sort(unique(fl_raw$commodity_desc)), collapse = ", "))

# 2. Tidy ----
nass_citrus_fl <- fl_raw |>
  mutate(
    fips = if_else(agg_level_desc == "COUNTY" & !is.na(county_code) & county_code != "",
                   paste0(state_fips_code, str_pad(county_code, 3, pad = "0")), NA_character_),
    year = as.integer(year), value = parse_value(Value)
  ) |>
  transmute(
    source = source_desc, year, freq = freq_desc,
    reference_period = reference_period_desc,
    agg_level = agg_level_desc, state_alpha,
    asd_desc = if ("asd_desc" %in% names(fl_raw)) asd_desc else NA_character_,
    county_name, fips,
    commodity = commodity_desc, statcat = statisticcat_desc, class_desc,
    prodn_practice = prodn_practice_desc, util_practice = util_practice_desc,
    short_desc, domain = domain_desc, domaincat = domaincat_desc,
    unit = unit_desc, value, value_raw = as.character(Value)
  ) |>
  distinct() |>
  arrange(commodity, agg_level, source, statcat, county_name, year)

saveRDS(nass_citrus_fl, file.path(out_dir, "nass_citrus_fl.rds"))
write_csv(nass_citrus_fl, file.path(out_dir, "nass_citrus_fl.csv"))
message("nass_citrus_fl: ", format(nrow(nass_citrus_fl), big.mark = ","),
        " rows | levels: ", paste(sort(unique(nass_citrus_fl$agg_level)), collapse = "/"),
        " | years ", min(nass_citrus_fl$year, na.rm = TRUE), "-",
        max(nass_citrus_fl$year, na.rm = TRUE))

# 2b. Split by aggregation level -> separate files ----
# FL levels present: STATE, COUNTY, "REGION : SUB-STATE".
level_files <- tribble(
  ~agg_level,            ~slug,
  "STATE",               "state",
  "COUNTY",              "county",
  "REGION : SUB-STATE",  "substate"
)
for (i in seq_len(nrow(level_files))) {
  lvl  <- level_files$agg_level[i]
  slug <- level_files$slug[i]
  d <- filter(nass_citrus_fl, agg_level == lvl)
  if (nrow(d) == 0) { message("  (no rows at level: ", lvl, ")"); next }
  saveRDS(d,  file.path(out_dir, paste0("nass_fl_", slug, ".rds")))
  write_csv(d, file.path(out_dir, paste0("nass_fl_", slug, ".csv")))
  message("  nass_fl_", slug, ": ", format(nrow(d), big.mark = ","), " rows")
}
# Any other levels not in the map (so nothing is silently dropped)
other_lvls <- setdiff(unique(nass_citrus_fl$agg_level), level_files$agg_level)
if (length(other_lvls) > 0)
  message("  NOTE: levels not split into their own file: ",
          paste(other_lvls, collapse = ", "), " (still in nass_citrus_fl).")

# 3. INVENTORY — the "what can I pull in FL?" view ----
nass_inventory <- nass_citrus_fl |>
  group_by(commodity, source, agg_level, statcat, unit, short_desc) |>
  summarise(
    n_obs        = n(),
    year_min     = min(year, na.rm = TRUE),
    year_max     = max(year, na.rm = TRUE),
    n_years      = n_distinct(year),
    n_counties   = n_distinct(fips[agg_level == "COUNTY"]),
    n_suppressed = sum(is.na(value)),
    .groups = "drop"
  ) |>
  arrange(commodity, agg_level, statcat, short_desc)

write_csv(nass_inventory, file.path(out_dir, "nass_inventory.csv"))
message("nass_inventory: ", nrow(nass_inventory),
        " distinct FL series -> scripts/R/_outputs/nass_inventory.csv")

# Console preview: series per commodity x level x statcat
nass_inventory |>
  count(commodity, agg_level, statcat, name = "n_series") |>
  arrange(commodity, agg_level, statcat) |>
  print(n = 200)
