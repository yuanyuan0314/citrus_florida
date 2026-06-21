# ============================================================
# 01b_nass_explore.R — fetch FL citrus: SURVEY=state, CENSUS=county
# Author: Yuanyuan Wen (with Claude Code)
# Purpose: Targeted fetch for the 10 citrus commodities in Florida:
#            * STATE level  <- SURVEY program (annual long series:
#              acreage, production, value, price, yield, ...)
#            * COUNTY level <- CENSUS program (5-yearly: acreage,
#              operations)
#          This is the clean split — SURVEY has no usable county
#          citrus, and CENSUS at state/sub-state adds noise (mixed
#          units, "REGION : SUB-STATE"), so we don't pull those.
#          Commodities are used directly (no discovery step).
# Inputs:  NASS_API_KEY from .Renviron
# Outputs: data/raw/nass/fl_survey_state_*.rds,
#          data/raw/nass/fl_census_county_*.rds        (cached raw)
#          scripts/R/_outputs/nass_fl_state.rds / .csv   (SURVEY, state)
#          scripts/R/_outputs/nass_fl_county.rds / .csv  (CENSUS, county)
#          scripts/R/_outputs/nass_citrus_fl.rds / .csv  (both stacked)
#          scripts/R/_outputs/nass_inventory.csv         (what's available)
# Note:    OPERATIONS (operator counts) is a CENSUS measure -> present at
#          COUNTY here, but NOT at STATE (state is SURVEY-only). Say so if
#          a state operations KPI is needed. No seed (INV-9 n/a).
# ============================================================

# 0. Setup ----
library(tidyverse)
library(here)
library(rnassqs)
library(janitor)
library(httr)

options(timeout = 600)

raw_dir <- here("data", "raw", "nass")
out_dir <- here("scripts", "R", "_outputs")
dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# >>> NASS API KEY REQUIRED HERE <<<  (free key: https://quickstats.nass.usda.gov/api)
# Put  NASS_API_KEY=your_key  in a .Renviron file at the repo root (copy
# .Renviron.example to .Renviron), then restart R. See 01_get_nass.R for details.
api_key <- trimws(Sys.getenv("NASS_API_KEY"))
if (!nzchar(api_key) && file.exists(here(".Renviron"))) {
  readRenviron(here(".Renviron")); api_key <- trimws(Sys.getenv("NASS_API_KEY"))
}
stopifnot(
  "NASS_API_KEY not found. Get a free key at https://quickstats.nass.usda.gov/api and put 'NASS_API_KEY=your_key' in a .Renviron file at the repo root, then restart R." =
    nzchar(api_key))
nassqs_auth(key = api_key)
message("NASS key loaded (", nchar(api_key), " chars).")

COMMODITIES <- c("CITRUS TOTALS", "CITRUS, OTHER", "GRAPEFRUIT", "LEMONS",
                 "LEMONS & LIMES", "LIMES", "ORANGES", "TANGELOS",
                 "TANGERINES", "TEMPLES")

# --- helpers (auth via global token; NO key= arg) -------------------
nass_explain_error <- function(params) {
  resp <- try(GET("https://quickstats.nass.usda.gov/api/api_GET/",
                  query = c(list(key = api_key, format = "JSON"), params)), silent = TRUE)
  if (!inherits(resp, "try-error"))
    message("  API says [HTTP ", status_code(resp), "]: ",
            substr(content(resp, as = "text", encoding = "UTF-8"), 1, 300))
  invisible(NULL)
}
nass_pull <- function(params, cache_name, max_tries = 4) {
  cache <- file.path(raw_dir, paste0(cache_name, ".rds"))
  if (file.exists(cache)) { message("cache hit: ", cache_name); return(readRDS(cache)) }
  for (i in seq_len(max_tries)) {
    message("API pull:  ", cache_name, " (attempt ", i, "/", max_tries, ")")
    err_msg <- NULL
    res <- tryCatch(nassqs(params), error = function(e) {
      err_msg <<- conditionMessage(e); message("  -> failed: ", sub("\n.*", "", err_msg)); NULL })
    if (!is.null(res)) { saveRDS(res, cache); return(res) }
    if (!is.null(err_msg) && grepl("400", err_msg, fixed = TRUE)) break  # no-match: skip
    if (i < max_tries) Sys.sleep(10 * i)
  }
  nass_explain_error(params); message("  (", cache_name, ": no data — skipped)"); NULL
}
parse_value <- function(x) {
  if (is.numeric(x)) return(x)
  suppressWarnings(readr::parse_number(as.character(x),
                                       na = c("(D)", "(Z)", "(NA)", "(X)", "")))
}

# Pull one commodity at one program/level for Florida (minimal params).
pull_one <- function(commodity, source, agg, tag) {
  nass_pull(list(source_desc = source, agg_level_desc = agg,
                 state_alpha = "FL", commodity_desc = commodity),
            paste0(tag, "_", make_clean_names(commodity)))
}

# Tidy raw NASS rows into the project long format.
tidy_nass <- function(raw) {
  if (is.null(raw) || nrow(raw) == 0) return(NULL)
  raw |>
    mutate(
      fips = if_else(agg_level_desc == "COUNTY" & !is.na(county_code) & county_code != "",
                     paste0(state_fips_code, str_pad(county_code, 3, pad = "0")), NA_character_),
      year = as.integer(year), value = parse_value(Value)
    ) |>
    transmute(
      source = source_desc, year, freq = freq_desc,
      reference_period = reference_period_desc,
      agg_level = agg_level_desc, state_alpha,
      county_name, fips,
      commodity = commodity_desc, statcat = statisticcat_desc, class_desc,
      prodn_practice = prodn_practice_desc, util_practice = util_practice_desc,
      short_desc, domain = domain_desc, domaincat = domaincat_desc,
      unit = unit_desc, value, value_raw = as.character(Value)
    ) |>
    distinct()
}

# 1. STATE <- SURVEY ----
message("== STATE level (SURVEY) ==")
state_raw <- map(COMMODITIES, \(c) pull_one(c, "SURVEY", "STATE", "fl_survey_state")) |>
  compact() |> bind_rows()
nass_fl_state <- tidy_nass(state_raw)
stopifnot("No SURVEY state rows returned." = !is.null(nass_fl_state) && nrow(nass_fl_state) > 0)
nass_fl_state <- arrange(nass_fl_state, commodity, statcat, year)
saveRDS(nass_fl_state, file.path(out_dir, "nass_fl_state.rds"))
write_csv(nass_fl_state, file.path(out_dir, "nass_fl_state.csv"))
message("nass_fl_state [SURVEY]: ", format(nrow(nass_fl_state), big.mark = ","),
        " rows | commodities: ", n_distinct(nass_fl_state$commodity),
        " | years ", min(nass_fl_state$year, na.rm = TRUE), "-",
        max(nass_fl_state$year, na.rm = TRUE))

# 2. COUNTY <- CENSUS ----
message("== COUNTY level (CENSUS) ==")
county_raw <- map(COMMODITIES, \(c) pull_one(c, "CENSUS", "COUNTY", "fl_census_county")) |>
  compact() |> bind_rows()
nass_fl_county <- tidy_nass(county_raw)
stopifnot("No CENSUS county rows returned." = !is.null(nass_fl_county) && nrow(nass_fl_county) > 0)
nass_fl_county <- nass_fl_county |>
  filter(!county_name %in% c("OTHER (COMBINED) COUNTIES", "OTHER COUNTIES", "")) |>
  arrange(commodity, statcat, county_name, year)
saveRDS(nass_fl_county, file.path(out_dir, "nass_fl_county.rds"))
write_csv(nass_fl_county, file.path(out_dir, "nass_fl_county.csv"))
message("nass_fl_county [CENSUS]: ", format(nrow(nass_fl_county), big.mark = ","),
        " rows | commodities: ", n_distinct(nass_fl_county$commodity),
        " | census years: ", paste(sort(unique(nass_fl_county$year)), collapse = ", "))

# 2b. STATE operations <- CENSUS (operations is a Census-only measure; ----
#     SURVEY has none, and summing counties undercounts due to (D) suppression,
#     so we pull the authoritative state Census figure — operations only.)
message("== STATE operations (CENSUS, operations only) ==")
operstate_raw <- map(COMMODITIES, \(c) pull_one(c, "CENSUS", "STATE", "fl_census_state")) |>
  compact() |> bind_rows()
nass_fl_state_oper <- tidy_nass(operstate_raw)
if (!is.null(nass_fl_state_oper)) {
  nass_fl_state_oper <- nass_fl_state_oper |>
    filter(str_detect(coalesce(unit, ""), "OPERATIONS")) |>
    arrange(commodity, short_desc, year)
  saveRDS(nass_fl_state_oper, file.path(out_dir, "nass_fl_state_operations.rds"))
  write_csv(nass_fl_state_oper, file.path(out_dir, "nass_fl_state_operations.csv"))
  message("nass_fl_state_operations [CENSUS]: ", nrow(nass_fl_state_oper),
          " rows | census years: ",
          paste(sort(unique(nass_fl_state_oper$year)), collapse = ", "))
} else {
  message("(no CENSUS state operations returned)")
}

# 3. Combined + inventory ----
nass_citrus_fl <- bind_rows(nass_fl_state, nass_fl_county)
saveRDS(nass_citrus_fl, file.path(out_dir, "nass_citrus_fl.rds"))
write_csv(nass_citrus_fl, file.path(out_dir, "nass_citrus_fl.csv"))

nass_inventory <- nass_citrus_fl |>
  group_by(commodity, source, agg_level, statcat, unit, short_desc) |>
  summarise(
    n_obs = n(), year_min = min(year, na.rm = TRUE), year_max = max(year, na.rm = TRUE),
    n_years = n_distinct(year),
    n_counties = n_distinct(fips[agg_level == "COUNTY"]),
    n_suppressed = sum(is.na(value)), .groups = "drop"
  ) |>
  arrange(commodity, agg_level, statcat, short_desc)
write_csv(nass_inventory, file.path(out_dir, "nass_inventory.csv"))
message("nass_inventory: ", nrow(nass_inventory),
        " distinct FL series -> scripts/R/_outputs/nass_inventory.csv")

nass_inventory |>
  count(commodity, agg_level, statcat, name = "n_series") |>
  arrange(commodity, agg_level, statcat) |>
  print(n = 200)
