import os
import shutil
import pandas as pd

# Input directories and files
source_dir = "/home/foketch/genome_assembly/chloroplast_tools/filtered_cp_genomes_of_angio_n_others"

csv_file = "/home/foketch/genome_assembly/chloroplast_tools/results/df_header_metadata.csv"

destination_dir = "/home/foketch/genome_assembly/chloroplast_tools/data/filtered_cp_genomes_of_angio_n_others"

# Create destination directory if it does not exist
os.makedirs(destination_dir, exist_ok=True)

# Read CSV
df = pd.read_csv(csv_file)

# Extract file names
target_files = df["file_name"].dropna().unique()

moved = 0
missing = []
failed = []

for file_name in target_files:

    source_file = os.path.join(source_dir, file_name)
    destination_file = os.path.join(destination_dir, file_name)

    if not os.path.exists(source_file):
        missing.append(file_name)
        continue

    try:
        shutil.move(source_file, destination_file)
        moved += 1
        print(f"Moved: {file_name}")

    except OSError as e:
        failed.append((file_name, str(e)))
        print(f"Failed: {file_name} -> {e}")

# Summary
print("\n===== SUMMARY =====")
print(f"Successfully moved: {moved}")
print(f"Missing files: {len(missing)}")
print(f"Failed moves: {len(failed)}")

# Save log of failures (if any)
if failed:
    log_file = os.path.join(destination_dir, "failed_move_log.txt")
    with open(log_file, "w") as f:
        for fname, err in failed:
            f.write(f"{fname}\t{err}\n")

    print(f"\nFailed move log saved to: {log_file}")