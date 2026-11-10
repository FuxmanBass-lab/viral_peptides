#!/bin/bash
#$ -N SLiMProb_all_peptides
#$ -cwd
#$ -j y
#$ -o slimprob.$JOB_ID.log
#$ -V
#$ -l h_rt=48:00:00
#$ -l h_vmem=16G
#$ -pe smp 4

echo "=============================="
echo "SLiMProb job started"
echo "Job ID: $JOB_ID"
echo "Host: $(hostname)"
echo "Start time: $(date)"
echo "Working directory: $(pwd)"
echo "=============================="

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SLIMS_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
SLIMSUITE_PATH="${SLIMSUITE_PATH:-$SLIMS_DIR/SLiMSuite}"
export SLIMSUITE_PATH
SLIMPROB="$SLIMSUITE_PATH/tools/slimprob.py"
SEQIN="$SLIMS_DIR/Data/all_peps_fasta.csv"
MOTIFS="$SLIMS_DIR/Data/elm2019.motifs"
RESDIR="$SLIMS_DIR/Results"

if [[ ! -f "$SLIMPROB" ]]; then
    echo "SLiMProb not found at $SLIMPROB. Run setup_slims_suite.sh or set SLIMSUITE_PATH."
    exit 2
fi

# Load modules if required (comment out if not needed)
# module load python/3.9

# Sanity checks
echo "Checking inputs..."
ls -lh "$SEQIN" || exit 1
ls -lh "$MOTIFS" || exit 1
mkdir -p "$RESDIR" || exit 1

echo "Inputs OK"
echo

# Run SLiMProb
echo "Running SLiMProb..."
python "$SLIMPROB" \
    seqin="$SEQIN" \
    motifs="$MOTIFS" \
    goodmotif=* \
    resdir="$RESDIR" \
    resfile=all_peptides_slimprob_summary.csv \
    runid=all_peptides_run_1 \
    slimchance=T \
    v=2 \
    force=T \
    i=-1 \
    masking=F \
    efilter=F \
    maxsize=0 \
    WallTime=24 \
    logtime=T

EXIT_CODE=$?

echo
echo "=============================="
echo "SLiMProb finished"
echo "End time: $(date)"
echo "Exit code: $EXIT_CODE"
echo "=============================="

exit $EXIT_CODE
