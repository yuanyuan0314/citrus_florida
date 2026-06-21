# ============================================================
# 05_get_dor_parcels.R — FL DOR parcel POLYGONS for citrus parcels
# Author: Yuanyuan Wen (with Claude Code)
# Purpose: Download the county parcel GIS layers from the DOR Data
#          Portal Map Data archive, keep only the citrus parcels
#          (DOR use code 66, identified by 03_get_dor_nal.R), join
#          the NAL attributes (acres, just value, sales), and save an
#          sf object for the dashboard's parcel map.
# Inputs:  scripts/R/_outputs/nal_citrus_parcels_top2.rds  (from 03)
#          DOR Map Data (verified pattern, 2024F confirmed HTTP 200):
#          .../Map Data/<Y>F/<Y>F PAR/<county_slug>_<Y>Ppar.zip
# Outputs: data/raw/dor_parcels/<slug>_<Y>Ppar.zip + unzipped shp (cached)
#          scripts/R/_outputs/dor_citrus_parcels.rds   (sf, EPSG:4326)
# CRS:     parcels reprojected to EPSG:4326 for leaflet. Light geometry
#          simplification (in EPSG:5070, 5 m) to keep the widget small.
# Caveats: full county parcel layers are LARGE downloads (100s of MB).
#          GIS year (2024) may differ from the NAL roll year (2025) — a
#          few parcels won't match; we inner-join on the parcel id and
#          note the count dropped. No seed (INV-9 n/a).
# ============================================================

# 0. Setup ----
library(tidyverse)
library(here)
library(sf)

options(timeout = 1800)          # big files
sf::sf_use_s2(FALSE)

raw_dir <- here("data", "raw", "dor_parcels")
out_dir <- here("scripts", "R", "_outputs")
dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)

norm_name <- function(x) str_replace_all(toupper(x), "[^A-Z]", "")
pid_key   <- function(x) gsub("[^A-Za-z0-9]", "", toupper(as.character(x)))

# County (normalized NASS name) -> DOR GIS file slug (lowercase, no spaces)
SLUG <- c(POLK = "polk", HENDRY = "hendry", DESOTO = "desoto",
          HIGHLANDS = "highlands", HARDEE = "hardee")

# Parcel GIS URL for a county slug + roll year
par_url <- function(slug, year) {
  base <- "https://floridarevenue.com/property/dataportal/Documents/PTO%20Data%20Portal/Map%20Data"
  paste0(base, "/", year, "F/", URLencode(paste0(year, "F PAR")),
         "/", slug, "_", year, "Ppar.zip")
}

# Is the file a real zip? (a 404 can save an HTML page that is not a zip)
is_zip <- function(f) {
  if (!file.exists(f) || file.size(f) < 4) return(FALSE)
  con <- file(f, "rb"); on.exit(close(con))
  sig <- readBin(con, "raw", 2)
  length(sig) == 2 && sig[1] == as.raw(0x50) && sig[2] == as.raw(0x4b)  # "PK"
}

download_safe <- function(url, dest) {
  if (file.exists(dest) && is_zip(dest)) { message("cache hit: ", basename(dest)); return(TRUE) }
  status <- tryCatch(download.file(url, dest, mode = "wb", quiet = FALSE),
                     error = function(e) 1L, warning = function(w) 1L)
  if (status != 0L || !is_zip(dest)) { unlink(dest); return(FALSE) }
  TRUE
}

# Try recent roll years until one downloads (2024F is verified)
download_parcels <- function(slug) {
  for (y in c(2025, 2024, 2023)) {
    dest <- file.path(raw_dir, paste0(slug, "_", y, "Ppar.zip"))
    if (download_safe(par_url(slug, y), dest)) return(list(zip = dest, year = y))
  }
  stop("Could not download parcel GIS for '", slug, "' (tried 2025/2024/2023).")
}

unzip_once <- function(zip_path) {
  exdir <- sub("\\.zip$", "", zip_path)
  if (!dir.exists(exdir)) {
    ex <- unzip(zip_path, exdir = exdir)
    if (length(ex) == 0) { unlink(exdir, recursive = TRUE); unlink(zip_path)
      stop("Unzip failed — removed cached zip; re-run: ", basename(zip_path)) }
  }
  shp <- list.files(exdir, pattern = "\\.shp$", ignore.case = TRUE,
                    full.names = TRUE, recursive = TRUE)[1]
  stopifnot("No .shp inside parcel zip" = !is.na(shp))
  shp
}

# 1. Citrus parcels (from 03) ----
citrus <- readRDS(out("nal_citrus_parcels_top2.rds")) |>
  mutate(pid = pid_key(parcel_id))
stopifnot("no citrus parcels from 03" = nrow(citrus) > 0)
counties <- citrus |> distinct(county_name) |> pull(county_name)
message("Counties with citrus parcels: ", paste(counties, collapse = ", "))

# 2. Per county: download GIS, keep citrus parcels, attach NAL attributes ----
get_county_parcels <- function(cn) {
  slug <- unname(SLUG[norm_name(cn)])
  if (is.na(slug)) stop("No GIS slug mapped for county: ", cn,
                        " — add it to SLUG.", call. = FALSE)
  message("== ", cn, " (", slug, ") ==")
  dl  <- download_parcels(slug)
  shp <- unzip_once(dl$zip)

  gis <- st_read(shp, quiet = TRUE)
  idf <- intersect(c("PARCELID", "PARCEL_ID", "PARCELNO", "PIN", "ALTKEY"),
                   toupper(names(gis)))
  names(gis)[toupper(names(gis)) %in% idf] <- "PARCELID"
  stopifnot("No parcel-id field found in GIS" = "PARCELID" %in% names(gis))

  cc <- filter(citrus, county_name == cn)
  gis |>
    transmute(PARCELID, pid = pid_key(PARCELID), gis_year = dl$year) |>
    inner_join(cc, by = "pid")          # keep only citrus (DOR_UC 66) parcels
}

parcels <- map(counties, get_county_parcels) |> bind_rows() |> st_as_sf()
message("Citrus parcels matched to geometry: ", format(nrow(parcels), big.mark = ","))

# 3. Reproject + light simplify + hover label ----
parcels <- parcels |>
  st_transform(5070) |>
  st_simplify(dTolerance = 5, preserveTopology = TRUE) |>
  st_transform(4326) |>
  mutate(
    jv_per_acre = if_else(acres > 0, just_value / acres, NA_real_),
    label = paste0(
      "<b>Parcel ", parcel_id, "</b><br>",
      str_to_title(county_name), " County<br>",
      "Acres: ", scales::comma(round(acres, 1)), "<br>",
      "Just value: ", scales::dollar(round(just_value)), "<br>",
      "$/acre: ", scales::dollar(round(jv_per_acre)), "<br>",
      "Last sale: ",
      if_else(is.na(sale_yr1), "n/a",
              paste0(scales::dollar(round(sale_prc1)), " (", sale_yr1, ")")))
  )

saveRDS(parcels, out("dor_citrus_parcels.rds"))
message("Saved dor_citrus_parcels.rds: ", nrow(parcels), " polygons | GIS year(s): ",
        paste(sort(unique(parcels$gis_year)), collapse = ", "))
