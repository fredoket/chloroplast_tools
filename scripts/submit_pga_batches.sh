#!/bin/bash
# ==========================================================
# AUTO BATCH SUBMISSION FOR PGA (5777 GENOMES SAFE MODE)
# ==========================================================

set -euo pipefail

PROJECT_DIR="/home/foketch/genome_assembly/chloroplast_tools"
SLURM_SCRIPT="${PROJECT_DIR}/scripts/run_pga_array.sh"
GENOME_LIST="${PROJECT_DIR}/genome_list.txt"

TOTAL=$(wc -l < "${GENOME_LIST}")
BATCH_SIZE=1000

echo "========================================================"
echo "PGA BATCH SUBMISSION"
echo "Total genomes: ${TOTAL}"
echo "Batch size   : ${BATCH_SIZE}"
echo "Max array    : 1000 (SLURM limit)"
echo "========================================================"

OFFSET=0
BATCH_ID=1

while [[ ${OFFSET} -lt ${TOTAL} ]]; do

    END=$BATCH_SIZE
    if (( OFFSET + BATCH_SIZE > TOTAL )); then
        END=$((TOTAL - OFFSET))
    fi

    echo ""
    echo "Submitting batch ${BATCH_ID}"
    echo "OFFSET = ${OFFSET}"
    echo "ARRAY  = 1-${END}"

    sbatch \
        --export=OFFSET=${OFFSET} \
        --array=1-${END}%25 \
        "${SLURM_SCRIPT}"

    OFFSET=$((OFFSET + BATCH_SIZE))
    BATCH_ID=$((BATCH_ID + 1))

done

echo ""
echo "All batches submitted successfully."