#!/bin/bash
#$ -N brbseq_pipeline
#$ -cwd
#$ -o ../logs/brbseq_pipeline.out
#$ -e ../logs/brbseq_pipeline.err
#$ -l h_rt=12:00:00
#$ -l h_vmem=64G
#$ -pe smp 12


# Activate Conda env
source /projectnb/vcres/myousry/miniconda3/etc/profile.d/conda.sh
conda activate brbseq

# Run pipeline
bash 00_brb_seq_pipeline.sh #