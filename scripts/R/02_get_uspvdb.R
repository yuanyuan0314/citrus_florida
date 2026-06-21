# ============================================================
# 02_get_uspvdb.R — USGS/LBNL US Large-Scale Solar PV Database
# Author: Yuanyuan Wen (with Claude Code)
# Purpose: Download USPVDB (>=1 MW facility polygons + year
#          online), filter to Florida, save sf object.
# Inputs:  https://energy.usgs.gov/uspvdb/ (v4.0, 2026-04-14;
#          URLs are version-agnostic — vintage recorded below)
# Outputs: data/raw/uspvdb/uspvdbGeoJSON.zip (+ metadata xml)
#          scripts/R/_outputs/uspvdb_fl.rds  (sf, EPSG:4326)
# Notes:   No randomness -> no seed. Vintage note: INV on dashboard.
# ============================================================

# 0. Setup ----
library(tidyverse)
library(here)
library(sf)

options(timeout = 600)

raw_dir <- here("data", "raw", "uspvdb")
out_dir <- here("scripts", "R", "_outputs")
dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

#' Download to dest atomically: remove partial files on failure so the
#' skip-if-exists cache is never poisoned by a corrupt download.
download_safe <- function(url, dest) {
  if (file.exists(dest)) {
    message("cache hit: ", basename(dest))
    return(invisible(dest))
  }
  status <- tryCatch(download.file(url, dest, mode = "wb"),
                     error   = function(e) { message("  -> ", conditionMessage(e)); 1L },
                     warning = function(w) { message("  -> ", conditionMessage(w)); 1L })
  if (status != 0L || !file.exists(dest) || file.size(dest) == 0) {
    unlink(dest)
    stop("Download failed (partial file removed): ", url, call. = FALSE)
  }
  invisible(dest)
}

#' Unzip with verification: a corrupt zip only *warns* in unzip(), so
#' check the result and clear both zip and dir on failure.
unzip_safe <- function(zip_path, exdir) {
  if (dir.exists(exdir)) return(invisible(exdir))
  extracted <- unzip(zip_path, exdir = exdir)
  if (length(extracted) == 0) {
    unlink(exdir, recursive = TRUE); unlink(zip_path)
    stop("Unzip failed — removed cached zip; re-run to re-download: ",
         basename(zip_path), call. = FALSE)
  }
  invisible(exdir)
}

zip_path  <- file.path(raw_dir, "uspvdbGeoJSON.zip")
meta_path <- file.path(raw_dir, "uspvdb_metadata.xml")

# 1. Download (skip-if-exists) ----
download_safe("https://energy.usgs.gov/uspvdb/assets/data/uspvdbGeoJSON.zip",
              zip_path)
if (!file.exists(meta_path)) {
  try(download.file("https://energy.usgs.gov/uspvdb/assets/data/uspvdb_v4_0_20260414.xml",
                    meta_path, mode = "wb"), silent = TRUE)
}

# 2. Read + filter Florida ----
unzip_dir <- file.path(raw_dir, "geojson")
unzip_safe(zip_path, unzip_dir)
geojson_file <- list.files(unzip_dir, pattern = "\\.geojson$", ignore.case = TRUE,
                           full.names = TRUE, recursive = TRUE)[1]
stopifnot("No .geojson found in USPVDB zip" = !is.na(geojson_file))

# Vintage from the data file itself (URL always serves the latest release,
# so a hardcoded version string would drift)
vintage_stamp <- str_extract(basename(geojson_file), "[Vv]\\d+[_.]\\d+[_.]?\\d*")
vintage_note  <- paste0("USPVDB ", coalesce(vintage_stamp, "v4.0"),
                        " (downloaded ", Sys.Date(), ")")

uspvdb <- st_read(geojson_file, quiet = TRUE) |> st_transform(4326)

uspvdb_fl <- uspvdb |>
  filter(p_state == "FL") |>
  select(any_of(c("case_id", "p_name", "p_state", "p_county",
                  "p_year", "p_cap_ac", "p_cap_dc", "p_area",
                  "p_agrivolt", "p_zscore"))) |>
  mutate(vintage = vintage_note)

saveRDS(uspvdb_fl, file.path(out_dir, "uspvdb_fl.rds"))
message("uspvdb_fl: ", nrow(uspvdb_fl), " FL facilities; years ",
        paste(range(uspvdb_fl$p_year, na.rm = TRUE), collapse = "-"),
        "; total ", round(sum(uspvdb_fl$p_cap_dc, na.rm = TRUE)), " MWdc")
