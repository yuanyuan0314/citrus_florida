# ============================================================
# 00_setup.R — Install/verify project R packages
# Author: Yuanyuan Wen (with Claude Code)
# Purpose: One-time environment setup. Installs any missing
#          packages used by the B2 data pipeline. Idempotent.
# Inputs:  none
# Outputs: scripts/R/_outputs/session_info.txt
# ============================================================

pkgs <- c(
  "tidyverse",  # data wrangling + ggplot2
  "here",       # repo-root-relative paths (INV-10)
  "rnassqs",    # USDA NASS QuickStats API
  "sf",         # vector geospatial (USPVDB, parcels, county polygons)
  "terra",      # raster (CDL land cover)
  "CropScapeR", # USDA CDL county clips via CropScape API
  "rmapshaper", # topology-safe polygon simplification (map geometry slimming)
  "tigris",     # Census TIGER county boundaries
  "leaflet",    # interactive choropleths for the dashboard
  "htmltools",  # HTML hover labels in leaflet
  "scales",     # comma()/dollar() formatting
  "janitor"     # clean_names() for messy admin files
)

installed <- rownames(installed.packages())
missing <- setdiff(pkgs, installed)

if (length(missing) > 0) {
  message("Installing: ", paste(missing, collapse = ", "))
  install.packages(missing, repos = "https://cloud.r-project.org")
} else {
  message("All packages already installed.")
}

# Verify everything loads
for (p in pkgs) library(p, character.only = TRUE)

dir.create(file.path("scripts", "R", "_outputs"), recursive = TRUE, showWarnings = FALSE)
writeLines(capture.output(sessionInfo()),
           file.path("scripts", "R", "_outputs", "session_info.txt"))
message("Setup complete. sessionInfo written to scripts/R/_outputs/session_info.txt")
