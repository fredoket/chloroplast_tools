#!/bin/bash
# ==========================================================
# PGA SLURM ARRAY JOB (PRODUCTION + BATCH SAFE)
# Compatible with SLURM MaxArraySize = 1001
# Handles 5777 genomes via OFFSET batching system
# ==========================================================

#SBATCH --job-name=pga_annotation
#SBATCH --array=1-1000%25
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=02:00:00
#SBATCH --output=logs/pga_%A_%a.out
#SBATCH --error=logs/pga_%A_%a.err
#SBATCH --partition=cpulong

set -euo pipefail

# ----------------------------------------------------------
# PROJECT PATHS
# ----------------------------------------------------------

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FASTA_DIR="${PROJECT_DIR}/data/angio_fasta"
REF_DIR="${PROJECT_DIR}/references"
RESULTS_DIR="${PROJECT_DIR}/results/PGA_annotation"
GENOME_LIST="${PROJECT_DIR}/genome_list.txt"
PGA_SCRIPT="${PROJECT_DIR}/tools/PGA/PGA.pl"
LOG_DIR="${PROJECT_DIR}/logs"

# ----------------------------------------------------------
# SAFETY CHECKS
# ----------------------------------------------------------

CPUS=${SLURM_CPUS_PER_TASK:-4}

# ----------------------------------------------------------
# BATCH SYSTEM (CRITICAL FOR 5777 GENOMES)
# ----------------------------------------------------------

BATCH_SIZE=1000
OFFSET=${OFFSET:-0}
INDEX=$((OFFSET + SLURM_ARRAY_TASK_ID))

# ----------------------------------------------------------
# REFERENCES
# ----------------------------------------------------------

REF_ALL="${REF_DIR}/NC_001879.gb,${REF_DIR}/NC_000932.gb,${REF_DIR}/NC_001320.gb,${REF_DIR}/NC_005086.gb"
REFS="${REF_ALL}"

# ----------------------------------------------------------
# CREATE OUTPUT STRUCTURE
# ----------------------------------------------------------

mkdir -p "${RESULTS_DIR}"
mkdir -p "${LOG_DIR}"

# ----------------------------------------------------------
# VALIDATION
# ----------------------------------------------------------

if [[ ! -f "${GENOME_LIST}" ]]; then
    echo "[ERROR] genome_list.txt not found: ${GENOME_LIST}"
    exit 1
fi

if [[ ! -f "${PGA_SCRIPT}" ]]; then
    echo "[ERROR] PGA.pl not found: ${PGA_SCRIPT}"
    exit 1
fi

# ----------------------------------------------------------
# GET GENOME (SAFE INDEXING)
# ----------------------------------------------------------

GENOME=$(sed -n "${INDEX}p" "${GENOME_LIST}" | tr -d '\r')

if [[ -z "${GENOME}" ]]; then
    echo "[SKIP] No genome at INDEX=${INDEX}"
    exit 0
fi

if [[ ! -f "${GENOME}" ]]; then
    echo "[SKIP] File not found: ${GENOME}"
    exit 0
fi

if [[ ! -s "${GENOME}" ]]; then
    echo "[SKIP] Empty genome file: ${GENOME}"
    exit 0
fi

# ----------------------------------------------------------
# CLEAN BASENAME
# ----------------------------------------------------------

BASENAME=$(basename "${GENOME}")
BASENAME="${BASENAME%.fasta}"
BASENAME="${BASENAME%.fa}"
BASENAME="${BASENAME%.fna}"

GENOME_OUTDIR="${RESULTS_DIR}/${BASENAME}"

# ----------------------------------------------------------
# SKIP IF COMPLETED
# ----------------------------------------------------------

if [[ -f "${GENOME_OUTDIR}/${BASENAME}.gb" ]]; then
    echo "[SKIP] ${BASENAME} already completed"
    exit 0
fi

mkdir -p "${GENOME_OUTDIR}"

# ----------------------------------------------------------
# LOGGING
# ----------------------------------------------------------

echo "========================================================"
echo "PGA ANNOTATION JOB"
echo "========================================================"
echo "SLURM Array ID : ${SLURM_ARRAY_TASK_ID}"
echo "OFFSET         : ${OFFSET}"
echo "Computed Index : ${INDEX}"
echo "Genome         : ${GENOME}"
echo "Output         : ${GENOME_OUTDIR}"
echo "CPUs           : ${CPUS}"
echo "Started        : $(date)"
echo "========================================================"

# ----------------------------------------------------------
# RUN PGA
# ----------------------------------------------------------

perl "${PGA_SCRIPT}" \
    -s "${REFS}" \
    -g "${GENOME}" \
    -o "${GENOME_OUTDIR}" \
    -t "${CPUS}"

EXIT_CODE=$?

# ----------------------------------------------------------
# POST-RUN CHECKS
# ----------------------------------------------------------

echo ""
echo "Exit code : ${EXIT_CODE}"
echo "Finished  : $(date)"

if [[ ${EXIT_CODE} -ne 0 ]]; then
    echo "${BASENAME}" >> "${RESULTS_DIR}/failed_genomes.log"
    echo "[FAILED] ${BASENAME}"
    exit ${EXIT_CODE}
fi

if [[ ! -f "${GENOME_OUTDIR}/${BASENAME}.gb" ]]; then
    echo "${BASENAME}" >> "${RESULTS_DIR}/failed_genomes.log"
    echo "[FAILED] Missing GenBank output"
    exit 1
fi

# ----------------------------------------------------------
# SUCCESS LOG
# ----------------------------------------------------------

echo "${BASENAME}" >> "${RESULTS_DIR}/completed_genomes.log"

echo "[DONE] ${BASENAME}"
ls -lh "${GENOME_OUTDIR}/"

exit 0