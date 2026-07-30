#!/usr/bin/env Rscript

# ============================================================
# Regenerate volcano plots from existing DESeq2 DE tables
# (results/deseq2/tables/DE_*.tsv) without rerunning DESeq2.
#
# Colour scheme: significantly depleted (down) = blue,
# significantly enriched (up) = red, everything else = grey.
# Kept consistent with make_volcano() in 01_run_deseq2.r.
# ============================================================

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(ggrepel)
  library(ggrastr)
})

tables_dir <- "../results/deseq2/tables"
draft_dir  <- "../results/deseq2/draft"
dir.create(draft_dir, showWarnings = FALSE, recursive = TRUE)

padj_cutoff <- 0.25
lfc_cutoff  <- 0.5

pal <- c("Depleted (down)" = "#2166AC",
         "Not significant" = "grey75",
         "Enriched (up)"   = "#B2182B")

de_files <- list.files(tables_dir, pattern = "^DE_.*\\.tsv$", full.names = TRUE)
if (length(de_files) == 0) stop("No DE_*.tsv files in ", tables_dir, ". Run 01_run_deseq2.r first.")

for (f in de_files) {
  comp <- sub("^DE_", "", tools::file_path_sans_ext(basename(f)))
  res <- fread(f)

  if (!all(c("log2FoldChange", "padj") %in% colnames(res)) ||
      nrow(res[!is.na(padj)]) == 0) {
    message("[skip] no usable results: ", comp)
    next
  }

  plot_dt <- copy(res)
  plot_dt[, neg_log10_padj := -log10(padj)]
  plot_dt[is.na(neg_log10_padj) | is.infinite(neg_log10_padj), neg_log10_padj := NA_real_]
  plot_dt[, significant := !is.na(padj) & padj < padj_cutoff & abs(log2FoldChange) >= lfc_cutoff]
  plot_dt[, direction := fcase(
    significant & log2FoldChange > 0, "Enriched (up)",
    significant & log2FoldChange < 0, "Depleted (down)",
    default = "Not significant"
  )]
  plot_dt[, direction := factor(direction,
    levels = c("Depleted (down)", "Not significant", "Enriched (up)"))]

  label_dt <- plot_dt[significant == TRUE][order(padj)][1:min(.N, 15)]
  if ("gene_name" %in% colnames(label_dt)) {
    label_dt[, label := fifelse(!is.na(gene_name) & gene_name != "", gene_name, as.character(gene_id))]
  } else {
    label_dt[, label := as.character(gene_id)]
  }

  n_up   <- plot_dt[direction == "Enriched (up)", .N]
  n_down <- plot_dt[direction == "Depleted (down)", .N]

  p <- ggplot(plot_dt, aes(x = log2FoldChange, y = neg_log10_padj)) +
    # Rasterise only the point cloud (thousands of genes) so Illustrator opens
    # the PDF quickly; axes, dashed lines, gene labels and legend stay vector.
    ggrastr::rasterise(
      geom_point(aes(color = direction), size = 1.2, alpha = 0.8),
      dpi = 300) +
    scale_color_manual(values = pal, name = NULL, drop = FALSE) +
    geom_vline(xintercept = c(-lfc_cutoff, lfc_cutoff), linetype = "dashed", linewidth = 0.3) +
    geom_hline(yintercept = -log10(padj_cutoff), linetype = "dashed", linewidth = 0.3) +
    ggrepel::geom_text_repel(data = label_dt, aes(label = label),
                             size = 3, max.overlaps = Inf) +
    labs(
      title = comp,
      subtitle = paste0(n_down, " down / ", n_up, " up  (padj < ", padj_cutoff,
                        ", |log2FC| >= ", lfc_cutoff, ")"),
      x = "log2 fold change", y = "-log10 adjusted p-value"
    ) +
    theme_classic(base_size = 12) +
    theme(legend.position = "top")

  ggsave(file.path(draft_dir, paste0("volcano_", comp, ".pdf")), p,
         width = 6, height = 5, dpi = 300)
}

message("Volcano plots written to ", draft_dir)
