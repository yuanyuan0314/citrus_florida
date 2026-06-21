# ============================================================
# 04_county_choropleth.R — county map layers (year-stacked) for the dashboard
# Author: Yuanyuan Wen (with Claude Code)
# Purpose: Build three Florida county map layers, each STACKED across the
#          five census years (2002, 2007, 2012, 2017, 2022) so the dashboard
#          can offer a year selector (radio) per map:
#            1. bearing acreage          (ACRES BEARING)
#            2. operations with bearing  (OPERATIONS WITH AREA BEARING)
#            3. non-bearing acreage      (ACRES NON-BEARING)
#          (County-level PRODUCTION does not exist in the NASS Census —
#           production is state-only — so these three acreage/operations
#           measures stand in for the "where it is" maps.)
#          Each county carries its value + within-year Florida RANK for hover.
# Inputs:  scripts/R/_outputs/nass_fl_county.rds   (from 01c_filter_fl.R), else
#          scripts/R/_outputs/nass_county.rds       (from 01; bearing only)
# Outputs: scripts/R/_outputs/county_choropleth.rds  (named list of 3 long sf,
#          EPSG:4326; each has a `year` column with all census years stacked)
# Notes:   No raster -> 4326 (leaflet). Suppressed "(D)" -> NA -> grey.
#          No randomness -> no seed (INV-9 n/a). here() paths (INV-10).
# ============================================================

# 0. Setup ----
library(tidyverse)
library(here)
library(sf)
library(tigris)
library(scales)

options(tigris_use_cache = TRUE, timeout = 600)
sf::sf_use_s2(FALSE)

out <- function(f) here("scripts", "R", "_outputs", f)

# Long county data (prefer the comprehensive FL county file)
src <- if (file.exists(out("nass_fl_county.rds"))) out("nass_fl_county.rds") else out("nass_county.rds")
message("Using ", basename(src))
county <- readRDS(src)
if ("agg_level" %in% names(county)) county <- filter(county, agg_level == "COUNTY")
stopifnot("No county rows available" = nrow(county) > 0)

CENSUS_YEARS <- c(2002, 2007, 2012, 2017, 2022)

# Measures to map, keyed by their NASS short_desc (CITRUS TOTALS = all citrus)
MEAS <- tribble(
  ~key,         ~short_desc,                                       ~title,                            ~unit,
  "bearing",    "CITRUS TOTALS - ACRES BEARING",                   "Bearing acreage",                 "acres",
  "operations", "CITRUS TOTALS - OPERATIONS WITH AREA BEARING",    "Operations with bearing citrus",  "operations",
  "nonbearing", "CITRUS TOTALS - ACRES NON-BEARING",               "Non-bearing acreage",             "acres"
)

# 1. Florida county polygons (EPSG:4326) ----
fl <- counties(state = "FL", cb = TRUE, year = 2022, progress_bar = FALSE) |>
  st_transform(4326) |>
  transmute(fips = GEOID, county_poly = NAME)
# Simplify county boundaries — these get duplicated across 5 years x 3 measures
# in the leaflet layers, so detail balloons the embedded HTML. Topology-safe.
fl <- rmapshaper::ms_simplify(fl, keep = 0.03, keep_shapes = TRUE) |> st_make_valid()

# 2. Build one year-stacked sf per measure ----
build_layer <- function(sd, title, unit) {
  d <- county |>
    filter(short_desc == sd, year %in% CENSUS_YEARS, !is.na(value), value > 0) |>
    group_by(fips, county_name, year) |>
    summarise(value = sum(value), .groups = "drop")
  if (nrow(d) == 0) { message("  (no data for: ", sd, ")"); return(NULL) }
  d <- d |>
    group_by(year) |>
    mutate(rank = rank(-value, ties.method = "min"), n_ranked = n()) |>
    ungroup() |>
    mutate(
      title = title, unit = unit,
      label = paste0("<b>", str_to_title(county_name), " County</b><br>",
                     title, " (", year, "): <b>",
                     comma(round(value)), " ", unit, "</b><br>",
                     "Florida rank: ", rank, " of ", n_ranked))
  fl |> inner_join(d, by = "fips") |> st_as_sf()
}

choro <- pmap(list(MEAS$short_desc, MEAS$title, MEAS$unit), build_layer) |>
  set_names(MEAS$key)

# 3. Report + save ----
walk2(names(choro), choro, function(k, x) {
  if (is.null(x)) message(k, ": (no data)")
  else message(k, ": ", nrow(x), " county-year rows | years ",
               paste(sort(unique(x$year)), collapse = ", "))
})

saveRDS(choro, out("county_choropleth.rds"))

# 4. Bearing-acreage CHANGE 2002 -> 2022 by county ----
bc <- county |>
  filter(short_desc == "CITRUS TOTALS - ACRES BEARING",
         year %in% c(2002, 2022), !is.na(value)) |>
  group_by(fips, county_name, year) |>
  summarise(value = sum(value), .groups = "drop") |>
  pivot_wider(names_from = year, values_from = value, names_prefix = "y") |>
  # Counties with no reported 2002 bearing acres are treated as a 0 base
  # (near-zero / newly-emerging citrus), so the 2002 -> 2022 change is defined.
  mutate(y2002 = coalesce(y2002, 0),
         delta = y2022 - y2002)   # NA only if 2022 is missing
bearing_change <- fl |>
  inner_join(bc, by = "fips") |>
  st_as_sf() |>
  mutate(label = paste0("<b>", str_to_title(county_name), " County</b><br>",
                        "Bearing acres 2002: ", comma(round(y2002)), "<br>",
                        "Bearing acres 2022: ", comma(round(y2022)), "<br>",
                        "<b>Change: ", ifelse(delta >= 0, "+", ""),
                        comma(round(delta)), " ac</b>"))
saveRDS(bearing_change, out("bearing_change.rds"))
message("bearing_change: ", sum(!is.na(bearing_change$delta)),
        " counties with 2002 & 2022 bearing acres")
message("Saved county_choropleth.rds (year-stacked layers: ",
        paste(names(compact(choro)), collapse = ", "), ")")
