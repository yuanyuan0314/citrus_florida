# ============================================================
# run_all.R — one-click build for the Florida Citrus dashboard
# ------------------------------------------------------------
# Open this file in RStudio and click "Source" (top-right of the editor),
# or run from the repo root:
#     Rscript run_all.R
#
# It runs every analysis script in order and then renders the Quarto
# dashboard to dashboard/index.html. Each numbered script writes its
# results to scripts/R/_outputs/; the dashboard reads ONLY from there.
# Scripts are sourced in isolated environments and pass data to each
# other via those .rds files, so the run order is all that matters.
#
# Requirements
#   * R packages — the first step (00_setup.R) installs anything missing.
#   * Quarto (https://quarto.org), either on your PATH or as the R
#     package `quarto`.
#   * A free USDA NASS QuickStats API key in a .Renviron file at the
#     repo root:  NASS_API_KEY=your_key   (needed for steps 1-2 only).
#
# Just want the webpage (no API key)?  The repo already ships the
# computed scripts/R/_outputs/*.rds, so you can skip the data pulls:
# set RUN_DATA_PIPELINE <- FALSE below (or run with the environment
# variable RUN_DATA_PIPELINE=FALSE) to go straight to rendering.
# ============================================================

if (!requireNamespace("here", quietly = TRUE)) install.packages("here")
library(here)

# ---- switches (env vars override the defaults) ---------------
flag <- function(name, default) {
  v <- Sys.getenv(name, unset = NA_character_)
  if (is.na(v) || v == "") return(default)
  isTRUE(as.logical(v))
}
RUN_SETUP         <- flag("RUN_SETUP",         TRUE)  # install/refresh R packages
RUN_DATA_PIPELINE <- flag("RUN_DATA_PIPELINE", TRUE)  # run the data scripts (NASS key needed for 1-2)
RENDER_DASHBOARD  <- flag("RENDER_DASHBOARD",  TRUE)  # render dashboard/index.qmd -> index.html

# ---- the pipeline, in order ----------------------------------
setup   <- "scripts/R/00_setup.R"
scripts <- c(
  "scripts/R/01_get_nass.R",          # NASS state series + county ranking
  "scripts/R/01b_nass_explore.R",     # NASS FL state/county/operations  (REQUIRED, despite the name)
  "scripts/R/02_get_uspvdb.R",        # USPVDB utility-scale solar facilities
  "scripts/R/03_get_dor_nal.R",       # FL DOR NAL parcel attributes (top-2 counties)
  "scripts/R/04_county_choropleth.R", # county map layers + 2002->2022 bearing-acreage change
  "scripts/R/06_cdl_transition.R",    # Hendry CDL citrus transition, 2008 -> 2025
  "scripts/R/07_solar_zonal.R",       # county-level solar zonal statistics
  "scripts/R/08_dor_hendry_parcels.R" # Hendry DOR citrus parcels (auto-downloads its zip)
)
# Auxiliary scripts, NOT needed for the dashboard (left out on purpose):
#   05_get_dor_parcels.R  — full top-2-county parcel polygons (very large download)
#   01c/01d/01e, exlore_usda_nass.R — exploratory NASS reshaping

run_one <- function(path) {
  cat("\n========== ", path, "  ==========\n", sep = "")
  t0 <- Sys.time()
  source(here(path), local = new.env())   # isolated env; scripts share data via _outputs/*.rds
  cat(sprintf("---- done in %.1f s\n", as.numeric(Sys.time() - t0, units = "secs")))
}

if (RUN_SETUP)         run_one(setup)
if (RUN_DATA_PIPELINE) for (s in scripts) run_one(s)

# ---- render the dashboard ------------------------------------
if (RENDER_DASHBOARD) {
  qmd <- here("dashboard", "index.qmd")
  cat("\n========== render ", qmd, "  ==========\n", sep = "")
  rendered <- FALSE
  if (requireNamespace("quarto", quietly = TRUE)) {
    quarto::quarto_render(qmd)
    rendered <- TRUE
  } else {
    code <- suppressWarnings(tryCatch(
      system2("quarto", c("render", shQuote(qmd))), error = function(e) 127L))
    rendered <- identical(as.integer(code), 0L)
  }
  if (rendered) {
    cat("\nDashboard rendered -> dashboard/index.html\n")
  } else {
    cat("\n[!] Quarto was not found. Install it from https://quarto.org, then run:\n",
        "      quarto render dashboard/index.qmd\n", sep = "")
  }
}

cat("\nAll requested steps complete.\n")
