# Peptide-property prediction

`Scripts/calculate_peptide_properties.py` calculates disorder, secondary-structure, and solvent-accessibility properties for the peptide library. It combines metapredict, S4PRED, and the standalone NetSurfP-3.0 model.

## Inputs

By default, the script expects:

- `data/VP_library_all_sequences.csv`
- `data/full_library_virus_proteins.csv`
- `../RITA_and_ABT_pos_selection_screens.xlsx` (the workbook's `ABT` sheet)

The two CSVs are included under `SLIMs/Data/`; pass those paths using `--library-csv` and `--proteins-csv`. The library needs peptide identifiers, sequences, VT/VP codes, and NCBI/UniProt IDs. The protein table needs an `Identifier` column and a protein sequence column.

## Environments

Create the figure/prediction environment from the repository root:

```bash
conda env create -f Environment_Setup/Environment_Setup.yaml
conda activate peptide-figure-repro
```

Create the separate NetSurfP runtime:

```bash
conda env create -f Calculate_Peptide_Properties/envs/NetSurfP3_properties_env.yml
```

The NetSurfP checkpoint is approximately 3.1 GiB and is not tracked in Git. Place the matching `nsp3.pth` model in `NetSurfP-3.0_standalone/models/`, or pass its location using `--netsurfp-model`. Verify it with SHA-256 `c38c6f5a4b4b2e3c911b20a189a2cd504eef75465c967bda41389a7b0eb566d4`.

## Run

From the repository root:

```bash
conda activate peptide-figure-repro
python Calculate_Peptide_Properties/Scripts/calculate_peptide_properties.py \
  --library-csv SLIMs/Data/VP_library_all_sequences.csv \
  --proteins-csv SLIMs/Data/full_library_virus_proteins.csv \
  --netsurfp-model Calculate_Peptide_Properties/NetSurfP-3.0_standalone/models/nsp3.pth \
  --netsurfp-processes 1 \
  --s4pred-threads 1
```

S4PRED is located in the active environment automatically. If it is installed outside the expected package layout, pass `--s4pred-script /path/to/run_model.py`. NetSurfP runs with `conda run` in the `nsp3` environment; change that environment name with `--netsurfp-env`. If Conda/Micromamba is not available in the process environment, pass the environment's Python executable with `--netsurfp-python /path/to/nsp3/bin/python`. NetSurfP defaults to one concurrent model process and S4PRED to one CPU thread to limit resource use; adjust with `--netsurfp-processes` and `--s4pred-threads` only if resources allow.

Results are written to `Calculate_Peptide_Properties/results/ABT_peptides/`. The full-library run processes 1,653 full proteins and 28,112 peptides and can take substantial time and memory. Run the script with `--help` for all configurable paths.

For a bounded end-to-end check on real data, add `--max-peptides 10` and set `--results-dir /tmp/property-smoke`; this predicts the first ten VT/VP peptides and only their associated proteins. Omit `--max-peptides` for the full analysis.
