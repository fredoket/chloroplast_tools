#!/bin/bash
# ==========================================================
# PGA AUTO INSTALL + VALIDATION (ROBUST VERSION)
# ==========================================================

set -euo pipefail

# ----------------------------------------------------------
# PROJECT PATHS (auto-detected)
# ----------------------------------------------------------

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TOOLS_DIR="${PROJECT_DIR}/tools"
PGA_DIR="${TOOLS_DIR}/PGA"

# We'll dynamically locate PGA.pl after install
PGA_SCRIPT=""

# Colours
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

pass()    { echo -e "  ${GREEN}[PASS]${NC}    $1"; }
fail()    { echo -e "  ${RED}[FAIL]${NC}    $1"; exit 1; }
warn()    { echo -e "  ${YELLOW}[WARN]${NC}    $1"; }
info()    { echo -e "  ${BLUE}[INFO]${NC}    $1"; }
section() { echo -e "\n${BLUE}--- $1 ---${NC}"; }

echo "========================================================"
echo " PGA AUTO INSTALL & VALIDATION"
echo "========================================================"
echo " Project : ${PROJECT_DIR}"
echo " Started : $(date)"
echo "========================================================"

# ----------------------------------------------------------
# STEP 1: CHECK TOOLS DIRECTORY
# ----------------------------------------------------------

section "1. Checking tools directory"

[[ -d "${TOOLS_DIR}" ]] || fail "Missing tools directory: ${TOOLS_DIR}"
pass "Tools directory exists"

mkdir -p "${TOOLS_DIR}/PGA" 2>/dev/null || true

# ----------------------------------------------------------
# STEP 2: INSTALL / FIX PGA
# ----------------------------------------------------------

section "2. Installing / Repairing PGA"

# If PGA exists but broken → delete it
if [[ -d "${PGA_DIR}" ]]; then
    if find "${PGA_DIR}" -name "PGA.pl" | grep -q "PGA.pl"; then
        pass "PGA already installed and valid"
    else
        warn "Broken PGA detected — removing and reinstalling"
        rm -rf "${PGA_DIR}"
    fi
fi

# Install if missing
if [[ ! -d "${PGA_DIR}" ]]; then
    info "Cloning PGA from GitHub..."

    cd "${TOOLS_DIR}"

    if ! command -v git &>/dev/null; then
        fail "git not available"
    fi

    git clone https://github.com/quxiaojian/PGA.git PGA

    pass "PGA cloned"

    cd "${PROJECT_DIR}"
fi

# ----------------------------------------------------------
# STEP 3: LOCATE PGA.pl (robust search)
# ----------------------------------------------------------

section "3. Locating PGA.pl"

PGA_SCRIPT=$(find "${PGA_DIR}" -name "PGA.pl" | head -1 || true)

if [[ -z "${PGA_SCRIPT}" ]]; then
    fail "PGA.pl not found anywhere inside ${PGA_DIR}"
else
    pass "PGA.pl found: ${PGA_SCRIPT}"
fi

# ----------------------------------------------------------
# STEP 4: CHECK PERL
# ----------------------------------------------------------

section "4. Checking Perl"

command -v perl &>/dev/null || fail "Perl not found"

PERL_VER=$(perl --version | grep -oP 'v[\d.]+')
pass "Perl OK (${PERL_VER})"

# ----------------------------------------------------------
# STEP 5: CHECK BIOPERL
# ----------------------------------------------------------

section "5. Checking BioPerl"

if perl -e "use Bio::SeqIO;" 2>/dev/null; then
    pass "BioPerl installed"
else
    warn "BioPerl missing"
    info "Install: conda install -c bioconda perl-bioperl"
fi

# ----------------------------------------------------------
# STEP 6: CHECK BLAT
# ----------------------------------------------------------

section "6. Checking BLAT"

if command -v blat &>/dev/null; then
    pass "BLAT found"
else
    warn "BLAT missing"
    info "Install: conda install -c bioconda blat"
fi

# ----------------------------------------------------------
# FINAL SUMMARY
# ----------------------------------------------------------

echo ""
echo "========================================================"
echo " INSTALLATION COMPLETE"
echo "========================================================"

echo -e " PGA location:"
echo "   ${PGA_SCRIPT}"

echo ""
echo " Completed: $(date)"
echo "========================================================"