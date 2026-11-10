# NetSurfP-3.0 standalone runtime

This is the NetSurfP-3.0 standalone inference code used by the peptide-property workflow. The parent directory contains the project-level run instructions.

From the repository root, create its Conda environment and run the included example:

```bash
conda env create -f Calculate_Peptide_Properties/envs/NetSurfP3_properties_env.yml
conda run -n nsp3 python Calculate_Peptide_Properties/NetSurfP-3.0_standalone/nsp3.py \
  -m /path/to/nsp3.pth \
  -i Calculate_Peptide_Properties/NetSurfP-3.0_standalone/example.fasta \
  -o Calculate_Peptide_Properties/NetSurfP-3.0_standalone/test-output
```

The checkpoint is approximately 3.1 GiB and is not included in Git. Obtain the project-matched checkpoint through the approved model-storage location; verify SHA-256 `c38c6f5a4b4b2e3c911b20a189a2cd504eef75465c967bda41389a7b0eb566d4`. The inference code and checkpoint are distributed separately; retain their associated citations and terms.
