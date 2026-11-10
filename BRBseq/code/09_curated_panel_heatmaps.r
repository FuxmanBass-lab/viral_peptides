#!/usr/bin/env Rscript

# ============================================================
# Curated pathway panels: cell death, cellular stress, and both together.
#
# Companion to 07_publication_figs.r. That script picks rows data-driven
# (significant in >=1 column, then top-N by n_sig then max|NES|), which favours
# pathways shared across many columns and silently drops the rest. Here the rows
# are FIXED by biology instead: every pathway in a panel is shown for every
# block, significant or not, so a flat/absent response is visible rather than
# being filtered out.
#
# Differences from 07 that are deliberate:
#   - no top-N cut and no "significant in >=1 column" filter
#   - rows are NOT clustered; order is the curated group order, with gaps
#   - columns are NOT clustered; fixed prefer_order, so A/B/C read the same way
#   - within a panel set, one NES colour scale shared by all three blocks, so a
#     given red means the same thing in every block of that set
#
# Every pathway lives in exactly ONE (domain, group) bucket -- see `curated`
# below; the script stops if that is ever violated. The combined panel is the
# union of the two domains, so no row is duplicated there either.
#
# Reads the existing GSEA outputs; does not re-run fgsea. Pathways requested but
# never scored (name drift vs MSigDB, or outside fgsea's 15-500 gene size range)
# are reported on stderr, not silently dropped -- see UNAVAILABLE.
#
# Out: results/gsea/reactome/<style>/heatmaps/<prefix>_<block>.pdf
#      results/gsea/reactome/<style>/heatmaps/<prefix>_<block>_values.tsv
# ============================================================

suppressPackageStartupMessages({
  library(data.table)
  library(pheatmap)
  library(grid)
})

# Base pdf() device + Helvetica, matching 07_publication_figs.r so the panels
# drop into the same figure. Keep all on-canvas text ASCII.
PDF_DEV   <- "pdf"
BASE_FONT <- "Helvetica"

gsea_dir    <- "../results/gsea/reactome"
padj_cutoff <- 0.05

grp <- function(domain, group, ...) {
  kv <- list(...)
  data.table(domain = domain, group = group,
             pathway = names(kv), label = unlist(kv, use.names = FALSE))
}

# ==================================================================
# THE MASTER TABLE. One row per pathway, assigned to exactly one bucket.
# Row order here IS the plotted row order.
#
# Two assignments are judgement calls, made once, here:
#   - the four AUTOPHAGY terms sit under stress/proteostasis, not under death.
#     Autophagy is primarily a stress-adaptation and clearance mechanism;
#     autophagic cell death is a contested minority reading. To treat autophagy
#     as a death fate instead, move the whole grp() block to domain "Cell death".
#   - OXIDATIVE_STRESS_INDUCED_SENESCENCE sits under death/senescence, not under
#     stress/oxidative. Senescence is a terminal cell fate, and keeping it with
#     the other five senescence terms is what makes that group interpretable.
# ==================================================================
curated <- rbindlist(list(

  # ---------------- domain: CELL DEATH ----------------
  grp("Cell death", "Apoptosis core",
    REACTOME_APOPTOSIS                                 = "Apoptosis",
    REACTOME_PROGRAMMED_CELL_DEATH                     = "Programmed cell death",
    REACTOME_INTRINSIC_PATHWAY_FOR_APOPTOSIS           = "Intrinsic pathway for apoptosis",
    REACTOME_DEFECTIVE_INTRINSIC_PATHWAY_FOR_APOPTOSIS = "Defective intrinsic pathway for apoptosis",
    REACTOME_APOPTOTIC_EXECUTION_PHASE                 = "Apoptotic execution phase",
    REACTOME_APOPTOTIC_CLEAVAGE_OF_CELLULAR_PROTEINS   = "Apoptotic cleavage of cellular proteins",
    REACTOME_APOPTOTIC_FACTOR_MEDIATED_RESPONSE        = "Apoptotic factor-mediated response",
    REACTOME_DISEASES_OF_PROGRAMMED_CELL_DEATH         = "Diseases of programmed cell death"),

  grp("Cell death", "Extrinsic / death receptor",
    REACTOME_TNF_SIGNALING                                 = "TNF signaling",
    REACTOME_TNFR2_NON_CANONICAL_NF_KB_PATHWAY             = "TNFR2 non-canonical NF-kB pathway",
    REACTOME_CELL_DEATH_SIGNALLING_VIA_NRAGE_NRIF_AND_NADE = "Cell death signalling via NRAGE/NRIF/NADE",
    REACTOME_NRAGE_SIGNALS_DEATH_THROUGH_JNK               = "NRAGE signals death through JNK"),

  grp("Cell death", "Regulated necrosis",
    REACTOME_REGULATED_NECROSIS                = "Regulated necrosis",
    REACTOME_RIPK1_MEDIATED_REGULATED_NECROSIS = "RIPK1-mediated regulated necrosis"),

  # RITA acts by stabilising p53, so this group is the mechanistic core.
  grp("Cell death", "p53 axis",
    REACTOME_TRANSCRIPTIONAL_REGULATION_BY_TP53                  = "Transcriptional regulation by TP53",
    REACTOME_STABILIZATION_OF_P53                                = "Stabilization of p53",
    REACTOME_REGULATION_OF_TP53_ACTIVITY                         = "Regulation of TP53 activity",
    REACTOME_REGULATION_OF_TP53_ACTIVITY_THROUGH_PHOSPHORYLATION = "  ... through phosphorylation",
    REACTOME_REGULATION_OF_TP53_ACTIVITY_THROUGH_ACETYLATION     = "  ... through acetylation",
    REACTOME_REGULATION_OF_TP53_ACTIVITY_THROUGH_METHYLATION     = "  ... through methylation",
    REACTOME_REGULATION_OF_TP53_EXPRESSION_AND_DEGRADATION       = "TP53 expression and degradation",
    REACTOME_TP53_REGULATES_TRANSCRIPTION_OF_CELL_DEATH_GENES    = "TP53 -> cell death genes",
    REACTOME_TP53_REGULATES_TRANSCRIPTION_OF_GENES_INVOLVED_IN_CYTOCHROME_C_RELEASE = "TP53 -> cytochrome c release genes",
    REACTOME_TP53_REGULATES_TRANSCRIPTION_OF_CELL_CYCLE_GENES    = "TP53 -> cell cycle genes",
    REACTOME_TP53_REGULATES_TRANSCRIPTION_OF_GENES_INVOLVED_IN_G2_CELL_CYCLE_ARREST = "TP53 -> G2 arrest genes",
    REACTOME_TP53_REGULATES_TRANSCRIPTION_OF_ADDITIONAL_CELL_CYCLE_GENES_WHOSE_EXACT_ROLE_IN_THE_P53_PATHWAY_REMAIN_UNCERTAIN = "TP53 -> additional cell cycle genes",
    REACTOME_TP53_REGULATES_TRANSCRIPTION_OF_DNA_REPAIR_GENES    = "TP53 -> DNA repair genes",
    REACTOME_TP53_REGULATES_METABOLIC_GENES                      = "TP53 -> metabolic genes",
    REACTOME_G1_S_DNA_DAMAGE_CHECKPOINTS                         = "G1/S DNA damage checkpoints",
    REACTOME_G2_M_DNA_DAMAGE_CHECKPOINT                          = "G2/M DNA damage checkpoint"),

  grp("Cell death", "Senescence",
    REACTOME_CELLULAR_SENESCENCE                                          = "Cellular senescence",
    REACTOME_ONCOGENE_INDUCED_SENESCENCE                                  = "Oncogene-induced senescence",
    REACTOME_OXIDATIVE_STRESS_INDUCED_SENESCENCE                          = "Oxidative stress-induced senescence",
    REACTOME_DNA_DAMAGE_TELOMERE_STRESS_INDUCED_SENESCENCE                = "DNA damage / telomere stress senescence",
    REACTOME_SENESCENCE_ASSOCIATED_SECRETORY_PHENOTYPE_SASP               = "Senescence-associated secretory phenotype",
    REACTOME_FORMATION_OF_SENESCENCE_ASSOCIATED_HETEROCHROMATIN_FOCI_SAHF = "Senescence-associated heterochromatin foci"),

  # ---------------- domain: CELLULAR STRESS ----------------
  # The eIF2alpha node itself: two of the four eIF2alpha kinases (GCN2, PERK),
  # the ATF4 transcriptional output, and the starvation parent term.
  grp("Cellular stress", "eIF2a / integrated stress response",
    REACTOME_RESPONSE_OF_EIF2AK4_GCN2_TO_AMINO_ACID_DEFICIENCY               = "GCN2 (EIF2AK4) to amino acid deficiency",
    REACTOME_PERK_REGULATES_GENE_EXPRESSION                                  = "PERK (EIF2AK3) regulates gene expression",
    REACTOME_ATF4_ACTIVATES_GENES_IN_RESPONSE_TO_ENDOPLASMIC_RETICULUM_STRESS = "ATF4 activates genes (ER stress)",
    REACTOME_CELLULAR_RESPONSE_TO_STARVATION                                 = "Cellular response to starvation"),

  grp("Cellular stress", "ER stress / UPR",
    REACTOME_UNFOLDED_PROTEIN_RESPONSE_UPR  = "Unfolded protein response (UPR)",
    REACTOME_IRE1ALPHA_ACTIVATES_CHAPERONES = "IRE1alpha activates chaperones"),

  grp("Cellular stress", "Heat shock / HSF1",
    REACTOME_CELLULAR_RESPONSE_TO_HEAT_STRESS                = "Cellular response to heat stress",
    REACTOME_HSF1_ACTIVATION                                 = "HSF1 activation",
    REACTOME_HSF1_DEPENDENT_TRANSACTIVATION                  = "HSF1-dependent transactivation",
    REACTOME_REGULATION_OF_HSF1_MEDIATED_HEAT_SHOCK_RESPONSE = "Regulation of HSF1-mediated HSR",
    REACTOME_ATTENUATION_PHASE                               = "Attenuation phase",
    REACTOME_HSP90_CHAPERONE_CYCLE_FOR_STEROID_HORMONE_RECEPTORS_SHR_IN_THE_PRESENCE_OF_LIGAND = "HSP90 chaperone cycle (SHR)"),

  grp("Cellular stress", "Oxidative / chemical stress",
    REACTOME_CELLULAR_RESPONSE_TO_CHEMICAL_STRESS      = "Cellular response to chemical stress",
    REACTOME_DETOXIFICATION_OF_REACTIVE_OXYGEN_SPECIES = "Detoxification of reactive oxygen species",
    REACTOME_GLUTATHIONE_CONJUGATION                   = "Glutathione conjugation",
    REACTOME_FOXO_MEDIATED_TRANSCRIPTION_OF_OXIDATIVE_STRESS_METABOLIC_AND_NEURONAL_GENES = "FOXO -> oxidative stress genes"),

  grp("Cellular stress", "Hypoxia / replication stress",
    REACTOME_CELLULAR_RESPONSE_TO_HYPOXIA                        = "Cellular response to hypoxia",
    REACTOME_ACTIVATION_OF_ATR_IN_RESPONSE_TO_REPLICATION_STRESS = "ATR activation (replication stress)"),

  grp("Cellular stress", "Nutrient / energy sensing",
    REACTOME_MTOR_SIGNALLING                                  = "mTOR signalling",
    REACTOME_MTORC1_MEDIATED_SIGNALLING                       = "mTORC1-mediated signalling",
    REACTOME_AMINO_ACIDS_REGULATE_MTORC1                      = "Amino acids regulate mTORC1",
    REACTOME_ENERGY_DEPENDENT_REGULATION_OF_MTOR_BY_LKB1_AMPK  = "LKB1-AMPK regulation of mTOR",
    REACTOME_INTEGRATION_OF_ENERGY_METABOLISM                 = "Integration of energy metabolism"),

  # eIF2alpha phosphorylation shuts down cap-dependent initiation, so these are
  # the readout of the eIF2a group above, not an independent stress axis.
  grp("Cellular stress", "Translational output",
    REACTOME_EUKARYOTIC_TRANSLATION_INITIATION = "Eukaryotic translation initiation",
    REACTOME_TRANSLATION                       = "Translation",
    REACTOME_ACTIVATION_OF_THE_MRNA_UPON_BINDING_OF_THE_CAP_BINDING_COMPLEX_AND_EIFS_AND_SUBSEQUENT_BINDING_TO_43S = "mRNA activation: cap complex + eIFs -> 43S",
    REACTOME_SRP_DEPENDENT_COTRANSLATIONAL_PROTEIN_TARGETING_TO_MEMBRANE = "SRP-dependent cotranslational targeting",
    REACTOME_NONSENSE_MEDIATED_DECAY_NMD       = "Nonsense-mediated decay (NMD)"),

  grp("Cellular stress", "Proteostasis / clearance",
    REACTOME_ANTIGEN_PROCESSING_UBIQUITINATION_PROTEASOME_DEGRADATION = "Ubiquitination / proteasome degradation",
    REACTOME_AUTOPHAGY                     = "Autophagy",
    REACTOME_SELECTIVE_AUTOPHAGY           = "Selective autophagy",
    REACTOME_CHAPERONE_MEDIATED_AUTOPHAGY  = "Chaperone-mediated autophagy",
    REACTOME_LATE_ENDOSOMAL_MICROAUTOPHAGY = "Late endosomal microautophagy")
))

# One bucket per pathway is the whole point of the layout: enforce it.
dups <- curated[duplicated(pathway), unique(pathway)]
if (length(dups))
  stop("pathway assigned to more than one bucket: ", paste(dups, collapse = ", "))

# Fixed group -> colour map, shared by every panel, so "p53 axis" is the same
# colour whether you are looking at the death panel or the combined one.
# Death groups are warm, stress groups cool, which echoes the domain track.
GROUP_COLS <- c(
  "Apoptosis core"                     = "#99000D",
  "Extrinsic / death receptor"         = "#E31A1C",
  "Regulated necrosis"                 = "#FB6A4A",
  "p53 axis"                           = "#FD8D3C",
  "Senescence"                         = "#B15928",
  "eIF2a / integrated stress response" = "#08519C",
  "ER stress / UPR"                    = "#3182BD",
  "Heat shock / HSF1"                  = "#6BAED6",
  "Oxidative / chemical stress"        = "#238B45",
  "Hypoxia / replication stress"       = "#74C476",
  "Nutrient / energy sensing"          = "#6A51A3",
  "Translational output"               = "#9E9AC8",
  "Proteostasis / clearance"           = "#737373"
)
DOMAIN_COLS <- c("Cell death" = "#5D3A9B", "Cellular stress" = "#E66100")
stopifnot(all(unique(curated$group) %in% names(GROUP_COLS)),
          all(unique(curated$domain) %in% names(DOMAIN_COLS)))

# Requested but never scored by fgsea. Listed on every run so each figure says
# out loud what is missing from it; recovering these needs a GSEA re-run.
UNAVAILABLE <- list(
  "Cell death" = c(
    "REACTOME_DEATH_RECEPTOR_SIGNALLING"                = "pathways.txt spelling; MSigDB has DEATH_RECEPTOR_SIGNALING (one L), 154 genes",
    "REACTOME_TNFR1_INDUCED_NFKAPPAB_SIGNALING_PATHWAY" = "pathways.txt spelling; MSigDB has TNFR1_INDUCED_NF_KAPPA_B_SIGNALING_PATHWAY",
    "REACTOME_REGULATION_OF_TNFR1_SIGNALING"            = "absent from this MSigDB release"),
  "Cellular stress" = c(
    "REACTOME_RESPONSE_OF_EIF2AK1_HRI_TO_HEME_DEFICIENCY"    = "not in pathways.txt; testable (15 genes) if added",
    "REACTOME_MITOCHONDRIAL_UNFOLDED_PROTEIN_RESPONSE_UPRMT" = "not in pathways.txt; testable (18 genes) if added",
    "REACTOME_ATF6_ATF6_ALPHA_ACTIVATES_CHAPERONES"          = "only 12 genes, below fgsea minSize=15",
    "REACTOME_RECYCLING_OF_EIF2_GDP"                         = "only 8 genes, below fgsea minSize=15")
)

panels <- list(
  list(prefix = "D_death_panel",        domains = "Cell death",                     title = "Cell death / apoptosis panel"),
  list(prefix = "E_stress_panel",       domains = "Cellular stress",                title = "Cellular stress panel"),
  list(prefix = "F_death_stress_panel", domains = c("Cell death", "Cellular stress"), title = "Cell death and cellular stress panel")
)

# ------------------------------------------------------------------
styles <- list(
  plots  = list(cell = 10, fs = 7,  fs_row = 6.5,  fs_col = 8,  num = 7),
  poster = list(cell = 20, fs = 14, fs_row = 12.5, fs_col = 16, num = 14)
)

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
  B_peptide_in_RITA = build_block("^Reactome_DE_RITA_(.*)_vs_N1\\.tsv$",   "\\1", exclude = "WT"),
  C_peptide_in_DMSO = build_block("^Reactome_DE_DMSO_(.*)_vs_N1\\.tsv$",   "\\1", exclude = "WT")
)
block_subtitles <- c(
  A_RITA_signature  = "RITA vs DMSO (per group)",
  B_peptide_in_RITA = "tile vs vector under RITA",
  C_peptide_in_DMSO = "tile vs vector under DMSO"
)

read_gsea <- function(path) {
  if (!file.exists(path)) return(NULL)
  dt <- fread(path)
  if (!all(c("pathway", "NES", "padj") %in% colnames(dt))) return(NULL)
  dt[, .(pathway, NES, padj)]
}

# Read each block once; every panel indexes into the same named vectors.
block_vals <- list()
for (bn in names(blocks)) {
  bl <- blocks[[bn]]
  if (is.null(bl) || length(bl) < 2) next
  nes_list <- list(); padj_list <- list()
  for (lab in names(bl)) {
    dt <- read_gsea(bl[[lab]]); if (is.null(dt)) next
    nes_list[[lab]]  <- setNames(dt$NES,  dt$pathway)
    padj_list[[lab]] <- setNames(dt$padj, dt$pathway)
  }
  if (length(nes_list) >= 2) block_vals[[bn]] <- list(nes = nes_list, padj = padj_list)
}
if (length(block_vals) == 0) stop("no blocks assembled -- check ", gsea_dir)

# ONE NES colour scale for every panel and every block this script writes,
# computed over all curated pathways at once. Per-panel limits would render the
# same NES at different intensities in D vs E vs F, which breaks the whole point
# of curated panels: being able to lay them side by side and compare directly.
# The cost is that the death panel never reaches full saturation on its own.
NES_LIM <- ceiling(10 * max(abs(unlist(lapply(block_vals, function(bv)
  sapply(bv$nes, function(v) v[curated$pathway])))), na.rm = TRUE)) / 10
NES_BREAKS <- seq(-NES_LIM, NES_LIM, length.out = 101)
NES_PAL    <- colorRampPalette(c("#2166AC", "white", "#B2182B"))(100)
message("global NES colour limit: +/-", NES_LIM)

# ==================================================================
draw_panel <- function(pan) {
  message("\n===== ", pan$title, " =====")
  rows <- curated[domain %in% pan$domains]
  rows[, domain := factor(domain, levels = intersect(names(DOMAIN_COLS), unique(domain)))]
  rows[, group  := factor(group,  levels = unique(group))]

  mats <- lapply(block_vals, function(bv) list(
    nes  = `rownames<-`(sapply(bv$nes,  function(v) v[rows$pathway]), rows$pathway),
    padj = `rownames<-`(sapply(bv$padj, function(v) v[rows$pathway]), rows$pathway)))

  # Drop panel rows never scored in ANY block, so the same rows appear in A/B/C
  # and no all-grey band is carried through the figure set.
  scored <- Reduce(`|`, lapply(mats, function(m) rowSums(!is.na(m$nes)) > 0))
  rows_k <- droplevels(rows[scored])
  message(nrow(rows), " pathways requested, ", nrow(rows_k), " plotted")
  for (d in rows$pathway[!scored]) message("  not scored, dropped: ", d)
  for (dm in pan$domains) for (u in names(UNAVAILABLE[[dm]]))
    message("  not in figure: ", u, "  (", UNAVAILABLE[[dm]][[u]], ")")

  multi_domain <- nlevels(rows_k$domain) > 1
  ann_row <- if (multi_domain)
    data.frame(Group = rows_k$group, Domain = rows_k$domain, row.names = rows_k$label)
  else
    data.frame(Group = rows_k$group, row.names = rows_k$label)
  ann_cols <- list(Group  = GROUP_COLS[levels(rows_k$group)],
                   Domain = DOMAIN_COLS[levels(rows_k$domain)])

  gaps <- head(cumsum(as.integer(table(rows_k$group))), -1)
  if (multi_domain) {
    # Repeat the domain boundary so pheatmap draws a visibly wider break there
    # than between groups inside a domain.
    dom_end <- head(cumsum(as.integer(table(rows_k$domain))), -1)
    gaps <- sort(c(gaps, rep(dom_end, 2)))
  }

  for (style_name in names(styles)) {
    cfg <- styles[[style_name]]
    heat_dir <- file.path(gsea_dir, style_name, "heatmaps")
    dir.create(heat_dir, showWarnings = FALSE, recursive = TRUE)

    for (bn in names(mats)) {
      nes  <- mats[[bn]]$nes[scored, , drop = FALSE]
      padj <- mats[[bn]]$padj[scored, , drop = FALSE]
      rownames(nes) <- rows_k$label; rownames(padj) <- rows_k$label
      star  <- ifelse(!is.na(padj) & padj < padj_cutoff, "*", "")
      n_sig <- sum(star == "*")

      pheatmap(
        nes, color = NES_PAL, breaks = NES_BREAKS,
        cluster_rows = FALSE, cluster_cols = FALSE,      # curated order, both axes
        gaps_row = gaps,
        annotation_row = ann_row,
        annotation_colors = ann_cols,
        annotation_names_row = FALSE,
        cellwidth = 2 * cfg$cell, cellheight = cfg$cell,
        display_numbers = star, number_color = "black", fontsize_number = cfg$num,
        na_col = "grey90",
        # Keep the second line short: pheatmap centres `main` on the heatmap
        # body, so a line wider than the body is clipped at the left page edge.
        main = paste0(pan$title, ": ", block_subtitles[[bn]], "\n",
                      n_sig, " cells padj<", padj_cutoff, " (*)"),
        fontsize = cfg$fs, fontsize_row = cfg$fs_row, fontsize_col = cfg$fs_col,
        angle_col = 0, border_color = NA,
        filename = file.path(heat_dir, paste0(pan$prefix, "_", bn, ".pdf"))
      )

      # Numbers behind the figure, so any cell can be checked.
      out <- data.table(domain = as.character(rows_k$domain),
                        group = as.character(rows_k$group),
                        pathway = rows_k$pathway, label = rows_k$label)
      for (cl in colnames(nes)) {
        out[[paste0("NES_",  cl)]] <- nes[, cl]
        out[[paste0("padj_", cl)]] <- padj[, cl]
      }
      fwrite(out, file.path(heat_dir, paste0(pan$prefix, "_", bn, "_values.tsv")), sep = "\t")
    }
    message("-> ", heat_dir)
  }
}

for (pan in panels) draw_panel(pan)
message("\nDone.")
