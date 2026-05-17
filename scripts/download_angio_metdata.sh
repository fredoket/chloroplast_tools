#!/usr/bin/env bash

set -euo pipefail

# ==========================================================
# Chloroplast Genome Metadata + Full Taxonomy Retrieval
#
# Retrieves:
#   - accession
#   - genome size
#   - publication year
#   - taxonomy ID
#   - kingdom
#   - phylum
#   - class
#   - order
#   - family
#   - genus
#   - species
#   - title
#
# Output:
#   chloroplast_metadata_full_taxonomy.csv
#
# No GenBank flat files downloaded
# Uses only NCBI E-utilities
# ==========================================================

OUTDIR="chloroplast_taxonomy_dataset"

mkdir -p "$OUTDIR"

SEARCH_JSON="$OUTDIR/search.json"
SUMMARY_XML="$OUTDIR/summary.xml"
TAX_XML="$OUTDIR/taxonomy.xml"

CSV="$OUTDIR/chloroplast_metadata_full_taxonomy.csv"

QUERY="(chloroplast[All Fields] AND genome[All Fields]) AND chloroplast[filter]"

echo "======================================"
echo "Searching NCBI chloroplast genomes"
echo "======================================"

# ----------------------------------------------------------
# STEP 1: Search nucleotide database
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
# STEP 3: Download nucleotide summaries
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

    echo "Processed nucleotide batch starting at $i"

    sleep 0.34
done

# ----------------------------------------------------------
# STEP 4: Extract unique taxonomy IDs
# ----------------------------------------------------------

echo "Extracting taxonomy IDs..."

python3 - <<EOF
import re

xml = open("$SUMMARY_XML").read()

taxids = set(
    re.findall(
        r'<Item Name="TaxId" Type="Integer">(\d+)</Item>',
        xml
    )
)

with open("$OUTDIR/taxids.txt", "w") as f:
    for t in sorted(taxids):
        f.write(t + "\n")

print("Unique taxonomy IDs:", len(taxids))
EOF

# ----------------------------------------------------------
# STEP 5: Download taxonomy metadata
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

    sleep 0.34
done

# ----------------------------------------------------------
# STEP 6: Parse everything into CSV
# ----------------------------------------------------------

echo "Parsing metadata and taxonomy..."

python3 - <<EOF
import re
import csv

# ------------------------------------------------------
# Parse taxonomy XML
# ------------------------------------------------------

tax_xml = open("$TAX_XML").read()

tax_records = re.findall(r"<Taxon>(.*?)</Taxon>", tax_xml, re.S)

taxonomy = {}

for rec in tax_records:

    taxid_match = re.search(r"<TaxId>(\d+)</TaxId>", rec)
    sci_match = re.search(r"<ScientificName>(.*?)</ScientificName>", rec)

    if not taxid_match:
        continue

    taxid = taxid_match.group(1)
    species = sci_match.group(1) if sci_match else "NA"

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

    taxonomy[taxid] = {
        "species": species,
        **ranks
    }

# ------------------------------------------------------
# Parse nucleotide summaries
# ------------------------------------------------------

summary_xml = open("$SUMMARY_XML").read()

docs = re.findall(r"<DocSum>(.*?)</DocSum>", summary_xml, re.S)

rows = []

for d in docs:

    def extract(name):
        m = re.search(
            rf'<Item Name="{name}" Type="[^"]+">(.*?)</Item>',
            d,
            re.S
        )
        return m.group(1).strip() if m else "NA"

    accession = extract("Caption")
    title = extract("Title")
    taxid = extract("TaxId")
    length = extract("Length")

    create_date = extract("CreateDate")
    year = create_date[:4] if create_date != "NA" else "NA"

    tx = taxonomy.get(taxid, {})

    rows.append([
        accession,
        length,
        year,
        taxid,
        tx.get("kingdom", "NA"),
        tx.get("phylum", "NA"),
        tx.get("class", "NA"),
        tx.get("order", "NA"),
        tx.get("family", "NA"),
        tx.get("genus", "NA"),
        tx.get("species", "NA"),
        title
    ])

# ------------------------------------------------------
# Write CSV
# ------------------------------------------------------

with open("$CSV", "w", newline="") as f:

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
print("Records written:", len(rows))
print("CSV:", "$CSV")
EOF

echo "======================================"
echo "FINISHED"
echo "Output:"
echo "$CSV"
echo "======================================"