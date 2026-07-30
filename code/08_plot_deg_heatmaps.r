#!/usr/bin/env Rscript

# ============================================================
# Gene-level DEG heatmaps of the peptide effect (tile vs N1 vector control).
#
# For each condition (RITA, DMSO):
#   1) call DEGs per peptide  (padj < 0.25 & |log2FC| >= 0.5, the project's
#      standard "significant" definition, matching 01_run_deseq2.r),
#   2) keep peptides with at least MIN_DEG DEGs,
#   3) take the union of those peptides' DEGs as the rows,
#   4) draw a heatmap whose cells are the tile-vs-N1 log2 fold changes, with
#      "*" marking the cells that are themselves significant.
#
# Complements the pathway-level (NES) block heatmaps in 07_publication_figs.r:
# this one is gene-level. Non-destructive; writes under parallel <style>
# subfolders so the figures from 05/06/07 are left untouched.
#
# Output: results/deseq2/<style>/deg_heatmaps/DEG_heatmap_<COND>.pdf
#         results/deseq2/<style>/deg_heatmaps/DEG_heatmap_<COND>_genes.tsv
# ============================================================

suppressPackageStartupMessages({
  library(data.table)
  library(pheatmap)
  library(grid)
})

# ---- DEG definition ----
# padj < 0.05 (stricter than the 0.25 used elsewhere in the project for the
# "significant" summary column) & |log2FC| >= 0.5.
padj_cutoff <- 0.05
lfc_cutoff  <- 0.5
MIN_DEG     <- 20          # a peptide is shown only if it has >= MIN_DEG DEGs

tables_dir <- "../results/deseq2/tables"

# Base pdf() (not cairo_pdf) keeps text labels as single editable strings in
# Illustrator; Helvetica is a base-14 PDF font so nothing needs embedding.
# Keep all on-canvas text ASCII.
PDF_DEV   <- "pdf"
BASE_FONT <- "Helvetica"

# Tile column order to match the rest of the project's figures.
prefer_order <- function(cols) {
  pref <- c("WT", "N1", "T1", "T4", "T5", "T6", "T7", "T9", "T10", "A2", "B6")
  c(intersect(pref, cols), setdiff(cols, pref))
}

# Per-style sizing. label_max: above this many genes we drop row labels and the
# per-cell "*" (they become unreadable); the heatmap then fills a fixed canvas.
styles <- list(
  plots = list(
    base = 8, heat_cell = 9, heat_fs = 7, heat_fs_row = 5.5, heat_fs_col = 8,
    heat_num = 6, heat_tree_c = 14, heat_tree_r = 18,
    label_max = 60, big_h = 9.0, big_w_extra = 1.6
  ),
  poster = list(
    base = 18, heat_cell = 20, heat_fs = 14, heat_fs_row = 11, heat_fs_col = 16,
    heat_num = 13, heat_tree_c = 20, heat_tree_r = 26,
    label_max = 45, big_h = 14.0, big_w_extra = 2.6
  )
)

# ------------------------------------------------------------------
# Build the log2FC + significance-star matrices for one condition.
# Returns NULL if fewer than 2 peptides clear the MIN_DEG bar.
# ------------------------------------------------------------------
build_condition <- function(cond) {
  pat   <- sprintf("^DE_%s_(.*)_vs_N1\\.tsv$", cond)
  files <- list.files(tables_dir, pattern = pat, full.names = TRUE)
  if (length(files) == 0) return(NULL)
  labs  <- sub(pat, "\\1", basename(files))
  # WT vs N1 measures the vector effect, not a peptide tile -- exclude it.
  keep  <- labs != "WT"
  files <- files[keep]; labs <- labs[keep]
  if (length(files) == 0) return(NULL)

  lfc_list  <- list()   # named log2FC vectors per peptide
  padj_list <- list()
  deg_sets  <- list()   # DEG gene_ids per peptide
  name_map  <- character(0)   # gene_id -> gene_name (for small heatmaps)
  for (i in seq_along(files)) {
    dt <- fread(files[i])
    if (!all(c("gene_id", "log2FoldChange", "padj") %in% colnames(dt))) next
    lab <- labs[i]
    lfc_list[[lab]]  <- setNames(dt$log2FoldChange, dt$gene_id)
    padj_list[[lab]] <- setNames(dt$padj,           dt$gene_id)
    is_deg <- !is.na(dt$padj) & dt$padj < padj_cutoff &
              abs(dt$log2FoldChange) >= lfc_cutoff
    deg_sets[[lab]] <- dt$gene_id[is_deg]
    if ("gene_name" %in% colnames(dt)) {
      nm <- dt$gene_name; names(nm) <- dt$gene_id
      nm <- nm[!is.na(nm) & nm != ""]
      name_map[names(nm)] <- nm
    }
  }

  n_deg <- vapply(deg_sets, length, integer(1))
  sel   <- names(n_deg)[n_deg >= MIN_DEG]
  if (length(sel) < 2) {
    message("  ", cond, ": only ", length(sel),
            " peptide(s) with >= ", MIN_DEG, " DEGs -- skipping heatmap.")
    return(NULL)
  }
  sel <- sel[order(match(sel, prefer_order(sel)))]

  genes <- sort(unique(unlist(deg_sets[sel])))      # union of the DEGs
  lfc_mat  <- sapply(sel, function(p) lfc_list[[p]][genes])
  padj_mat <- sapply(sel, function(p) padj_list[[p]][genes])
  lfc_mat  <- matrix(lfc_mat,  nrow = length(genes), dimnames = list(genes, sel))
  padj_mat <- matrix(padj_mat, nrow = length(genes), dimnames = list(genes, sel))

  list(lfc = lfc_mat, padj = padj_mat, genes = genes,
       name_map = name_map, sel = sel, n_deg = n_deg[sel])
}

# ------------------------------------------------------------------
draw_heatmap <- function(cond, dat, style_name, cfg, out_dir) {
  lfc_mat  <- dat$lfc
  padj_mat <- dat$padj
  n <- nrow(lfc_mat); m <- ncol(lfc_mat)

  # Significance stars (only legible on the small heatmaps).
  star <- ifelse(!is.na(padj_mat) & padj_mat < padj_cutoff &
                 abs(lfc_mat) >= lfc_cutoff, "*", "")

  # Symmetric, outlier-robust color limit; clamp display values into range so
  # a few extreme fold changes don't wash out the rest.
  finite <- abs(lfc_mat[is.finite(lfc_mat)])
  lim <- max(as.numeric(stats::quantile(finite, 0.98, na.rm = TRUE)), 1)
  disp <- lfc_mat
  disp[is.finite(disp) & disp >  lim] <-  lim
  disp[is.finite(disp) & disp < -lim] <- -lim
  breaks <- seq(-lim, lim, length.out = 101)
  pal <- colorRampPalette(c("#2166AC", "white", "#B2182B"))(100)

  # Cluster on a NA->0 copy (NA = gene absent from that peptide's results).
  cl <- disp; cl[is.na(cl)] <- 0
  col_hc <- if (m > 2) hclust(dist(t(cl))) else FALSE
  row_hc <- if (n > 2) hclust(dist(cl))    else FALSE

  small   <- n <= cfg$label_max
  rownm   <- if (small) {
    nm <- dat$name_map[rownames(disp)]
    ifelse(!is.na(nm) & nm != "", nm, rownames(disp))
  } else FALSE
  out_pdf <- file.path(out_dir, paste0("DEG_heatmap_", cond, ".pdf"))
  main <- sprintf("%s: peptide (tile vs N1) log2FC -- %d DEGs across %d peptides",
                  cond, n, m)

  common <- list(
    mat = disp, color = pal, breaks = breaks,
    cluster_cols = col_hc, cluster_rows = row_hc,
    na_col = "grey90", border_color = NA,
    fontsize = cfg$heat_fs, fontsize_col = cfg$heat_fs_col,
    angle_col = 0, main = main,
    treeheight_row = cfg$heat_tree_r, treeheight_col = cfg$heat_tree_c,
    filename = out_pdf
  )

  if (small) {
    # Fixed square-ish cells; let pheatmap auto-size the canvas so long gene
    # names always fit (matches the 07 block-heatmap behaviour).
    do.call(pheatmap, c(common, list(
      cellwidth = 2 * cfg$heat_cell, cellheight = cfg$heat_cell,
      show_rownames = TRUE, labels_row = rownm, fontsize_row = cfg$heat_fs_row,
      display_numbers = star, number_color = "black",
      fontsize_number = cfg$heat_num,
      main = paste0(main, "  (* padj<", padj_cutoff, ")")
    )))
  } else {
    # Too many genes to label: fixed columns, rows fill a fixed-height canvas.
    # Widen the canvas if needed so the (centered) title is never clipped.
    w_content <- 2 * cfg$heat_cell * m / 72 + cfg$big_w_extra
    w_title   <- 0.085 * nchar(main) * cfg$base / 8
    w <- max(w_content, w_title)
    do.call(pheatmap, c(common, list(
      cellwidth = 2 * cfg$heat_cell, cellheight = NA,
      show_rownames = FALSE, display_numbers = FALSE,
      width = w, height = cfg$big_h
    )))
  }
  message("    -> ", out_pdf, "  (", n, " genes x ", m, " peptides)")

  # Companion gene table (gene_id, gene_name, per-peptide log2FC & padj).
  gt <- data.table(gene_id = rownames(lfc_mat),
                   gene_name = dat$name_map[rownames(lfc_mat)])
  for (p in colnames(lfc_mat)) {
    gt[[paste0("log2FC_", p)]] <- lfc_mat[, p]
    gt[[paste0("padj_",   p)]] <- padj_mat[, p]
  }
  fwrite(gt, file.path(out_dir, paste0("DEG_heatmap_", cond, "_genes.tsv")),
         sep = "\t")
}

# ==================================================================
conditions <- c("RITA", "DMSO")
built <- lapply(conditions, build_condition)
names(built) <- conditions

for (style_name in names(styles)) {
  cfg <- styles[[style_name]]
  message("\n===== style: ", style_name, " =====")
  out_dir <- file.path("../results/deseq2", style_name, "deg_heatmaps")
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  for (cond in conditions) {
    dat <- built[[cond]]
    if (is.null(dat)) next
    message("  ", cond, ": peptides >= ", MIN_DEG, " DEGs = ",
            paste(sprintf("%s(%d)", names(dat$n_deg), dat$n_deg), collapse = ", "))
    draw_heatmap(cond, dat, style_name, cfg, out_dir)
  }
}
message("\nDone.")
