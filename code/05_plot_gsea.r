#!/usr/bin/env Rscript

# ============================================================
# Plots for the Reactome fgsea results (output of 03_gsea.r).
#
# Produces:
#   1) Per-comparison dotplots of the top enriched pathways
#      -> results/gsea/reactome/plots/dotplots/<comparison>.pdf
#   2) Cross-comparison NES heatmaps, one per analysis block, so tiles
#      can be compared side by side:
#        A_RITA_signature   : RITA vs DMSO, every group
#        B_peptide_in_RITA  : tile vs vector (N1), under RITA
#        C_peptide_in_DMSO  : tile vs vector (N1), under DMSO
#      -> results/gsea/reactome/plots/heatmaps/<block>.pdf
#      Rows = pathways significant (padj<cutoff) in >=1 column; "*" marks
#      the significant cells; colour = NES (blue down / red up).
# ============================================================

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(pheatmap)
  library(grid)
})

gsea_dir  <- "../results/gsea/reactome"
dot_dir   <- file.path(gsea_dir, "draft", "dotplots")
heat_dir  <- file.path(gsea_dir, "draft", "heatmaps")
dir.create(dot_dir,  showWarnings = FALSE, recursive = TRUE)
dir.create(heat_dir, showWarnings = FALSE, recursive = TRUE)

padj_cutoff  <- 0.05
top_n_dot    <- 25   # pathways per dotplot
max_rows_heat <- 60  # cap heatmap rows for readability

# Tidy long REACTOME_ names into readable labels
pretty_path <- function(x, width = 55) {
  x <- sub("^REACTOME_", "", x)
  x <- gsub("_", " ", x)
  x <- tolower(x)
  substr(x, 1, 1) <- toupper(substr(x, 1, 1))
  ifelse(nchar(x) > width, paste0(substr(x, 1, width - 1), "…"), x)
}

read_gsea <- function(path) {
  if (!file.exists(path)) return(NULL)
  dt <- fread(path)
  if (!all(c("pathway", "NES", "padj") %in% colnames(dt))) return(NULL)
  if (!"size" %in% colnames(dt)) dt[, size := NA_integer_]
  dt[, .(pathway, NES, padj, size)]
}

# -------------------- 1) DOTPLOTS --------------------
de_files <- list.files(gsea_dir, pattern = "^Reactome_DE_.*\\.tsv$", full.names = TRUE)

for (f in de_files) {
  comp <- sub("^Reactome_DE_", "", tools::file_path_sans_ext(basename(f)))
  dt <- read_gsea(f)
  if (is.null(dt)) next

  sig <- dt[!is.na(padj) & padj < padj_cutoff]
  if (nrow(sig) == 0) {
    message("[skip dotplot] no significant pathways: ", comp)
    next
  }
  sig <- sig[order(padj)][1:min(.N, top_n_dot)]
  sig[, label := pretty_path(pathway)]
  sig[, label := factor(label, levels = label[order(NES)])]
  sig[, direction := fifelse(NES > 0, "up", "down")]

  p <- ggplot(sig, aes(x = NES, y = label)) +
    geom_vline(xintercept = 0, color = "grey70", linewidth = 0.3) +
    geom_point(aes(size = size, color = -log10(padj))) +
    scale_color_gradient(low = "grey75", high = "firebrick", name = "-log10(padj)") +
    scale_size_continuous(name = "set size", range = c(2, 7)) +
    labs(
      title = comp,
      subtitle = paste0("top ", nrow(sig), " of ",
                        dt[!is.na(padj) & padj < padj_cutoff, .N],
                        " pathways at padj < ", padj_cutoff),
      x = "NES (normalized enrichment score)", y = NULL
    ) +
    theme_classic(base_size = 11) +
    theme(plot.title = element_text(face = "bold", size = 11))

   h <- 1.5 + 0.28 * nrow(sig)
  ggsave(file.path(dot_dir, paste0(comp, ".pdf")), p, width = 9, height = h,
         limitsize = FALSE)
}
message("Dotplots written to ", dot_dir)

# -------------------- 2) HEATMAPS PER BLOCK --------------------
# Each block: a named list mapping column label -> gsea file path.
prefer_order <- function(cols) {
  pref <- c("WT", "N1", "T1", "T4", "T5", "T6", "T7", "T9", "T10", "A2", "B6")
  c(intersect(pref, cols), setdiff(cols, pref))
}

build_block <- function(pattern, capture, exclude = character(0)) {
  files <- list.files(gsea_dir, pattern = pattern, full.names = TRUE)
  if (length(files) == 0) return(NULL)
  labs <- sub(pattern, capture, basename(files))
  keep <- !(labs %in% exclude)
  files <- files[keep]; labs <- labs[keep]
  if (length(files) == 0) return(NULL)
  ord  <- order(match(labs, prefer_order(labs)))
  setNames(files[ord], labs[ord])
}

blocks <- list(
  # WT vs N1 is the vector effect (not a peptide), so it is excluded from the
  # peptide-vs-vector blocks B and C; it remains in block A.
  A_RITA_signature  = build_block("^Reactome_DE_(.*)_RITA_vs_DMSO\\.tsv$", "\\1"),
  B_peptide_in_RITA = build_block("^Reactome_DE_RITA_(.*)_vs_N1\\.tsv$",    "\\1", exclude = "WT"),
  C_peptide_in_DMSO = build_block("^Reactome_DE_DMSO_(.*)_vs_N1\\.tsv$",    "\\1", exclude = "WT")
)

block_titles <- c(
  A_RITA_signature  = "Block A: RITA vs DMSO (RITA signature per group)",
  B_peptide_in_RITA = "Block B: tile vs vector (N1) under RITA",
  C_peptide_in_DMSO = "Block C: tile vs vector (N1) under DMSO"
)

for (bn in names(blocks)) {
  bl <- blocks[[bn]]
  if (is.null(bl) || length(bl) < 2) {
    message("[skip heatmap] not enough columns for block ", bn)
    next
  }

  nes_list  <- list()
  padj_list <- list()
  for (lab in names(bl)) {
    dt <- read_gsea(bl[[lab]])
    if (is.null(dt)) next
    nes_list[[lab]]  <- setNames(dt$NES,  dt$pathway)
    padj_list[[lab]] <- setNames(dt$padj, dt$pathway)
  }
  all_paths <- sort(unique(unlist(lapply(nes_list, names))))

  nes_mat  <- sapply(nes_list,  function(v) v[all_paths])
  padj_mat <- sapply(padj_list, function(v) v[all_paths])
  rownames(nes_mat) <- all_paths
  rownames(padj_mat) <- all_paths

  # Keep pathways significant in >=1 column
  sig_any <- rowSums(padj_mat < padj_cutoff, na.rm = TRUE) > 0
  nes_mat  <- nes_mat[sig_any, , drop = FALSE]
  padj_mat <- padj_mat[sig_any, , drop = FALSE]
  if (nrow(nes_mat) == 0) {
    message("[skip heatmap] no significant pathways in block ", bn)
    next
  }

  # Cap rows: rank by (# significant columns, then max |NES|)
  if (nrow(nes_mat) > max_rows_heat) {
    n_sig   <- rowSums(padj_mat < padj_cutoff, na.rm = TRUE)
    max_abs <- apply(abs(nes_mat), 1, max, na.rm = TRUE)
    keep <- order(n_sig, max_abs, decreasing = TRUE)[1:max_rows_heat]
    nes_mat  <- nes_mat[keep, , drop = FALSE]
    padj_mat <- padj_mat[keep, , drop = FALSE]
  }

  rownames(nes_mat) <- pretty_path(rownames(nes_mat), width = 60)
  star <- ifelse(!is.na(padj_mat) & padj_mat < padj_cutoff, "*", "")

  lim <- max(abs(nes_mat), na.rm = TRUE)
  breaks <- seq(-lim, lim, length.out = 101)
  pal <- colorRampPalette(c("#2166AC", "white", "#B2182B"))(100)

  h <- max(4, 0.22 * nrow(nes_mat) + 2)
  w <- max(6, 0.55 * ncol(nes_mat) + 6)

  # Cluster on a copy with NAs imputed to 0 (dist() cannot handle NAs), but
  # display the original matrix (NAs shown in na_col).
  cl_mat <- nes_mat
  cl_mat[is.na(cl_mat)] <- 0
  col_hc <- hclust(dist(t(cl_mat)))
  row_hc <- if (nrow(cl_mat) > 2) hclust(dist(cl_mat)) else FALSE

  pheatmap(
    nes_mat,
    color = pal, breaks = breaks,
    cluster_cols = col_hc, cluster_rows = row_hc,
    display_numbers = star, number_color = "black", fontsize_number = 10,
    na_col = "grey90",
    main = paste0(block_titles[[bn]], "  (* padj<", padj_cutoff, ")"),
    fontsize_row = 7, fontsize_col = 10, angle_col = 0,
    border_color = NA,
    filename = file.path(heat_dir, paste0(bn, ".pdf")),
    width = w, height = h
  )
  message("Heatmap written: ", file.path(heat_dir, paste0(bn, ".pdf")),
          "  (", nrow(nes_mat), " pathways x ", ncol(nes_mat), " cols)")
}

message("Done.")
