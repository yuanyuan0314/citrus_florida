# ============================================================
# theme_dashboard.R — shared plotting identity for the dashboard
# Okabe-Ito colorblind-safe palette (INV-12); white bg (INV-11).
# Sourced by dashboard/index.qmd.
# ============================================================

suppressPackageStartupMessages({
  library(ggplot2)
})

# Okabe-Ito palette (named for legible reuse)
oi <- c(
  orange    = "#E69F00",
  skyblue   = "#56B4E9",
  green     = "#009E73",
  yellow    = "#F0E442",
  blue      = "#0072B2",
  vermilion = "#D55E00",
  purple    = "#CC79A7",
  black     = "#000000",
  grey      = "#999999"
)

theme_dashboard <- function(base_size = 13) {
  theme_minimal(base_size = base_size) +
    theme(
      plot.title    = element_text(face = "bold"),
      plot.subtitle = element_text(color = "grey30"),
      plot.caption  = element_text(color = "grey45", size = rel(0.8), hjust = 0),
      axis.title    = element_text(color = "grey20"),
      legend.position   = "bottom",
      legend.title      = element_blank(),
      panel.grid.minor  = element_blank(),
      panel.grid.major  = element_line(color = "grey92"),
      plot.background   = element_rect(fill = "white", color = NA),
      panel.background  = element_rect(fill = "white", color = NA)
    )
}

# Standard source-note caption helper
src_note <- function(x) paste0("Source: ", x)
