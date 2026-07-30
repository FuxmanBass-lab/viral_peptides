#!/usr/bin/env Rscript

# ============================================================
# Styled, ready-to-use versions of the key figures, in two flavours:
#   publication/ : compact, small print fonts (for a paper)
#   poster/      : small data panels with large fonts (for a poster, read
#                  from a distance) -- bigger points, fewer/larger labels.
# Non-destructive: writes under parallel subfolders of each results dir; the
# working figures from 05/06 are left untouched.
#
# For each style:
#   1) GSEA dotplots   -> results/gsea/reactome/<style>/dotplots/<comp>.pdf
#   2) Block heatmaps  -> results/gsea/reactome/<style>/heatmaps/<block>.pdf
#   3) Volcano plots   -> results/deseq2/<style>/volcanoes/<comp>.pdf
# ============================================================

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(ggrepel)
  library(ggrastr)
  library(pheatmap)
  library(grid)
  library(stringr)
})

# Use the base pdf() device (NOT cairo_pdf): it writes each text label as a
# single string, so Illustrator imports words/sentences as one editable text
# box instead of fragmenting them glyph-by-glyph. Helvetica is a standard
# base-14 PDF font, so no embedding is needed and it stays fully editable.
# Keep all on-canvas text ASCII (base pdf can't encode glyphs like >= or ...).
PDF_DEV   <- "pdf"
BASE_FONT <- "Helvetica"

# Compact theme; legend keys scale with the base font so poster legends grow too.
theme_pub <- function(base = 8) {
  theme_classic(base_size = base, base_family = BASE_FONT) +
    theme(
      plot.title    = element_text(face = "bold", size = base),
      plot.subtitle = element_text(size = base - 1, color = "grey30"),
      axis.text     = element_text(size = base - 1, color = "black"),
      axis.line     = element_line(linewidth = 0.3 * base / 8),
      axis.ticks    = element_line(linewidth = 0.3 * base / 8),
      legend.key.size = unit(0.04 * base, "cm"),
      legend.title  = element_text(size = base - 1),
      legend.text   = element_text(size = base - 2),
      legend.margin = margin(0, 0, 0, 0),
      plot.margin   = margin(4, 4, 4, 4)
    )
}

pretty_comp <- function(x) gsub("_", " ", x)
pretty_path <- function(x, wrap = 36) {
  x <- sub("^REACTOME_", "", x)
  x <- gsub("_", " ", tolower(x))
  substr(x, 1, 1) <- toupper(substr(x, 1, 1))
  str_wrap(x, width = wrap)
}
read_gsea <- function(path) {
  if (!file.exists(path)) return(NULL)
  dt <- fread(path)
  if (!all(c("pathway", "NES", "padj") %in% colnames(dt))) return(NULL)
  if (!"size" %in% colnames(dt)) dt[, size := NA_integer_]
  dt[, .(pathway, NES, padj, size)]
}

gsea_dir    <- "../results/gsea/reactome"
tables_dir  <- "../results/deseq2/tables"
padj_cutoff <- 0.05
v_padj <- 0.25; v_lfc <- 0.5
pal_v <- c("Depleted (down)" = "#2166AC",
           "Not significant" = "grey78",
           "Enriched (up)"   = "#B2182B")

# ------------------------------------------------------------------
# Per-style configuration. Width/height closures keep figures sized to content.
# ------------------------------------------------------------------
styles <- list(
  plots = list(
    base = 8,
    dot_top = 20, dot_wrap = 36, dot_size = c(1.2, 4.5),
    dot_w = function(mc) 2.0 + 0.045 * mc + 1.0,
    dot_h = function(n)  0.9 + 0.205 * n,
    heat_max = 40, heat_cell = 10, heat_fs = 7,
    heat_fs_row = 6.5, heat_fs_col = 8, heat_num = 7,
    heat_tree_c = 14, heat_lab = 2.7, heat_hbase = 1.0,
    volc_w = 3.6, volc_h = 3.5, volc_pt = 0.6, volc_lab_n = 10,
    volc_lab_sz = 2.0, volc_seg = 0.2,
    volc_leg = c("Depleted (down)", "Not significant", "Enriched (up)"),
    volc_short_sub = FALSE
  ),
  poster = list(
    base = 18,
    dot_top = 12, dot_wrap = 28, dot_size = c(3, 11),
    dot_w = function(mc) 3.0 + 0.10 * mc + 2.2,
    dot_h = function(n)  1.8 + 0.46 * n,
    heat_max = 22, heat_cell = 20, heat_fs = 14,
    heat_fs_row = 12.5, heat_fs_col = 16, heat_num = 14,
    heat_tree_c = 20, heat_lab = 4.0, heat_hbase = 1.8,
    volc_w = 4.8, volc_h = 4.6, volc_pt = 1.4, volc_lab_n = 6,
    volc_lab_sz = 5.0, volc_seg = 0.4,
    volc_leg = c("Down", "n.s.", "Up"),
    volc_short_sub = TRUE
  )
)

# ==================================================================
make_figs <- function(style_name, cfg) {
  message("\n===== style: ", style_name, " =====")

  # ---------- 1) DOTPLOTS ----------
  dot_dir <- file.path(gsea_dir, style_name, "dotplots")
  dir.create(dot_dir, showWarnings = FALSE, recursive = TRUE)
  de_files <- list.files(gsea_dir, pattern = "^Reactome_DE_.*\\.tsv$", full.names = TRUE)

  for (f in de_files) {
    comp <- sub("^Reactome_DE_", "", tools::file_path_sans_ext(basename(f)))
    dt <- read_gsea(f); if (is.null(dt)) next
    sig <- dt[!is.na(padj) & padj < padj_cutoff]
    if (nrow(sig) == 0) next
    n_total <- nrow(sig)
    sig <- sig[order(padj)][1:min(.N, cfg$dot_top)]
    sig[, label := pretty_path(pathway, wrap = cfg$dot_wrap)]
    sig[, label := factor(label, levels = label[order(NES)])]

    rng <- range(sig$NES); show_zero <- rng[1] < 0 & rng[2] > 0
    p <- ggplot(sig, aes(NES, label))
    if (show_zero) p <- p + geom_vline(xintercept = 0, color = "grey70", linewidth = 0.3)
    p <- p +
      geom_point(aes(size = size, color = -log10(padj))) +
      scale_color_gradientn(colours = c("#D6F3E2", "#44CC7D", "#13532E"),
                            name = "-log10(padj)") +
      scale_size_continuous(name = "set size", range = cfg$dot_size) +
      scale_x_continuous(expand = expansion(mult = 0.06)) +
      labs(title = pretty_comp(comp),
           subtitle = paste0("top ", nrow(sig), " of ", n_total,
                             " pathways (padj < ", padj_cutoff, ")"),
           x = "NES", y = NULL) +
      theme_pub(cfg$base) +
      guides(size = guide_legend(order = 1), color = guide_colorbar(order = 2))

    max_chars <- max(nchar(unlist(strsplit(as.character(sig$label), "\n"))))
    ggsave(file.path(dot_dir, paste0(comp, ".pdf")), p,
           width = cfg$dot_w(max_chars), height = cfg$dot_h(nrow(sig)),
           device = PDF_DEV, useDingbats = FALSE, limitsize = FALSE)
  }
  message("dotplots -> ", dot_dir)

  # ---------- 2) BLOCK HEATMAPS ----------
  heat_dir <- file.path(gsea_dir, style_name, "heatmaps")
  dir.create(heat_dir, showWarnings = FALSE, recursive = TRUE)

  prefer_order <- function(cols) {
    pref <- c("WT", "N1", "T1", "T4", "T5", "T6", "T7", "T9", "T10", "A2", "B6")
    c(intersect(pref, cols), setdiff(cols, pref))
  }
  build_block <- function(pattern, capture, exclude = character(0)) {
    files <- list.files(gsea_dir, pattern = pattern, full.names = TRUE)
    if (length(files) == 0) return(NULL)
    labs <- sub(pattern, capture, basename(files))
    keep <- !(labs %in% exclude); files <- files[keep]; labs <- labs[keep]
    if (length(files) == 0) return(NULL)
    ord <- order(match(labs, prefer_order(labs)))
    setNames(files[ord], labs[ord])
  }
  blocks <- list(
    A_RITA_signature  = build_block("^Reactome_DE_(.*)_RITA_vs_DMSO\\.tsv$", "\\1"),
    B_peptide_in_RITA = build_block("^Reactome_DE_RITA_(.*)_vs_N1\\.tsv$",    "\\1", exclude = "WT"),
    C_peptide_in_DMSO = build_block("^Reactome_DE_DMSO_(.*)_vs_N1\\.tsv$",    "\\1", exclude = "WT")
  )
  block_titles <- c(
    A_RITA_signature  = "RITA vs DMSO (per group)",
    B_peptide_in_RITA = "Tile vs vector under RITA",
    C_peptide_in_DMSO = "Tile vs vector under DMSO"
  )

  for (bn in names(blocks)) {
    bl <- blocks[[bn]]
    if (is.null(bl) || length(bl) < 2) next
    nes_list <- list(); padj_list <- list()
    for (lab in names(bl)) {
      dt <- read_gsea(bl[[lab]]); if (is.null(dt)) next
      nes_list[[lab]]  <- setNames(dt$NES,  dt$pathway)
      padj_list[[lab]] <- setNames(dt$padj, dt$pathway)
    }
    all_paths <- sort(unique(unlist(lapply(nes_list, names))))
    nes_mat  <- sapply(nes_list,  function(v) v[all_paths])
    padj_mat <- sapply(padj_list, function(v) v[all_paths])
    rownames(nes_mat) <- all_paths; rownames(padj_mat) <- all_paths

    sig_any <- rowSums(padj_mat < padj_cutoff, na.rm = TRUE) > 0
    nes_mat <- nes_mat[sig_any, , drop = FALSE]; padj_mat <- padj_mat[sig_any, , drop = FALSE]
    if (nrow(nes_mat) == 0) next
    if (nrow(nes_mat) > cfg$heat_max) {
      n_sig   <- rowSums(padj_mat < padj_cutoff, na.rm = TRUE)
      max_abs <- apply(abs(nes_mat), 1, max, na.rm = TRUE)
      keep <- order(n_sig, max_abs, decreasing = TRUE)[1:cfg$heat_max]
      nes_mat <- nes_mat[keep, , drop = FALSE]; padj_mat <- padj_mat[keep, , drop = FALSE]
    }
    rownames(nes_mat) <- sub("^REACTOME_", "", rownames(nes_mat)) |>
      (\(x) { x <- gsub("_", " ", tolower(x)); substr(x,1,1) <- toupper(substr(x,1,1))
              ifelse(nchar(x) > 60, paste0(substr(x,1,57), "..."), x) })()
    star <- ifelse(!is.na(padj_mat) & padj_mat < padj_cutoff, "*", "")
    lim <- max(abs(nes_mat), na.rm = TRUE)
    breaks <- seq(-lim, lim, length.out = 101)
    pal <- colorRampPalette(c("#2166AC", "white", "#B2182B"))(100)
    cl_mat <- nes_mat; cl_mat[is.na(cl_mat)] <- 0
    col_hc <- hclust(dist(t(cl_mat)))
    row_hc <- if (nrow(cl_mat) > 2) hclust(dist(cl_mat)) else FALSE

    # Fixed square cells + no row dendrogram keep it tight; let pheatmap
    # auto-size the canvas (width/height = NA) so the full pathway names
    # always fit and never clip off the page edge.
    pheatmap(
      nes_mat, color = pal, breaks = breaks,
      cluster_cols = col_hc, cluster_rows = row_hc,
      cellwidth = 2 * cfg$heat_cell, cellheight = cfg$heat_cell,   # width = 2x height
      display_numbers = star, number_color = "black", fontsize_number = cfg$heat_num,
      na_col = "grey90",
      main = paste0(block_titles[[bn]], "  (* padj<", padj_cutoff, ")"),
      fontsize = cfg$heat_fs, fontsize_row = cfg$heat_fs_row,
      fontsize_col = cfg$heat_fs_col, angle_col = 0, border_color = NA,
      treeheight_row = 0, treeheight_col = cfg$heat_tree_c,    # no row dendrogram
      filename = file.path(heat_dir, paste0(bn, ".pdf"))
    )
  }
  message("heatmaps -> ", heat_dir)

  # ---------- 3) VOLCANOES ----------
  volc_dir <- file.path("../results/deseq2", style_name, "volcanoes")
  dir.create(volc_dir, showWarnings = FALSE, recursive = TRUE)
  v_files <- list.files(tables_dir, pattern = "^DE_.*\\.tsv$", full.names = TRUE)
  for (f in v_files) {
    comp <- sub("^DE_", "", tools::file_path_sans_ext(basename(f)))
    res <- fread(f)
    if (!all(c("log2FoldChange", "padj") %in% colnames(res)) ||
        nrow(res[!is.na(padj)]) == 0) next
    d <- copy(res)
    d[, neg_log10_padj := -log10(padj)]
    d[is.na(neg_log10_padj) | is.infinite(neg_log10_padj), neg_log10_padj := NA_real_]
    d[, significant := !is.na(padj) & padj < v_padj & abs(log2FoldChange) >= v_lfc]
    d[, direction := fcase(
      significant & log2FoldChange > 0, "Enriched (up)",
      significant & log2FoldChange < 0, "Depleted (down)",
      default = "Not significant")]
    d[, direction := factor(direction,
      levels = c("Depleted (down)", "Not significant", "Enriched (up)"))]
    lab <- d[significant == TRUE][order(padj)][1:min(.N, cfg$volc_lab_n)]
    if ("gene_name" %in% colnames(lab))
      lab[, label := fifelse(!is.na(gene_name) & gene_name != "", gene_name, as.character(gene_id))]
    else lab[, label := as.character(gene_id)]
    n_up <- d[direction == "Enriched (up)", .N]; n_dn <- d[direction == "Depleted (down)", .N]

    flfc <- d[!is.na(padj) & is.finite(log2FoldChange), abs(log2FoldChange)]
    xlim_v <- max(stats::quantile(flfc, 0.995, na.rm = TRUE),
                  abs(lab$log2FoldChange), v_lfc * 2, na.rm = TRUE)
    xlim_v <- ceiling(xlim_v * 2) / 2

    p <- ggplot(d, aes(log2FoldChange, neg_log10_padj)) +
      # Rasterise only the point cloud (thousands of genes) so Illustrator opens
      # the PDF quickly; axes, dashed lines, gene labels and legend stay vector.
      ggrastr::rasterise(
        geom_point(aes(color = direction), size = cfg$volc_pt, alpha = 0.7, stroke = 0),
        dpi = 300) +
      scale_color_manual(values = pal_v, labels = cfg$volc_leg, name = NULL, drop = FALSE) +
      geom_vline(xintercept = c(-v_lfc, v_lfc), linetype = "dashed", linewidth = 0.25, color = "grey50") +
      geom_hline(yintercept = -log10(v_padj), linetype = "dashed", linewidth = 0.25, color = "grey50") +
      ggrepel::geom_text_repel(data = lab, aes(label = label), size = cfg$volc_lab_sz,
                               max.overlaps = Inf, segment.size = cfg$volc_seg, min.segment.length = 0) +
      coord_cartesian(xlim = c(-xlim_v, xlim_v)) +
      labs(title = pretty_comp(comp),
           subtitle = if (cfg$volc_short_sub) paste0(n_dn, " down / ", n_up, " up")
                      else paste0(n_dn, " down / ", n_up, " up  (padj<", v_padj, ", |log2FC|>=", v_lfc, ")"),
           x = "log2 fold change", y = "-log10 adj. p") +
      theme_pub(cfg$base) +
      theme(legend.position = "top", legend.box.spacing = unit(2, "pt"))
    ggsave(file.path(volc_dir, paste0("volcano_", comp, ".pdf")), p,
           width = cfg$volc_w, height = cfg$volc_h, device = PDF_DEV, useDingbats = FALSE)
  }
  message("volcanoes -> ", volc_dir)
}

for (sn in names(styles)) make_figs(sn, styles[[sn]])
message("\nDone.")
