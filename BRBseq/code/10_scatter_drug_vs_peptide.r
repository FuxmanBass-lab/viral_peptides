#!/usr/bin/env Rscript

# ============================================================
# Drug effect (x) vs peptide effect (y), as a scatter, at gene and pathway level.
#
# Two questions, distinguished by what sits on the y axis:
#
#   y = tile vs N1 under RITA   "does the peptide push along or against the
#                                drug response, while the drug is acting?"
#   y = tile vs N1 under DMSO   PRIMING: "does the peptide, at baseline with no
#                                drug, already move the genes that RITA will
#                                later move?"  Positive => peptide pre-moves
#                                them the way RITA will (priming); negative =>
#                                pre-moves them the opposite way (buffering).
#
# Distinct from 04_compare_dmso_rita.r, which pairs a DIFFERENT axis
# (tile-vs-N1 under DMSO against tile-vs-N1 under RITA).
#
# *** SHARED-SAMPLE BIAS -- read before quoting any r from this script. ***
# When both axes are built from overlapping libraries, a non-zero r is expected
# under the null. Writing each contrast in log space as a difference of group
# means, a sample shared with the SAME sign in both axes biases r positive, and
# with OPPOSITE signs biases it negative:
#
#   id                    x                  y                shared      bias
#   selfRITA_vs_pepRITA   tileR - tileD      tileR - N1R      tileR ++    POSITIVE
#   N1RITA_vs_pepRITA     N1R   - N1D        tileR - N1R      N1R   +-    NEGATIVE
#   N1RITA_vs_pepDMSO     N1R   - N1D        tileD - N1D      N1D   --    POSITIVE
#   WTRITA_vs_pepDMSO     WTR   - WTD        tileD - N1D      none        UNBIASED
#
# Note the trap for the priming question: N1RITA_vs_pepDMSO is biased in exactly
# the direction that would fake a priming result. WTRITA_vs_pepDMSO shares no
# libraries between its axes and is the one to trust; the N1 version is kept only
# because it uses the same vector reference as the rest of the analysis.
# The bias is stamped on every panel.
#
# Out: results/deseq2/<style>/scatters/            gene-level  (log2FC vs log2FC)
#      results/gsea/reactome/<style>/scatters/     pathway-level (NES vs NES)
#      scatter_<level>_<id>_correlations.tsv  in each
# ============================================================

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(ggrepel)
  library(ggrastr)
})

# Base pdf() device + Helvetica, matching 07_publication_figs.r.
# Keep all on-canvas text ASCII (base pdf cannot encode glyphs like >= or ...).
PDF_DEV   <- "pdf"
BASE_FONT <- "Helvetica"

tables_dir <- "../results/deseq2/tables"
gsea_dir   <- "../results/gsea/reactome"

# Gene significance uses the project's volcano cutoff (01/06/07); pathway
# significance uses the GSEA cutoff (07). Kept identical on purpose.
g_padj <- 0.25; g_lfc <- 0.5
p_padj <- 0.05

TILES <- c("T1", "T4", "T5", "T6", "T7", "T9", "T10", "A2", "B6")

# ------------------------------------------------------------------
# The contrasts to draw. `x` and `y` are sprintf templates over the tile name.
# ------------------------------------------------------------------
CONTRASTS <- list(
  list(id = "selfRITA_vs_pepRITA",
       x = "%s_RITA_vs_DMSO",  y = "RITA_%s_vs_N1",
       xlab = "tile RITA vs DMSO",        ylab = "tile vs N1 under RITA",
       bias = "shared tile-RITA samples: r biased POSITIVE",
       note = "up-right/down-left = peptide pushes along the drug response"),
  list(id = "N1RITA_vs_pepRITA",
       x = "N1_RITA_vs_DMSO",  y = "RITA_%s_vs_N1",
       xlab = "N1 (vector) RITA vs DMSO", ylab = "tile vs N1 under RITA",
       bias = "shared N1-RITA samples: r biased NEGATIVE",
       note = "up-right/down-left = peptide pushes along the drug response"),
  list(id = "N1RITA_vs_pepDMSO",
       x = "N1_RITA_vs_DMSO",  y = "DMSO_%s_vs_N1",
       xlab = "N1 (vector) RITA vs DMSO", ylab = "tile vs N1 under DMSO (baseline)",
       bias = "shared N1-DMSO samples: r biased POSITIVE -- fakes priming",
       note = "PRIMING: up-right/down-left = peptide pre-moves RITA-responsive genes"),
  list(id = "WTRITA_vs_pepDMSO",
       x = "WT_RITA_vs_DMSO",  y = "DMSO_%s_vs_N1",
       xlab = "WT RITA vs DMSO",          ylab = "tile vs N1 under DMSO (baseline)",
       bias = "no shared samples between axes: UNBIASED",
       note = "PRIMING: up-right/down-left = peptide pre-moves RITA-responsive genes")
)

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
      strip.background = element_blank(),
      strip.text    = element_text(face = "bold", size = base),
      plot.margin   = margin(4, 4, 4, 4)
    )
}

# Colour encodes WHICH COMPARISON CALLED THE FEATURE SIGNIFICANT, not which
# comparison it has a value from -- every plotted point has both an x and a y
# (the merge drops anything missing either). A "Drug axis only" point still has
# a y value; that value just did not clear the padj cutoff.
# These are hard-threshold bins, so points sitting either side of the cutoff can
# be near-identical: check padj_x/padj_y in the source tables before reading much
# into a single point's colour.
CATS <- c("Both axes", "Drug axis only", "Peptide axis only", "Neither")
PAL  <- c("Both axes"         = "#6A3D9A", "Drug axis only" = "#B2182B",
          "Peptide axis only" = "#2166AC", "Neither"        = "grey78")

styles <- list(
  plots  = list(base = 8,  pt = 0.55, lab_n = 6, lab_sz = 1.9, seg = 0.2,
                w1 = 3.9, h1 = 3.5, ncol = 3),
  poster = list(base = 18, pt = 1.5,  lab_n = 4, lab_sz = 4.2, seg = 0.4,
                w1 = 5.0, h1 = 4.8, ncol = 3)
)

read_de <- function(path) {
  if (!file.exists(path)) return(NULL)
  dt <- fread(path)
  if (!all(c("gene_id", "log2FoldChange", "padj") %in% colnames(dt))) return(NULL)
  if (!"gene_name" %in% colnames(dt)) dt[, gene_name := NA_character_]
  dt[, .(key = gene_id,
         name = fifelse(!is.na(gene_name) & gene_name != "", gene_name, gene_id),
         eff = log2FoldChange, padj)]
}
read_gs <- function(path) {
  if (!file.exists(path)) return(NULL)
  dt <- fread(path)
  if (!all(c("pathway", "NES", "padj") %in% colnames(dt))) return(NULL)
  lab <- sub("^REACTOME_", "", dt$pathway)
  lab <- gsub("_", " ", tolower(lab))
  substr(lab, 1, 1) <- toupper(substr(lab, 1, 1))
  dt[, .(key = pathway, name = lab, eff = NES, padj)]
}

# ------------------------------------------------------------------
# Join one level (gene or pathway) for one contrast. NULL if nothing joined.
# ------------------------------------------------------------------
build <- function(level, ct) {
  reader  <- if (level == "gene") read_de else read_gs
  dir     <- if (level == "gene") tables_dir else gsea_dir
  pre     <- if (level == "gene") "DE_" else "Reactome_DE_"
  sig_fun <- if (level == "gene")
    function(d) !is.na(d$padj) & d$padj < g_padj & abs(d$eff) >= g_lfc
  else
    function(d) !is.na(d$padj) & d$padj < p_padj

  out <- list()
  for (tile in TILES) {
    # sprintf ignores extra args when the template has no %s, so a fixed
    # reference like "N1_RITA_vs_DMSO" passes through unchanged.
    x <- reader(file.path(dir, paste0(pre, sprintf(ct$x, tile), ".tsv")))
    y <- reader(file.path(dir, paste0(pre, sprintf(ct$y, tile), ".tsv")))
    if (is.null(x) || is.null(y)) next
    x[, sig := sig_fun(.SD)]; y[, sig := sig_fun(.SD)]
    setnames(x, c("eff", "padj", "sig"), c("x", "padj_x", "sig_x"))
    setnames(y, c("eff", "padj", "sig"), c("y", "padj_y", "sig_y"))
    m <- merge(x[, .(key, name, x, padj_x, sig_x)],
               y[, .(key, y, padj_y, sig_y)], by = "key")
    m <- m[!is.na(x) & !is.na(y)]
    if (nrow(m) == 0) next
    m[, tile := tile]
    m[, category := fcase(
      sig_x &  sig_y, "Both axes",
      sig_x & !sig_y, "Drug axis only",
      !sig_x & sig_y, "Peptide axis only",
      default = "Neither")]
    out[[tile]] <- m
  }
  if (length(out) == 0) return(NULL)
  dt <- rbindlist(out)
  dt[, category := factor(category, levels = CATS)]
  dt[, tile := factor(tile, levels = intersect(TILES, unique(tile)))]
  dt[]
}

cor_stats <- function(d) {
  both <- d[sig_x | sig_y]
  data.table(
    n            = nrow(d),
    pearson_all  = if (nrow(d)    >= 3) cor(d$x, d$y) else NA_real_,
    spearman_all = if (nrow(d)    >= 3) suppressWarnings(cor(d$x, d$y, method = "spearman")) else NA_real_,
    n_sig_either = nrow(both),
    pearson_sig  = if (nrow(both) >= 3) cor(both$x, both$y) else NA_real_,
    spearman_sig = if (nrow(both) >= 3) suppressWarnings(cor(both$x, both$y, method = "spearman")) else NA_real_,
    n_concordant = d[sign(x) == sign(y) & (sig_x | sig_y), .N],
    n_opposed    = d[sign(x) != sign(y) & (sig_x | sig_y), .N])
}

# Top-n most significant double-hits, computed PER TILE so a faceted plot
# labels every panel rather than spending its whole label budget on one.
top_labels <- function(d, n) {
  lab <- d[category == "Both axes"][
    order(pmin(padj_x, padj_y, na.rm = TRUE)), head(.SD, n), by = tile]
  # Reactome names run to 60+ chars and collide even with repel; clip them.
  lab[, short := fifelse(nchar(name) > 34, paste0(substr(name, 1, 31), "..."), name)]
  lab[]
}

# One panel. `d` holds a single tile when standalone, all tiles when faceted.
panel <- function(d, cfg, level, ct, standalone) {
  st   <- cor_stats(d)
  lab  <- top_labels(d, cfg$lab_n)
  unit <- if (level == "gene") "log2FC" else "NES"

  pts <- geom_point(aes(color = category), size = cfg$pt, alpha = 0.75, stroke = 0)
  p <- ggplot(d, aes(x, y)) +
    geom_hline(yintercept = 0, linewidth = 0.25, color = "grey70") +
    geom_vline(xintercept = 0, linewidth = 0.25, color = "grey70") +
    geom_abline(slope =  1, intercept = 0, linetype = "dashed", linewidth = 0.25, color = "grey55") +
    geom_abline(slope = -1, intercept = 0, linetype = "dotted", linewidth = 0.25, color = "grey55") +
    # Rasterise only the dense gene cloud; pathway points stay vector.
    (if (level == "gene") ggrastr::rasterise(pts, dpi = 300) else pts) +
    scale_color_manual(values = PAL, drop = FALSE,
                       name = paste0("Significant (padj<", if (level == "gene") g_padj else p_padj, ") in:")) +
    # Title above the keys, not beside them: inline it and the four labels run
    # past the panel edge at publication width.
    guides(color = guide_legend(title.position = "top", nrow = 1,
                                override.aes = list(size = 1.4, alpha = 1))) +
    coord_equal() +
    labs(x = paste0(unit, ": ", ct$xlab), y = paste0(unit, ": ", ct$ylab)) +
    theme_pub(cfg$base)

  if (standalone) {
    # Labels only on the single-tile figures. In the faceted grid ggrepel has no
    # room and pushes text across panel borders, so the grid stays an overview.
    p <- p + ggrepel::geom_text_repel(
        data = lab, aes(label = short), size = cfg$lab_sz, max.overlaps = Inf,
        segment.size = cfg$seg, min.segment.length = 0, box.padding = 0.35,
        force = 3, seed = 1) +
      labs(title = paste0(d$tile[1], ": ", ct$id, " (", level, "-level)"),
           subtitle = paste0(
             "r=", sprintf("%.2f", st$pearson_all), " all, ",
             sprintf("%.2f", st$pearson_sig), " sig-either (n=", st$n_sig_either, ")\n",
             st$n_concordant, " concordant / ", st$n_opposed, " opposed\n",
             ct$bias)) +
      theme(legend.position = "top", legend.box.spacing = unit(2, "pt"))
  }
  # Faceted callers add their own title/subtitle and per-panel r annotation.
  p
}

# ------------------------------------------------------------------
run <- function(level, ct) {
  dt <- build(level, ct)
  if (is.null(dt)) { message("  no data for ", level, "/", ct$id); return(NULL) }
  tiles_here <- levels(dt$tile)
  message("  ", level, "/", ct$id, ": ", length(tiles_here), " tiles (",
          paste(tiles_here, collapse = ", "), "), ", nrow(dt), " points")

  stats <- dt[, cor_stats(.SD), by = tile][
    , `:=`(level = level, contrast = ct$id, x_axis = ct$xlab, y_axis = ct$ylab,
           shared_sample_bias = ct$bias)]

  for (style_name in names(styles)) {
    cfg <- styles[[style_name]]
    out_dir <- file.path(if (level == "gene") "../results/deseq2" else gsea_dir,
                         style_name, "scatters")
    dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
    stem <- file.path(out_dir, paste0("scatter_", level, "_", ct$id))

    for (tl in tiles_here)
      ggsave(paste0(stem, "_", tl, ".pdf"),
             panel(dt[tile == tl], cfg, level, ct, standalone = TRUE),
             width = cfg$w1, height = cfg$h1 + 0.8, device = PDF_DEV, useDingbats = FALSE)

    # Faceted grid, with each tile's r drawn into its own panel.
    n <- length(tiles_here); nc <- min(cfg$ncol, n); nr <- ceiling(n / nc)
    ann <- stats[, .(tile, txt = paste0("r=", sprintf("%.2f", pearson_all)))]
    ann[, `:=`(x = min(dt$x, na.rm = TRUE), y = max(dt$y, na.rm = TRUE))]
    g <- panel(dt, cfg, level, ct, standalone = FALSE) +
      facet_wrap(~ tile, ncol = nc) +
      geom_text(data = ann, aes(x, y, label = txt), inherit.aes = FALSE,
                hjust = 0, vjust = 1, size = cfg$lab_sz + 0.6, family = BASE_FONT) +
      labs(title = paste0(ct$id, ", ", level, "-level"),
           subtitle = paste0(ct$note, "\ndashed y=x, dotted y=-x; ", ct$bias)) +
      theme(legend.position = "top", legend.box.spacing = unit(2, "pt"))
    ggsave(paste0(stem, "_grid.pdf"), g,
           width = cfg$w1 * nc + 1.4, height = (cfg$h1 * nr) + 1.4,
           device = PDF_DEV, useDingbats = FALSE, limitsize = FALSE)

    fwrite(stats, paste0(stem, "_correlations.tsv"), sep = "\t")
    message("    -> ", out_dir)
  }
  stats
}

all_stats <- list()
for (level in c("gene", "pathway"))
  for (ct in CONTRASTS) {
    message("\n===== ", level, " / ", ct$id, " =====")
    all_stats[[paste(level, ct$id)]] <- run(level, ct)
  }

st <- rbindlist(Filter(Negate(is.null), all_stats), fill = TRUE)
if (nrow(st)) {
  print(st[, .(level, contrast, tile, n, pearson_all, pearson_sig,
               n_sig_either, n_concordant, n_opposed)])
  fwrite(st, "../results/scatter_correlations_all.tsv", sep = "\t")
  message("\ncombined stats -> ../results/scatter_correlations_all.tsv")
}
message("\nDone.")
