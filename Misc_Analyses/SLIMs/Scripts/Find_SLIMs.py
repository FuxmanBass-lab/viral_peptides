import sys
import os
import subprocess
import tempfile
import pandas as pd
from tqdm import tqdm
import argparse
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SLIMS_DIR = SCRIPT_DIR.parent
REPO_ROOT = SLIMS_DIR.parent
parser = argparse.ArgumentParser(description="Find SLiMs for peptide groups using SLiMProb.")
parser.add_argument(
    "--slimsuite-path",
    type=Path,
    default=Path(os.environ.get("SLIMSUITE_PATH", SLIMS_DIR / "SLiMSuite")),
    help="SLiMSuite checkout containing tools/slimprob.py, libraries/, and data/.",
)
parser.add_argument(
    "--data-dir",
    type=Path,
    default=REPO_ROOT / "Calculate_Peptide_Properties" / "data",
    help="Directory containing VP_library_all_sequences.csv.",
)
parser.add_argument(
    "--screens-xlsx",
    type=Path,
    default=REPO_ROOT / "RITA_and_ABT_pos_selection_screens.xlsx",
    help="Workbook containing the ABT screen.",
)
parser.add_argument(
    "--results-dir",
    type=Path,
    default=SLIMS_DIR / "Results" / "group_analysis",
    help="Directory for generated SLiMProb results.",
)
args = parser.parse_args()

SLIMSUITE_PATH = args.slimsuite_path.resolve()
SLIMPROB_SCRIPT = SLIMSUITE_PATH / "tools" / "slimprob.py"
ELM_MOTIFS_FILE = SLIMS_DIR / "Data" / "elm2019.motifs"

for required_path in (
    SLIMPROB_SCRIPT,
    SLIMSUITE_PATH / "libraries" / "rje.py",
    ELM_MOTIFS_FILE,
):
    if not required_path.is_file():
        parser.error(
            "Required SLiMSuite or motif file not found: {}. Set --slimsuite-path "
            "or SLIMSUITE_PATH to a complete SLiMSuite checkout.".format(required_path)
        )

PYTHON_EXECUTABLE = sys.executable

DATA_DIR = args.data_dir.resolve()
RESULTS_DIR = str(args.results_dir.resolve())
library_path = DATA_DIR / "VP_library_all_sequences.csv"
for required_path in (library_path, args.screens_xlsx.resolve()):
    if not required_path.is_file():
        parser.error("Required analysis input not found: {}".format(required_path))
os.makedirs(RESULTS_DIR, exist_ok=True)


# Load input tables.
print("Loading data...")
full_library_df = pd.read_csv(library_path)
RITA_exp_df = pd.read_excel(args.screens_xlsx, sheet_name='ABT')


# --- SLiMSuite Input/Output Helper Functions ---

def create_fasta_from_df(df, id_col, seq_col, output_fasta_path):
    """
    Creates a FASTA file from a DataFrame, ensuring valid headers and sequences.
    """
    print("Generating FASTA for %d peptides..." % len(df))
    with open(output_fasta_path, 'w') as f:
        valid_rows = df[df[id_col].notna() & df[seq_col].notna()].copy()
        
        for index, row in valid_rows.iterrows():
            identifier = str(row[id_col]).strip()
            identifier = identifier.replace(' ', '_').replace('|', '_').replace('>', '') 
            sequence = str(row[seq_col]).strip()
            
            if identifier and sequence:
                f.write(">%s\n%s\n" % (identifier, sequence))
            else:
                pass 
    print("Generated FASTA file: %s with %d sequences." % (output_fasta_path, len(valid_rows)))


def run_slimprob(group_name, input_fasta_path, known_motifs_file_path, motif_filter_pattern, output_base_dir, slimprob_script, python_executable, max_seq=0):
    """
    Runs SLiMProb for a given group of peptides against known motifs, with an optional filter.
    """
    print("\n--- Running SLiMProb for group: %s ---" % group_name)

    sanitized_filter = motif_filter_pattern.replace('*', 'star').replace(',', '_') 
    slimprob_output_dir = os.path.join(output_base_dir, "slimprob_output_%s_%s" % (group_name.replace(' ', '_'), sanitized_filter))
    try:
        os.makedirs(slimprob_output_dir)
    except OSError as exc:
        if exc.errno == 17 and os.path.isdir(slimprob_output_dir):
            pass
        else: raise

    output_basename = "%s_slimprob_results" % group_name.replace(' ', '_')
    
    # SLiMProb: resfile (set by command) is for summary data (*.csv), occurrences are *.occ.csv
    summary_csv_output_path = os.path.join(slimprob_output_dir, "%s.csv" % output_basename)
    occurrences_csv_output_path = os.path.join(slimprob_output_dir, "%s.occ.csv" % output_basename) # SLiMProb typically names occurrences this way


    command = [
        python_executable, slimprob_script,
        "seqin=%s" % input_fasta_path,
        "motifs=%s" % known_motifs_file_path, 
        "goodmotif=%s" % motif_filter_pattern, 
        "resdir=%s/" % slimprob_output_dir, # SLiMSuite expects trailing slash
        "resfile=%s" % summary_csv_output_path, # This is the file for summary data
        "runid=%s_%s" % (group_name.replace(' ', '_'), sanitized_filter),
        "maxseq=%d" % max_seq,
        "slimchance=T", 
        "v=1",               # Set verbosity to 1 for SLiMProb
        "force=T",           # Force re-computation (ignore pickles)
        "i=-1",              # Disable interactivity for HPC environments
        "masking=F",         
        "efilter=F",     
        "maxsize=0",         # Disable the maximum total amino acids limit    
    ]

    print("SLiMProb command: %s" % ' '.join(command))

    try:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        stdout_bytes, stderr_bytes = process.communicate()
        stdout = stdout_bytes.decode('utf-8', errors='ignore') if stdout_bytes else ""
        stderr = stderr_bytes.decode('utf-8', errors='ignore') if stderr_bytes else ""

        if process.returncode != 0:
            print("SLiMProb Stdout for %s with filter '%s' (Error):\n%s" % (group_name, motif_filter_pattern, stdout))
            print("SLiMProb Stderr for %s with filter '%s' (Error):\n%s" % (group_name, motif_filter_pattern, stderr))
            raise Exception("SLiMProb subprocess failed with return code %d" % process.returncode)

        print("SLiMProb for %s with filter '%s' completed successfully." % (group_name, motif_filter_pattern))
        
        if stdout:
            print("SLiMProb Stdout for %s:\n%s" % (group_name, stdout))
        if stderr:
            print("SLiMProb Stderr for %s:\n%s" % (group_name, stderr))

        # Now check for the correctly named summary file
        if os.path.exists(summary_csv_output_path):
            slim_summary_df = pd.read_csv(summary_csv_output_path)
            print("Found %d known motifs with summary results for %s." % (len(slim_summary_df), group_name))
            return slim_summary_df
        else:
            raise FileNotFoundError(
                "SLiMProb completed without creating its summary file: {}".format(
                    summary_csv_output_path
                )
            )

    except Exception as e:
        print("An error occurred while running SLiMProb for %s with filter '%s': %s" % (group_name, motif_filter_pattern, e))
        raise


# --- Main Script Logic to filter data and run SLiMProb ---

print("\nFiltering Data ")
full_library_filtered = full_library_df[full_library_df['code'].isin(['VT', 'VP'])].copy()
RITA_exp_filtered = RITA_exp_df[RITA_exp_df['type'].isin(['VT', 'VP'])].copy()

# Removing leading M (from sequencing, exists in experimental peptides but not in true viral protein and would bias SLiM search)
RITA_exp_filtered['Aminoacids'] = RITA_exp_filtered['Aminoacids'].str[1:]

print("Number of peptides in full library (VT/VP): %d" % len(full_library_filtered))
print("Number of peptides used in ABT experiment (VT/VP): %d" % len(RITA_exp_filtered))

# Ensure 'identifier' is consistent for RITA_exp_filtered
RITA_exp_filtered['identifier'] = RITA_exp_filtered['tileID']

# Peptides Used vs. Not Used in Experiment (from the VT/VP filtered library)
used_sequences_set = set(RITA_exp_filtered['Aminoacids'].unique())
not_used_peptides_df = full_library_filtered[~full_library_filtered['Aminoacids'].isin(used_sequences_set)].copy()

# Experiment Significant vs. Non-Significant (from VT/VP used in experiment)
RITA_sig = RITA_exp_filtered[RITA_exp_filtered['sig'] == 'Yes'].copy()
RITA_non_sig = RITA_exp_filtered[RITA_exp_filtered['sig'] == 'No'].copy()

# Experiment Upregulated vs. Downregulated Significant (from VT/VP used and significant)
RITA_sig['log2FoldChange'] = pd.to_numeric(RITA_sig['log2FoldChange'], errors='coerce')
RITA_up = RITA_sig[RITA_sig['log2FoldChange'] > 0].copy()
RITA_down = RITA_sig[RITA_sig['log2FoldChange'] < 0].copy()

# Store DataFrames in a dictionary for easy iteration and FASTA creation
peptide_groups_dfs = {
    'Experiment_Significant_VT_VP': RITA_sig,
    'Experiment_NonSignificant_VT_VP': RITA_non_sig,
    'Experiment_Upregulated_VT_VP': RITA_up,
    'Experiment_Downregulated_VT_VP': RITA_down
}


# --- Run SLiMProb for each peptide group ---
print("\n--- Starting SLiMProb Analysis for Peptide Groups ---")
slimprob_results_summary = {}
slimprob_output_base_dir = os.path.join(RESULTS_DIR, "slimprob_analyses")
try:
    os.makedirs(slimprob_output_base_dir)
except OSError as exc:
    if exc.errno == 17 and os.path.isdir(slimprob_output_base_dir):
        pass
    else: raise

# Use "*" to match all motifs
# You can change this to "LIG_*" or "DEG_*" later if you want specific categories.
MOTIF_FILTER_TO_USE = "*" 

for group_name, group_df in tqdm(peptide_groups_dfs.items(), desc="Processing peptide groups for SLiMProb"):
    if group_df.empty:
        print("Skipping SLiMProb for empty group: %s" % group_name)
        slimprob_results_summary[group_name] = pd.DataFrame()
        continue

    with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix="_%s_slimprob.fasta" % group_name.replace(' ', '_')) as tmp_fasta_file:
        fasta_input_path = tmp_fasta_file.name
    
    create_fasta_from_df(group_df, 'identifier', 'Aminoacids', fasta_input_path)

    group_slim_results = run_slimprob(
        group_name=group_name,
        input_fasta_path=fasta_input_path,
        known_motifs_file_path=ELM_MOTIFS_FILE, 
        motif_filter_pattern=MOTIF_FILTER_TO_USE, 
        output_base_dir=slimprob_output_base_dir,
        slimprob_script=SLIMPROB_SCRIPT,
        python_executable=PYTHON_EXECUTABLE,
        max_seq=0
    )
    slimprob_results_summary[group_name] = group_slim_results

    if os.path.exists(fasta_input_path):
        os.remove(fasta_input_path)

print("\n--- SLiMProb Analysis Complete ---")
print("Summary of known motifs found per group:")
for group, results_df in slimprob_results_summary.items():
    num_motifs = len(results_df)
    print("- %s: %d known motifs (summary lines) with filter '%s'" % (group, num_motifs, MOTIF_FILTER_TO_USE))
    if num_motifs > 0:
        if 'p_UPC' in results_df.columns: 
            print("  Top 5 Motifs (by p_UPC - lower is more significant):")
            results_df['p_UPC'] = pd.to_numeric(results_df['p_UPC'], errors='coerce')
            print(results_df[['Pattern', 'N_UPC', 'E_UPC', 'p_UPC']].dropna(subset=['p_UPC']).sort_values(by='p_UPC').head())
        else:
            print("  Top 5 Motifs (No p_UPC column found):")
            print(results_df.head())
    print("-" * 30)

non_empty_slimprob_dfs = [df.assign(Group=name, MotifFilter=MOTIF_FILTER_TO_USE) 
                            for name, df in slimprob_results_summary.items() if not df.empty]

if non_empty_slimprob_dfs: 
    all_slimprob_results_combined = pd.concat(non_empty_slimprob_dfs)
    sanitized_filter_for_filename = MOTIF_FILTER_TO_USE.replace('*', 'star').replace(',', '_')
    combined_slimprob_results_path = os.path.join(slimprob_output_base_dir, "all_groups_slimprob_combined_summary_results_%s.csv" % sanitized_filter_for_filename)
    all_slimprob_results_combined.to_csv(combined_slimprob_results_path, index=False)
    print("\nAll SLiMProb summary results combined and saved to: %s" % combined_slimprob_results_path)
else:
    print("\nNo SLiMProb results found for any group with filter '%s'. No combined file generated." % MOTIF_FILTER_TO_USE)

print("\nScript execution finished.")