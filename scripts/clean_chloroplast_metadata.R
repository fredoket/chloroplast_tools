#!/usr/bin/env Rscript

# ==========================================================
# Chloroplast Metadata Cleaning Pipeline (Improved)
#
# Steps:
#   1. Load data
#   2. Clean + select core columns
#   3. Filter genome size >= 120kb
#   4. Deduplicate by taxonomy_id with ranking:
#        - complete genome preference
#        - newest year
#        - largest genome size
#   5. Save results
#
# Input:
#   data/chloroplast_metadata_full_taxonomy.csv
#
# Output:
#   results/chloroplast_metadata_cleaned.csv
# ==========================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(janitor)
  library(stringr)
})

# ----------------------------------------------------------
# PATHS
# ----------------------------------------------------------

input_file <- "data/chloroplast_metadata_full_taxonomy.csv"
output_file <- "results/chloroplast_metadata_cleaned.csv"

dir.create("results", showWarnings = FALSE)

# ----------------------------------------------------------
# LOAD + CLEAN + SELECT (YOUR REQUESTED STEP INTEGRATED)
# ----------------------------------------------------------

df_ch <- readr::read_csv(input_file, show_col_types = FALSE) |>
  janitor::clean_names() |>
  dplyr::select(
    accession,
    taxonomy_id,
    year,
    genome_size_bp,
    title
  ) |>
  dplyr::mutate(
    genome_size_bp = as.numeric(genome_size_bp),
    year = as.numeric(year),
    title = as.character(title),
    complete_flag = stringr::str_detect(
      stringr::str_to_lower(title),
      "complete genome"
    )
  ) |>
  dplyr::filter(genome_size_bp >= 120000)

cat("Initial filtered records:", nrow(df_ch), "\n")

# ----------------------------------------------------------
# DEDUPLICATION (IMPROVED LOGIC)
# ----------------------------------------------------------

df_clean <- df_ch |>
  dplyr::group_by(taxonomy_id) |>
  dplyr::arrange(
    dplyr::desc(complete_flag),     # prefer complete genomes
    dplyr::desc(year),              # newest first
    dplyr::desc(genome_size_bp)     # largest genome
  ) |>
  dplyr::slice(1) |>
  dplyr::ungroup()

# ----------------------------------------------------------
# SAVE OUTPUT
# ----------------------------------------------------------

write_csv(df_clean, output_file)

# ----------------------------------------------------------
# SUMMARY
# ----------------------------------------------------------

cat("\n=========================\n")
cat("CLEANING COMPLETE\n")
cat("=========================\n")

cat("Final records:", nrow(df_clean), "\n")
cat("Output file:", output_file, "\n")

cat("\nGenome size summary:\n")
print(summary(df_clean$genome_size_bp))