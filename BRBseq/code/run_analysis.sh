#!/bin/bash
#$ -N vp_analysis
#$ -cwd
#$ -o ../logs/analysis.out
#$ -e ../logs/analysis.err
#$ -l h_rt=04:00:00
#$ -l h_vmem=32G
#$ -pe smp 4
set -euo pipefail

# Downstream analysis for the viral peptide BRB-seq study.
# Assumes the count matrix and metadata already exist under ../results.
#   01 -> DESeq2: RITA signature + peptide-vs-vector (N1) per condition
#   03 -> fgsea Reactome enrichment on every DE result
#   04 -> per-tile DMSO-vs-RITA enrichment comparison (wired vs RITA-dependent)
#   05 -> dotplots per comparison + cross-comparison NES heatmaps

source /projectnb/vcres/myousry/miniconda3/etc/profile.d/conda.sh
conda activate brbseq

cd "$(dirname "$0")"

echo "[$(date)] 01_run_deseq2.r"
Rscript 01_run_deseq2.r

echo "[$(date)] 03_gsea.r"
Rscript 03_gsea.r

echo "[$(date)] 04_compare_dmso_rita.r"
Rscript 04_compare_dmso_rita.r

echo "[$(date)] 05_plot_gsea.r"
Rscript 05_plot_gsea.r

echo "[$(date)] 06_plot_volcanoes.r"
Rscript 06_plot_volcanoes.r

echo "[$(date)] 07_publication_figs.r"
Rscript 07_publication_figs.r

echo "[$(date)] 08_plot_deg_heatmaps.r"
Rscript 08_plot_deg_heatmaps.r

echo "[$(date)] Analysis complete."
