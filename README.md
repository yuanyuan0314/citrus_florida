# Florida Citrus Land-Use Dashboard

An interactive HTML dashboard on the decline of Florida citrus and where the land
is going — built from public data (USDA NASS, USDA Cropland Data Layer, the USGS/LBNL
solar PV database, and Florida DOR parcel records).

**▶ Live dashboard:** https://yuanyuan0314.github.io/citrus_florida/
(or open [`index.html`](index.html) directly — it is a single self-contained file).

---

## What's in this repo

```
index.html                     # the rendered dashboard (this is what GitHub Pages serves)
dashboard/
  index.qmd                    # dashboard source (Quarto); reads ONLY from scripts/R/_outputs/
  R/theme_dashboard.R          # shared ggplot theme + Okabe-Ito palette (sourced by index.qmd)
scripts/R/
  00_setup.R … 08_*.R          # the numbered data pipeline (details below)
  _outputs/*.rds               # pre-computed analysis objects the dashboard reads
.here                          # marks the repo root for R's here::here()
```

The pipeline writes every computed object to `scripts/R/_outputs/`, and the dashboard
reads **only** from there — it never touches raw data or re-runs heavy computation at
render time. The `_outputs/*.rds` files are committed, so **you can re-render the
dashboard immediately without an API key or any large downloads** (see Option A).

---

## How to reproduce the webpage

### Prerequisites

- **R** (≥ 4.3) and **Quarto** (≥ 1.4).
- R packages: `tidyverse`, `here`, `scales`, `sf`, `terra`, `leaflet`, `htmltools`,
  `tigris`, `rmapshaper`, `rnassqs`, `CropScapeR`, `ggplot2`.
  Running `scripts/R/00_setup.R` once installs anything missing.
- For the **full data pull** (Option B), a free USDA NASS QuickStats API key
  (https://quickstats.nass.usda.gov/api) placed in a `.Renviron` file at the repo root:
  `NASS_API_KEY=your_key_here`. *(Not needed for Option A.)*

### Option A — just re-render (fast; no API key, no downloads)

The analysis outputs are already in `scripts/R/_outputs/`, so you only need Quarto:

```sh
quarto render dashboard/index.qmd
```

This regenerates `dashboard/index.html`. (The copy served at the repo root is the same
file.) Run the command **from the repo root** so `here::here()` resolves paths correctly.

### Option B — rebuild everything from source

Run the scripts **in this order** (each caches its raw downloads and skips work that's
already done). All paths are relative via `here::here()`, so run them from the repo root,
e.g. `Rscript scripts/R/01_get_nass.R`.

| Order | Script | Produces in `scripts/R/_outputs/` | Notes / needs |
|------:|--------|-----------------------------------|---------------|
| 0 | `00_setup.R` | (installs packages) | internet (CRAN), one-time |
| 1 | `01_get_nass.R` | `nass_state`, `nass_county`, `county_ranking` | NASS API key |
| 2 | `01b_nass_explore.R` | `nass_fl_state`, `nass_fl_county`, `nass_fl_state_operations` | NASS API key — **required** despite the name |
| 3 | `02_get_uspvdb.R` | `uspvdb_fl` | downloads USGS/LBNL USPVDB |
| 4 | `03_get_dor_nal.R` | `nal_citrus_parcels_top2`, `nal_citrus_summary_top2` | downloads FL DOR NAL tax roll |
| 5 | `04_county_choropleth.R` | `county_choropleth`, `bearing_change` | needs step 2 + `tigris` |
| 6 | `06_cdl_transition.R` | `cdl_hendry_citrus_transition`, `cdl_hendry_change`, `cdl_hendry_extent` | CropScape API (CDL) |
| 7 | `07_solar_zonal.R` | `solar_county` | needs step 3 + `tigris` |
| 8 | `08_dor_hendry_parcels.R` | `dor_hendry_citrus_parcels` | needs a **manually downloaded** Hendry PAR shapefile (see below) |

Then render: `quarto render dashboard/index.qmd`.

**Optional / auxiliary scripts** (not required to build the dashboard):
`05_get_dor_parcels.R` (full top-2-county parcel polygons — a very large download),
and `01c_filter_fl.R` / `01d_nass_county_wide.R` / `01e_nass_state_wide.R` /
`exlore_usda_nass.R` (exploratory NASS reshaping; their outputs are not read by the dashboard).

### Manual step for `08_dor_hendry_parcels.R`

Florida DOR parcel **use codes** (`DOR_UC`, where 66 = citrus) are only published for
2024–2025. Download Hendry County's 2025 PAR parcel layer from the
[FL DOR Data Portal](https://floridarevenue.com/property/Pages/DataPortal.aspx),
save it as `data/raw/dor_nal/hendry_2025Ppar.zip`, then run the script. (A pre-computed
`dor_hendry_citrus_parcels.rds` is already in `_outputs/`, so Option A works without this.)

---

## Data sources & conventions

- **USDA NASS QuickStats** — citrus acreage / production / value (state SURVEY) and
  county bearing/non-bearing acreage + operations (Census of Agriculture).
- **USDA Cropland Data Layer (CDL)** — 30 m land cover. Citrus = classes **72 + 212**
  (Citrus + Oranges); Hendry County, 2008 vs 2025.
- **USGS / LBNL USPVDB** — utility-scale (≥ 1 MW) solar PV facility polygons + year online.
- **Florida DOR** — NAL tax roll (use code 66 = citrus) and PAR parcel geometry.
- **Census TIGER** via `tigris` — county boundaries.

Conventions: raster work in EPSG:5070 (CDL's native CRS), map vectors in EPSG:4326;
county FIPS kept as character keys; area in acres. CDL is < 40% accurate for Florida
crops, so the transition figures are read as **direction of travel, not exact acres**.

---

*Built as a public-data exploration of Florida citrus land-use transitions
(citrus greening / HLB, urban development, and utility-scale solar).*
