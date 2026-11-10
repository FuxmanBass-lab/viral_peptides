#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(data.table)
  library(DESeq2)
  library(ggplot2)
  library(ggrepel)
  library(ggrastr)
})

# ============================================================
# DESeq2 for the viral peptide BRB-seq study
# - input count matrix: ../results/matrix/all_samples.filtered_counts.tsv
# - input metadata:     ../results/metadata/final_sample_metadata.tsv
# - metadata sample labels are peptide_condition, e.g. WT_DMSO or N1_RITA
#
# Experimental design:
#   WT  = parental control cells
#   N1  = vector control (empty vector) -> reference for peptide effects
#   T*/A2/B6 = peptide tiles
#   Each group treated with DMSO or RITA.
#
# Comparisons:
#   Block A (RITA signature):  RITA vs DMSO within each group (covers WT and N1)
#   Block B/C (peptide effect): each group vs the vector control (N1) within
#                               each condition. Comparing to N1 (not WT) isolates
#                               the peptide effect from the vector/transduction
#                               effect. This also yields WT vs N1 (vector effect).
# Block D (wired vs RITA-dependent) is handled downstream by comparing the
# DMSO and RITA peptide-vs-vector enrichment results (see 04_compare_dmso_rita.r).
# ============================================================

# -------------------- CONFIG --------------------
count_file <- "../results/matrix/all_samples.filtered_counts.tsv"
metadata_file <- "../results/metadata/final_sample_metadata.tsv"
out_dir <- "../results/deseq2"

# Vector control is the reference for peptide-vs-control comparisons.
control_peptide_label <- "N1"
condition_levels <- c("DMSO", "RITA")
treatment_test_label <- "RITA"
treatment_control_label <- "DMSO"

run_peptide_vs_wt <- TRUE
run_rita_vs_dmso <- TRUE

min_reps_per_group <- 2
min_total_count <- 10

padj_cutoff <- 0.25
lfc_cutoff <- 0.5

# -------------------- HELPERS --------------------
safe_name <- function(x) {
  x <- gsub("[^A-Za-z0-9_.-]+", "_", x)
  x <- gsub("_+", "_", x)
  x <- gsub("^_|_$", "", x)
  x
}

write_empty_result <- function(path, reason) {
  dt <- data.table(
    gene_id = character(),
    gene_name = character(),
    baseMean = numeric(),
    log2FoldChange = numeric(),
    lfcSE = numeric(),
    stat = numeric(),
    pvalue = numeric(),
    padj = numeric(),
    reason = reason
  )
  fwrite(dt, path, sep = "\t")
}

# Volcano plot: significantly depleted genes blue, enriched red, rest grey.
# (Kept in sync with the standalone re-plotter 06_plot_volcanoes.r.)
make_volcano <- function(res_dt, title, out_file) {
  plot_dt <- copy(res_dt)
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

  pal <- c("Depleted (down)" = "#2166AC",
           "Not significant" = "grey75",
           "Enriched (up)"   = "#B2182B")

  label_dt <- plot_dt[significant == TRUE][order(padj)][1:min(.N, 15)]
  label_dt[, label := fifelse(!is.na(gene_name) & gene_name != "", gene_name, gene_id)]

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
    ggrepel::geom_text_repel(
      data = label_dt,
      aes(label = label),
      size = 3,
      max.overlaps = Inf
    ) +
    labs(
      title = title,
      subtitle = paste0(n_down, " down / ", n_up, " up  (padj < ", padj_cutoff,
                        ", |log2FC| >= ", lfc_cutoff, ")"),
      x = "log2 fold change",
      y = "-log10 adjusted p-value"
    ) +
    theme_classic(base_size = 12) +
    theme(legend.position = "top")

  ggsave(out_file, p, width = 6, height = 5, dpi = 300)
}

empty_summary <- function(comparison_type, condition, peptide, comparison_label,
                          test_group, control_group, n_test, n_control,
                          reason, out_table) {
  data.table(
    comparison_type = comparison_type,
    condition = condition,
    peptide = peptide,
    comparison = comparison_label,
    test_group = test_group,
    control_group = control_group,
    n_test = n_test,
    n_control = n_control,
    status = "skipped",
    reason = reason,
    output_table = out_table
  )
}

run_deseq_comparison <- function(comparison_type, condition, peptide,
                                 comparison_label, test_meta, control_meta,
                                 test_group_label, control_group_label,
                                 out_prefix, plot_title) {
  message("[INFO] Running ", comparison_label)

  out_table <- file.path(out_dir, "tables", paste0("DE_", safe_name(out_prefix), ".tsv"))
  out_plot <- file.path(out_dir, "draft", paste0("volcano_", safe_name(out_prefix), ".pdf"))

  if (nrow(test_meta) < min_reps_per_group) {
    reason <- paste0("Skipped: fewer than ", min_reps_per_group, " replicates for ", test_group_label)
    warning(reason)
    write_empty_result(out_table, reason)
    return(list(
      status = "skipped",
      summary = empty_summary(
        comparison_type, condition, peptide, comparison_label,
        test_group_label, control_group_label, nrow(test_meta), nrow(control_meta),
        reason, out_table
      )
    ))
  }

  if (nrow(control_meta) < min_reps_per_group) {
    reason <- paste0("Skipped: fewer than ", min_reps_per_group, " replicates for ", control_group_label)
    warning(reason)
    write_empty_result(out_table, reason)
    return(list(
      status = "skipped",
      summary = empty_summary(
        comparison_type, condition, peptide, comparison_label,
        test_group_label, control_group_label, nrow(test_meta), nrow(control_meta),
        reason, out_table
      )
    ))
  }

  sel_meta <- rbind(test_meta, control_meta, fill = TRUE)
  sel_meta[, de_group := fifelse(sample_id %in% test_meta$sample_id, test_group_label, control_group_label)]
  sel_meta[, de_group := factor(de_group, levels = c(control_group_label, test_group_label))]
  rownames(sel_meta) <- sel_meta$sample_id

  sel_counts <- count_matrix[, sel_meta$sample_id, drop = FALSE]
  comp_keep <- rowSums(sel_counts, na.rm = TRUE) >= min_total_count
  sel_counts <- sel_counts[comp_keep, , drop = FALSE]

  if (nrow(sel_counts) == 0) {
    reason <- "Skipped: no genes passed the count filter for this comparison"
    warning(reason)
    write_empty_result(out_table, reason)
    return(list(
      status = "skipped",
      summary = empty_summary(
        comparison_type, condition, peptide, comparison_label,
        test_group_label, control_group_label, nrow(test_meta), nrow(control_meta),
        reason, out_table
      )
    ))
  }

  dds <- DESeqDataSetFromMatrix(
    countData = round(sel_counts),
    colData = as.data.frame(sel_meta),
    design = ~ de_group
  )

  dds <- estimateSizeFactors(dds, type = "poscounts")
  dds <- DESeq(dds, quiet = TRUE)

  res <- results(dds, contrast = c("de_group", test_group_label, control_group_label))
  res_dt <- as.data.table(res, keep.rownames = "gene_id")
  res_dt <- merge(
    count_data_dt[, .(gene_id, gene_name)],
    res_dt,
    by = "gene_id",
    all.y = TRUE,
    sort = FALSE
  )
  setcolorder(res_dt, c("gene_id", "gene_name", setdiff(colnames(res_dt), c("gene_id", "gene_name"))))
  setorder(res_dt, padj, pvalue)

  fwrite(res_dt, out_table, sep = "\t")
  make_volcano(res_dt, title = plot_title, out_file = out_plot)

  n_sig <- res_dt[!is.na(padj) & padj < padj_cutoff, .N]
  n_sig_lfc <- res_dt[!is.na(padj) & padj < padj_cutoff & abs(log2FoldChange) >= lfc_cutoff, .N]

  return(list(
    status = "completed",
    summary = data.table(
      comparison_type = comparison_type,
      condition = condition,
      peptide = peptide,
      comparison = comparison_label,
      test_group = test_group_label,
      control_group = control_group_label,
      n_test = nrow(test_meta),
      n_control = nrow(control_meta),
      n_genes_tested = nrow(res_dt),
      n_padj_lt_cutoff = n_sig,
      n_padj_lt_cutoff_abs_lfc_ge_cutoff = n_sig_lfc,
      status = "completed",
      reason = NA_character_,
      output_table = out_table,
      output_plot = out_plot
    )
  ))
}

# -------------------- LOAD INPUTS --------------------
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(file.path(out_dir, "tables"), showWarnings = FALSE, recursive = TRUE)
dir.create(file.path(out_dir, "draft"), showWarnings = FALSE, recursive = TRUE)

if (!file.exists(count_file)) {
  stop("Missing count matrix: ", count_file)
}
if (!file.exists(metadata_file)) {
  stop("Missing sample metadata: ", metadata_file)
}

counts_dt <- fread(count_file)
metadata <- fread(metadata_file)

required_count_cols <- c("gene_id", "gene_name")
missing_count_cols <- setdiff(required_count_cols, colnames(counts_dt))
if (length(missing_count_cols) > 0) {
  stop("Count matrix is missing required columns: ", paste(missing_count_cols, collapse = ", "))
}

required_metadata_cols <- c("sample_id", "library", "sample", "well", "barcode_seq")
missing_metadata_cols <- setdiff(required_metadata_cols, colnames(metadata))
if (length(missing_metadata_cols) > 0) {
  stop("sample_sheet.tsv is missing required columns: ", paste(missing_metadata_cols, collapse = ", "))
}

# -------------------- PREP COUNTS --------------------
gene_info <- unique(counts_dt[, .(gene_id, gene_name)])
if (anyDuplicated(gene_info$gene_id) > 0) {
  warning("Duplicate gene_id values found. Collapsing duplicate rows by summed counts.")
}

count_cols <- setdiff(colnames(counts_dt), c("gene_id", "gene_name"))
count_data_dt <- counts_dt[, c("gene_id", count_cols), with = FALSE]
count_data_dt <- count_data_dt[, lapply(.SD, sum, na.rm = TRUE), by = gene_id, .SDcols = count_cols]

gene_name_map <- unique(counts_dt[, .(gene_id, gene_name)])
gene_name_map <- gene_name_map[!duplicated(gene_id)]
count_data_dt <- merge(gene_name_map, count_data_dt, by = "gene_id", all.y = TRUE, sort = FALSE)

count_matrix <- as.matrix(count_data_dt[, ..count_cols])
storage.mode(count_matrix) <- "integer"
rownames(count_matrix) <- count_data_dt$gene_id

# -------------------- PREP METADATA --------------------
metadata[, sample_id := as.character(sample_id)]
metadata[, library := as.character(library)]
metadata[, sample := as.character(sample)]
metadata[, well := as.character(well)]
metadata[, barcode_seq := as.character(barcode_seq)]

if (!("peptide" %in% colnames(metadata)) || !("condition" %in% colnames(metadata))) {
  if (any(!grepl("_[^_]+$", metadata$sample))) {
    stop("Metadata lacks peptide/condition columns, and not all sample labels contain a condition suffix.")
  }
  metadata[, peptide := sub("_[^_]+$", "", sample)]
  metadata[, condition := toupper(sub("^.*_([^_]+)$", "\\1", sample))]
}

metadata[, peptide := as.character(peptide)]
metadata[, condition := toupper(as.character(condition))]
metadata[, peptide_lower := tolower(peptide)]

unknown_conditions <- setdiff(sort(unique(metadata$condition)), condition_levels)
if (length(unknown_conditions) > 0) {
  stop("Unexpected condition values in metadata: ", paste(unknown_conditions, collapse = ", "))
}

metadata[, condition := factor(condition, levels = condition_levels)]
metadata[, library := factor(library)]
metadata[, well := factor(well)]

available_samples <- intersect(metadata$sample_id, colnames(count_matrix))
if (length(available_samples) == 0) {
  stop("No metadata sample_id values matched count matrix column names.")
}

metadata <- metadata[match(available_samples, sample_id)]
count_matrix <- count_matrix[, available_samples, drop = FALSE]
rownames(metadata) <- metadata$sample_id

keep_genes <- rowSums(count_matrix, na.rm = TRUE) >= min_total_count
count_matrix <- count_matrix[keep_genes, , drop = FALSE]
count_data_dt <- count_data_dt[match(rownames(count_matrix), gene_id)]

fwrite(metadata, file.path(out_dir, "metadata_used.tsv"), sep = "\t")

message("Retained ", nrow(metadata), " samples.")
message("Retained ", nrow(count_matrix), " genes with total counts >= ", min_total_count, ".")
message("Libraries: ", paste(sort(unique(as.character(metadata$library))), collapse = ", "))
message("Conditions: ", paste(sort(unique(as.character(metadata$condition))), collapse = ", "))
message("Peptides: ", paste(sort(unique(as.character(metadata$peptide))), collapse = ", "))

# -------------------- SAVE CLEAN COUNT MATRICES --------------------
metadata[, sample_label := paste0(as.character(condition), "_", as.character(peptide), "_", as.character(well))]

clean_count_matrix <- count_matrix
colnames(clean_count_matrix) <- metadata[match(colnames(clean_count_matrix), sample_id)]$sample_label

clean_count_dt <- as.data.table(clean_count_matrix, keep.rownames = "gene_id")
clean_count_dt <- merge(
  count_data_dt[, .(gene_id, gene_name)],
  clean_count_dt,
  by = "gene_id",
  all.y = TRUE,
  sort = FALSE
)
setcolorder(clean_count_dt, c("gene_id", "gene_name", setdiff(names(clean_count_dt), c("gene_id", "gene_name"))))
fwrite(clean_count_dt, file.path(out_dir, "clean_filtered_count_matrix.tsv"), sep = "\t")
message("Saved clean filtered count matrix with sample labels to ", file.path(out_dir, "clean_filtered_count_matrix.tsv"))

cpm_matrix <- clean_count_matrix
for (i in seq_len(ncol(cpm_matrix))) {
  col_sum <- sum(cpm_matrix[, i])
  if (col_sum > 0) {
    cpm_matrix[, i] <- (cpm_matrix[, i] / col_sum) * 1e6
  }
}

cpm_dt <- as.data.table(cpm_matrix, keep.rownames = "gene_id")
cpm_dt <- merge(
  count_data_dt[, .(gene_id, gene_name)],
  cpm_dt,
  by = "gene_id",
  all.y = TRUE,
  sort = FALSE
)
setcolorder(cpm_dt, c("gene_id", "gene_name", setdiff(names(cpm_dt), c("gene_id", "gene_name"))))
fwrite(cpm_dt, file.path(out_dir, "clean_filtered_cpm_matrix.tsv"), sep = "\t")
message("Saved CPM normalized count matrix to ", file.path(out_dir, "clean_filtered_cpm_matrix.tsv"))

# -------------------- RUN DESEQ2 --------------------
summary_rows <- list()
comparisons_run <- 0L
comparisons_skipped <- 0L

if (run_peptide_vs_wt) {
  for (condition_label in condition_levels) {
    message("\n[INFO] Processing peptide comparisons within ", condition_label)

    condition_meta <- metadata[as.character(condition) == condition_label]
    control_meta <- condition_meta[peptide_lower == tolower(control_peptide_label)]

    peptide_labels <- sort(unique(as.character(condition_meta$peptide)))
    peptide_labels <- peptide_labels[tolower(peptide_labels) != tolower(control_peptide_label)]

    if (length(peptide_labels) == 0) {
      warning("No viral peptide groups found for condition ", condition_label)
    }

    for (peptide_label in peptide_labels) {
      test_meta <- condition_meta[as.character(peptide) == peptide_label]
      comp_label <- paste0(condition_label, ": ", peptide_label, " vs ", control_peptide_label)
      comp <- run_deseq_comparison(
        comparison_type = "peptide_vs_vector",
        condition = condition_label,
        peptide = peptide_label,
        comparison_label = comp_label,
        test_meta = test_meta,
        control_meta = control_meta,
        test_group_label = peptide_label,
        control_group_label = control_peptide_label,
        out_prefix = paste0(condition_label, "__", peptide_label, "_vs_", control_peptide_label),
        plot_title = comp_label
      )

      summary_rows[[length(summary_rows) + 1L]] <- comp$summary
      if (comp$status == "completed") {
        comparisons_run <- comparisons_run + 1L
      } else {
        comparisons_skipped <- comparisons_skipped + 1L
      }
    }
  }
}

if (run_rita_vs_dmso) {
  message("\n[INFO] Processing RITA vs DMSO comparisons within each peptide")

  for (peptide_label in sort(unique(as.character(metadata$peptide)))) {
    peptide_meta <- metadata[as.character(peptide) == peptide_label]
    test_meta <- peptide_meta[as.character(condition) == treatment_test_label]
    control_meta <- peptide_meta[as.character(condition) == treatment_control_label]

    comp_label <- paste0(peptide_label, ": ", treatment_test_label, " vs ", treatment_control_label)
    comp <- run_deseq_comparison(
      comparison_type = "RITA_vs_DMSO",
      condition = NA_character_,
      peptide = peptide_label,
      comparison_label = comp_label,
      test_meta = test_meta,
      control_meta = control_meta,
      test_group_label = treatment_test_label,
      control_group_label = treatment_control_label,
      out_prefix = paste0(peptide_label, "__", treatment_test_label, "_vs_", treatment_control_label),
      plot_title = comp_label
    )

    summary_rows[[length(summary_rows) + 1L]] <- comp$summary
    if (comp$status == "completed") {
      comparisons_run <- comparisons_run + 1L
    } else {
      comparisons_skipped <- comparisons_skipped + 1L
    }
  }
}

if (length(summary_rows) > 0) {
  summary_dt <- rbindlist(summary_rows, fill = TRUE)
} else {
  summary_dt <- data.table(
    comparison_type = character(),
    condition = character(),
    peptide = character(),
    comparison = character(),
    test_group = character(),
    control_group = character(),
    n_test = integer(),
    n_control = integer(),
    status = character(),
    reason = character(),
    output_table = character()
  )
}
fwrite(summary_dt, file.path(out_dir, "deseq2_comparison_summary.tsv"), sep = "\t")

message("\nAll DESeq2 comparisons finished.")
message("Completed comparisons: ", comparisons_run)
message("Skipped comparisons: ", comparisons_skipped)
message("Results written to: ", out_dir)
