# Florida Citrus Land-Use Dashboard

An interactive HTML dashboard on the decline of Florida citrus and where the land
is going — built from public data (USDA NASS, USDA Cropland Data Layer, the USGS/LBNL
solar PV database, and Florida DOR parcel records).

**▶ Live dashboard:** https://yuanyuan0314.github.io/citrus_florida/
(or open [`index.html`](index.html) directly — it is a single self-contained file).

---

## What's in this repo

```
run_all.R                      # ONE-CLICK build: runs the whole pipeline, then renders
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
- A **USDA NASS QuickStats API key** — needed **only** if you rebuild the data from
  scratch (pipeline scripts `01_get_nass.R` and `01b_nass_explore.R`). **Not needed**
  just to render the dashboard from the shipped outputs.

#### Getting & setting the NASS API key

Only the two NASS scripts (`01`, `01b`) require this; everything else runs without it.

1. **Get a free key** (instant — it's emailed to you): **https://quickstats.nass.usda.gov/api**
2. **Where to paste it:** copy the file **`.Renviron.example`** (in the repo root) to a new
   file named **`.Renviron`** in the same folder, and paste your key after the `=`:
   ```
   NASS_API_KEY=YOUR-KEY-HERE
   ```
   No quotes, no spaces around `=`. (`.Renviron` is git-ignored, so your key never gets
   committed.)
3. **Restart R** (RStudio: *Session → Restart R*) so the key loads, then run as usual.

If you run `run_all.R` with the data pipeline on but no key, it stops with a message
pointing you to these exact steps — so you'll always know what's missing and where.

### Option 0 — one click (recommended)

Open **`run_all.R`** in RStudio and click **Source** (or run `Rscript run_all.R` from the
repo root). **That's it — one file produces the webpage.**

Because the computed outputs (`scripts/R/_outputs/*.rds`) ship with the repo, a fresh
clone renders the dashboard immediately — **no API key, no downloads needed.** The data
pipeline runs automatically *only* if those outputs are missing.

To rebuild everything from raw data (needs a free NASS API key — see Prerequisites),
run with the pipeline forced on: `RUN_DATA_PIPELINE=TRUE Rscript run_all.R`
(or set `RUN_DATA_PIPELINE <- TRUE` near the top of the file).

The two options below are the same thing done by hand, if you prefer to run pieces yourself.

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
| 8 | `08_dor_hendry_parcels.R` | `dor_hendry_citrus_parcels` | auto-downloads the Hendry 2025 PAR shapefile from the FL DOR portal (see below) |

Then render: `quarto render dashboard/index.qmd`.

**Optional / auxiliary scripts** (not required to build the dashboard):
`05_get_dor_parcels.R` (full top-2-county parcel polygons — a very large download),
and `01c_filter_fl.R` / `01d_nass_county_wide.R` / `01e_nass_state_wide.R` /
`exlore_usda_nass.R` (exploratory NASS reshaping; their outputs are not read by the dashboard).

### Note on `08_dor_hendry_parcels.R`

Florida DOR parcel **use codes** (`DOR_UC`, where 66 = citrus) are only published for
2024–2025. The script downloads Hendry County's 2025 PAR parcel layer automatically
(cache-and-skip) from the FL DOR Data Portal:

```
https://floridarevenue.com/property/dataportal/Documents/PTO%20Data%20Portal/Map%20Data/2025F/2025F%20PAR/hendry_2025Ppar.zip
```

If that download ever fails, fetch the file manually from the
[FL DOR Data Portal](https://floridarevenue.com/property/Pages/DataPortal.aspx)
(Map Data → 2025F → 2025F PAR) and save it as `data/raw/dor_nal/hendry_2025Ppar.zip`,
then re-run. (A pre-computed `dor_hendry_citrus_parcels.rds` is already in `_outputs/`,
so Option A works without this step.)

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
