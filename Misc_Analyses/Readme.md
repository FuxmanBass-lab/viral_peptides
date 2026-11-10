# Peptide tiling analyses

This directory contains notebooks, input tables, and scripts for reproducing analyses and figures for the paper. 

The original project README lists panels 1C, 2A, 2C, 3D, and S2A–S2F, along with Nutlin-3 supplemental results and RITA flow analysis. The notebook table below gives the main entry points; some notebooks generate multiple panels.

The export includes the data needed by most figure notebooks and precomputed SLiMProb results. Full property prediction uses the included peptide library and full-protein CSVs in `SLIMs/Data/`, plus the large NetSurfP model checkpoint, which is not stored in Git. Rerunning SLiMProb requires a pinned external SLiMSuite checkout.

## Quick start

Run commands from this directory. Create the analysis environment and launch JupyterLab:

```bash
conda env create -f Environment_Setup/Environment_Setup.yaml
conda activate peptide-figure-repro
python -m ipykernel install --user --name peptide-figure-repro --display-name "Python (peptide-figure-repro)"
jupyter lab
```

In JupyterLab, select the `Python (peptide-figure-repro)` kernel and run the notebooks from top to bottom. Keep the working directory at the repository root; the notebooks use paths relative to it.

## Figure and analysis workflows

| Notebook or script | Purpose / outputs |
|---|---|
| `Figure_1C_Distribution.ipynb` | Figure 1C peptide distribution analysis |
| `Figure_1_Hockey_Sticks.ipynb` | Hockey-stick screen visualization |
| `Figure_2_Properties.ipynb` | Peptide structural-property figures, including associated supplementary panels |
| `Figure_S2E_Processing.ipynb` | Processes annotations used for Supplementary Figure S2E; may query external NCBI services |
| `Figure_S2E_Analysis_Plots.ipynb` | Supplementary Figure S2E plots |
| `SLIMs/SLIMs_Analysis.ipynb` | SLiM enrichment analysis from the included SLiMProb occurrence table |
| `Figure_S2F.ipynb` | Supplementary Figure S2F; reads `SLIMs/Data/Results_Bulk_Secondary_Filter_Deleterious.csv` |
| `Nutlin_flow.ipynb` | Nutlin-3 flow analysis and supplemental results |
| `RITA_Flow_Analysis.ipynb` | RITA flow analysis |
| `Pymol_session.pse` | Pymol Session file used to generate protein visuals |
The notebooks write generated SLiM tables and plots beneath `SLIMs/Results/`. Existing PDFs at the repository root are reference outputs, not required inputs.

Several plotting notebooks request Arial. That font is not redistributed here; without it, Matplotlib may substitute another font and the figure typography can differ.

## Rerunning peptide-property predictions

The required CSV inputs are included in `SLIMs/Data/`:

- `SLIMs/Data/VP_library_all_sequences.csv`
- `SLIMs/Data/full_library_virus_proteins.csv`

The script defaults to `Calculate_Peptide_Properties/data/`; pass the included CSV locations explicitly as shown below. The screen workbook defaults to the included `RITA_and_ABT_pos_selection_screens.xlsx`.

Create the NetSurfP runtime environment:

```bash
conda env create -f Calculate_Peptide_Properties/envs/NetSurfP3_properties_env.yml
```

The main `peptide-figure-repro` environment also provides S4PRED and metapredict. S4PRED 1.2.1 requires PyTorch 2.6.0, which is pinned in the environment file. NetSurfP runs in the separate `nsp3` environment. The NetSurfP checkpoint is about 3.1 GiB and is excluded from Git; obtain the matching `nsp3.pth` checkpoint through the project’s approved model storage and provide it with `--netsurfp-model`. Its SHA-256 is `c38c6f5a4b4b2e3c911b20a189a2cd504eef75465c967bda41389a7b0eb566d4`.

Example, run from the repository root:

```bash
conda activate peptide-figure-repro
python Calculate_Peptide_Properties/Scripts/calculate_peptide_properties.py \
  --library-csv SLIMs/Data/VP_library_all_sequences.csv \
  --proteins-csv SLIMs/Data/full_library_virus_proteins.csv \
  --netsurfp-model Calculate_Peptide_Properties/NetSurfP-3.0_standalone/models/nsp3.pth \
  --netsurfp-processes 1 \
  --s4pred-threads 1
```

The NetSurfP checkpoint must be present at the path above, or supplied from another location. If Conda/Micromamba is not available in the process environment, pass the Python executable from the `nsp3` environment with `--netsurfp-python /path/to/nsp3/bin/python`. NetSurfP defaults to one model process, and S4PRED defaults to one CPU thread, to limit resource use; increase these settings only on a machine with sufficient RAM and CPUs. Results go to `Calculate_Peptide_Properties/results/ABT_peptides/`; this generated directory is ignored by Git. Use `--help` for all input, runtime, and output options.

The full-library workflow predicts 1,653 full proteins with NetSurfP and 28,112 peptides with S4PRED/metapredict; this is a substantial CPU- and memory-intensive run. The two CSV input tables are included in this export, and the protein identifiers in the current library match the protein table.

For a quick end-to-end check using real input rows, add `--max-peptides 10` and choose a temporary `--results-dir`; this limits structural prediction to the first ten VT/VP peptides and their associated proteins. Omit the option for the full analysis.

## Rerunning SLiMProb

SLiMProb imports the matching SLiMSuite `libraries/` modules. Install the upstream release at the pinned commit with:

```bash
bash SLIMs/Scripts/setup_slims_suite.sh
```

The setup script clones SLiMSuite release 1.12.0 (commit `242d0401252f5d5bb021e814ec60a47f8cf8fced`) to the ignored `SLIMs/SLiMSuite/` directory. It requires Git and an internet connection. If SLiMSuite is already installed elsewhere, set `SLIMSUITE_PATH` to that checkout before running either script; use the pinned commit for reproducible results.

For a cluster with the Sun Grid Engine `qsub` command, submit `SLIMs/Scripts/submit_slimprob_cluster.sh` from the repository root. Both scripts resolve their data and output paths relative to their own location. The SGE launcher exports the `SLIMSUITE_PATH` setting into the job.

The precomputed occurrence table `SLIMs/Data/all_peptides_slimprob_summary.occ.split.csv` allows the downstream SLiM enrichment notebook to run without rerunning SLiMProb. `SLIMs/Scripts/Find_SLIMs.py` is an additional group-analysis script; it also requires the full library CSV and screen workbook, plus the same SLiMSuite checkout.

To run the bundled full FASTA locally without overwriting existing results, choose a separate results directory and capture the log there:

```bash
mkdir -p /path/to/local/slimprob-results
SLIMPROB_RESDIR=/path/to/local/slimprob-results \
SLIMPROB_RESFILE=all_peptides_slimprob_summary.csv \
SLIMPROB_PYTHON="$(command -v python)" \
bash SLIMs/Scripts/submit_slimprob_local.sh \
  > /path/to/local/slimprob-results/run.log 2>&1
```

The local launcher accepts `SLIMPROB_SEQIN`, `SLIMPROB_MOTIFS`, `SLIMPROB_RESDIR`, `SLIMPROB_RESFILE`, `SLIMPROB_RUNID`, `SLIMPROB_PYTHON`, `SLIMPROB_VERBOSITY`, and `SLIMPROB_WALLTIME` overrides. It defaults to low verbosity to avoid excessive progress output. SLiMProb reads 28,112 sequences and 366 motifs, so the full search can take a long time and consume significant resources; inspect the run log and confirm both summary and occurrence CSVs are present before using the results.

## Included data

- `VTs_withprops_SLiMs.csv`: peptide identifiers, predicted properties, screen statistics, and detected SLiMs.
- `RITA_and_ABT_pos_selection_screens.xlsx`: positive-selection screen data, with separate RITA and ABT sheets.
- `RITA_Flow_Data.xlsx` and `Nutlin-3_flow.xlsx`: manually curated flow-cytometry measurements used by the flow notebooks.
- `GO_Term_Mapped_Viral_Proteins.csv`: annotations used in the Supplementary Figure S2E analysis.
- `SLIMs/Data/`: peptide FASTA, ELM motif definitions, SLiMProb occurrences, and the input table for Supplementary Figure S2F.

Please retain source citations and data-use terms when redistributing this directory. The NetSurfP model checkpoint and the external SLiMSuite source have separate distribution terms.


