import os
import pandas as pd

# Paths
fasta_dir = "/home/foketch/genome_assembly/chloroplast_tools/data/filtered_cp_genomes_of_angio_n_others"
metadata_file = "/home/foketch/genome_assembly/chloroplast_tools/results/df_header_metadata.csv"

# Load metadata
df = pd.read_csv(metadata_file)

# Ensure no missing values
df = df.dropna(subset=["file_name", "faster_header"])

# Convert to dictionary: file_name -> new header
header_map = dict(zip(df["file_name"], df["faster_header"]))

# Process each FASTA file
processed = 0
missing = []
failed = []

for file_name, new_header in header_map.items():

    fasta_path = os.path.join(fasta_dir, file_name)

    if not os.path.exists(fasta_path):
        missing.append(file_name)
        continue

    try:
        # Read FASTA
        with open(fasta_path, "r") as f:
            lines = f.readlines()

        # Replace headers
        new_lines = []
        for line in lines:
            if line.startswith(">"):
                new_lines.append(f">{new_header}\n")
            else:
                new_lines.append(line)

        # Write back (overwrite file)
        with open(fasta_path, "w") as f:
            f.writelines(new_lines)

        processed += 1
        print(f"Processed: {file_name}")

    except Exception as e:
        failed.append((file_name, str(e)))
        print(f"Failed: {file_name} -> {e}")

# Summary
print("\n===== SUMMARY =====")
print(f"Successfully processed: {processed}")
print(f"Missing files: {len(missing)}")
print(f"Failed files: {len(failed)}")

# Log failures
if failed:
    log_file = os.path.join(fasta_dir, "failed_header_rename_log.txt")
    with open(log_file, "w") as f:
        for fname, err in failed:
            f.write(f"{fname}\t{err}\n")

    print(f"\nFailure log saved to: {log_file}")