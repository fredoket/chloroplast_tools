#!/usr/bin/env python3

from pathlib import Path
from Bio import SeqIO
import re

# Directory containing FASTA files
fasta_dir = Path("/home/foketch/genome_assembly/chloroplast_tools/data/angio_fasta/angio_fasta_c")

# FASTA extensions
extensions = ("*.fasta", "*.fa", "*.fna", "*.fas")

# Collect FASTA files
fasta_files = []
for ext in extensions:
    fasta_files.extend(fasta_dir.glob(ext))

print(f"Found {len(fasta_files)} FASTA files")

# Remove unwanted prefixes
REMOVE_PREFIXES = [
    r"TPA_asm:\s*",
    r"MAG:\s*",
]

for fasta_file in fasta_files:

    updated_records = []

    try:
        for record in SeqIO.parse(fasta_file, "fasta"):

            header = record.description.strip()

            # Extract accession
            accession = header.split()[0]

            # Remove accession from description
            desc = header[len(accession):].strip()

            # Remove prefixes
            for pattern in REMOVE_PREFIXES:
                desc = re.sub(pattern, "", desc)

            # Extract genus + species
            words = desc.split()

            if len(words) >= 2:
                species = f"{words[0]} {words[1]}"
            else:
                species = desc

            # Final header
            new_header = f"{accession} {species}"

            # Correct Biopython handling
            record.id = new_header
            record.name = new_header
            record.description = ""

            updated_records.append(record)

        # Overwrite original file
        SeqIO.write(updated_records, fasta_file, "fasta")

        print(f"Updated: {fasta_file.name}")

    except Exception as e:
        print(f"Error processing {fasta_file.name}: {e}")

print("Done.")