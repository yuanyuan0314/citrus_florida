# ============================================================
# 07_solar_zonal.R — county-level zonal statistics for FL solar
# Author: Yuanyuan Wen (with Claude Code)
# Purpose: Aggregate USPVDB facilities to Florida counties for the dashboard's
#          solar map county layers:
#            - earliest facility year online
#            - total AC capacity (MW)
#            - total facility area (acres)
#          Facilities are assigned to a county by point-in-polygon (centroid).
# Inputs:  scripts/R/_outputs/uspvdb_fl.rds  (from 02_get_uspvdb.R)
# Outputs: scripts/R/_outputs/solar_county.rds  (sf 4326: county polygons +
#          earliest_year / total_ac / total_area / n_facilities)
# CRS:     EPSG:4326 for leaflet. No seed (INV-9 n/a). here() paths (INV-10).
# ============================================================

# 0. Setup ----
library(tidyverse)
library(here)
library(sf)
library(tigris)
library(rmapshaper)

options(tigris_use_cache = TRUE, timeout = 600)
sf::sf_use_s2(FALSE)

out <- function(f) here("scripts", "R", "_outputs", f)

fac <- readRDS(out("uspvdb_fl.rds")) |> st_transform(4326)
stopifnot("uspvdb_fl.rds empty" = nrow(fac) > 0)

# 1. Florida county polygons (simplified) ----
fl <- counties(state = "FL", cb = TRUE, year = 2022, progress_bar = FALSE) |>
  st_transform(4326) |>
  transmute(fips = GEOID, county = NAME)

# 2. Assign each facility to a county (centroid point-in-polygon) ----
ctr <- suppressWarnings(st_point_on_surface(fac))
ctr <- st_join(ctr, fl, join = st_intersects)

zonal <- ctr |>
  st_drop_geometry() |>
  filter(!is.na(fips)) |>
  group_by(fips, county) |>
  summarise(
    earliest_year = suppressWarnings(min(p_year,   na.rm = TRUE)),
    total_ac      = sum(p_cap_ac, na.rm = TRUE),
    total_area    = sum(p_area,   na.rm = TRUE),
    n_facilities  = n(),
    .groups = "drop") |>
  mutate(earliest_year = ifelse(is.finite(earliest_year), earliest_year, NA_integer_))

# 3. Join stats back to (simplified) county polygons ----
fl_s <- ms_simplify(fl, keep = 0.03, keep_shapes = TRUE) |> st_make_valid()
solar_county <- fl_s |>
  left_join(zonal, by = c("fips", "county")) |>
  mutate(has_solar = !is.na(n_facilities))

saveRDS(solar_county, out("solar_county.rds"))
message("solar_county: ", sum(solar_county$has_solar, na.rm = TRUE),
        " of ", nrow(solar_county), " counties have solar | ",
        "earliest year range ", min(zonal$earliest_year, na.rm = TRUE), "-",
        max(zonal$earliest_year, na.rm = TRUE),
        " | total MWac ", round(sum(zonal$total_ac, na.rm = TRUE)))
