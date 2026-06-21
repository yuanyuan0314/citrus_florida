# ============================================================
# 08_dor_hendry_parcels.R — Hendry citrus parcels (DOR use code 66), 2025
# Author: Yuanyuan Wen (with Claude Code)
# Purpose: Read the manually-downloaded Hendry 2025 PAR parcel shapefile
#          (geometry + NAL attributes incl DOR_UC), keep citrus parcels
#          (DOR use code 66), and save an sf layer for the dashboard's
#          CDL overlay map (administrative-parcel citrus vs satellite CDL).
# Inputs:  data/raw/dor_nal/hendry_2025Ppar.zip
# Outputs: scripts/R/_outputs/dor_hendry_citrus_parcels.rds  (sf 4326)
# CRS:     EPSG:4326 for leaflet. No seed (INV-9 n/a). here() paths (INV-10).
# ============================================================

suppressMessages({library(tidyverse); library(here); library(sf); library(rmapshaper)})
sf::sf_use_s2(FALSE)

raw <- here("data", "raw", "dor_nal")
out <- function(f) here("scripts", "R", "_outputs", f)

zip <- file.path(raw, "hendry_2025Ppar.zip")
stopifnot("hendry_2025Ppar.zip not found in data/raw/dor_nal" = file.exists(zip))
exdir <- file.path(raw, "hendry_2025Ppar")
if (!dir.exists(exdir)) unzip(zip, exdir = exdir)
shp <- list.files(exdir, pattern = "\\.shp$", ignore.case = TRUE,
                  full.names = TRUE, recursive = TRUE)[1]
stopifnot("no .shp inside the PAR zip" = !is.na(shp))

g <- st_read(shp, quiet = TRUE)
message("fields: ", paste(names(g), collapse = ", "))

# Detect the DOR use-code field
up  <- toupper(names(g))
ucf <- names(g)[up %in% c("DOR_UC", "DORUC", "PA_UC", "USE_CODE")][1]
if (is.na(ucf)) ucf <- names(g)[str_detect(up, "DOR.?UC")][1]
stopifnot("no DOR use-code field found in shapefile" = !is.na(ucf))
message("use-code field: ", ucf)

# Citrus = code 66 (strip leading zeros: "0066"/"66"/" 66" all match)
code <- str_remove(str_trim(as.character(g[[ucf]])), "^0+")
g66  <- g[which(code == "66"), ]
message("citrus (DOR_UC 66) parcels: ", nrow(g66))
stopifnot("no citrus parcels found" = nrow(g66) > 0)

# Best-effort attribute fields for hover
pick <- function(cands) { f <- names(g66)[toupper(names(g66)) %in% cands][1]
                          if (is.na(f)) NA_character_ else f }
pidf <- pick(c("PARCELID", "PARCEL_ID", "PARCELNO", "PIN"))
jvf  <- pick(c("JV", "JUST_VALUE"))

g66 <- g66 |> st_transform(5070) |> st_make_valid()
g66 <- ms_simplify(g66, keep = 0.08, keep_shapes = TRUE) |> st_transform(4326)

pid <- if (!is.na(pidf)) as.character(g66[[pidf]]) else rep(NA_character_, nrow(g66))
jv  <- if (!is.na(jvf)) suppressWarnings(as.numeric(g66[[jvf]])) else rep(NA_real_, nrow(g66))

parcels <- g66 |>
  st_geometry() |>
  st_sf() |>
  mutate(parcel_id = pid, just_value = jv,
    label = paste0("<b>Parcel ", coalesce(pid, "?"), "</b><br>",
                   "DOR citrus (use code 66), 2025",
                   ifelse(is.na(jv), "",
                          paste0("<br>Just value: $", formatC(round(jv), format = "d", big.mark = ",")))))

saveRDS(parcels, out("dor_hendry_citrus_parcels.rds"))
message("saved dor_hendry_citrus_parcels.rds: ", nrow(parcels), " citrus parcels")
