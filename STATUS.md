# VQR 2020–2024 — DMM/UNIPD Analysis: Status Report

**Date:** 11 June 2026  
**Project:** `/Users/russelllewis/Desktop/VQR_analysis/`  
**Goal:** Recreate the figures from `DMM_VQR_2020-2024_UNIPD_32.pdf` using `vqr_pipeline.R`.

---

## Status: Complete ✅

All six figures match the PDF presentation. Run the full pipeline with:

```r
source("vqr_pipeline.R")
```

Output is saved to `figure_vqr/`.

---

## Files

| File | Role |
|------|------|
| `vqr_pipeline.R` | Main pipeline — loads data, builds and saves all figures |
| `vqr_area_data.csv` | Area-level R indicators (Tab 2.1–2.3); semicolon-delimited |
| `vqr_ird_data.csv` | Department-level H, R, IRD indicators (Tab 2.4); semicolon-delimited |
| `DMM_VQR_2020-2024_UNIPD_32.pdf` | Target presentation (8 pages) |
| `Padova_Rapporto_Istituzione_VQR_2020_2024 copy.pdf` | Raw ANVUR source report (23 pages) — used for data extraction |

---

## Figures

| Output file | PDF page | Description | Status |
|---|---|---|---|
| `figure_vqr/area05_R.png` | p. 2 | Area 05 (Biologia): DMM vs peer depts, R1/R2/R1_2 bars | ✅ |
| `figure_vqr/area06_R.png` | p. 3 | Area 06 (Medicina): DMM vs peer depts, R1/R2/R1_2 bars | ✅ |
| `figure_vqr/dmm_summary_R.png` | p. 4 | DMM only: R1/R2/R1_2 by area with rank labels | ✅ |
| `figure_vqr/rank_R1_R2_R12_R.png` | p. 5 | All 32 depts ranked by R1, R2, R1_2 (3 panels) | ✅ |
| `figure_vqr/ird_rank_R.png` | p. 6 | IRD1_2 ranking; color = quality (R1_2) | ✅ |
| `figure_vqr/ird_scatter_R.png` | p. 7 | IRD vs dept size; DMM annotated with rank info | ✅ |

---

## Data Notes

### `vqr_area_data.csv`
- Covers departments in **Area 05** (Biology) and **Area 06** (Medicine) only.
- **R1 rows were missing** from the original CSV for most departments. They were manually extracted from pages 11–12 of the raw ANVUR PDF and added during this session.
- Area 05 R1 has **5 departments** (not 7): BCA and DNS are excluded because they had fewer than 10 expected permanent-staff products — an ANVUR reporting threshold, not a data gap.

### `vqr_ird_data.csv`
- Covers all **32 departments** at Università di Padova. ✅
- Used for the IRD ranking, IRD scatter, and the three-panel R1/R2/R1_2 ranking chart.

---

## Key Fixes Made to `vqr_pipeline.R`

1. **CSV delimiter** — changed `read_csv` → `read_delim(..., delim = ";")` (files are semicolon-separated).
2. **Department name spacing** — corrected the `sigle` lookup dictionary to match exact punctuation in the CSV (e.g., `"SCIENZE CARDIO- TORACO-"` not `"SCIENZE CARDIO - TORACO -"`).
3. **Area code format** — CSV uses `5`/`6`, not `"05"`/`"06"`; updated `plot_area()` calls accordingly.
4. **Palette name collision** — `c(DMM_R1 = RED["R1"])` produced keys like `DMM_R1.R1`; fixed with `unname()`.
5. **Missing R1 data** — extracted R1 rows for Areas 05 and 06 from the raw ANVUR PDF and added to `vqr_area_data.csv`.
6. **DMM label highlighting** — `ggtext::element_markdown()` does **not** render HTML/CSS in saved PNGs in this environment (ggtext 0.1.2 limitation). Workaround: `axis.text.y = element_blank()` + `geom_text()` with `color` and `fontface` aesthetics. Applied to `rank_R1_R2_R12_R.png` and `ird_rank_R.png`.
7. **Rank panel** — replaced broken `facet_wrap + coord_flip` approach with three independent plots combined via `patchwork`. Rank computation uses `ties.method = "first"` to match ANVUR ordering (DMM: R1=1°, R2=6°, R1_2=4° su 32).
8. **IRD rank chart** — added red bold DMM label, dark border on DMM bar, red title, tightened x-axis limits.
9. **IRD scatter** — added multi-line DMM annotation with arrow, labelled DFA/DII/DSB/DiBio/BCA, added trend line label, completed title with "(numero di docenti)".

---

## Dependencies

```r
# Required packages (all used in vqr_pipeline.R)
pkgs <- c("pdftools", "stringr", "dplyr", "tidyr", "ggplot2",
          "forcats", "scales", "ggrepel", "readr", "patchwork")
```

`ggtext` is **not** used in the final pipeline (see fix #6 above).

---

## Potential Next Steps

- Export all figures to PowerPoint using the `officer` block already stubbed out at the bottom of `vqr_pipeline.R`.
- Cross-check the manually extracted R1 values against the raw ANVUR PDF if exact reproducibility is critical.
- Update `vqr_area_data.csv` from the pipeline directly (set `USE_PDF <- TRUE` and point `PDF_PATH` to the raw report) once the regex parser is validated against the Padova report layout.
