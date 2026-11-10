# Viral peptide analyses

This repository contains two independent, self-contained analysis projects for "Peptide tiling across viral proteomes identifies modular regulators of stress-induced cell death" (PMID: 42620239, DOI: https://doi.org/10.64898/2026.08.04.742754). They address different questions, use
different data and software environments, and can be explored or reproduced
separately.

## Analysis projects

### [BRB-seq analysis](./BRBseq/)

The `BRBseq/` project analyzes bulk RNA barcoding and sequencing data from
viral-peptide tiles tested with DMSO or the p53 activator RITA. Its pipeline
uses DESeq2 for differential expression and fgsea for Reactome pathway
enrichment, with comparisons designed to distinguish baseline peptide effects
from effects that occur with RITA treatment.

Start with the [BRB-seq README](./BRBseq/README.md) for the experimental design,
analysis steps, statistical thresholds, requirements, and reproduction
instructions. The project includes analysis scripts and derived results; raw
sequencing data and the full count matrices are not included in this repository.
The README describes their availability and the additional inputs needed to
rerun preprocessing.

### [Miscellaneous peptide-tiling analyses](./Misc_Analyses/)

The `Misc_Analyses/` project contains figure notebooks, data, and scripts for
peptide-distribution and structural-property analyses, SLiM enrichment, GO
annotations, and RITA/Nutlin flow-cytometry analyses. It includes a dedicated
Python environment for its notebooks and documents separate workflows for
rerunning peptide-property predictions and SLiMProb.

Start with the [Miscellaneous analyses README](./Misc_Analyses/Readme.md) for
the notebook guide, environment setup, data inventory, and workflow details.
Some computational workflows require external resources that are not bundled,
including the NetSurfP model checkpoint and a pinned SLiMSuite checkout.

## Working with the projects

Run each project's commands from that project's directory and follow its own
README. The projects are intentionally kept in separate subdirectories; their
dependencies, inputs, and reproduction steps are not shared.

Please consult both project READMEs for data availability, software
requirements, citations, and third-party data or software terms before
redistributing or rerunning analyses.
