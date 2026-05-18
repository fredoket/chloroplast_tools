#!/usr/bin/env python3

import pandas as pd
import time
import requests
import xml.etree.ElementTree as ET

# ==========================================================
# INPUT DATA
# ==========================================================

df = pd.read_csv("results/chloroplast_metadata_cleaned.csv")

print("Initial records:", len(df))

# unique taxonomy IDs
taxids = df["taxonomy_id"].dropna().astype(int).unique()

# ==========================================================
# NCBI TAXONOMY FETCH FUNCTION
# ==========================================================

BASE_URL = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"

def fetch_taxonomy_xml(taxid):
    try:
        r = requests.get(
            BASE_URL,
            params={
                "db": "taxonomy",
                "id": taxid,
                "retmode": "xml"
            },
            timeout=10
        )
        return r.text
    except Exception:
        return None

# ==========================================================
# ANGIOSPERM CHECK
# ==========================================================

def is_angiosperm(xml_text):
    if xml_text is None:
        return False

    xml_lower = xml_text.lower()

    return (
        "angiosperm" in xml_lower or
        "magnoliophyta" in xml_lower or
        "flowering plants" in xml_lower
    )

# ==========================================================
# PROCESS TAXIDS
# ==========================================================

results = []

print("Checking angiosperm status...")

for i, taxid in enumerate(taxids):

    xml = fetch_taxonomy_xml(taxid)

    results.append({
        "taxonomy_id": taxid,
        "is_angiosperm": is_angiosperm(xml)
    })

    if i % 50 == 0:
        print(f"Processed {i}/{len(taxids)}")

    time.sleep(0.34)  # NCBI rate limit

tax_df = pd.DataFrame(results)

# ==========================================================
# MERGE BACK
# ==========================================================

df_final = df.merge(tax_df, on="taxonomy_id", how="left")

df_final = df_final[df_final["is_angiosperm"] == True]

# ==========================================================
# SAVE OUTPUT
# ==========================================================

df_final.to_csv(
    "results/angiosperm_chloroplast_final.csv",
    index=False
)

print("\n=========================")
print("ANGIOSPERM FILTER DONE")
print("=========================")
print("Final records:", len(df_final))
print("Output: results/angiosperm_chloroplast_final.csv")