# ============================================================
# 01e_nass_state_wide.R — reshape FL state citrus to wide form
# Author: Yuanyuan Wen (with Claude Code)
# Purpose: From nass_fl_state (long, many mixed units), split short_desc
#          into <crop> and <item>, then pivot <item> to columns —
#          one row per crop x year (x program / util / domain / period).
#          Each item column carries its own unit in the name
#          (e.g. "PRODUCTION, MEASURED IN TONS"), so units never mix
#          within a column — the fix for the messy single `unit` column.
# Inputs:  scripts/R/_outputs/nass_fl_state.rds   (from 01c_filter_fl.R)
# Outputs: scripts/R/_outputs/nass_fl_state_wide.rds / .csv
# Notes:   short_desc = "<crop> - <item>"; split on the FIRST " - " only
#          (crop may contain a comma, e.g. "ORANGES, VALENCIA"; item may
#          contain further " - " and is kept whole via too_many="merge").
#          Suppressed "(D)" stay NA (not 0). No seed (INV-9 n/a).
# ============================================================

# 0. Setup ----
library(tidyverse)
library(here)

out <- function(f) here("scripts", "R", "_outputs", f)
state <- readRDS(out("nass_fl_state.rds"))
stopifnot("nass_fl_state.rds is empty" = nrow(state) > 0)

# 1. Split short_desc -> crop + item (first " - " only) ----
state_split <- state |>
  separate_wider_delim(
    short_desc, delim = " - ",
    names = c("crop", "item"),
    too_many = "merge",       # keep any extra " - " inside item
    too_few  = "align_start"
  )

# 2. Pivot item -> columns ----
# Preserve NA for suppressed cells: NA only if every value is NA.
sum_keep_na <- function(x) if (all(is.na(x))) NA_real_ else sum(x, na.rm = TRUE)

# Disambiguating id columns. util/prodn practice, domain/domaincat, and
# reference_period keep distinct series (e.g. processing vs fresh price,
# chemical-use breakdowns, monthly vs marketing-year prices) from colliding.
id_cols <- c("source", "agg_level", "state_alpha", "year", "commodity", "crop",
             "util_practice", "prodn_practice", "domain", "domaincat",
             "freq", "reference_period")

# Flag any residual collisions (would be aggregated by sum_keep_na)
dups <- state_split |>
  count(across(all_of(id_cols)), item, name = "nrow") |>
  filter(nrow > 1)
if (nrow(dups) > 0)
  message("NOTE: ", nrow(dups),
          " id+item combos had >1 row and were aggregated (sum, NA-preserving). ",
          "Inspect if exact values matter.")

nass_fl_state_wide <- state_split |>
  select(all_of(id_cols), item, value) |>
  pivot_wider(names_from = item, values_from = value, values_fn = sum_keep_na) |>
  arrange(crop, year)

saveRDS(nass_fl_state_wide, out("nass_fl_state_wide.rds"))
write_csv(nass_fl_state_wide, out("nass_fl_state_wide.csv"))

# 3. Report ----
item_cols <- setdiff(names(nass_fl_state_wide), id_cols)
message("nass_fl_state_wide: ", format(nrow(nass_fl_state_wide), big.mark = ","),
        " rows x ", ncol(nass_fl_state_wide), " cols (", length(item_cols), " item columns)")
message("Crops: ", paste(sort(unique(nass_fl_state_wide$crop)), collapse = ", "))
message("Year range: ", min(nass_fl_state_wide$year, na.rm = TRUE), "-",
        max(nass_fl_state_wide$year, na.rm = TRUE))
message("Item columns:")
walk(sort(item_cols), ~ message("  - ", .x))
