#!/bin/bash
set -euo pipefail

# ============================================================
# BRB-seq human-only pipeline for the viral peptide study
# - processes one sequencing library / lane:
#     VPBRB_1.fq.gz and VPBRB_2.fq.gz -> viral_peptides
# - aligns the library with STARsolo
# - reads sample/well assignments from metadata.tsv
# - maps wells to barcode sequences using barcodes_96_V5D.tsv
# - parses sample labels such as WT_DMSO and N1_RITA into peptide/condition
# - outputs:
#     1) per-library filtered count matrix
#     2) combined filtered count matrix
#     3) final sample metadata table
# ============================================================

# -------------------- CONFIG --------------------
THREADS=12
RUN_FASTQC=1                      # 1 = run FastQC, 0 = skip
STAR_OVERWRITE=0                  # 1 = rerun STAR even if outputs exist
INDEX_OVERWRITE=0                 # 1 = rebuild STAR index even if it exists
SJDB_OVERHANG=99                  # use read length - 1 for your cDNA read

# Resolve script location so paths work no matter where you run from
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

DATA_DIR="$PROJECT_DIR/data"
FASTQ_DIR="$DATA_DIR/fasta"
LIBRARY_NAME="viral_peptides"
FASTQ_PREFIX="VPBRB"

# Input files
METADATA_TSV="$DATA_DIR/metadata/metadata.tsv"
BARCODE_MAP_TSV="$DATA_DIR/metadata/barcodes_96_V5D.tsv"
BARCODE_WHITELIST="$DATA_DIR/metadata/whitelist.txt"

# Human reference only
HUMAN_FA="$PROJECT_DIR/genomes/human/Homo_sapiens.GRCh38.dna.primary_assembly.fa"
HUMAN_GTF="$PROJECT_DIR/genomes/human/Homo_sapiens.GRCh38.110.gtf"
GENOME_DIR="$PROJECT_DIR/genomes/human/STAR_index"

# Output dirs
WORK_DIR="$PROJECT_DIR/workdir"
ALIGN_DIR="$WORK_DIR/aligned"
QC_DIR="$PROJECT_DIR/results/qc"
MATRIX_DIR="$PROJECT_DIR/results/matrix"
COMBINED_FASTQ_DIR="$WORK_DIR/combined_fastq"
META_OUT_DIR="$PROJECT_DIR/results/metadata"
LOG_DIR="$PROJECT_DIR/logs"

mkdir -p \
    "$WORK_DIR" \
    "$COMBINED_FASTQ_DIR" \
    "$ALIGN_DIR" \
    "$QC_DIR" \
    "$MATRIX_DIR/per_library" \
    "$META_OUT_DIR" \
    "$LOG_DIR" \
    "$GENOME_DIR"

# -------------------- CHECK INPUTS --------------------
echo "[INFO] Checking required inputs"

for f in "$METADATA_TSV" "$BARCODE_MAP_TSV" "$HUMAN_FA" "$HUMAN_GTF"; do
    if [[ ! -f "$f" ]]; then
        echo "[ERROR] Missing required file: $f" >&2
        exit 1
    fi
done

if [[ ! -d "$FASTQ_DIR" ]]; then
    echo "[ERROR] FASTQ_DIR does not exist: $FASTQ_DIR" >&2
    exit 1
fi

# If whitelist does not exist, derive it from barcode map second column
if [[ ! -f "$BARCODE_WHITELIST" ]]; then
    echo "[INFO] whitelist.txt not found. Building from barcode column of $BARCODE_MAP_TSV"
    python3 - <<PY
import csv
from pathlib import Path

barcode_map = Path(r"$BARCODE_MAP_TSV")
whitelist = Path(r"$BARCODE_WHITELIST")

with barcode_map.open() as fh:
    reader = csv.reader(fh, delimiter="\t")
    rows = [row for row in reader if row and any(x.strip() for x in row)]

if len(rows) < 2:
    raise SystemExit(f"Barcode map looks empty or malformed: {barcode_map}")

barcodes = []
for row in rows[1:]:
    if len(row) < 2:
        continue
    bc = row[1].strip()
    if bc:
        barcodes.append(bc)

if not barcodes:
    raise SystemExit(f"No barcodes parsed from {barcode_map}")

with whitelist.open("w") as out:
    for bc in barcodes:
        out.write(bc + "\n")
PY
fi

if [[ ! -f "$BARCODE_WHITELIST" ]]; then
    echo "[ERROR] Could not create/find whitelist: $BARCODE_WHITELIST" >&2
    exit 1
fi

# -------------------- PREP SAMPLE SHEET --------------------
echo "[INFO] Building sample sheet from metadata.tsv"

SAMPLE_SHEET="$META_OUT_DIR/sample_sheet.tsv"

python3 - <<PY
import csv
import re
import sys
from pathlib import Path

metadata_tsv = Path(r"$METADATA_TSV")
out_tsv = Path(r"$SAMPLE_SHEET")

barcode_map_tsv = Path(r"$BARCODE_MAP_TSV")
library_name = r"$LIBRARY_NAME"


def normalize_well(well):
    well = well.strip().upper()
    if not well:
        return well
    row = well[0]
    col = well[1:]
    if col.isdigit():
        return f"{row}{int(col):02d}"
    return well


# -------- read barcode map --------
well_to_barcode = {}
with barcode_map_tsv.open() as fh:
    reader = csv.reader(fh, delimiter="\t")
    rows = [row for row in reader if row and any(x.strip() for x in row)]

if len(rows) < 2:
    raise SystemExit(f"Barcode map looks empty or malformed: {barcode_map_tsv}")

for row in rows[1:]:
    if len(row) < 2:
        continue
    well = normalize_well(row[0])
    barcode = row[1].strip()
    if well and barcode:
        well_to_barcode[well] = barcode

if not well_to_barcode:
    raise SystemExit(f"No well-to-barcode mappings parsed from {barcode_map_tsv}")

# -------- read metadata --------
kept = []

with metadata_tsv.open() as fh:
    reader = csv.DictReader(fh, delimiter="\t")
    required = {"well", "sample"}
    missing = required - set(reader.fieldnames or [])
    if missing:
        raise SystemExit(f"Missing required metadata columns: {sorted(missing)}")

    for row in reader:
        well_raw = row["well"].strip()
        well_norm = normalize_well(well_raw)
        sample = row["sample"].strip()

        if not well_raw or not sample:
            continue

        if well_norm not in well_to_barcode:
            raise SystemExit(
                f"Well {well_raw} normalized to {well_norm} was not found in barcode map {barcode_map_tsv}"
            )

        barcode_seq = well_to_barcode[well_norm]

        if "_" not in sample:
            raise SystemExit(
                f"Sample {sample!r} does not contain a condition suffix like _DMSO or _RITA"
            )

        peptide, condition = sample.rsplit("_", 1)
        condition = condition.upper()
        if condition not in {"DMSO", "RITA"}:
            raise SystemExit(
                f"Sample {sample!r} has condition {condition!r}; expected DMSO or RITA"
            )

        kept.append({
            "sample_id": f"{library_name}_{sample}_{well_raw}",
            "library": library_name,
            "sample": sample,
            "peptide": peptide,
            "condition": condition,
            "well": well_raw,
            "well_barcode_map": well_norm,
            "barcode_seq": barcode_seq,
        })

if not kept:
    raise SystemExit("No samples found in clean metadata.")

with out_tsv.open("w", newline="") as out:
    writer = csv.DictWriter(
        out,
        fieldnames=["sample_id", "library", "sample", "peptide", "condition", "well", "well_barcode_map", "barcode_seq"],
        delimiter="\t"
    )
    writer.writeheader()
    writer.writerows(kept)

print(f"Wrote sample sheet: {out_tsv}")
print(f"Kept {len(kept)} samples.")
PY

# -------------------- BUILD STAR INDEX --------------------

if [[ "$INDEX_OVERWRITE" -eq 1 || ! -f "$GENOME_DIR/SA" ]]; then
    echo "[INFO] Building STAR index at $GENOME_DIR"
    rm -rf "$GENOME_DIR"
    mkdir -p "$GENOME_DIR"

    STAR \
      --runMode genomeGenerate \
      --genomeDir "$GENOME_DIR" \
      --genomeFastaFiles "$HUMAN_FA" \
      --sjdbGTFfile "$HUMAN_GTF" \
      --sjdbOverhang "$SJDB_OVERHANG" \
      --runThreadN "$THREADS" \
      > "$LOG_DIR/star_genome_generate.log" 2>&1
else
    echo "[INFO] STAR index already exists: $GENOME_DIR"
fi

# -------------------- STAGE SINGLE SEQUENCING LIBRARY --------------------
echo "[INFO] Staging single sequencing library"

LIBRARIES=("$LIBRARY_NAME")

r1="$FASTQ_DIR/${FASTQ_PREFIX}_1.fq.gz"
r2="$FASTQ_DIR/${FASTQ_PREFIX}_2.fq.gz"

if [[ ! -f "$r1" || ! -f "$r2" ]]; then
    echo "[ERROR] Missing FASTQ pair for $FASTQ_PREFIX:" >&2
    echo "[ERROR]   $r1" >&2
    echo "[ERROR]   $r2" >&2
    exit 1
fi

combined_r1="$COMBINED_FASTQ_DIR/${LIBRARY_NAME}_1.fastq.gz"
combined_r2="$COMBINED_FASTQ_DIR/${LIBRARY_NAME}_2.fastq.gz"

if [[ "$STAR_OVERWRITE" -eq 1 || ! -e "$combined_r1" || ! -e "$combined_r2" ]]; then
    echo "[INFO] Linking FASTQs for $LIBRARY_NAME"
    rm -f "$combined_r1" "$combined_r2"
    ln -s "$r1" "$combined_r1"
    ln -s "$r2" "$combined_r2"
else
    echo "[INFO] Staged FASTQs already exist for $LIBRARY_NAME"
fi

# -------------------- ALIGN EACH LIBRARY --------------------
for library in "${LIBRARIES[@]}"; do
    R1="$COMBINED_FASTQ_DIR/${library}_1.fastq.gz"
    R2="$COMBINED_FASTQ_DIR/${library}_2.fastq.gz"

    if [[ ! -f "$R1" || ! -f "$R2" ]]; then
        echo "[WARNING] Missing combined FASTQ pair for $library, skipping"
        continue
    fi

    # Only process libraries that appear in the sample sheet
    n_keep=$(awk -F'\t' -v lib="$library" 'NR>1 && $2==lib {n++} END{print n+0}' "$SAMPLE_SHEET")
    if [[ "$n_keep" -eq 0 ]]; then
        echo "[INFO] No samples for $library, skipping alignment"
        continue
    fi

    echo
    echo "[INFO] =================================================="
    echo "[INFO] Processing library: $library"
    echo "[INFO] Samples kept for this library: $n_keep"
    echo "[INFO] =================================================="

    LIB_ALIGN_DIR="$ALIGN_DIR/$library"
    mkdir -p "$LIB_ALIGN_DIR"

    if [[ "$RUN_FASTQC" -eq 1 ]]; then
        echo "[INFO] Running FastQC for $library"
        fastqc --outdir "$QC_DIR" "$R1" "$R2" > "$LOG_DIR/${library}.fastqc.log" 2>&1
    fi

    SOLO_DONE="$LIB_ALIGN_DIR/Solo.out/Gene/raw/barcodes.tsv"
    if [[ "$STAR_OVERWRITE" -eq 1 || ! -f "$SOLO_DONE" ]]; then
        echo "[INFO] Running STARsolo for $library"

        rm -rf "$LIB_ALIGN_DIR"
        mkdir -p "$LIB_ALIGN_DIR"

        STAR \
          --runMode alignReads \
          --genomeDir "$GENOME_DIR" \
          --readFilesIn "$R2" "$R1" \
          --readFilesCommand zcat \
          --outFileNamePrefix "$LIB_ALIGN_DIR/" \
          --runThreadN "$THREADS" \
          --outSAMtype BAM SortedByCoordinate \
          --outSAMunmapped Within \
          --outSAMmapqUnique 60 \
          --outBAMsortingThreadN "$THREADS" \
          --soloType CB_UMI_Simple \
          --soloCBstart 1 --soloCBlen 14 \
          --soloUMIstart 15 --soloUMIlen 14 \
          --soloCBwhitelist "$BARCODE_WHITELIST" \
          --soloStrand Forward \
          --soloCellFilter None \
          --soloUMIdedup NoDedup 1MM_All \
          --soloBarcodeReadLength 0 \
          --soloFeatures Gene \
          --quantMode GeneCounts \
          --outSAMattributes NH HI nM AS CR UR CB UB GX GN sS sQ sM \
          --outFilterMultimapNmax 1 \
          > "$LOG_DIR/${library}.star.log" 2>&1
    else
        echo "[INFO] STARsolo output already exists for $library"
    fi

    echo "[INFO] Converting and filtering matrix for $library"

    Rscript - <<EOF
library(data.table)
library(Matrix)

library_name <- "$library"
sample_sheet <- fread("$SAMPLE_SHEET", sep="\t", header=TRUE, data.table=FALSE, stringsAsFactors=FALSE)
sample_sheet <- sample_sheet[sample_sheet\$library == library_name, , drop=FALSE]

if (nrow(sample_sheet) == 0) {
    stop("No samples for library: ", library_name)
}

matrix_dir <- file.path("$LIB_ALIGN_DIR", "Solo.out", "Gene", "raw")
mtx_file <- file.path(matrix_dir, "umiDedup-1MM_All.mtx")
if (!file.exists(mtx_file)) {
    stop("Missing MTX file: ", mtx_file)
}

features_file <- file.path(matrix_dir, "features.tsv")
barcodes_file <- file.path(matrix_dir, "barcodes.tsv")

mat <- readMM(mtx_file)
features <- fread(features_file, header=FALSE, sep="\t", data.table=FALSE, stringsAsFactors=FALSE)
barcodes <- fread(barcodes_file, header=FALSE, sep="\t", data.table=FALSE, stringsAsFactors=FALSE)

barcode_vec <- as.character(barcodes[[1]])

if (ncol(features) >= 2) {
    gene_id <- as.character(features[[1]])
    gene_name <- as.character(features[[2]])
} else {
    gene_id <- as.character(features[[1]])
    gene_name <- gene_id
}

keep_idx <- match(sample_sheet\$barcode_seq, barcode_vec)

if (any(is.na(keep_idx))) {
    missing_bcs <- sample_sheet\$barcode_seq[is.na(keep_idx)]
    stop(
        "Some barcodes from sample sheet were not found in STARsolo barcodes.tsv for ",
        library_name, ": ",
        paste(missing_bcs, collapse=", ")
    )
}

sub_mat <- mat[, keep_idx, drop=FALSE]
colnames(sub_mat) <- sample_sheet\$sample_id
rownames(sub_mat) <- gene_id

dense_mat <- as.matrix(sub_mat)

counts_dt <- data.table(
    gene_id = gene_id,
    gene_name = gene_name
)
counts_dt <- cbind(counts_dt, as.data.table(dense_mat, keep.rownames=FALSE))

counts_out <- file.path("$MATRIX_DIR", "per_library", paste0(library_name, ".filtered_counts.tsv"))
fwrite(counts_dt, file=counts_out, sep="\t", quote=FALSE)
EOF

done

# -------------------- MERGE ALL FILTERED MATRICES --------------------
echo
echo "[INFO] Merging per-library matrices"

Rscript - <<EOF
library(data.table)

matrix_files <- Sys.glob(file.path("$MATRIX_DIR", "per_library", "*.filtered_counts.tsv"))
if (length(matrix_files) == 0) {
    stop("No per-library filtered count matrices found.")
}

merged <- NULL

for (f in matrix_files) {
    dt <- fread(f, sep="\t", header=TRUE, data.table=FALSE, stringsAsFactors=FALSE)

    if (!all(c("gene_id", "gene_name") %in% colnames(dt))) {
        stop("Missing gene_id/gene_name in: ", f)
    }

    if (is.null(merged)) {
        merged <- dt
    } else {
        merged <- merge(
            merged,
            dt,
            by = c("gene_id", "gene_name"),
            all = TRUE,
            sort = FALSE
        )
    }
}

# replace NA in count columns with 0
count_cols <- setdiff(colnames(merged), c("gene_id", "gene_name"))
for (cc in count_cols) {
    merged[[cc]][is.na(merged[[cc]])] <- 0
}

# write full matrix
full_out <- file.path("$MATRIX_DIR", "all_samples.filtered_counts.tsv")
fwrite(merged, file=full_out, sep="\t", quote=FALSE)
EOF



# -------------------- COPY FINAL SAMPLE METADATA --------------------
cp "$SAMPLE_SHEET" "$META_OUT_DIR/final_sample_metadata.tsv"

echo
echo "[INFO] DONE"
echo "[INFO] Final sample metadata:          $META_OUT_DIR/final_sample_metadata.tsv"
echo "[INFO] Staged FASTQs:                  $COMBINED_FASTQ_DIR/"
echo "[INFO] Per-library count matrices:      $MATRIX_DIR/per_library/"
echo "[INFO] Combined count matrix:           $MATRIX_DIR/all_samples.filtered_counts.tsv"
echo "[INFO] STAR logs:                       $LOG_DIR/"
