# Viral peptides — BRB-seq analysis

Bulk RNA barcoding and sequencing (BRB-seq) analysis of nine viral peptide tiles
tested for their ability to modulate the transcriptional response to **RITA**, a
p53 activator. The central question is whether any peptide dampens the
RITA-induced apoptotic / p53 program, and whether such effects are constitutive
("wired") or appear only when RITA is present.

This repository contains the **analysis code and derived results**. Raw
sequencing data and the full count matrices are deposited at GEO (see
[Data availability](#data-availability)).

---

## Experimental design

A single BRB-seq library across one 96-well plate. Every group was treated with
either **DMSO** (vehicle) or **RITA**.

| Group | Role | Replicates per condition |
|---|---|---|
| `WT` | parental cells | 6 |
| `N1` | empty-vector control | 6 |
| `T1, T4, T5, T6, T7, T9, T10, A2, B6` | viral peptide tiles | 4 |

**Reference choice matters here.** Peptide tiles are compared against the
empty-vector control `N1`, *not* against `WT`. This isolates the peptide effect
from the vector/transduction effect; `WT` vs `N1` then measures the vector effect
on its own.

Four blocks of comparisons are run:

| Block | Contrast | Question |
|---|---|---|
| **A** | RITA vs DMSO, within each group | What is the RITA signature? |
| **B** | each tile vs `N1`, under RITA | Does the peptide alter the drug response? |
| **C** | each tile vs `N1`, under DMSO | Does the peptide act at baseline? |
| **D** | B vs C enrichment, per tile | Wired, or RITA-dependent? |

---

## Repository layout

```
code/                     analysis pipeline (see below)
data/
  metadata/               plate map, 96 well barcodes, STARsolo whitelist
  reactome/               762 curated Reactome pathway names
results/
  metadata/               final per-sample sheet used by the analysis
  qc/                     FastQC reports
  deseq2/
    deseq2_comparison_summary.tsv    DE gene counts, all 31 comparisons
    metadata_used.tsv                samples entering the models
    plots/                           volcanoes, scatters, DEG heatmaps
  gsea/
    reactome/
      *.tsv               fgsea results per comparison
      plots/              dotplots, NES heatmaps, scatters
    dmso_vs_rita/         Block D tables, NES scatters, tile_wiring_summary.tsv
METHODS.md                methods text + GEO "data processing" fields
environment.yml           curated dependencies (pinned)
environment.full.yml      complete 533-package environment export
```

## Pipeline

### 1. Preprocessing — `code/00_brb_seq_pipeline.sh`

Demultiplexes, aligns, and quantifies in one STARsolo pass.

- **Input:** paired FASTQ. Read 1 = 14 nt well barcode + 14 nt UMI; read 2 = 150 nt cDNA.
- **Reference:** Ensembl GRCh38 primary assembly, release 110 GTF (`--sjdbOverhang 99`).
- **STARsolo:** `CB_UMI_Simple`, forward-stranded, 96-barcode whitelist, no cell
  filtering, gene-level features, unique alignments only, UMIs collapsed at 1 mismatch.
- **Output:** `results/matrix/all_samples.filtered_counts.tsv` — 62,754 genes × 96 samples.

Run on an SGE cluster via `code/run.sh` (12 cores, 64 GB, 12 h).

### 2. Downstream analysis — `code/run_analysis.sh`

Assumes the count matrix and sample sheet already exist.

| Script | Purpose |
|---|---|
| `01_run_deseq2.r` | DESeq2 for all four blocks; writes DE tables + volcanoes |
| `03_gsea.r` | preranked fgsea on the Wald statistic vs curated Reactome sets |
| `04_compare_dmso_rita.r` | Block D: per-tile DMSO vs RITA enrichment concordance |
| `05_plot_gsea.r` | dotplots per comparison, cross-tile NES heatmaps |
| `06_plot_volcanoes.r` | standalone volcano re-plotter |
| `07_publication_figs.r` | manuscript figures (data-driven pathway selection) |
| `08_plot_deg_heatmaps.r` | DE gene heatmaps |
| `09_curated_panel_heatmaps.r` | fixed biology-driven pathway panels (not auto-selected) |
| `10_scatter_drug_vs_peptide.r` | drug effect vs peptide effect scatters |

> Scripts `09` and `10` are not part of `run_analysis.sh`; run them individually
> after the main pipeline. `10_scatter_drug_vs_peptide.r` documents a
> shared-sample correlation bias in its header — **read that note before quoting
> any correlation coefficient from it.**

**Figure variants.** Scripts `07`–`10` emit every figure in two styles, written to
sibling directories named after the style: `plots/` (compact, manuscript-styled)
and `poster/` (large fonts). Scripts `01`, `05` and `06` additionally write quick
draft figures to `draft/`. Only `plots/` is tracked here; `poster/` and `draft/`
are gitignored and regenerate on a re-run.

### Statistical thresholds

- **DE:** DESeq2, `poscounts` size factors, Wald test, BH correction.
  Called at `padj < 0.25` and `|log2FC| >= 0.5`.
- **Enrichment:** fgsea multilevel, gene sets of 15–500 genes, `padj < 0.05`.
  Only run for comparisons with ≥ 20 DE genes.

> The permissive 0.25 FDR is a deliberate concession to the tiles' n = 4
> replication (controls have n = 6). **Treat tile DE counts as relative, not
> absolute.**

## Reproducing

```bash
conda env create -f environment.yml
conda activate brbseq

# preprocessing — needs raw FASTQ + a built STAR index (not in this repo)
bash code/00_brb_seq_pipeline.sh

# downstream — needs only the count matrix and sample sheet
cd code && bash run_analysis.sh
```

Both `code/run.sh` and `code/run_analysis.sh` hardcode a cluster-specific conda
path (`/projectnb/vcres/...`); edit that line for your system.

## Requirements

STAR 2.7.11b · FastQC 0.12.1 · R 4.5.3 · DESeq2 1.50.2 · fgsea 1.36.2 ·
msigdbr 26.1.0 · org.Hs.eg.db 3.22.0. Full pins in `environment.yml`.

Preprocessing needs ~64 GB RAM and ~150 GB free disk for the STAR index and
alignments.

## Data availability

Not in this repository, by design — raw and intermediate data total ~401 GB.

| Data | Location |
|---|---|
| Raw FASTQ | GEO accession `GSEXXXXXX` *(pending)* |
| Raw UMI count matrix (62,754 × 96) | GEO supplementary file |
| CPM matrix (20,402 filtered genes) | GEO supplementary file |
| Per-comparison DESeq2 tables | regenerate with `01_run_deseq2.r` |
| GRCh38 genome + STAR index | Ensembl release 110 |

`METHODS.md` contains the GEO-ready data-processing description.

## License

MIT — see [LICENSE](LICENSE).
