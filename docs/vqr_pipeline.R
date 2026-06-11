###############################################################################
# VQR 2020–2024 — Pipeline di analisi e visualizzazione (R)
#
# Replica in R del flusso usato per il Dipartimento di Medicina Molecolare (DMM):
#   1. Estrazione del testo dal PDF ANVUR  (pdftools)
#   2. Parsing delle tabelle per dipartimento  (stringr / regex)
#   3. Riordino dei dati  (dplyr / tidyr)
#   4. Visualizzazioni  (ggplot2)
#   5. (Opzionale) export in PowerPoint  (officer)
#
# Fonte dati: ANVUR, VQR 2020–2024 — Risultati delle singole istituzioni:
#             Università degli Studi di Padova (28 maggio 2026).
#   Tab. 2.1 = R1 (personale a tempo indeterminato)   [per area]
#   Tab. 2.2 = R2 (neo-assunti / avanzamenti)          [per area]
#   Tab. 2.3 = R1_2 (tutto il personale)               [per area]
#   Tab. 2.4 = H, R, IRD per dipartimento              [sommati sulle aree]
#
# NOTA: il parsing del PDF (sezione 2) dipende da come `pdftools` rende il
# testo, che può differire leggermente da altri estrattori: le regex potrebbero
# richiedere piccoli aggiustamenti. Per garantire risultati riproducibili, lo
# script per default carica i CSV già verificati (vqr_area_data.csv,
# vqr_ird_data.csv). Imposta USE_PDF <- TRUE per estrarre direttamente dal PDF.
###############################################################################

# ------------------------------------------------------------------ #
# 0. Setup
# ------------------------------------------------------------------ #
pkgs <- c("pdftools", "stringr", "dplyr", "tidyr", "ggplot2", "patchwork", "forcats", "scales")
to_install <- setdiff(pkgs, rownames(installed.packages()))
if (length(to_install)) install.packages(to_install)
invisible(lapply(pkgs, library, character.only = TRUE))

USE_PDF  <- FALSE   # TRUE = estrai dal PDF; FALSE = usa i CSV verificati
PDF_PATH <- "Padova_Rapporto_Istituzione_VQR_2020_2024.pdf"
OUT_DIR  <- "figure_vqr"
if (!dir.exists(OUT_DIR)) dir.create(OUT_DIR)

# Palette istituzionale (UniPD)
RED   <- c(R1 = "#9B0014", R2 = "#C0504D", R1_2 = "#E2A39E")  # DMM (sfumature di rosso)
GRAY  <- c(R1 = "#5A5A5A", R2 = "#9A9A9A", R1_2 = "#CCCCCC")  # altri dipartimenti
INK   <- "#1A1A1A"; REF_LINE <- "#111111"
it_num <- scales::label_number(accuracy = 0.01, decimal.mark = ",")  # virgola decimale

# ------------------------------------------------------------------ #
# 1–2. Estrazione + parsing dal PDF  (opzionale)
# ------------------------------------------------------------------ #
parse_area_tables <- function(pdf_path) {
  # Tab. 2.1/2.2/2.3 sono su queste pagine (1-based) del rapporto Padova:
  page_sets <- list(R1 = 12:13, R2 = 14:16, R1_2 = 17:20)
  # n. complessivo di dipartimenti per area (denominatore di graduatoria),
  # usato per isolare le righe della tabella corretta:
  denom <- list(R1 = c(`05` = 140, `06` = 151),
                R2 = c(`05` = 185, `06` = 176),
                R1_2 = c(`05` = 211, `06` = 189))
  txt_all <- pdf_text(pdf_path)
  # riga tabella: v  n  I  R  pos  num_dip  quartile  pos_q  num_q  (preceduta da area+nome)
  pat <- "([56])\\s+([A-ZÀ-Ü][^0-9]*?)\\s+(\\d{1,3},\\d\\d)\\s+(\\d+)\\s+(\\d,\\d\\d)\\s+([012],\\d\\d)\\s+(\\d+)\\s+(\\d+)\\s+([1-4])\\s+(\\d+)\\s+(\\d+)"
  out <- list()
  for (ind in names(page_sets)) {
    txt <- paste(txt_all[page_sets[[ind]]], collapse = " ")
    txt <- str_squish(txt)
    mm  <- str_match_all(txt, pat)[[1]]
    if (nrow(mm) == 0) next
    df <- tibble(
      indicatore  = ind,
      area        = paste0("0", mm[, 2]),
      dipartimento= str_squish(mm[, 3]),
      n           = as.integer(mm[, 5]),
      R           = as.numeric(sub(",", ".", mm[, 6])),
      pos         = as.integer(mm[, 8]),
      num_dip     = as.integer(mm[, 9]),
      quartile    = as.integer(mm[, 10])
    )
    # tieni solo le righe con il denominatore d'area atteso, deduplica per nome
    keep <- mapply(function(a, nd) nd == denom[[ind]][[sub("^0", "0", a)]],
                   df$area, df$num_dip)
    df <- df[keep, ]
    df <- df[!duplicated(paste(df$area, df$dipartimento)), ]
    out[[ind]] <- df
  }
  bind_rows(out)
}

parse_ird_table <- function(pdf_path) {
  txt <- str_squish(paste(pdf_text(pdf_path)[21:23], collapse = " "))
  # 11 numeri per riga: n  mob  H1 R1 IRD1  H2 R2 IRD2  H1_2 R1_2 IRD1_2
  pat <- "(\\d{2,4}) (\\d{1,4}) ([01],\\d\\d) ([012],\\d\\d) ([01],\\d\\d) ([01],\\d\\d) ([012],\\d\\d) ([01],\\d\\d) ([01],\\d\\d) ([012],\\d\\d) ([01],\\d\\d)"
  mm <- str_match_all(txt, pat)[[1]]
  # I nomi nel PDF vanno spesso a capo: in produzione mappare via dizionario di
  # sotto-stringhe (come nello script Python). Qui si raccomanda il CSV.
  num <- function(j) as.numeric(gsub(",", ".", mm[, j]))
  tibble(n_attesi = as.integer(mm[, 2]), n_mobilita = as.integer(mm[, 3]),
         H1 = num(4), R1 = num(5), IRD1 = num(6),
         H2 = num(7), R2 = num(8), IRD2 = num(9),
         H1_2 = num(10), R1_2 = num(11), IRD1_2 = num(12))
}

# ------------------------------------------------------------------ #
# Caricamento dati (CSV verificati per default)
# ------------------------------------------------------------------ #
if (USE_PDF) {
  area_df <- parse_area_tables(PDF_PATH)
  ird_df  <- parse_ird_table(PDF_PATH)   # nomi da completare via dizionario
} else {
  area_df <- readr::read_delim("vqr_area_data.csv", delim = ";", show_col_types = FALSE)
  ird_df  <- readr::read_delim("vqr_ird_data.csv", delim = ";", show_col_types = FALSE)
}

# sigle brevi per le etichette dei grafici per-area
sigle <- c(
  "BIOLOGIA (DiBio)" = "DiBio", "BIOMEDICINA COMPARATA E ALIMENTAZIONE (BCA)" = "BCA",
  "MEDICINA - DIMED" = "DIMED", "MEDICINA MOLECOLARE - DMM" = "DMM",
  "NEUROSCIENZE - DNS" = "DNS", "SCIENZE BIOMEDICHE - DSB" = "DSB",
  "SCIENZE DEL FARMACO - DSF" = "DSF", "SALUTE DELLA DONNA E DEL BAMBINO - SDB" = "SDB",
  "SCIENZE CARDIO- TORACO-VASCOLARI E SANITA' PUBBLICA" = "Cardio-Tor.",
  "SCIENZE CHIRURGICHE ONCOLOGICHE E GASTROENTEROLOGICHE- DiSCOG" = "DiSCOG"
)
area_df <- area_df %>%
  mutate(sigla = ifelse(dipartimento %in% names(sigle), sigle[dipartimento], dipartimento),
         is_dmm = str_detect(dipartimento, "MOLECOLARE"),
         indicatore = factor(indicatore, levels = c("R1", "R2", "R1_2")))

# ------------------------------------------------------------------ #
# 3–4. VISUALIZZAZIONI
# ------------------------------------------------------------------ #

## (A) Barre raggruppate per area: DMM in rosso, altri in grigio -----------
plot_area <- function(area_code, titolo) {
  d <- area_df %>% filter(area == area_code)
  ord <- d %>% filter(indicatore == "R1_2") %>% arrange(desc(R)) %>% pull(sigla)
  ord <- union(ord, unique(d$sigla))
  d <- d %>% mutate(sigla = factor(sigla, levels = ord),
                    grp = paste0(ifelse(is_dmm, "DMM_", "ALT_"), indicatore))
  pal <- c(DMM_R1 = unname(RED["R1"]), DMM_R2 = unname(RED["R2"]), DMM_R1_2 = unname(RED["R1_2"]),
           ALT_R1 = unname(GRAY["R1"]), ALT_R2 = unname(GRAY["R2"]), ALT_R1_2 = unname(GRAY["R1_2"]))
  ggplot(d, aes(sigla, R, group = indicatore, fill = grp)) +
    geom_col(position = position_dodge(width = 0.8), width = 0.75) +
    geom_hline(yintercept = 1, linetype = "dashed", color = REF_LINE) +
    geom_text(aes(label = it_num(R)),
              position = position_dodge(width = 0.8), vjust = -0.4, size = 2.6) +
    scale_fill_manual(values = pal, guide = "none") +
    labs(title = titolo, x = NULL,
         y = "Indicatore R  (>1 = sopra la media nazionale)") +
    theme_minimal(base_size = 12) +
    theme(panel.grid.major.x = element_blank(),
          axis.text.x = element_text(face = ifelse(levels(d$sigla) == "DMM", "bold", "plain")))
}
ggsave(file.path(OUT_DIR, "area05_R.png"),
       plot_area("5", "Area 05 — Biologia: DMM vs altri dipartimenti"),
       width = 11.5, height = 5.4, dpi = 200)
ggsave(file.path(OUT_DIR, "area06_R.png"),
       plot_area("6", "Area 06 — Medicina: DMM vs altri dipartimenti"),
       width = 11.5, height = 5.4, dpi = 200)

## (B) Classifica IRD1_2 tra i 32 dipartimenti (colore = qualità R1_2) ------
ird_df    <- ird_df |> mutate(is_dmm = str_detect(dipartimento, "MOLECOLARE"))
ird_sorted <- ird_df |> mutate(lbl_fct = fct_reorder(sigla, IRD1_2))

p_ird <- ggplot(ird_sorted, aes(x = IRD1_2, y = lbl_fct)) +
  # All bars — gradient fill, no border
  geom_col(aes(fill = R1_2), width = 0.75, color = NA) +
  # DMM bar second — adds visible dark border without losing the gradient fill
  geom_col(data = filter(ird_sorted, is_dmm),
           aes(fill = R1_2), width = 0.75, color = "#1A1A1A", linewidth = 1.1) +
  # Custom y-axis labels: DMM in red bold via geom_text aesthetics
  geom_text(
    aes(x = -0.005, y = lbl_fct,
        label = as.character(lbl_fct),
        color = is_dmm,
        fontface = ifelse(is_dmm, "bold", "plain")),
    hjust = 1, size = 2.5
  ) +
  geom_text(aes(label = it_num(IRD1_2)), hjust = -0.15, size = 2.5, color = INK) +
  scale_fill_gradientn(
    colors = c("#B2182B","#F4A582","#FFFFBF","#A6D96A","#1A9850"),
    values = scales::rescale(c(0.90, 0.97, 1.00, 1.08, 1.20)),
    name = "R1_2 (qualità)",
    breaks = c(0.95, 1.00, 1.05, 1.10, 1.15),
    limits = c(0.90, 1.20)
  ) +
  scale_color_manual(values = c("FALSE" = "gray30", "TRUE" = "#9B0014"), guide = "none") +
  scale_x_continuous(
    limits = c(-0.008, 0.285),
    labels = function(x) ifelse(x < 0, "", it_num(x)),
    expand = expansion(mult = c(0, 0.04))
  ) +
  coord_cartesian(clip = "off") +
  labs(
    title   = "Indicatori pesati (IRD): confronto tra dipartimenti",
    x       = "IRD1_2 (indicatore quali-quantitativo, pesato per dimensione)",
    y       = NULL,
    caption = "Fonte: ANVUR, VQR 2020–2024 — Risultati delle singole istituzioni: Università degli Studi di Padova (28 maggio 2026), Tabella 2.4 (indicatori H, R, IRD per dipartimento, sommati sulle aree)."
  ) +
  theme_minimal(base_size = 10) +
  theme(
    plot.title         = element_text(color = "#9B0014", face = "bold", size = 13),
    axis.text.y        = element_blank(),
    axis.ticks.y       = element_blank(),
    panel.grid.major.y = element_blank(),
    panel.grid.minor   = element_blank(),
    legend.position    = "right",
    legend.key.height  = unit(1.8, "cm"),
    plot.caption       = element_text(size = 6.5, color = "gray40"),
    plot.margin        = margin(t = 4, r = 8, b = 4, l = 55)
  )
ggsave(file.path(OUT_DIR, "ird_rank_R.png"), p_ird, width = 8.8, height = 8, dpi = 200)

## (C) Scatter dimensione vs IRD: l'IRD dipende dal numero di docenti --------
dmm_sc <- ird_df |>
  mutate(rk_ird = rank(desc(IRD1_2), ties.method = "first"),
         rk_r12 = rank(desc(R1_2),   ties.method = "first")) |>
  filter(is_dmm)

# Annotation anchor (text box lower-right of DMM point, arrow to point)
ann_x_sc <- 195; ann_y_sc <- 0.082
ann_lbl_sc <- paste0(
  "DMM  (R1_2=", it_num(dmm_sc$R1_2), " \u00b7 ",
  dmm_sc$rk_r12, "\u00b0 per qualit\u00e0,\n",
  dmm_sc$rk_ird, "\u00b0 per IRD su 32)"
)

p_sc <- ggplot(ird_df, aes(n_attesi, IRD1_2)) +
  geom_smooth(method = "lm", se = FALSE,
              linetype = "dashed", color = "#AAAAAA", linewidth = 0.8) +
  annotate("text", x = 130, y = 0.248,
           label = "Tendenza (IRD cresce con la dimensione)",
           hjust = 0, size = 2.8, color = "gray50", fontface = "italic") +
  geom_point(aes(fill = R1_2), shape = 21, size = 4, color = "white") +
  geom_point(data = filter(ird_df, is_dmm),
             shape = 21, size = 6, color = "#9B0014", fill = NA, stroke = 1.5) +
  # Arrow from text anchor to DMM point
  annotate("segment",
           x = ann_x_sc, xend = dmm_sc$n_attesi + 3,
           y = ann_y_sc + 0.003, yend = dmm_sc$IRD1_2 - 0.002,
           color = "#9B0014", linewidth = 0.6,
           arrow = arrow(length = unit(5, "pt"), type = "closed")) +
  # DMM annotation label box
  annotate("label",
           x = ann_x_sc, y = ann_y_sc,
           label = ann_lbl_sc,
           color = "#9B0014", fill = "white",
           label.color = "#9B0014", label.size = 0.4,
           size = 2.8, hjust = 0, vjust = 1, lineheight = 1.1) +
  # Labels for key departments
  ggrepel::geom_text_repel(
    data = filter(ird_df, sigla %in% c("DFA", "DII", "DSB", "DiBio", "BCA")),
    aes(label = sigla), size = 2.8, color = INK,
    nudge_y = 0.005, segment.color = "gray60", segment.size = 0.3,
    min.segment.length = 0.2, box.padding = 0.3, point.padding = 0.2,
    seed = 42
  ) +
  scale_fill_gradientn(
    colors = c("#B2182B","#F4A582","#FFFFBF","#A6D96A","#1A9850"),
    values = scales::rescale(c(0.90, 0.97, 1.00, 1.08, 1.20)),
    name = "R1_2 (qualit\u00e0)",
    breaks = c(0.95, 1.00, 1.05, 1.10, 1.15),
    limits = c(0.90, 1.20)
  ) +
  labs(
    title   = "Perch\u00e9 l'IRD dipende dalla dimensione (numero di docenti)",
    x       = "Dimensione del dipartimento \u2014 n. prodotti attesi (\u2248 numero di docenti)",
    y       = "IRD1_2 (indicatore pesato)",
    caption = "Fonte: ANVUR, VQR 2020\u20132024 \u2014 Risultati delle singole istituzioni: Universit\u00e0 degli Studi di Padova (28 maggio 2026), Tabella 2.4 (indicatori H, R, IRD per dipartimento, sommati sulle aree)."
  ) +
  theme_minimal(base_size = 11) +
  theme(
    plot.title        = element_text(color = "#9B0014", face = "bold", size = 13),
    plot.caption      = element_text(size = 6.5, color = "gray40"),
    legend.key.height = unit(1.6, "cm")
  )
ggsave(file.path(OUT_DIR, "ird_scatter_R.png"), p_sc, width = 9.2, height = 5.6, dpi = 200)

## (D) Posizione del DMM su R1, R2, R1_2 (32 dip.): DMM rosso, altri grigio --
# Ranks for panel subtitles (ties.method = "first" matches ANVUR ordering)
dmm_vals_rank <- ird_df |>
  mutate(across(c(R1, R2, R1_2),
                \(x) rank(desc(x), ties.method = "first"), .names = "rk_{.col}")) |>
  filter(is_dmm) |>
  select(R1, R2, R1_2, rk_R1, rk_R2, rk_R1_2)

panel_labels_rank <- c(
  R1   = paste0("R1 — personale a tempo indeterminato\nDMM: ",
                it_num(dmm_vals_rank$R1),   " — ", dmm_vals_rank$rk_R1,   "° su 32"),
  R2   = paste0("R2 — neo-assunti/avanzamenti\nDMM: ",
                it_num(dmm_vals_rank$R2),   " — ", dmm_vals_rank$rk_R2,   "° su 32"),
  R1_2 = paste0("R1_2 — tutto il personale\nDMM: ",
                it_num(dmm_vals_rank$R1_2), " — ", dmm_vals_rank$rk_R1_2, "° su 32")
)

# One sub-plot per indicator; combined with patchwork so each has its own axis
make_rank_panel <- function(col, color, strip_title) {
  d <- ird_df |>
    transmute(R = .data[[col]], is_dmm,
              lbl_fct = fct_reorder(sigla, R),
              fill    = ifelse(is_dmm, color, "#B0B0B0"))
  ggplot(d, aes(x = R, y = lbl_fct, fill = fill)) +
    geom_col(width = 0.78) +
    # Custom y-labels: DMM in red bold via color/fontface aesthetics
    geom_text(
      aes(x = -0.04, y = lbl_fct, label = as.character(lbl_fct),
          color = is_dmm, fontface = ifelse(is_dmm, "bold", "plain")),
      hjust = 1, size = 2.2) +
    geom_text(aes(label = it_num(R)), hjust = -0.08, size = 2.0, color = INK) +
    geom_vline(xintercept = 1, linetype = "dashed", color = REF_LINE, linewidth = 0.3) +
    scale_fill_identity() +
    scale_color_manual(values = c("FALSE" = "gray30", "TRUE" = "#9B0014"), guide = "none") +
    scale_x_continuous(breaks = seq(0, 1.4, 0.2), limits = c(-0.05, 1.52),
                       labels = function(x) ifelse(x < 0, "", it_num(x)),
                       expand = expansion(mult = c(0, 0.02))) +
    coord_cartesian(clip = "off") +
    labs(title = strip_title, x = NULL, y = NULL) +
    theme_minimal(base_size = 9.5) +
    theme(plot.title = element_text(color = "#9B0014", face = "bold",
                                    size = 8.5, lineheight = 1.2),
          axis.text.y = element_blank(), axis.ticks.y = element_blank(),
          panel.grid.major.y = element_blank(), panel.grid.minor = element_blank(),
          plot.margin = margin(t = 4, r = 8, b = 4, l = 55))
}

p_rank <- (
  make_rank_panel("R1",   unname(RED["R1"]),   panel_labels_rank["R1"])   |
  make_rank_panel("R2",   unname(RED["R2"]),   panel_labels_rank["R2"])   |
  make_rank_panel("R1_2", unname(RED["R1_2"]), panel_labels_rank["R1_2"])
) + patchwork::plot_annotation(
  title   = "Posizione del DMM tra i dipartimenti di Padova — R1, R2, R1_2",
  caption = "Valori R complessivi di ateneo (Tabella 2.4, sommati sulle aree)  ·  linea = media nazionale R=1,0  ·  DMM evidenziato in rosso",
  theme   = theme(plot.title   = element_text(color = "#9B0014", face = "bold", size = 13),
                  plot.caption = element_text(size = 7, color = "gray40"))
)
ggsave(file.path(OUT_DIR, "rank_R1_R2_R12_R.png"), p_rank, width = 14, height = 7.5, dpi = 200)

# ------------------------------------------------------------------ #
# 5. (Opzionale) export in PowerPoint con officer
# ------------------------------------------------------------------ #
# library(officer)
# doc <- read_pptx()  # oppure read_pptx("TemplatePPT_Dipartimento_Medicina_molecolare.pptx")
# add_fig <- function(doc, png, titolo) {
#   doc <- add_slide(doc, layout = "Title and Content", master = "Office Theme")
#   doc <- ph_with(doc, titolo, location = ph_location_type("title"))
#   ph_with(doc, external_img(png, width = 11, height = 5.3),
#           location = ph_location(left = 1, top = 1.6))
# }
# for (f in c("area05_R.png","area06_R.png","rank_R1_R2_R12_R.png",
#             "ird_rank_R.png","ird_scatter_R.png"))
#   doc <- add_fig(doc, file.path(OUT_DIR, f), tools::file_path_sans_ext(basename(f)))
# print(doc, target = "DMM_VQR_R.pptx")

message("Fatto. Figure salvate in: ", normalizePath(OUT_DIR))
