library(dplyr)
library(stringr)

df_fasta_header <- readr::read_csv("data/fasta_header_names.csv") |>
  dplyr::distinct(name, .keep_all = TRUE) |>
  filter(!str_detect(name, regex("UNVERIFIED", ignore_case = TRUE))) |>
  mutate(
    name = str_remove_all(name, "\\[|\\]"),
    name = str_remove(name, "TPA_asm:\\s*"),
    scientific_name = name
    
  ) |>
  distinct(name, .keep_all = TRUE)|>
  
  mutate(
    cleaned = name |>
      str_remove(accession) |>
      str_remove(",.*$") |>
      str_remove("\\b(chloroplast|cultivar|isolate|genome|plastid|complete|partial|voucher|sequence)\\b.*$") |>
      str_squish()
  ) |>
  mutate(
    cleaned = cleaned %>%
      # Remove bracketed taxonomic sections e.g. (sect. Taraxacum)
      str_remove_all("\\s*\\([^\\)]+\\)") %>%
      
      # Retain Genus + species OR Genus + sp.
      str_extract("^[A-Z][a-zA-Z-]+\\s+(?:sp\\.|[a-z-]+)") %>%
      
      # Trim whitespace
      str_trim()
  ) |>
  distinct(cleaned, .keep_all = TRUE) |>
  filter(!str_detect(cleaned, "^[A-Z][a-zA-Z-]+\\s+sp\\.?$")) |>
  dplyr::select(file_name, accession, cleaned) |>
  mutate(faster_header = paste(accession, cleaned))

