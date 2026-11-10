#!/usr/bin/env Rscript

library(fgsea)
library(data.table)
library(msigdbr)
library(tidyverse)
library(AnnotationDbi)
library(org.Hs.eg.db)

# === Load desired Reactome pathway names ===
desired_pathways <- fread("../data/reactome/pathways.txt", header = FALSE, fill = TRUE)[[1]]
desired_pathways <- trimws(desired_pathways)
desired_pathways <- desired_pathways[desired_pathways != ""]
desired_pathways <- desired_pathways[desired_pathways != "Pathways"]

# === Load Reactome gene sets via MSigDB (works across msigdbr versions) ===
reactome_sets <- tryCatch(
  msigdbr(species = "Homo sapiens", collection = "C2", subcollection = "CP:REACTOME"),
  error = function(e) msigdbr(species = "Homo sapiens", category = "C2", subcategory = "CP:REACTOME")
) %>% as.data.table()

# Filter only the desired pathways
reactome_sets <- reactome_sets[gs_name %in% desired_pathways]

# Check for missing pathway names
missing <- setdiff(desired_pathways, unique(reactome_sets$gs_name))
if (length(missing) > 0) {
  warning("These pathway names were not found in MSigDB: ", paste(missing, collapse = ", "))
}

# Format pathways list
pathways <- split(reactome_sets$gene_symbol, reactome_sets$gs_name)

# === Significance gate ===
# Only run pathway analysis for comparisons with at least this many significant
# DEGs, using the SAME call as the volcano plots (padj < 0.25 & |log2FC| >= 0.5;
# see 01_run_deseq2.r / 06_plot_volcanoes.r). Comparisons below the threshold are
# too sparse to interpret at the pathway level and are skipped (no output written).
padj_cutoff   <- 0.25
lfc_cutoff    <- 0.5
min_sig_degs  <- 20

# === DE result files ===
de_files <- list.files("../results/deseq2/tables", pattern = "^DE_.*\\.tsv$", full.names = TRUE)

# Output directory
gsea_dir <- "../results/gsea/reactome"
dir.create(gsea_dir, showWarnings = FALSE, recursive = TRUE)

# === Run GSEA on each DE result ===
for (file in de_files) {
  message("Processing ", basename(file))

  res <- fread(file)

  # Gate: require >= min_sig_degs significant DEGs (volcano cutoff) or skip.
  if (all(c("padj", "log2FoldChange") %in% colnames(res))) {
    n_sig_degs <- res[!is.na(padj) & padj < padj_cutoff &
                        abs(log2FoldChange) >= lfc_cutoff, .N]
  } else {
    n_sig_degs <- 0L
  }
  if (n_sig_degs < min_sig_degs) {
    message("  skip (", n_sig_degs, " significant DEGs < ", min_sig_degs, ")")
    next
  }
  message("  ", n_sig_degs, " significant DEGs -> running GSEA")

  # Rank by the Wald statistic when available (standard for preranked GSEA:
  # it folds effect size and significance together); fall back to log2FC.
  rank_col <- if ("stat" %in% colnames(res)) "stat" else "log2FoldChange"
  res <- res[!is.na(get(rank_col))]

  # Identify or create gene symbol column
  symbol_col <- intersect(c("symbol", "gene_symbol", "label"), colnames(res))

  if (length(symbol_col) > 0) {
    res[, symbol := get(symbol_col[1])]
  } else {
    # Try to recover symbols from Ensembl gene IDs stored in the first column/gene column
    id_col <- intersect(c("gene", "gene_id", "rownames"), colnames(res))
    if (length(id_col) == 0) {
      id_col <- colnames(res)[1]
    }

    res[, gene_id_raw := get(id_col[1])]
    res[, gene_id_clean := sub("\\..*$", "", gene_id_raw)]

    map_dt <- data.table(
      gene_id_clean = unique(res$gene_id_clean),
      symbol = mapIds(
        org.Hs.eg.db,
        keys = unique(res$gene_id_clean),
        keytype = "ENSEMBL",
        column = "SYMBOL",
        multiVals = "first"
      )
    )

    res <- merge(res, map_dt, by = "gene_id_clean", all.x = TRUE)
    res[, symbol := fifelse(is.na(symbol) | symbol == "", gene_id_raw, symbol)]
  }

  # Deduplicate and clean
  res <- res[!is.na(symbol) & symbol != ""]
  res <- res[!duplicated(symbol)]

  # Rank genes by the chosen statistic over the FULL gene list. Do NOT pre-filter
  # to pathway genes: fgsea evaluates each pathway's enrichment against the whole
  # ranked list, so restricting the list would invalidate the null distribution.
  ranked <- res[[rank_col]]
  names(ranked) <- res$symbol
  ranked <- ranked[!is.na(ranked)]
  ranked <- sort(ranked, decreasing = TRUE)

  if (length(ranked) < 15) {
    warning("Skipping ", basename(file), ": fewer than 15 ranked genes after symbol mapping")
    next
  }

  # Run fgsea (multilevel; nperm-based fgseaSimple is deprecated)
  fgsea_res <- fgsea(
    pathways = pathways,
    stats = ranked,
    minSize = 15,
    maxSize = 500
  ) %>% as.data.table() %>%
    arrange(padj)

  # Save
  out_file <- file.path(gsea_dir, paste0("Reactome_", tools::file_path_sans_ext(basename(file)), ".tsv"))
  fwrite(fgsea_res, out_file, sep = "\t")
}

message("All Reactome GSEA analyses complete.")
