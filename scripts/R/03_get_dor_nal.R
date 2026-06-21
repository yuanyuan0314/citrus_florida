# ============================================================
# 03_get_dor_nal.R — FL DOR NAL tax roll: citrus parcels,
#                    top-2 production counties
# Author: Yuanyuan Wen (with Claude Code)
# Purpose: Download the 2025 Final NAL (Name-Address-Legal)
#          county tax-roll files for the top-2 citrus-production
#          counties (from 01_get_nass.R ranking), filter to
#          DOR use code 66 ("Orchard Groves, Citrus, etc."),
#          and produce parcel-level extracts + county summaries.
# Inputs:  scripts/R/_outputs/county_ranking.rds
#          DOR Data Portal (verified URL pattern, 2025F only):
#          .../Tax Roll Data Files/NAL/2025F/<County> <NN> Final NAL 2025.zip
# Outputs: data/raw/dor_nal/*.zip (cached)
#          scripts/R/_outputs/nal_citrus_parcels_top2.rds
#          scripts/R/_outputs/nal_citrus_summary_top2.rds / .csv
# Caveats: DOR_UC 66 = "Orchard Groves, Citrus, Etc." — includes
#          some non-citrus orchards (small in FL). 2025F is the
#          only roll year on the public portal; historical rolls
#          require a request to DOR (PTOTechnology@floridarevenue.com).
# ============================================================

# 0. Setup ----
library(tidyverse)
library(here)
library(janitor)

options(timeout = 600)

raw_dir <- here("data", "raw", "dor_nal")
out_dir <- here("scripts", "R", "_outputs")
dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)

ROLL_YEAR <- 2025  # only year available on the public portal (checked 2026-06-11)
SQFT_PER_ACRE <- 43560

# NASS county name (uppercase) -> DOR NAL filename stem + county FIPS.
# DOR codes verified by HTTP 200 on 2026-06-11 except Hardee (inferred
# from the alphabetical 11-77 scheme; verify on first use).
dor_lookup <- tribble(
  ~county_name, ~file_stem,      ~county_fips, ~verified,
  "POLK",       "Polk 63",       "12105",      TRUE,
  "DESOTO",     "Desoto 24",     "12027",      TRUE,
  "HIGHLANDS",  "Highlands 38",  "12055",      TRUE,
  "HENDRY",     "Hendry 36",     "12051",      TRUE,
  "HARDEE",     "Hardee 35",     "12049",      FALSE
)

nal_url <- function(file_stem) {
  base <- "https://floridarevenue.com/property/dataportal/Documents/PTO%20Data%20Portal/Tax%20Roll%20Data%20Files/NAL"
  paste0(base, "/", ROLL_YEAR, "F/", URLencode(paste0(file_stem, " Final NAL ", ROLL_YEAR, ".zip")))
}

# Normalized name key: "DE SOTO" / "DeSoto" / "ST. LUCIE" all collapse
norm_name <- function(x) str_replace_all(toupper(x), "[^A-Z]", "")

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

#' Unzip with verification: corrupt zips only *warn* in unzip().
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

# 1. Resolve top-2 counties ----
# Default: read the ranking produced by 01_get_nass.R.
# Manual override: set TOP2_OVERRIDE if the NASS county pull failed.
# (FCS 2023-24 ranking: Polk 3.86M > DeSoto 3.14M > Highlands 2.79M boxes.)
TOP2_OVERRIDE <- NULL                      # e.g. c("POLK", "DESOTO")

ranking_path <- file.path(out_dir, "county_ranking.rds")
if (!is.null(TOP2_OVERRIDE)) {
  top2 <- tibble(county_name = toupper(TOP2_OVERRIDE),
                 fips = NA_character_,
                 rank_basis = "manual override (FCS 2023-24)")
} else if (file.exists(ranking_path)) {
  top2 <- readRDS(ranking_path) |> slice_min(rank, n = 2)
} else {
  stop("county_ranking.rds not found. Either run 01_get_nass.R first ",
       "or set TOP2_OVERRIDE <- c(\"POLK\", \"DESOTO\") above.")
}
# Join on character FIPS where available (ranking branch); fall back to
# the normalized name (override branch, or NASS spelling variants like
# "DE SOTO" vs "DESOTO"). Never join on raw county_name.
lk <- dor_lookup |> mutate(name_key = norm_name(county_name)) |> select(-county_name)
top2 <- top2 |>
  mutate(name_key = norm_name(county_name)) |>
  left_join(lk, by = "name_key")
# FIPS rescue: if the name key missed but we have a FIPS, match on it
miss <- is.na(top2$file_stem) & !is.na(top2$fips)
if (any(miss)) {
  idx <- match(top2$fips[miss], lk$county_fips)
  top2$file_stem[miss]   <- lk$file_stem[idx]
  top2$verified[miss]    <- lk$verified[idx]
  top2$county_fips[miss] <- lk$county_fips[idx]
}
top2 <- top2 |> mutate(fips = coalesce(fips, county_fips))

stopifnot("Top-2 county missing from dor_lookup — add its DOR code + FIPS" =
            !any(is.na(top2$file_stem)))
if (any(!top2$verified)) {
  message("WARNING: DOR URL not yet verified for: ",
          paste(top2$county_name[!top2$verified], collapse = ", "),
          " — if the download 404s, check the filename on the DOR portal.")
}
message("Top-2 counties: ", paste(top2$county_name, collapse = ", "),
        " (basis: ", top2$rank_basis[1], ")")

# 2. Download + read each county's NAL (cache-and-skip) ----
read_county_nal <- function(county_name, file_stem, fips) {
  zip_path <- file.path(raw_dir, paste0(gsub(" ", "_", file_stem), "_", ROLL_YEAR, ".zip"))
  message("NAL: ", county_name)
  download_safe(nal_url(file_stem), zip_path)

  csv_dir <- file.path(raw_dir, paste0(gsub(" ", "_", file_stem), "_", ROLL_YEAR))
  unzip_safe(zip_path, csv_dir)
  csv_file <- list.files(csv_dir, pattern = "\\.csv$", ignore.case = TRUE,
                         full.names = TRUE, recursive = TRUE)[1]
  stopifnot("No CSV inside NAL zip" = !is.na(csv_file))

  read_csv(csv_file, col_types = cols(.default = "c"), progress = FALSE) |>
    clean_names() |>
    mutate(county_name = county_name, fips = fips)
}

nal_all <- pmap(list(top2$county_name, top2$file_stem, top2$fips), read_county_nal) |>
  bind_rows()
message("NAL rows read (all uses): ", format(nrow(nal_all), big.mark = ","))

# 3. Filter to citrus use code + tidy ----
parse_num <- function(x) suppressWarnings(readr::parse_number(x))

citrus_parcels <- nal_all |>
  # DOR_UC is a code, not a number: compare as a string with leading
  # zeros stripped ("66", " 66", "066" all match; no float ==)
  filter(str_remove(str_trim(dor_uc), "^0+") == "66") |>
  transmute(
    county_name, fips,
    parcel_id  = parcel_id,
    dor_uc     = dor_uc,
    acres      = parse_num(lnd_sqfoot) / SQFT_PER_ACRE,
    just_value = parse_num(jv),
    land_value = parse_num(lnd_val),
    sale_prc1  = parse_num(sale_prc1),
    sale_yr1   = suppressWarnings(as.integer(sale_yr1)),
    roll_year  = ROLL_YEAR
  )

saveRDS(citrus_parcels, file.path(out_dir, "nal_citrus_parcels_top2.rds"))

# 4. County summaries ----
citrus_summary <- citrus_parcels |>
  group_by(county_name, fips) |>
  summarise(
    n_parcels        = n(),
    total_acres      = sum(acres, na.rm = TRUE),
    median_acres     = median(acres, na.rm = TRUE),
    total_just_value = sum(just_value, na.rm = TRUE),
    jv_per_acre      = total_just_value / total_acres,
    n_sold_2020plus  = sum(sale_yr1 >= 2020, na.rm = TRUE),
    roll_year        = ROLL_YEAR,
    .groups = "drop"
  )

saveRDS(citrus_summary, file.path(out_dir, "nal_citrus_summary_top2.rds"))
write_csv(citrus_summary, file.path(out_dir, "nal_citrus_summary_top2.csv"))

message("Citrus (DOR_UC 66) parcels by county:")
message(paste(capture.output(as.data.frame(citrus_summary)), collapse = "\n"))
message("Summary written: ", file.path(out_dir, "nal_citrus_summary_top2.csv"))
