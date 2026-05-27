#!/usr/bin/env python3
# ==========================================================
# Calculate Chloroplast Genome Sizes from FASTA Files
# ==========================================================
import os
import sys
import pandas as pd
from pathlib import Path

def calculate_fasta_size(fasta_file):
    """
    Calculate total sequence length from a FASTA file.
    Ignores sequence headers and counts only nucleotides.
    """
    total_length = 0
    try:
        with open(fasta_file, 'r') as f:
            for line in f:
                line = line.strip()
                # Skip header lines (start with '>')
                if not line.startswith('>') and line:
                    total_length += len(line)
    except Exception as e:
        print(f"[ERROR] {fasta_file}: {e}")
        return None
    return total_length

def process_fasta_directory(directory_path):
    """
    Process all FASTA files in a directory and calculate sizes.
    """
    fasta_dir = Path(directory_path)
    
    if not fasta_dir.exists():
        print(f"[ERROR] Directory does not exist: {directory_path}")
        return None
    
    # Find all FASTA files (.fasta, .fa, .fna extensions)
    fasta_files = list(fasta_dir.glob("*.fasta")) + \
                  list(fasta_dir.glob("*.fa")) + \
                  list(fasta_dir.glob("*.fna"))
    
    if not fasta_files:
        print(f"[WARNING] No FASTA files found in {directory_path}")
        return None
    
    print(f"Found {len(fasta_files)} FASTA files\n")
    
    results = []
    
    for i, fasta_file in enumerate(sorted(fasta_files), 1):
        filename = fasta_file.name
        accession = filename.split('.')[0]  # Extract accession (filename without extension)
        
        size = calculate_fasta_size(fasta_file)
        
        if size is not None:
            results.append({
                'accession': accession,
                'filename': filename,
                'size_bp': size,
                'size_kb': round(size / 1000, 2),
                'size_mb': round(size / 1000000, 3)
            })
            print(f"[{i}/{len(fasta_files)}] {accession}: {size:,} bp ({size/1000:.2f} kb)")
        else:
            print(f"[{i}/{len(fasta_files)}] {filename}: FAILED")
    
    # Create DataFrame
    df = pd.DataFrame(results)
    
    # Calculate statistics
    print("\n" + "="*60)
    print("GENOME SIZE STATISTICS")
    print("="*60)
    print(f"Total genomes: {len(df)}")
    print(f"Mean size: {df['size_bp'].mean():,.0f} bp ({df['size_kb'].mean():.2f} kb)")
    print(f"Median size: {df['size_bp'].median():,.0f} bp ({df['size_bp'].median()/1000:.2f} kb)")
    print(f"Min size: {df['size_bp'].min():,} bp ({df['size_kb'].min():.2f} kb)")
    print(f"Max size: {df['size_bp'].max():,} bp ({df['size_kb'].max():.2f} kb)")
    print(f"Std Dev: {df['size_bp'].std():,.0f} bp")
    print("="*60 + "\n")
    
    # Save to CSV in results directory
    results_dir = Path("results")
    results_dir.mkdir(exist_ok=True)
    output_csv = results_dir / "genome_sizes.csv"
    df.to_csv(output_csv, index=False)
    print(f"Results saved to: {output_csv}\n")
    
    # Display full table
    print(df.to_string(index=False))
    
    return df

# ==========================================================
# MAIN
# ==========================================================
if __name__ == "__main__":
    # Change this path to your directory
    fasta_directory = "data/angio_fasta_c"
    
    # Accept directory path as command-line argument
    if len(sys.argv) > 1:
        fasta_directory = sys.argv[1]
    
    print(f"Processing FASTA files in: {fasta_directory}\n")
    df = process_fasta_directory(fasta_directory)
    
    if df is not None:
        print("\n✓ All genomes processed successfully!")
    else:
        print("\n✗ Error processing directory")
        sys.exit(1)