# ============================================================
# 06_cdl_transition.R — Hendry citrus land-use transition, CDL 2008 vs 2025
# Author: Yuanyuan Wen (with Claude Code)
# Purpose: Answer "what did Hendry's 2008 citrus land become by 2025?" using
#          USDA Cropland Data Layer (citrus = classes 72 + 212). Produces:
#          (1) a transition table (2008 citrus pixels -> 2025 category, acres/%),
#          (2) map geometry: a CHANGE layer (citrus retained / lost / gained)
#              and the 2008 & 2025 citrus EXTENTS as separate layers, so the
#              dashboard can overlay/toggle the two years.
#          (Parcel-level DOR use codes only exist publicly from 2024 — see
#           MEMORY — so satellite land cover is the only source with a 2008
#           endpoint. CDL is <40% accurate for FL crops: read as direction
#           of travel, not exact acres.)
# Inputs:  CropScape API (CropScapeR), Hendry FIPS 12051, years 2008 & 2025
# Outputs: data/raw/cdl/cdl_hendry_<year>.tif                 (cached)
#          scripts/R/_outputs/cdl_hendry_citrus_transition.rds / .csv
#          scripts/R/_outputs/cdl_hendry_citrus_transition_raw.csv
#          scripts/R/_outputs/cdl_hendry_change.rds   (sf 4326: retained/lost/gained)
#          scripts/R/_outputs/cdl_hendry_extent.rds   (sf 4326: year 2008 / 2025)
# CRS:     CDL native EPSG:5070; map geometry reprojected to 4326 for leaflet.
# Notes:   No randomness -> no seed (INV-9 n/a). here() paths (INV-10).
# ============================================================

# 0. Setup ----
library(tidyverse)
library(here)
library(terra)
library(sf)
library(CropScapeR)

options(timeout = 600)
sf::sf_use_s2(FALSE)
dir.create(here("data", "tmp"), recursive = TRUE, showWarnings = FALSE)
terraOptions(tempdir = here("data", "tmp"))

cdl_dir <- here("data", "raw", "cdl")
out_dir <- here("scripts", "R", "_outputs")
dir.create(cdl_dir, recursive = TRUE, showWarnings = FALSE)

FIPS         <- "12051"   # Hendry County
# CDL codes counted as citrus: 72 = Citrus (generic) AND 212 = Oranges.
# Florida citrus is mostly oranges, which CDL labels 212 — omitting it
# severely undercounts citrus and mislabels 72<->212 reclassification as
# loss/gain. Add other citrus codes here if a year uses them.
CITRUS_CODES <- c(72, 212)
ACRES_PER_PX <- 900 * 0.000247105

# 1. Download (cache-and-skip) CDL county clips; fall back if a year missing ----
get_cdl <- function(year) {
  f <- file.path(cdl_dir, paste0("cdl_hendry_", year, ".tif"))
  if (file.exists(f)) { message("cache hit: ", basename(f)); return(rast(f)) }
  message("CropScape pull: Hendry ", year, " ...")
  r <- terra::rast(GetCDLData(aoi = FIPS, year = year, type = "f"))
  writeRaster(r, f, overwrite = TRUE)
  r
}
get_cdl_try <- function(years) {
  for (y in years) {
    r <- tryCatch(get_cdl(y), error = function(e) {
      message("  CDL ", y, " unavailable: ", conditionMessage(e)); NULL })
    if (!is.null(r)) return(list(r = r, year = y))
  }
  stop("No CDL year available among: ", paste(years, collapse = ", "))
}

early <- get_cdl_try(2008); YEAR_EARLY <- early$year; r0 <- early$r
late  <- get_cdl_try(c(2025, 2024)); YEAR_LATE <- late$year; r1 <- late$r
message("Years used: ", YEAR_EARLY, " -> ", YEAR_LATE)

if (!compareGeom(r0, r1, stopOnError = FALSE, messages = FALSE)) {
  message("Grids differ — resampling ", YEAR_LATE, " to the ", YEAR_EARLY, " grid (nearest).")
  r1 <- resample(r1, r0, method = "near")
}

# 2. CDL class legend (full official USDA CDL legend) ----
# Mapped explicitly because the cached CDL GeoTIFF drops its attribute table.
# Citrus is handled by code (72 + 212) downstream; this just names each class
# so the categories group correctly. (e.g. 71 = Other Tree Crops, NOT citrus.)
CDL_LEGEND <- c(
  "1"="Corn","2"="Cotton","3"="Rice","4"="Sorghum","5"="Soybeans","6"="Sunflower",
  "10"="Peanuts","11"="Tobacco","12"="Sweet Corn","13"="Pop or Orn Corn","14"="Mint",
  "21"="Barley","22"="Durum Wheat","23"="Spring Wheat","24"="Winter Wheat",
  "25"="Other Small Grains","26"="Dbl Crop WinWht/Soybeans","27"="Rye","28"="Oats",
  "29"="Millet","30"="Speltz","31"="Canola","32"="Flaxseed","33"="Safflower",
  "34"="Rape Seed","35"="Mustard","36"="Alfalfa","37"="Other Hay/Non Alfalfa",
  "38"="Camelina","39"="Buckwheat","41"="Sugarbeets","42"="Dry Beans","43"="Potatoes",
  "44"="Other Crops","45"="Sugarcane","46"="Sweet Potatoes","47"="Misc Vegs & Fruits",
  "48"="Watermelons","49"="Onions","50"="Cucumbers","51"="Chick Peas","52"="Lentils",
  "53"="Peas","54"="Tomatoes","55"="Caneberries","56"="Hops","57"="Herbs",
  "58"="Clover/Wildflowers","59"="Sod/Grass Seed","60"="Switchgrass",
  "61"="Fallow/Idle Cropland","62"="Pasture/Grass","63"="Forest","64"="Shrubland","65"="Barren",
  "66"="Cherries","67"="Peaches","68"="Apples","69"="Grapes","70"="Christmas Trees",
  "71"="Other Tree Crops","72"="Citrus","74"="Pecans","75"="Almonds","76"="Walnuts",
  "77"="Pears","81"="Clouds/No Data","82"="Developed","83"="Water","87"="Wetlands",
  "88"="Nonag/Undefined","92"="Aquaculture","111"="Open Water",
  "112"="Perennial Ice/Snow","121"="Developed/Open Space",
  "122"="Developed/Low Intensity","123"="Developed/Med Intensity",
  "124"="Developed/High Intensity","131"="Barren","141"="Deciduous Forest",
  "142"="Evergreen Forest","143"="Mixed Forest","152"="Shrubland",
  "176"="Grassland/Pasture","190"="Woody Wetlands","195"="Herbaceous Wetlands",
  "204"="Pistachios","205"="Triticale","206"="Carrots","207"="Asparagus",
  "208"="Garlic","209"="Cantaloupes","210"="Prunes","211"="Olives","212"="Oranges",
  "213"="Honeydew Melons","214"="Broccoli","215"="Avocados","216"="Peppers",
  "217"="Pomegranates","218"="Nectarines","219"="Greens","220"="Plums",
  "221"="Strawberries","222"="Squash","223"="Apricots","224"="Vetch",
  "225"="Dbl Crop WinWht/Corn","226"="Dbl Crop Oats/Corn","227"="Lettuce",
  "228"="Dbl Crop Triticale/Corn","229"="Pumpkins",
  "230"="Dbl Crop Lettuce/Durum Wht","231"="Dbl Crop Lettuce/Cantaloupe",
  "232"="Dbl Crop Lettuce/Cotton","233"="Dbl Crop Lettuce/Barley",
  "234"="Dbl Crop Durum Wht/Sorghum","235"="Dbl Crop Barley/Sorghum",
  "236"="Dbl Crop WinWht/Sorghum","237"="Dbl Crop Barley/Corn",
  "238"="Dbl Crop WinWht/Cotton","239"="Dbl Crop Soybeans/Cotton",
  "240"="Dbl Crop Soybeans/Oats","241"="Dbl Crop Corn/Soybeans","242"="Blueberries",
  "243"="Cabbage","244"="Cauliflower","245"="Celery","246"="Radishes",
  "247"="Turnips","248"="Eggplants","249"="Gourds","250"="Cranberries",
  "254"="Dbl Crop Barley/Soybeans")
name_of <- function(code) {
  nm <- unname(CDL_LEGEND[as.character(code)])
  ifelse(is.na(nm), paste0("CDL ", code), nm)
}
group_cat <- function(name) {
  n <- toupper(name)
  case_when(
    str_detect(n, "CITRUS|ORANGE|GRAPEFRUIT|TANGERINE|TANGELO|TEMPLE|LEMON|LIME") ~ "Citrus (unchanged)",
    str_detect(n, "DEVELOP")                                  ~ "Developed",     # 82 Developed + 121-124
    str_detect(n, "AQUACULT")                                 ~ "Aquaculture",   # 92 only (kept distinct)
    str_detect(n, "OPEN WATER") | n == "WATER"                ~ "Water",         # 111 / 83; NOT Watermelons (48)
    str_detect(n, "WETLAND")                                  ~ "Wetlands",
    str_detect(n, "FOREST")                                   ~ "Forest",
    str_detect(n, "GRASS|PASTURE|SHRUB|HAY|ALFALFA|CLOVER|SOD|SWITCHGRASS") ~ "Grass/Pasture/Hay",
    str_detect(n, "FALLOW|IDLE")                              ~ "Fallow/Idle",
    str_detect(n, "BARREN|CLOUD|NO DATA|NONAG|UNDEFINED|BACKGROUND|ICE/SNOW") ~ "Barren/No data",
    str_detect(n, "SUGARCANE")                                ~ "Sugarcane",
    # Residual bucket: small leftover classes (here CDL 3 Rice + 71 Other Tree
    # Crops). Named "Other" — NOT "Other crops" — to avoid colliding with the
    # specific CDL class 44 "Other Crops", which is a different thing entirely.
    TRUE                                                      ~ "Other")
}

# 3. Transition table: 2025 class for pixels that were citrus in 2008 ----
df <- tibble(y0 = as.vector(values(r0)), y1 = as.vector(values(r1))) |>
  filter(y0 %in% CITRUS_CODES, !is.na(y1))
total_citrus_px <- nrow(df)
stopifnot("No 2008 citrus pixels found." = total_citrus_px > 0)

raw_tab <- df |>
  count(y1, name = "pixels") |>
  mutate(cdl_class = name_of(y1), acres = pixels * ACRES_PER_PX,
         pct = 100 * pixels / total_citrus_px) |>
  arrange(desc(pixels))
write_csv(raw_tab, file.path(out_dir, "cdl_hendry_citrus_transition_raw.csv"))

transition <- raw_tab |>
  # citrus-unchanged is code-based (covers 72 Citrus + 212 Oranges); the rest
  # fall to name-based categories.
  mutate(category = if_else(y1 %in% CITRUS_CODES, "Citrus (unchanged)",
                            group_cat(cdl_class))) |>
  group_by(category) |>
  summarise(acres = sum(acres), pixels = sum(pixels), pct = sum(pct),
            # CDL class codes (and names) that make up each category
            codes   = paste(sort(unique(y1)), collapse = ", "),
            classes = paste(sort(unique(cdl_class)), collapse = "; "),
            .groups = "drop") |>
  arrange(desc(acres)) |>
  mutate(from_year = YEAR_EARLY, to_year = YEAR_LATE,
         total_2008_citrus_acres = total_citrus_px * ACRES_PER_PX)
saveRDS(transition, file.path(out_dir, "cdl_hendry_citrus_transition.rds"))
write_csv(transition, file.path(out_dir, "cdl_hendry_citrus_transition.csv"))

# 4. Map geometry: change layer + the two yearly citrus extents ----
# Topology-safe simplification (ms_simplify keeps shared boundaries, so the
# change classes stay coincident and the derived year extents tile exactly —
# no per-layer drift, and a far smaller file than unsimplified polygons).
poly_4326 <- function(spatvec) {
  if (nrow(spatvec) == 0) return(NULL)
  s <- st_as_sf(spatvec) |> st_make_valid() |> st_transform(5070)
  s <- rmapshaper::ms_simplify(s, keep = 0.05, keep_shapes = TRUE, explode = FALSE)
  st_make_valid(s) |> st_transform(4326)
}
mask_citrus <- function(r) {
  m <- r == CITRUS_CODES[1]
  for (cc in CITRUS_CODES[-1]) m <- m | (r == cc)
  ifel(m, 1, NA)
}

c08 <- mask_citrus(r0); c25 <- mask_citrus(r1)

# change: 1 retained, 2 lost (2008 only), 3 gained (2025 only)
chg <- ifel(!is.na(c08) & !is.na(c25), 1,
            ifel(!is.na(c08) & is.na(c25), 2,
                 ifel(is.na(c08) & !is.na(c25), 3, NA)))
names(chg) <- "code"

chg_sf <- poly_4326(as.polygons(chg, dissolve = TRUE))
extent_sf <- NULL
if (!is.null(chg_sf)) {
  chg_sf <- chg_sf |>
    mutate(category = recode(as.integer(code),
      `1` = "Retained citrus", `2` = "Lost (2008 only)", `3` = "Gained (2025 only)")) |>
    select(category)
  saveRDS(chg_sf, file.path(out_dir, "cdl_hendry_change.rds"))

  # Year extents derived from the SAME simplified polygons -> exact tiling:
  # 2008 = retained ∪ lost, 2025 = retained ∪ gained.
  union_cat <- function(cats) {
    g <- chg_sf |> filter(category %in% cats)
    if (nrow(g) == 0) return(NULL)
    st_sf(geometry = st_union(st_geometry(g)))
  }
  e08 <- union_cat(c("Retained citrus", "Lost (2008 only)"))
  e25 <- union_cat(c("Retained citrus", "Gained (2025 only)"))
  extent_sf <- bind_rows(
    if (!is.null(e08)) mutate(e08, year = YEAR_EARLY),
    if (!is.null(e25)) mutate(e25, year = YEAR_LATE))
}
saveRDS(extent_sf, file.path(out_dir, "cdl_hendry_extent.rds"))

# 5. Report ----
message("Hendry ", YEAR_EARLY, " citrus footprint: ",
        format(round(total_citrus_px * ACRES_PER_PX), big.mark = ","), " acres")
message("Where it went by ", YEAR_LATE, ":")
message(paste(capture.output(as.data.frame(transition[, c("category","acres","pct")])),
              collapse = "\n"))
message("--- top raw ", YEAR_LATE, " CDL classes (verify labels) ---")
message(paste(capture.output(as.data.frame(head(raw_tab[, c("y1","cdl_class","acres","pct")], 12))),
              collapse = "\n"))
message("Saved change + extent sf for the overlay map.")
