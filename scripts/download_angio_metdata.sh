#!/usr/bin/env bash

set -euo pipefail

# ==========================================================
# Angiosperm Chloroplast Genome + Full Taxonomy Pipeline
# With Quality Filtering (Publication-grade plastomes only)
#
# Filters:
#   - Angiosperms only (txid3398)
#   - Chloroplast genomes only
#   - Complete genomes only
#   - Size: 120–180 kb
#   - Removes partial/fragment/draft
#
# Output:
#   chloroplast_metadata_full_taxonomy.csv
# ==========================================================

OUTDIR="chloroplast_taxonomy_dataset"
mkdir -p "$OUTDIR"

SEARCH_JSON="$OUTDIR/search.json"
SUMMARY_XML="$OUTDIR/summary.xml"
TAX_XML="$OUTDIR/taxonomy.xml"

CSV="$OUTDIR/chloroplast_metadata_full_taxonomy.csv"

# ----------------------------------------------------------
# QUERY: Angiosperms + chloroplast
# ----------------------------------------------------------
QUERY="txid3398[Organism:exp] AND chloroplast[filter]"

echo "======================================"
echo "Searching Angiosperm chloroplast genomes"
echo "======================================"

# ----------------------------------------------------------
# STEP 1: Search NCBI
# ----------------------------------------------------------
curl -s "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi" \
    -d "db=nucleotide" \
    -d "term=$QUERY" \
    -d "retmax=100000" \
    -d "retmode=json" \
    > "$SEARCH_JSON"

echo "Search complete"

# ----------------------------------------------------------
# STEP 2: Extract IDs
# ----------------------------------------------------------
IDS=$(python3 - <<EOF
import json
data=json.load(open("$SEARCH_JSON"))
print(",".join(data["esearchresult"]["idlist"]))
EOF
)

TOTAL=$(python3 - <<EOF
import json
data=json.load(open("$SEARCH_JSON"))
print(len(data["esearchresult"]["idlist"]))
EOF
)

echo "Total records found: $TOTAL"

# ----------------------------------------------------------
# STEP 3: Download summaries
# ----------------------------------------------------------
echo "Downloading nucleotide summaries..."

> "$SUMMARY_XML"

BATCH=500
IFS=',' read -ra ARR <<< "$IDS"

for ((i=0; i<${#ARR[@]}; i+=BATCH)); do

    IDS_BATCH=$(IFS=','; echo "${ARR[@]:i:BATCH}")

    curl -s "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi" \
        -d "db=nucleotide" \
        -d "id=$IDS_BATCH" \
        -d "retmode=xml" \
        >> "$SUMMARY_XML"

    echo "Processed batch starting at $i"

    sleep 0.3
done

# ----------------------------------------------------------
# STEP 4: Extract taxonomy IDs
# ----------------------------------------------------------
echo "Extracting taxonomy IDs..."

python3 - <<EOF
import re

xml = open("$SUMMARY_XML").read()

taxids = set(
    re.findall(r'<Item Name="TaxId" Type="Integer">(\d+)</Item>', xml)
)

with open("$OUTDIR/taxids.txt", "w") as f:
    for t in sorted(taxids):
        f.write(t + "\n")

print("Unique taxonomy IDs:", len(taxids))
EOF

# ----------------------------------------------------------
# STEP 5: Download taxonomy
# ----------------------------------------------------------
echo "Downloading taxonomy records..."

> "$TAX_XML"

mapfile -t TAXIDS < "$OUTDIR/taxids.txt"

TBATCH=200

for ((i=0; i<${#TAXIDS[@]}; i+=TBATCH)); do

    TAX_BATCH=$(IFS=','; echo "${TAXIDS[@]:i:TBATCH}")

    curl -s "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi" \
        -d "db=taxonomy" \
        -d "id=$TAX_BATCH" \
        -d "retmode=xml" \
        >> "$TAX_XML"

    echo "Processed taxonomy batch starting at $i"

    sleep 0.3
done

# ----------------------------------------------------------
# STEP 6: Parse + QC FILTER + CSV
# ----------------------------------------------------------
echo "Parsing metadata and applying quality filters..."

python3 - <<EOF
import re
import csv

# -----------------------------
# QUALITY FILTER FUNCTION
# -----------------------------
def is_good_plastome(length, title):
    try:
        length = int(length)
    except:
        return False

    title = title.lower()

    # size filter (core plastome range)
    if length < 120000 or length > 180000:
        return False

    # must be complete genome
    if "complete genome" not in title:
        return False

    # remove bad assemblies
    bad = ["partial", "fragment", "draft", "segment"]
    if any(b in title for b in bad):
        return False

    return True

# -----------------------------
# PARSE TAXONOMY
# -----------------------------
tax_xml = open("$TAX_XML").read()

tax_records = re.findall(r"<Taxon>(.*?)</Taxon>", tax_xml, re.S)

taxonomy = {}

for rec in tax_records:

    taxid_match = re.search(r"<TaxId>(\d+)</TaxId>", rec)
    sci_match = re.search(r"<ScientificName>(.*?)</ScientificName>", rec)

    if not taxid_match:
        continue

    taxid = taxid_match.group(1)

    ranks = {
        "kingdom": "NA",
        "phylum": "NA",
        "class": "NA",
        "order": "NA",
        "family": "NA",
        "genus": "NA"
    }

    lineage = re.findall(
        r"<Taxon>.*?<ScientificName>(.*?)</ScientificName>.*?<Rank>(.*?)</Rank>.*?</Taxon>",
        rec,
        re.S
    )

    for name, rank in lineage:
        if rank in ranks:
            ranks[rank] = name

    taxonomy[taxid] = ranks

# -----------------------------
# PARSE NUCLEOTIDE SUMMARY
# -----------------------------
summary_xml = open("$SUMMARY_XML").read()

docs = re.findall(r"<DocSum>(.*?)</DocSum>", summary_xml, re.S)

rows = []

def extract(name, block):
    m = re.search(rf'<Item Name="{name}" Type="[^"]+">(.*?)</Item>', block, re.S)
    return m.group(1).strip() if m else "NA"

for d in docs:

    accession = extract("Caption", d)
    title = extract("Title", d)
    taxid = extract("TaxId", d)
    length = extract("Length", d)
    year = extract("CreateDate", d)[:4]

    # APPLY QUALITY FILTER
    if not is_good_plastome(length, title):
        continue

    tx = taxonomy.get(taxid, {})

    rows.append([
        accession,
        length,
        year,
        taxid,
        tx.get("kingdom","NA"),
        tx.get("phylum","NA"),
        tx.get("class","NA"),
        tx.get("order","NA"),
        tx.get("family","NA"),
        tx.get("genus","NA"),
        tx.get("species","NA") if "species" in tx else "NA",
        title
    ])

# -----------------------------
# WRITE CSV
# -----------------------------
out = "$CSV"

with open(out, "w", newline="") as f:
    writer = csv.writer(f)

    writer.writerow([
        "accession",
        "genome_size_bp",
        "year",
        "taxonomy_id",
        "kingdom",
        "phylum",
        "class",
        "order",
        "family",
        "genus",
        "species",
        "title"
    ])

    writer.writerows(rows)

print("DONE")
print("High-quality plastomes retained:", len(rows))
print("CSV:", out)
EOF

echo "======================================"
echo "FINISHED CLEAN PLASTOME DATASET"
echo "Output:"
echo "$CSV"
echo "======================================"