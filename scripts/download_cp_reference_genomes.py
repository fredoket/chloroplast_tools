#!/usr/bin/env python3

# ==========================================================
# Download curated angiosperm chloroplast reference genomes
# in GenBank format from NCBI
#
# Output:
#   references/
#       ├── NC_001879.gb   # Nicotiana tabacum
#       ├── NC_000932.gb   # Arabidopsis thaliana
#       ├── NC_001320.gb   # Oryza sativa
#       └── ...
#
# Downloads one GenBank file per accession
# Uses NCBI E-utilities via requests (no edirect needed)
# Handles SSL issues common on HPC clusters
# ==========================================================

import os
import time
import requests
import urllib3

# ----------------------------------------------------------
# CONFIGURATION
# ----------------------------------------------------------

OUTDIR = "references"
os.makedirs(OUTDIR, exist_ok=True)

# Suppress SSL warnings if using verify=False on HPC
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# Set to False if HPC has SSL certificate issues
VERIFY_SSL = True

# NCBI API key (optional but increases rate limit from 3 to 10 req/sec)
# Register at: https://www.ncbi.nlm.nih.gov/account/
NCBI_API_KEY = None   # Replace with your key e.g. "abc123def456..."

# ----------------------------------------------------------
# CURATED REFERENCE ACCESSIONS
# ----------------------------------------------------------

REFERENCES = [

    # --- Tier 1: Gold standard references ---
    ("NC_001879", "Nicotiana_tabacum",                          "Solanaceae",       "Eudicot"),
    ("NC_000932", "Arabidopsis_thaliana",                       "Brassicaceae",     "Eudicot"),
    ("NC_001320", "Oryza_sativa",                               "Poaceae",          "Monocot"),
    ("NC_001666", "Zea_mays",                                   "Poaceae",          "Monocot"),
    ("NC_002202", "Spinacia_oleracea",                          "Amaranthaceae",    "Eudicot"),

    # --- Eudicots ---
    ("NC_008235", "Populus_alba",                               "Salicaceae",       "Eudicot"),
    ("NC_007957", "Vitis_vinifera",                             "Vitaceae",         "Eudicot"),
    ("NC_007977", "Helianthus_annuus",                          "Asteraceae",       "Eudicot"),
    ("NC_007942", "Glycine_max",                                "Fabaceae",         "Eudicot"),
    ("NC_014676", "Theobroma_cacao",                            "Malvaceae",        "Eudicot"),
    ("NC_002694", "Lotus_japonicus",                            "Fabaceae",         "Eudicot"),

    # --- Monocots ---
    ("NC_013991", "Phoenix_dactylifera",                        "Arecaceae",        "Monocot"),
    ("NC_013273", "Musa_acuminata",                             "Musaceae",         "Monocot"),
    ("NC_002762", "Triticum_aestivum",                          "Poaceae",          "Monocot"),

    # --- Basal angiosperms ---
    ("NC_005086", "Amborella_trichopoda",                       "Amborellaceae",    "Basal"),
    ("NC_006050", "Nymphaea_alba",                              "Nymphaeaceae",     "Basal"),
    ("NC_008326", "Liriodendron_tulipifera",                    "Magnoliaceae",     "Magnoliid"),
    ("NC_008457", "Piper_cenocladum",                           "Piperaceae",       "Magnoliid"),

]

# ----------------------------------------------------------
# NCBI DOWNLOAD FUNCTION
# ----------------------------------------------------------

BASE_URL = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"

def download_genbank(accession, species, family, group):
    """Download a GenBank file for one accession."""

    outfile = os.path.join(OUTDIR, f"{accession}.gb")

    # Skip if already downloaded
    if os.path.exists(outfile) and os.path.getsize(outfile) > 1000:
        print(f"  [SKIP]       {accession}  {species}")
        return True

    params = {
        "db":      "nucleotide",
        "id":      accession,
        "rettype": "genbank",
        "retmode": "text",
    }

    if NCBI_API_KEY:
        params["api_key"] = NCBI_API_KEY

    try:
        response = requests.get(
            BASE_URL,
            params=params,
            timeout=120,
            verify=VERIFY_SSL
        )
        response.raise_for_status()

        text = response.text.strip()

        # Validate GenBank format
        if not text.startswith("LOCUS"):
            print(f"  [FAILED]     {accession}  {species} : invalid GenBank format")
            return False

        with open(outfile, "w") as f:
            f.write(text + "\n")

        # Quick content check
        gene_count = text.count('     gene            ')
        size_kb    = len(text) / 1024

        print(f"  [DOWNLOADED] {accession}  {species:<40} genes={gene_count}  size={size_kb:.1f}kb")
        return True

    except requests.exceptions.SSLError:
        print(f"  [SSL ERROR]  {accession} — retrying without SSL verification...")
        return download_genbank_no_ssl(accession, species, family, group)

    except Exception as e:
        print(f"  [ERROR]      {accession}  {species} : {e}")
        return False


def download_genbank_no_ssl(accession, species, family, group):
    """Fallback: retry without SSL verification (for HPC SSL issues)."""

    outfile = os.path.join(OUTDIR, f"{accession}.gb")

    params = {
        "db":      "nucleotide",
        "id":      accession,
        "rettype": "genbank",
        "retmode": "text",
    }

    if NCBI_API_KEY:
        params["api_key"] = NCBI_API_KEY

    try:
        response = requests.get(
            BASE_URL,
            params=params,
            timeout=120,
            verify=False        # SSL disabled for HPC firewall workaround
        )
        response.raise_for_status()

        text = response.text.strip()

        if not text.startswith("LOCUS"):
            print(f"  [FAILED]     {accession} : invalid GenBank format")
            return False

        with open(outfile, "w") as f:
            f.write(text + "\n")

        gene_count = text.count('     gene            ')
        size_kb    = len(text) / 1024
        print(f"  [DOWNLOADED] {accession}  {species:<40} genes={gene_count}  size={size_kb:.1f}kb  (SSL disabled)")
        return True

    except Exception as e:
        print(f"  [ERROR]      {accession} : {e}")
        return False

# ----------------------------------------------------------
# VALIDATE DOWNLOADED GENBANK FILES
# ----------------------------------------------------------

def validate_genbank(accession, species):
    """Check downloaded GenBank file has key chloroplast features."""

    outfile = os.path.join(OUTDIR, f"{accession}.gb")

    if not os.path.exists(outfile):
        return

    with open(outfile) as f:
        text = f.read()

    gene_count = text.count('     gene            ')
    trna_count = text.count('tRNA')
    rrna_count = text.count('rRNA')
    has_lsc    = 'LSC' in text or 'large single' in text.lower()

    status = "OK" if gene_count >= 50 else "WARNING: low gene count"

    print(f"  {accession:<15} {species:<40} genes={gene_count:>3}  tRNA={trna_count:>3}  rRNA={rrna_count:>2}  [{status}]")

# ----------------------------------------------------------
# MAIN
# ----------------------------------------------------------

print("=" * 70)
print("ANGIOSPERM CHLOROPLAST REFERENCE GENOME DOWNLOADER")
print("=" * 70)
print(f"Output directory : {OUTDIR}")
print(f"Total references : {len(REFERENCES)}")
print(f"SSL verification : {VERIFY_SSL}")
print(f"NCBI API key     : {'Set' if NCBI_API_KEY else 'Not set (max 3 req/sec)'}")
print("=" * 70)

# Rate limit: 3/sec without API key, 10/sec with key
SLEEP = 0.34 if not NCBI_API_KEY else 0.11

results = {"downloaded": [], "skipped": [], "failed": []}

# Group downloads by angiosperm group for clarity
current_group = None

for i, (accession, species, family, group) in enumerate(REFERENCES, start=1):

    if group != current_group:
        current_group = group
        print(f"\n--- {group} ---")

    print(f"[{i:>2}/{len(REFERENCES)}]", end=" ")
    success = download_genbank(accession, species, family, group)

    if success:
        outfile = os.path.join(OUTDIR, f"{accession}.gb")
        if os.path.getsize(outfile) > 1000:
            if "SKIP" in str(success):
                results["skipped"].append(accession)
            else:
                results["downloaded"].append(accession)
    else:
        results["failed"].append(accession)

    time.sleep(SLEEP)

# ----------------------------------------------------------
# VALIDATION SUMMARY
# ----------------------------------------------------------

print("\n" + "=" * 70)
print("VALIDATION CHECK")
print("=" * 70)
print(f"{'Accession':<15} {'Species':<40} {'Genes':>5}  {'tRNA':>4}  {'rRNA':>4}  Status")
print("-" * 70)

for accession, species, family, group in REFERENCES:
    validate_genbank(accession, species)

# ----------------------------------------------------------
# FINAL SUMMARY
# ----------------------------------------------------------

total     = len(REFERENCES)
n_files   = len([f for f in os.listdir(OUTDIR) if f.endswith(".gb")])
total_mb  = sum(
    os.path.getsize(os.path.join(OUTDIR, f))
    for f in os.listdir(OUTDIR) if f.endswith(".gb")
) / (1024 * 1024)

print("\n" + "=" * 70)
print("DOWNLOAD COMPLETE")
print("=" * 70)
print(f"References downloaded : {n_files}/{total}")
print(f"Output directory      : {OUTDIR}/")
print(f"Total size            : {total_mb:.2f} MB")

if results["failed"]:
    print(f"\nFailed accessions ({len(results['failed'])}):")
    for acc in results["failed"]:
        print(f"  - {acc}")
    print("\nTip: If failures are SSL-related, set VERIFY_SSL = False at top of script.")
    print("     Or download failed genomes locally and scp to HPC.")

print("\nFiles ready for PGA annotation:")
print(f"  perl PGA.pl -s {OUTDIR}/NC_001879.gb,{OUTDIR}/NC_000932.gb,{OUTDIR}/NC_001320.gb \\")
print(f"              -g your_genome.fasta -o output/")
print("=" * 70)