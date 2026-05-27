#!/usr/bin/env python3

from pathlib import Path
from Bio import SeqIO
import csv

# Directory containing FASTA files
fasta_dir = Path("/home/foketch/genome_assembly/chloroplast_tools/data/angio_fasta_c")

# Output CSV file
output_csv = fasta_dir / "fasta_header_names.csv"

# FASTA extensions
extensions = ("*.fasta", "*.fa", "*.fna", "*.fas")

# Collect FASTA files
fasta_files = []
for ext in extensions:
    fasta_files.extend(fasta_dir.glob(ext))

print(f"Found {len(fasta_files)} FASTA files")

rows = []

for fasta_file in fasta_files:

    try:
        for record in SeqIO.parse(fasta_file, "fasta"):

            header = record.description.strip()

            # Extract accession
            accession = header.split()[0]

            # Everything after accession
            name = header[len(accession):].strip()

            rows.append([
                fasta_file.name,
                accession,
                name,
                header
            ])

    except Exception as e:
        print(f"Error processing {fasta_file.name}: {e}")

# Write CSV
with open(output_csv, "w", newline="", encoding="utf-8") as csvfile:

    writer = csv.writer(csvfile)

    writer.writerow([
        "file_name",
        "accession",
        "name",
        "full_header"
    ])

    writer.writerows(rows)

print(f"CSV saved to: {output_csv}")
print(f"Total headers extracted: {len(rows)}")