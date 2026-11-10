#!/bin/bash

echo "=============================="
echo "SLiMProb job started"
echo "Host: $(hostname)"
echo "Start time: $(date)"
echo "Working directory: $(pwd)"
echo "=============================="


SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SLIMS_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
SLIMSUITE_PATH="${SLIMSUITE_PATH:-$SLIMS_DIR/SLiMSuite}"
export SLIMSUITE_PATH
SLIMPROB="$SLIMSUITE_PATH/tools/slimprob.py"
SEQIN="${SLIMPROB_SEQIN:-$SLIMS_DIR/Data/all_peps_fasta.csv}"
MOTIFS="${SLIMPROB_MOTIFS:-$SLIMS_DIR/Data/elm2019.motifs}"
RESDIR="${SLIMPROB_RESDIR:-$SLIMS_DIR/Results}"
RESFILE="${SLIMPROB_RESFILE:-all_peptides_slimprob_summary.csv}"
RUNID="${SLIMPROB_RUNID:-all_peptides_run_1}"
PYTHON_EXECUTABLE="${SLIMPROB_PYTHON:-python}"
VERBOSITY="${SLIMPROB_VERBOSITY:-0}"
WALLTIME="${SLIMPROB_WALLTIME:-24}"

# Sanity checks
echo "Checking inputs..."
if [[ ! -f "$SLIMPROB" ]]; then
    echo "SLiMProb not found at $SLIMPROB. Run setup_slims_suite.sh or set SLIMSUITE_PATH."
    exit 2
fi
ls -lh "$SEQIN" || exit 1
ls -lh "$MOTIFS" || exit 1
mkdir -p "$RESDIR" || exit 1

echo "Inputs OK"
echo

# Run SLiMProb
echo "Running SLiMProb..."
"$PYTHON_EXECUTABLE" "$SLIMPROB" \
    seqin="$SEQIN" \
    motifs="$MOTIFS" \
    goodmotif='*' \
    resdir="${RESDIR%/}/" \
    resfile="$RESFILE" \
    runid="$RUNID" \
    slimchance=T \
    v="$VERBOSITY" \
    force=T \
    i=-1 \
    masking=F \
    efilter=F \
    maxsize=0 \
    WallTime="$WALLTIME" \
    logtime=T
EXIT_CODE=$?


echo
echo "=============================="
echo "SLiMProb finished"
echo "End time: $(date)"
echo "Exit code: $EXIT_CODE"
echo "=============================="

exit $EXIT_CODE
