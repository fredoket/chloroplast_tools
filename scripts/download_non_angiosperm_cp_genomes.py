#!/usr/bin/env python3
# ==========================================================
# Download individual non-angiosperm chloroplast FASTA files
#
# Input:
#   results/non_angiosperm_chloroplast_final.csv
#
# Output:
#   results/non_angio_fasta/
#       ├── PV216845.fasta
#       ├── OR264260.fasta
#       └── ...
#
# Downloads one FASTA per accession
# Uses NCBI E-utilities
# ==========================================================
import os
import time
import pandas as pd
import requests
# ----------------------------------------------------------
# PATHS
# ----------------------------------------------------------
INPUT_CSV = "results/non_angiosperm_chloroplast_metadata.csv"
OUTDIR = "results/non_angio_fasta"
os.makedirs(OUTDIR, exist_ok=True)
# ----------------------------------------------------------
# LOAD ACCESSIONS
# ----------------------------------------------------------
df = pd.read_csv(INPUT_CSV)
accessions = (
    df["accession"]
    .dropna()
    .astype(str)
    .unique()
)
print("Total accessions:", len(accessions))
# ----------------------------------------------------------
# NCBI FASTA DOWNLOAD FUNCTION
# ----------------------------------------------------------
BASE_URL = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"
def download_fasta(accession):
    outfile = os.path.join(
        OUTDIR,
        f"{accession}.fasta"
    )
    # Skip existing files
    if os.path.exists(outfile):
        print(f"[SKIP] {accession}")
        return
    params = {
        "db": "nucleotide",
        "id": accession,
        "rettype": "fasta",
        "retmode": "text"
    }
    try:
        response = requests.get(
            BASE_URL,
            params=params,
            timeout=60
        )
        response.raise_for_status()
        fasta_text = response.text.strip()
        # Check valid FASTA
        if not fasta_text.startswith(">"):
            print(f"[FAILED] {accession} : invalid FASTA")
            return
        with open(outfile, "w") as f:
            f.write(fasta_text + "\n")
        print(f"[DOWNLOADED] {accession}")
    except Exception as e:
        print(f"[ERROR] {accession} : {e}")
# ----------------------------------------------------------
# DOWNLOAD LOOP
# ----------------------------------------------------------
print("\nStarting FASTA downloads...\n")
for i, accession in enumerate(accessions, start=1):
    print(f"[{i}/{len(accessions)}]", end=" ")
    download_fasta(accession)
    # Respect NCBI rate limits
    time.sleep(0.34)
# ----------------------------------------------------------
# SUMMARY
# ----------------------------------------------------------
print("\n======================================")
print("DOWNLOAD COMPLETE")
print("======================================")
print("FASTA directory:")
print(OUTDIR)
print("======================================")