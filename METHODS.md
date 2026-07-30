# BRB-seq data analysis — Methods

## Summary paragraph (manuscript form)

Bulk RNA barcoding and sequencing (BRB-seq) was performed on a single 96-well
library comprising parental (WT) cells, empty-vector control cells (N1), and
nine viral peptide tile lines (T1, T4, T5, T6, T7, T9, T10, A2, B6), each treated
with either DMSO or RITA. The library was sequenced paired-end, with read 1
carrying the 14-nt well-specific sample barcode followed by a 14-nt unique
molecular identifier (UMI) and read 2 carrying the 150-nt cDNA insert. Raw read
quality was assessed with FastQC v0.12.1.

Reads were demultiplexed, aligned, and quantified in a single pass with STARsolo
(STAR v2.7.11b) against the Ensembl GRCh38 primary assembly with the Ensembl
release 110 GTF annotation (index built with `--sjdbOverhang 99`). STARsolo was
run in `CB_UMI_Simple` mode (`--soloCBstart 1 --soloCBlen 14 --soloUMIstart 15
--soloUMIlen 14`) against a whitelist of the 96 well barcodes, with forward
strandedness (`--soloStrand Forward`), no cell calling (`--soloCellFilter None`),
and gene-level features (`--soloFeatures Gene`). Only uniquely mapping reads were
retained (`--outFilterMultimapNmax 1`); 954,871,778 read pairs were processed and
81.1% mapped uniquely. UMIs were collapsed allowing one mismatch
(`--soloUMIdedup 1MM_All`), and the resulting UMI-deduplicated gene × barcode
matrix was subset to the 96 expected well barcodes and relabeled with sample
identifiers, giving a 62,754 gene × 96 sample count matrix.

Genes with fewer than 10 total UMI counts across all samples were removed,
leaving 20,402 genes. Counts per million (CPM) were computed by dividing each
gene's count by its sample's total counts and scaling by 10^6; CPM values are
provided for visualization only and were not used for statistical testing.

Differential expression was performed on raw UMI counts with DESeq2 v1.50.2 in
R v4.5.3. Each contrast was fit as an independent two-group model
(`~ group`) restricted to the relevant samples, with genes re-filtered to ≥10
total counts within that contrast, size factors estimated using the `poscounts`
estimator (robust to the zero-inflation typical of 3'-end BRB-seq data), and
significance assessed by the Wald test with Benjamini–Hochberg correction.
Given the modest replication of the peptide tiles (n = 4 per condition, versus
n = 6 for WT and N1), genes were called differentially expressed at
adjusted p < 0.25 and |log2 fold change| ≥ 0.5. Three families of contrasts were
run: (i) RITA versus DMSO within each cell line, defining the RITA response;
(ii) each peptide tile versus the empty-vector control N1 within each treatment,
which isolates the peptide effect from the vector/transduction effect; and
(iii) WT versus N1, which quantifies the vector effect itself. N1, not WT, was
used as the reference for all peptide comparisons.

Pathway-level analysis used preranked gene set enrichment analysis with fgsea
v1.36.2 (multilevel algorithm). Ensembl gene IDs were mapped to HGNC symbols with
org.Hs.eg.db v3.22.0, and genes were ranked over the full tested gene list by the
DESeq2 Wald statistic. Gene sets were the Reactome collection retrieved through
msigdbr v26.1.0 (MSigDB C2, CP:REACTOME), restricted to a curated set of 762
pathways relevant to p53 signaling, apoptosis, cell cycle, and stress response,
and further limited to sets of 15–500 detected genes. To avoid interpreting
enrichment from underpowered contrasts, GSEA was run only for comparisons with at
least 20 differentially expressed genes at the thresholds above; pathways were
considered significant at adjusted p < 0.05. Finally, per-tile enrichment profiles
under DMSO and under RITA were compared (shared, condition-specific, and Spearman
correlation of normalized enrichment scores) to distinguish constitutive peptide
effects from RITA-dependent ones.

---

## GEO "data processing" fields (bullet form)

- **Base calling / demultiplexing:** Well-level demultiplexing was performed by
  STARsolo using the 14-nt sample barcode on read 1 against a whitelist of the 96
  plate barcodes; no separate demultiplexing step was used.
- **Read QC:** FastQC v0.12.1.
- **Alignment:** STAR v2.7.11b (STARsolo), `--soloType CB_UMI_Simple`,
  `--soloCBstart 1 --soloCBlen 14 --soloUMIstart 15 --soloUMIlen 14`,
  `--soloStrand Forward`, `--soloCellFilter None`, `--soloFeatures Gene`,
  `--outFilterMultimapNmax 1` (unique alignments only),
  `--soloUMIdedup 1MM_All`.
- **Genome build / annotation:** Ensembl *Homo sapiens* GRCh38 primary assembly;
  Ensembl release 110 GTF; STAR index built with `--sjdbOverhang 99`.
- **Quantification:** Gene-level UMI counts from the STARsolo
  `Solo.out/Gene/raw` matrix (`umiDedup-1MM_All.mtx`), subset to the 96 expected
  well barcodes.
- **Filtering / normalization:** Genes with <10 total UMI counts across all
  samples removed (62,754 → 20,402 genes). CPM = per-sample counts / sample total
  × 10^6 (supplied for visualization; DE used raw counts).
- **Differential expression:** DESeq2 v1.50.2 (R v4.5.3), per-contrast two-group
  design, `poscounts` size factors, Wald test, Benjamini–Hochberg FDR; called at
  padj < 0.25 and |log2FC| ≥ 0.5. Peptide tiles were compared to the empty-vector
  control (N1).
- **Pathway enrichment:** fgsea v1.36.2 (multilevel) preranked on the DESeq2 Wald
  statistic; Reactome gene sets via msigdbr v26.1.0 (C2, CP:REACTOME) restricted
  to 762 curated pathways; `minSize = 15`, `maxSize = 500`; run only for contrasts
  with ≥20 DE genes; significance at padj < 0.05.
- **Genome build:** GRCh38 (Ensembl release 110).
- **Supplementary files format and content:**
  - `viral_peptides.count_matrix.tsv` — tab-delimited raw UMI count matrix,
    62,754 genes × 96 samples; columns 1–2 are `gene_id` (Ensembl) and
    `gene_name`, remaining columns are sample IDs matching `sample_metadata.tsv`.
  - `viral_peptides.cpm_matrix.tsv` — tab-delimited CPM matrix for the 20,402
    filtered genes, same gene annotation columns; sample columns are labeled
    `<condition>_<peptide>_<well>`.
  - `sample_metadata.tsv` — per-sample table of library, sample group, peptide,
    treatment condition, plate well, and well barcode sequence.

---

## Notes / to fill in before submission

- Sequencing instrument and run configuration are not recorded in the analysis
  outputs and must be added to the GEO submission (STAR reports an average input
  cDNA read length of 150 nt).
- Wet-lab details (cell line, transduction, RITA concentration and treatment
  duration, library prep kit) are outside the scope of this data-analysis
  methods text and should be described in the experimental methods.
