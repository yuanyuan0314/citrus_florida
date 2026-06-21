# ============================================================
# 01_get_nass.R — USDA NASS QuickStats: Florida citrus panel
# Author: Yuanyuan Wen (with Claude Code)
# Purpose: Curated pull for the dashboard pipeline —
#          (a) STATE long series via SURVEY  -> headline decline,
#          (b) COUNTY x year via CENSUS      -> ranking + panel.
#          Discovers the real commodity names from the API first,
#          then pulls every citrus commodity (oranges, grapefruit,
#          tangerines, tangelos, temples, lemons, limes, pummelos,
#          mandarins, "citrus totals", ...).
#          (To EXPLORE the full breadth of what QuickStats holds —
#           all programs/years/levels/stats — run 01b_nass_explore.R.)
# Inputs:  NASS_API_KEY from .Renviron (trimmed; never printed/saved)
# Outputs: data/raw/nass/*.rds            (cached raw API pulls)
#          scripts/R/_outputs/nass_state.rds   (long: commodity x year x statcat)
#          scripts/R/_outputs/nass_county.rds  (long; CENSUS, 5-yearly)
#          scripts/R/_outputs/county_ranking.rds / .csv
# Key facts (2026-06-11/16, confirmed against the QuickStats UI):
#   * SURVEY "Fruit & Tree Nuts" has NO county level -> COUNTY = CENSUS only.
#   * County citrus reports AREA BEARING, AREA NON-BEARING, and their sum.
#   * nassqs()/nassqs_param_values() REJECT an explicit key= arg — auth
#     comes from the global token set by nassqs_auth().
# Notes:   No randomness -> no seed (INV-9 n/a). here() paths (INV-10).
# ============================================================

# 0. Setup ----
library(tidyverse)
library(here)
library(rnassqs)
library(janitor)
library(httr)   # only to surface API error bodies on failure

options(timeout = 600)

raw_dir <- here("data", "raw", "nass")
out_dir <- here("scripts", "R", "_outputs")
dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# .Renviron is only read at R startup; load it now if needed.
api_key <- trimws(Sys.getenv("NASS_API_KEY"))
if (!nzchar(api_key) && file.exists(here(".Renviron"))) {
  readRenviron(here(".Renviron"))
  api_key <- trimws(Sys.getenv("NASS_API_KEY"))
}
stopifnot(
  "NASS_API_KEY still empty after readRenviron — confirm .Renviron is at the repo root and contains NASS_API_KEY=..., then restart R (Session > Restart R)." =
    nzchar(api_key))
nassqs_auth(key = api_key)
message("NASS key loaded (", nchar(api_key), " chars).")

# Matches every citrus commodity NASS uses (incl. CITRUS TOTALS, CITRUS OTHER).
CITRUS_RX <- "ORANGE|GRAPEFRUIT|TANGERINE|TANGELO|TEMPLE|LEMON|LIME|CITRUS|KUMQUAT|PUMMELO|POMELO|MANDARIN|TANGOR|CALAMON"

# --- helpers -------------------------------------------------

nass_explain_error <- function(params) {
  resp <- try(GET("https://quickstats.nass.usda.gov/api/api_GET/",
                  query = c(list(key = api_key, format = "JSON"), params)),
              silent = TRUE)
  if (!inherits(resp, "try-error")) {
    message("  API says [HTTP ", status_code(resp), "]: ",
            substr(content(resp, as = "text", encoding = "UTF-8"), 1, 300))
  }
  invisible(NULL)
}

# Cached query: retry transient 504s; stop early on 400; auth via global token.
nass_pull <- function(params, cache_name, max_tries = 4) {
  cache <- file.path(raw_dir, paste0(cache_name, ".rds"))
  if (file.exists(cache)) { message("cache hit: ", cache_name); return(readRDS(cache)) }
  for (i in seq_len(max_tries)) {
    message("API pull:  ", cache_name, " (attempt ", i, "/", max_tries, ")")
    err_msg <- NULL
    res <- tryCatch(nassqs(params), error = function(e) {
      err_msg <<- conditionMessage(e); message("  -> failed: ", sub("\n.*", "", err_msg)); NULL
    })
    if (!is.null(res)) { saveRDS(res, cache); return(res) }
    if (!is.null(err_msg) && grepl("400", err_msg, fixed = TRUE)) break
    if (i < max_tries) Sys.sleep(10 * i)
  }
  nass_explain_error(params); warning("Query gave up: ", cache_name); NULL
}

# Ask the API which citrus commodities actually exist for a program/geography.
discover_citrus <- function(source, agg_level) {
  vals <- tryCatch(
    nassqs_param_values("commodity_desc",
      source_desc = source, sector_desc = "CROPS",
      group_desc = "FRUIT & TREE NUTS",
      agg_level_desc = agg_level, state_alpha = "FL"),
    error = function(e) {
      message("  discovery failed (", source, "/", agg_level, "): ",
              conditionMessage(e)); character(0)
    })
  hits <- grep(CITRUS_RX, vals, value = TRUE, ignore.case = TRUE)
  message(source, "/", agg_level, " citrus commodities found: ",
          if (length(hits)) paste(hits, collapse = ", ") else "(none)")
  hits
}

parse_value <- function(x) {
  if (is.numeric(x)) return(x)
  suppressWarnings(readr::parse_number(as.character(x),
                                       na = c("(D)", "(Z)", "(NA)", "")))
}

# 1. STATE long series (SURVEY) — every citrus commodity, bearing + non-bearing
state_commodities <- discover_citrus("SURVEY", "STATE")
stopifnot("No state SURVEY citrus commodities discovered — check key/connectivity" =
            length(state_commodities) > 0)

state_raw <- nass_pull(
  list(source_desc       = "SURVEY",
       sector_desc       = "CROPS",
       group_desc        = "FRUIT & TREE NUTS",
       agg_level_desc    = "STATE",
       state_alpha       = "FL",
       commodity_desc    = state_commodities,
       statisticcat_desc = c("AREA BEARING", "AREA NON-BEARING")),
  "state_citrus_area")
stopifnot("No state-level rows returned" = !is.null(state_raw) && nrow(state_raw) > 0)

nass_state <- state_raw |>
  transmute(
    commodity = commodity_desc,
    statcat   = statisticcat_desc,
    unit      = unit_desc,
    short_desc,
    year      = as.integer(year),
    acres     = parse_value(Value)
  ) |>
  filter(!is.na(acres)) |>
  distinct() |>
  arrange(commodity, statcat, year)

saveRDS(nass_state, file.path(out_dir, "nass_state.rds"))
message("nass_state: ", nrow(nass_state), " rows; commodities: ",
        n_distinct(nass_state$commodity), "; years ",
        min(nass_state$year), "-", max(nass_state$year))

# 2. COUNTY x year panel (CENSUS — the only program with county citrus) ----
county_commodities <- discover_citrus("CENSUS", "COUNTY")
stopifnot("No CENSUS county citrus commodities discovered for FL" =
            length(county_commodities) > 0)

county_raw <- nass_pull(
  list(source_desc       = "CENSUS",
       sector_desc       = "CROPS",
       group_desc        = "FRUIT & TREE NUTS",
       agg_level_desc    = "COUNTY",
       state_alpha       = "FL",
       commodity_desc    = county_commodities,
       statisticcat_desc = c("AREA BEARING", "AREA NON-BEARING", "AREA GROWN", "AREA")),
  "county_census_citrus_area")
stopifnot("No county CENSUS rows returned" = !is.null(county_raw) && nrow(county_raw) > 0)

nass_county <- county_raw |>
  filter(!is.na(county_ansi), county_ansi != "") |>
  transmute(
    county_name = county_name,
    fips        = paste0("12", str_pad(county_ansi, 3, pad = "0")),  # char FIPS
    commodity   = commodity_desc,
    statcat     = statisticcat_desc,
    unit        = unit_desc,
    short_desc,
    year        = as.integer(year),
    value       = parse_value(Value)
  ) |>
  filter(!is.na(value),
         !county_name %in% c("OTHER (COMBINED) COUNTIES", "OTHER COUNTIES", "")) |>
  distinct() |>
  arrange(commodity, statcat, county_name, year)

saveRDS(nass_county, file.path(out_dir, "nass_county.rds"))
message("nass_county [CENSUS]: ", nrow(nass_county), " rows; commodities: ",
        n_distinct(nass_county$commodity), "; years ",
        paste(sort(unique(nass_county$year)), collapse = ", "))

# 3. Top-2 counties by total citrus BEARING acreage (latest census year) ----
bearing <- nass_county |> filter(statcat == "AREA BEARING", str_detect(unit, "ACRE"))
stopifnot("No AREA BEARING acreage rows to rank counties" = nrow(bearing) > 0)

if (any(bearing$commodity == "CITRUS TOTALS")) {
  rank_pool <- filter(bearing, commodity == "CITRUS TOTALS")
  rank_desc <- "CITRUS TOTALS bearing acres"
} else {
  rank_pool <- bearing
  rank_desc <- "all-citrus bearing acres (summed across commodities)"
}
rank_year <- max(rank_pool$year)

county_ranking <- rank_pool |>
  filter(year == rank_year) |>
  group_by(county_name, fips) |>
  summarise(rank_value = sum(value, na.rm = FALSE), .groups = "drop") |>
  arrange(desc(rank_value)) |>
  mutate(rank       = row_number(),
         rank_basis = paste0(rank_desc, ", ", rank_year, " [CENSUS]"))

saveRDS(county_ranking, file.path(out_dir, "county_ranking.rds"))
write_csv(county_ranking, file.path(out_dir, "county_ranking.csv"))

top2 <- head(county_ranking, 2)
message("Ranking basis: ", top2$rank_basis[1])
message("TOP 2: ", paste(top2$county_name, collapse = ", "),
        " (", paste(format(round(top2$rank_value), big.mark = ","), collapse = " / "),
        " acres)")
