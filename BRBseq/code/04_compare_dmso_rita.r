#!/usr/bin/env Rscript

# ============================================================
# Block D: are the peptide tiles "wired" to affect certain pathways,
# or do they only affect them when RITA is administered?
#
# For each tile we already have (vs the N1 vector control):
#   RITA:  Reactome_DE_RITA__<tile>_vs_N1.tsv   (peptide effect under RITA)
#   DMSO:  Reactome_DE_DMSO__<tile>_vs_N1.tsv   (peptide effect at baseline)
#
# This script joins the two enrichment results per tile on pathway and
# classifies each pathway as:
#   shared        - significant in both, same direction (wired / RITA-independent)
#   RITA_specific - significant only under RITA           (RITA-dependent)
#   DMSO_specific - significant only at baseline
#   opposite      - significant in both, opposite direction
# It also reports the correlation of NES between conditions (overall wiring).
# ============================================================

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
})

gsea_dir <- "../results/gsea/reactome"
out_dir  <- "../results/gsea/dmso_vs_rita"
dir.create(file.path(out_dir, "tables"), showWarnings = FALSE, recursive = TRUE)
dir.create(file.path(out_dir, "plots"),  showWarnings = FALSE, recursive = TRUE)

padj_sig <- 0.05   # pathway significance threshold

# Discover tiles from the RITA peptide-vs-vector GSEA outputs.
# Note: 01_run_deseq2.r's safe_name() collapses "__" to "_", so the on-disk
# names are Reactome_DE_RITA_<tile>_vs_N1.tsv (single underscore).
rita_files <- list.files(
  gsea_dir,
  pattern = "^Reactome_DE_RITA_.*_vs_N1\\.tsv$",
  full.names = FALSE
)
tiles <- sub("^Reactome_DE_RITA_(.*)_vs_N1\\.tsv$", "\\1", rita_files)
tiles <- setdiff(tiles, "WT")  # WT vs N1 is the vector effect, not a peptide

if (length(tiles) == 0) {
  stop("No 'Reactome_DE_RITA__*_vs_N1.tsv' files found in ", gsea_dir,
       ". Run 03_gsea.r first.")
}

read_gsea <- function(path) {
  if (!file.exists(path)) return(NULL)
  dt <- fread(path)
  if (!all(c("pathway", "NES", "padj") %in% colnames(dt))) return(NULL)
  dt[, .(pathway, NES, padj)]
}

all_summaries <- list()

for (tile in tiles) {
  rita_path <- file.path(gsea_dir, paste0("Reactome_DE_RITA_", tile, "_vs_N1.tsv"))
  dmso_path <- file.path(gsea_dir, paste0("Reactome_DE_DMSO_", tile, "_vs_N1.tsv"))

  rita <- read_gsea(rita_path)
  dmso <- read_gsea(dmso_path)
  if (is.null(rita) || is.null(dmso)) {
    message("[WARN] Missing RITA or DMSO enrichment for ", tile, "; skipping.")
    next
  }

  setnames(rita, c("NES", "padj"), c("NES_RITA", "padj_RITA"))
  setnames(dmso, c("NES", "padj"), c("NES_DMSO", "padj_DMSO"))

  m <- merge(rita, dmso, by = "pathway", all = TRUE)
  m[, sig_RITA := !is.na(padj_RITA) & padj_RITA < padj_sig]
  m[, sig_DMSO := !is.na(padj_DMSO) & padj_DMSO < padj_sig]
  m[, same_dir := !is.na(NES_RITA) & !is.na(NES_DMSO) &
        sign(NES_RITA) == sign(NES_DMSO)]

  m[, category := fcase(
    sig_RITA & sig_DMSO &  same_dir, "shared",
    sig_RITA & sig_DMSO & !same_dir, "opposite",
    sig_RITA & !sig_DMSO,            "RITA_specific",
    !sig_RITA & sig_DMSO,            "DMSO_specific",
    default = "ns_both"
  )]

  setorder(m, padj_RITA, padj_DMSO)
  fwrite(m, file.path(out_dir, "tables", paste0("compare_", tile, ".tsv")), sep = "\t")

  # NES scatter: shared pathways lie on the diagonal (wired);
  # points hugging an axis are condition-specific.
  plot_dt <- m[!is.na(NES_RITA) & !is.na(NES_DMSO)]
  if (nrow(plot_dt) > 0) {
    p <- ggplot(plot_dt, aes(x = NES_DMSO, y = NES_RITA, color = category)) +
      geom_hline(yintercept = 0, linewidth = 0.3, color = "grey70") +
      geom_vline(xintercept = 0, linewidth = 0.3, color = "grey70") +
      geom_abline(slope = 1, intercept = 0, linetype = "dashed", linewidth = 0.3) +
      geom_point(size = 1.6, alpha = 0.8) +
      labs(
        title = paste0(tile, " vs vector: pathway NES, DMSO vs RITA"),
        x = "NES (DMSO: tile vs vector)",
        y = "NES (RITA: tile vs vector)"
      ) +
      theme_classic(base_size = 12)
    ggsave(file.path(out_dir, "plots", paste0("NES_scatter_", tile, ".pdf")),
           p, width = 6.5, height = 5, dpi = 300)
  }

  # Overall wiring: NES correlation across pathways shared by both runs
  cor_dt <- m[!is.na(NES_RITA) & !is.na(NES_DMSO)]
  nes_cor <- if (nrow(cor_dt) >= 3) {
    suppressWarnings(cor(cor_dt$NES_RITA, cor_dt$NES_DMSO, method = "spearman"))
  } else NA_real_

  all_summaries[[tile]] <- data.table(
    tile          = tile,
    n_pathways    = nrow(m),
    n_sig_RITA    = m[sig_RITA == TRUE, .N],
    n_sig_DMSO    = m[sig_DMSO == TRUE, .N],
    n_shared      = m[category == "shared", .N],
    n_RITA_specific = m[category == "RITA_specific", .N],
    n_DMSO_specific = m[category == "DMSO_specific", .N],
    n_opposite    = m[category == "opposite", .N],
    nes_spearman  = nes_cor
  )
}

if (length(all_summaries) > 0) {
  summary_dt <- rbindlist(all_summaries, fill = TRUE)
  setorder(summary_dt, -n_shared)
  fwrite(summary_dt, file.path(out_dir, "tile_wiring_summary.tsv"), sep = "\t")
  message("Wrote per-tile comparison tables and ",
          file.path(out_dir, "tile_wiring_summary.tsv"))
  print(summary_dt)
} else {
  message("No tiles compared.")
}
