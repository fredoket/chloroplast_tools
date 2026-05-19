#!/usr/bin/env python3

# ==========================================================
# Pre-check FASTA files before PGA chloroplast annotation
#
# Checks performed per FASTA file:
#   1. File exists and is not empty
#   2. Valid FASTA format (starts with >)
#   3. Single sequence (PGA expects one genome per file)
#   4. Sequence length (chloroplast: 100kb - 220kb)
#   5. Valid nucleotide characters (A, T, G, C, N only)
#   6. N content not excessive (< 5%)
#   7. No duplicate accessions across files
#
# Output:
#   results/qc/
#       ├── qc_passed.txt        # Genomes ready for PGA
#       ├── qc_failed.txt        # Genomes with critical issues
#       ├── qc_warnings.txt      # Genomes with minor issues
#       └── qc_summary.tsv       # Full report per genome
#
# Usage:
#   python3 scripts/precheck_fasta.py
# ==========================================================

import os
import re
import sys
import gzip
import hashlib
from pathlib import Path
from collections import defaultdict
from datetime import datetime

# ----------------------------------------------------------
# CONFIGURATION
# ----------------------------------------------------------

GENOME_DIR   = "data/angio_fasta"                  # Directory with FASTA files
OUTDIR_QC    = "results/qc"              # QC output directory
FASTA_EXT    = (".fasta", ".fa", ".fna") # Accepted extensions

# Chloroplast genome size thresholds (bp)
MIN_LENGTH   = 100_000    # 100 kb  — below this is likely incomplete
MAX_LENGTH   = 220_000    # 220 kb  — above this is likely contaminated

# N content threshold
MAX_N_PCT    = 5.0        # Flag if >5% of sequence is N

# ----------------------------------------------------------
# SETUP
# ----------------------------------------------------------

os.makedirs(OUTDIR_QC, exist_ok=True)

# Output files
SUMMARY_TSV  = os.path.join(OUTDIR_QC, "qc_summary.tsv")
PASSED_TXT   = os.path.join(OUTDIR_QC, "qc_passed.txt")
FAILED_TXT   = os.path.join(OUTDIR_QC, "qc_failed.txt")
WARNINGS_TXT = os.path.join(OUTDIR_QC, "qc_warnings.txt")

# ----------------------------------------------------------
# HELPER FUNCTIONS
# ----------------------------------------------------------

def open_file(filepath):
    """Open regular or gzipped FASTA files."""
    if str(filepath).endswith(".gz"):
        return gzip.open(filepath, "rt")
    return open(filepath, "r")


def parse_fasta(filepath):
    """
    Parse FASTA file. Returns list of (header, sequence) tuples.
    Handles multi-line sequences.
    """
    records = []
    header  = None
    seq_parts = []

    try:
        with open_file(filepath) as f:
            for line in f:
                line = line.rstrip()
                if not line:
                    continue
                if line.startswith(">"):
                    if header is not None:
                        records.append((header, "".join(seq_parts).upper()))
                    header    = line[1:].strip()
                    seq_parts = []
                else:
                    seq_parts.append(line)

            if header is not None:
                records.append((header, "".join(seq_parts).upper()))

    except Exception as e:
        return None, str(e)

    return records, None


def check_nucleotides(sequence):
    """Check for invalid characters in sequence."""
    valid   = set("ATGCNRYWSKMBDHV")   # IUPAC nucleotide codes
    invalid = set(sequence) - valid
    return invalid


def n_content(sequence):
    """Calculate percentage of N bases."""
    if len(sequence) == 0:
        return 0.0
    return (sequence.count("N") / len(sequence)) * 100


def gc_content(sequence):
    """Calculate GC content percentage."""
    if len(sequence) == 0:
        return 0.0
    gc = sequence.count("G") + sequence.count("C")
    return (gc / len(sequence)) * 100


def file_md5(filepath):
    """Compute MD5 hash of file for duplicate detection."""
    h = hashlib.md5()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def format_bp(bp):
    """Format base pair count for display."""
    if bp >= 1_000_000:
        return f"{bp/1_000_000:.2f} Mb"
    elif bp >= 1_000:
        return f"{bp/1_000:.1f} kb"
    return f"{bp} bp"

# ----------------------------------------------------------
# MAIN CHECK FUNCTION
# ----------------------------------------------------------

def check_fasta(filepath):
    """
    Run all QC checks on a single FASTA file.

    Returns:
        dict with keys: status, warnings, errors, metrics
    """

    result = {
        "file":      str(filepath),
        "basename":  Path(filepath).stem,
        "status":    "PASS",       # PASS / WARN / FAIL
        "errors":    [],
        "warnings":  [],
        "metrics":   {}
    }

    filepath = Path(filepath)

    # --------------------------------------------------
    # CHECK 1: File exists and is not empty
    # --------------------------------------------------

    if not filepath.exists():
        result["errors"].append("File does not exist")
        result["status"] = "FAIL"
        return result

    file_size = filepath.stat().st_size

    if file_size == 0:
        result["errors"].append("File is empty (0 bytes)")
        result["status"] = "FAIL"
        return result

    result["metrics"]["file_size_kb"] = round(file_size / 1024, 1)

    # --------------------------------------------------
    # CHECK 2: Valid FASTA format
    # --------------------------------------------------

    records, parse_error = parse_fasta(filepath)

    if parse_error:
        result["errors"].append(f"Could not parse file: {parse_error}")
        result["status"] = "FAIL"
        return result

    if not records:
        result["errors"].append("No sequences found in file")
        result["status"] = "FAIL"
        return result

    # Check first line starts with >
    try:
        with open_file(filepath) as f:
            first_line = f.readline().strip()
        if not first_line.startswith(">"):
            result["errors"].append("File does not start with '>' — invalid FASTA format")
            result["status"] = "FAIL"
            return result
    except Exception as e:
        result["errors"].append(f"Could not read file: {e}")
        result["status"] = "FAIL"
        return result

    # --------------------------------------------------
    # CHECK 3: Single sequence (PGA requires one genome)
    # --------------------------------------------------

    n_seqs = len(records)
    result["metrics"]["n_sequences"] = n_seqs

    if n_seqs > 1:
        result["errors"].append(
            f"File contains {n_seqs} sequences — PGA requires exactly 1 sequence per file"
        )
        result["status"] = "FAIL"
        # Still continue checks on first sequence

    header, sequence = records[0]
    result["metrics"]["header"] = header[:80]   # Truncate for display

    # --------------------------------------------------
    # CHECK 4: Sequence length (chloroplast size range)
    # --------------------------------------------------

    seq_len = len(sequence)
    result["metrics"]["length_bp"]  = seq_len
    result["metrics"]["length_fmt"] = format_bp(seq_len)

    if seq_len == 0:
        result["errors"].append("Sequence is empty")
        result["status"] = "FAIL"
        return result

    if seq_len < MIN_LENGTH:
        result["errors"].append(
            f"Sequence too short: {format_bp(seq_len)} "
            f"(minimum expected: {format_bp(MIN_LENGTH)}) — likely incomplete genome"
        )
        result["status"] = "FAIL"

    elif seq_len > MAX_LENGTH:
        result["warnings"].append(
            f"Sequence unusually long: {format_bp(seq_len)} "
            f"(maximum expected: {format_bp(MAX_LENGTH)}) — check for contamination"
        )
        if result["status"] == "PASS":
            result["status"] = "WARN"

    # --------------------------------------------------
    # CHECK 5: Valid nucleotide characters
    # --------------------------------------------------

    invalid_chars = check_nucleotides(sequence)
    result["metrics"]["invalid_chars"] = sorted(invalid_chars)

    if invalid_chars:
        result["errors"].append(
            f"Invalid characters in sequence: {sorted(invalid_chars)} "
            f"— may indicate non-nucleotide data or encoding issue"
        )
        result["status"] = "FAIL"

    # --------------------------------------------------
    # CHECK 6: N content
    # --------------------------------------------------

    n_pct = n_content(sequence)
    result["metrics"]["n_pct"] = round(n_pct, 2)

    if n_pct > MAX_N_PCT:
        result["warnings"].append(
            f"High N content: {n_pct:.2f}% "
            f"(threshold: {MAX_N_PCT}%) — assembly may have gaps"
        )
        if result["status"] == "PASS":
            result["status"] = "WARN"

    # --------------------------------------------------
    # CHECK 7: GC content (chloroplast: typically 34-40%)
    # --------------------------------------------------

    gc_pct = gc_content(sequence)
    result["metrics"]["gc_pct"] = round(gc_pct, 2)

    if gc_pct < 25 or gc_pct > 50:
        result["warnings"].append(
            f"Unusual GC content: {gc_pct:.2f}% "
            f"(expected 34-40% for most chloroplasts)"
        )
        if result["status"] == "PASS":
            result["status"] = "WARN"

    return result

# ----------------------------------------------------------
# COLLECT ALL FASTA FILES
# ----------------------------------------------------------

print("=" * 70)
print("FASTA PRE-CHECK FOR PGA CHLOROPLAST ANNOTATION")
print("=" * 70)
print(f"Genome directory : {GENOME_DIR}")
print(f"QC output        : {OUTDIR_QC}")
print(f"Started          : {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
print("=" * 70)

# Find all FASTA files
all_files = []
for ext in FASTA_EXT:
    all_files.extend(Path(GENOME_DIR).glob(f"*{ext}"))
    all_files.extend(Path(GENOME_DIR).glob(f"*{ext}.gz"))

all_files = sorted(set(all_files))

if not all_files:
    print(f"\nERROR: No FASTA files found in '{GENOME_DIR}'")
    print(f"Expected extensions: {FASTA_EXT}")
    sys.exit(1)

print(f"\nFound {len(all_files)} FASTA files\n")

# ----------------------------------------------------------
# RUN CHECKS
# ----------------------------------------------------------

results  = []
passed   = []
warned   = []
failed   = []
md5_seen = {}        # For duplicate detection
headers_seen = {}    # For duplicate header detection

for i, filepath in enumerate(all_files, start=1):

    # Progress indicator every 100 files
    if i % 100 == 0 or i == 1 or i == len(all_files):
        pct = 100 * i / len(all_files)
        print(f"  Checking [{i:>5}/{len(all_files)}]  {pct:.1f}%  ...  {filepath.name}")

    result = check_fasta(filepath)

    # --------------------------------------------------
    # CHECK 8: Duplicate file detection (by MD5)
    # --------------------------------------------------

    try:
        md5 = file_md5(filepath)
        if md5 in md5_seen:
            result["warnings"].append(
                f"Duplicate file — identical content to {md5_seen[md5]}"
            )
            if result["status"] == "PASS":
                result["status"] = "WARN"
        else:
            md5_seen[md5] = filepath.name
    except Exception:
        pass

    # --------------------------------------------------
    # CHECK 9: Duplicate sequence headers
    # --------------------------------------------------

    header = result["metrics"].get("header", "")
    if header:
        if header in headers_seen:
            result["warnings"].append(
                f"Duplicate sequence header — same header in {headers_seen[header]}"
            )
            if result["status"] == "PASS":
                result["status"] = "WARN"
        else:
            headers_seen[header] = filepath.name

    results.append(result)

    # Categorise
    if result["status"] == "PASS":
        passed.append(str(filepath))
    elif result["status"] == "WARN":
        warned.append(str(filepath))
    else:
        failed.append(str(filepath))

# ----------------------------------------------------------
# WRITE OUTPUT FILES
# ----------------------------------------------------------

# 1. Full summary TSV
with open(SUMMARY_TSV, "w") as f:
    f.write("basename\tstatus\tlength_bp\tlength_fmt\tn_sequences\t"
            "gc_pct\tn_pct\tfile_size_kb\terrors\twarnings\theader\n")

    for r in results:
        m = r["metrics"]
        f.write("\t".join([
            r["basename"],
            r["status"],
            str(m.get("length_bp",     "")),
            str(m.get("length_fmt",    "")),
            str(m.get("n_sequences",   "")),
            str(m.get("gc_pct",        "")),
            str(m.get("n_pct",         "")),
            str(m.get("file_size_kb",  "")),
            " | ".join(r["errors"])   if r["errors"]   else "",
            " | ".join(r["warnings"]) if r["warnings"] else "",
            m.get("header", ""),
        ]) + "\n")

# 2. Passed genomes list (ready for PGA)
with open(PASSED_TXT, "w") as f:
    for p in sorted(passed + warned):   # Include warnings in passed list
        f.write(p + "\n")

# 3. Failed genomes list
with open(FAILED_TXT, "w") as f:
    for p in failed:
        f.write(p + "\n")

# 4. Warnings list
with open(WARNINGS_TXT, "w") as f:
    for r in results:
        if r["status"] == "WARN":
            f.write(f"{r['file']}\n")
            for w in r["warnings"]:
                f.write(f"  WARNING: {w}\n")
            f.write("\n")

# ----------------------------------------------------------
# PRINT FAILED DETAILS
# ----------------------------------------------------------

if failed:
    print(f"\n{'=' * 70}")
    print("FAILED GENOMES — DETAILS")
    print(f"{'=' * 70}")
    for r in results:
        if r["status"] == "FAIL":
            print(f"\n  FILE   : {r['basename']}")
            for err in r["errors"]:
                print(f"  ERROR  : {err}")
            for warn in r["warnings"]:
                print(f"  WARN   : {warn}")
            m = r["metrics"]
            if "length_fmt" in m:
                print(f"  LENGTH : {m['length_fmt']}")

# ----------------------------------------------------------
# PRINT WARNING SUMMARY
# ----------------------------------------------------------

if warned:
    print(f"\n{'=' * 70}")
    print("GENOMES WITH WARNINGS (will still be annotated)")
    print(f"{'=' * 70}")
    for r in results:
        if r["status"] == "WARN":
            print(f"\n  FILE   : {r['basename']}")
            for w in r["warnings"]:
                print(f"  WARN   : {w}")
            m = r["metrics"]
            if "length_fmt" in m:
                print(f"  LENGTH : {m['length_fmt']}  GC: {m.get('gc_pct','')}%  N: {m.get('n_pct','')}%")

# ----------------------------------------------------------
# FINAL SUMMARY
# ----------------------------------------------------------

total      = len(all_files)
n_pass     = len(passed)
n_warn     = len(warned)
n_fail     = len(failed)
pass_rate  = 100 * (n_pass + n_warn) / total if total > 0 else 0

# Length statistics for passed genomes
lengths = [
    r["metrics"]["length_bp"]
    for r in results
    if "length_bp" in r["metrics"] and r["status"] != "FAIL"
]

print(f"\n{'=' * 70}")
print("QC SUMMARY")
print(f"{'=' * 70}")
print(f"Total files checked : {total}")
print(f"  PASS              : {n_pass}  ({100*n_pass/total:.1f}%)")
print(f"  WARN              : {n_warn}  ({100*n_warn/total:.1f}%) — will annotate")
print(f"  FAIL              : {n_fail}  ({100*n_fail/total:.1f}%) — excluded from PGA")
print(f"Ready for PGA       : {n_pass + n_warn}  ({pass_rate:.1f}%)")

if lengths:
    print(f"\nSequence length statistics (passing genomes):")
    print(f"  Min    : {format_bp(min(lengths))}")
    print(f"  Max    : {format_bp(max(lengths))}")
    print(f"  Mean   : {format_bp(int(sum(lengths)/len(lengths)))}")

print(f"\nOutput files:")
print(f"  Full report  : {SUMMARY_TSV}")
print(f"  Ready list   : {PASSED_TXT}  ({n_pass + n_warn} genomes)")
print(f"  Failed list  : {FAILED_TXT}  ({n_fail} genomes)")
print(f"  Warnings     : {WARNINGS_TXT}")
print(f"\nCompleted : {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
print("=" * 70)

# ----------------------------------------------------------
# NEXT STEP INSTRUCTIONS
# ----------------------------------------------------------

print("\nNEXT STEPS:")
print(f"  1. Review failed genomes : cat {FAILED_TXT}")
print(f"  2. Review warnings       : cat {WARNINGS_TXT}")
print(f"  3. Use passed list as input for SLURM array job:")
print(f"     cp {PASSED_TXT} genome_list.txt")
print(f"     sbatch scripts/run_pga_array.sh")
print("=" * 70)