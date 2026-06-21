# ============================================================
# 01d_nass_county_wide.R — reshape FL county citrus to wide form
# Author: Yuanyuan Wen (with Claude Code)
# Purpose: From nass_fl_county (long), split short_desc into <crop> and
#          <measure>, then pivot the six measures to columns:
#            ACRES BEARING, OPERATIONS WITH AREA BEARING,
#            ACRES BEARING & NON-BEARING,
#            OPERATIONS WITH AREA BEARING & NON-BEARING,
#            ACRES NON-BEARING, OPERATIONS WITH AREA NON-BEARING
#          -> one row per crop x county x year (x program/domain).
# Inputs:  scripts/R/_outputs/nass_fl_county.rds   (from 01c_filter_fl.R)
# Outputs: scripts/R/_outputs/nass_fl_county_wide.rds / .csv
# Notes:   short_desc = "<crop> - <measure>"; crop keeps NASS subclasses
#          (e.g. "ORANGES, VALENCIA", "ORANGES, MID & NAVEL", "CITRUS, OTHER").
#          Suppressed values ("(D)") stay NA (not 0). No seed (INV-9 n/a).
# ============================================================

# 0. Setup ----
library(tidyverse)
library(here)

out <- function(f) here("scripts", "R", "_outputs", f)
county <- readRDS(out("nass_fl_county.rds"))
stopifnot("nass_fl_county.rds is empty" = nrow(county) > 0)

# 1. Split short_desc -> crop + measure ----
# Split on the FIRST " - "; measure never contains " - ", so this is safe.
county_split <- county |>
  separate_wider_delim(
    short_desc, delim = " - ",
    names = c("crop", "measure"),
    too_many = "merge",       # safety: any extra goes to measure
    too_few  = "align_start"  # safety: missing measure -> NA
  )

# 2. Pivot the six measures to columns ----
# Preserve NA for suppressed cells: NA only if every contributing value is NA.
sum_keep_na <- function(x) if (all(is.na(x))) NA_real_ else sum(x, na.rm = TRUE)

id_cols <- c("source", "agg_level", "state_alpha", "county_name", "fips",
             "year", "commodity", "crop",
             "domain", "domaincat", "prodn_practice", "util_practice",
             "freq", "reference_period")

nass_fl_county_wide <- county_split |>
  select(all_of(id_cols), measure, value) |>
  pivot_wider(names_from = measure, values_from = value,
              values_fn = sum_keep_na) |>
  arrange(crop, county_name, year)

saveRDS(nass_fl_county_wide, out("nass_fl_county_wide.rds"))
write_csv(nass_fl_county_wide, out("nass_fl_county_wide.csv"))

# 3. Report ----
measure_cols <- setdiff(names(nass_fl_county_wide), id_cols)
message("nass_fl_county_wide: ", format(nrow(nass_fl_county_wide), big.mark = ","),
        " rows x ", ncol(nass_fl_county_wide), " cols")
message("Measure columns: ", paste(measure_cols, collapse = " | "))
message("Crops: ", paste(sort(unique(nass_fl_county_wide$crop)), collapse = ", "))
message("Census years present: ",
        paste(sort(unique(nass_fl_county_wide$year)), collapse = ", "))

# Coverage of the headline measure (ACRES BEARING) by year x #counties
if ("ACRES BEARING" %in% names(nass_fl_county_wide)) {
  nass_fl_county_wide |>
    filter(crop == "CITRUS TOTALS", !is.na(`ACRES BEARING`)) |>
    count(year, name = "n_counties_with_bearing_acres") |>
    arrange(year) |>
    print(n = 100)
}
