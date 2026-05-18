#!/bin/bash

################################################################################
# Automated Miniconda + Mamba Installation for HPC
# 
# Usage: bash install_conda_hpc.sh
# 
# This script will:
# 1. Detect system architecture
# 2. Download Miniconda
# 3. Install Miniconda in your home directory
# 4. Initialize conda
# 5. Install Mamba for faster package management
# 6. Configure bioconda and conda-forge channels
#
# Tested on: Linux x86_64, macOS Intel/Apple Silicon
################################################################################

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

# Installation path (change if you want different location)
CONDA_PREFIX="${CONDA_PREFIX:=$HOME/miniconda3}"

# Alternative: Install to scratch if home is limited
# CONDA_PREFIX="/scratch/$USER/miniconda3"

# Temporary directory for download
TMPDIR_CONDA="/tmp/conda_install_$$"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# FUNCTIONS
# ============================================================================

print_header() {
    echo ""
    echo -e "${BLUE}================================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================================================${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

check_system() {
    print_header "Step 1: Detecting System Architecture"
    
    # Detect OS
    OS=$(uname -s)
    ARCH=$(uname -m)
    
    echo "Operating System: $OS"
    echo "Architecture: $ARCH"
    
    # Determine installer filename
    if [[ "$OS" == "Linux" ]]; then
        if [[ "$ARCH" == "x86_64" ]]; then
            INSTALLER="Miniconda3-latest-Linux-x86_64.sh"
            MINIFORGE_INSTALLER="Miniforge3-Linux-x86_64.sh"
        elif [[ "$ARCH" == "aarch64" ]]; then
            INSTALLER="Miniconda3-latest-Linux-aarch64.sh"
            MINIFORGE_INSTALLER="Miniforge3-Linux-aarch64.sh"
        else
            print_error "Unsupported Linux architecture: $ARCH"
            exit 1
        fi
    elif [[ "$OS" == "Darwin" ]]; then  # macOS
        if [[ "$ARCH" == "x86_64" ]]; then
            INSTALLER="Miniconda3-latest-MacOSX-x86_64.sh"
            MINIFORGE_INSTALLER="Miniforge3-MacOSX-x86_64.sh"
        elif [[ "$ARCH" == "arm64" ]]; then
            INSTALLER="Miniconda3-latest-MacOSX-arm64.sh"
            MINIFORGE_INSTALLER="Miniforge3-MacOSX-arm64.sh"
        else
            print_error "Unsupported macOS architecture: $ARCH"
            exit 1
        fi
    else
        print_error "Unsupported operating system: $OS"
        exit 1
    fi
    
    print_success "System detected: $OS $ARCH"
    print_success "Installer: $INSTALLER"
}

check_disk_space() {
    print_header "Step 2: Checking Disk Space"
    
    # Check available space in home directory
    AVAILABLE_SPACE=$(df "$HOME" | awk 'NR==2 {print $4}')  # in KB
    REQUIRED_SPACE=$((3 * 1024 * 1024))  # 3 GB in KB
    
    echo "Available space in $HOME: $((AVAILABLE_SPACE / 1024 / 1024)) GB"
    echo "Required space: 3 GB"
    
    if [[ $AVAILABLE_SPACE -lt $REQUIRED_SPACE ]]; then
        print_warning "Limited space in home directory"
        echo "Alternative location with more space recommended."
        echo "You can set: CONDA_PREFIX=/scratch/\$USER/miniconda3"
        read -p "Continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        print_success "Sufficient disk space available"
    fi
}

download_miniconda() {
    print_header "Step 3: Downloading Miniconda"
    
    mkdir -p "$TMPDIR_CONDA"
    cd "$TMPDIR_CONDA"
    
    DOWNLOAD_URL="https://repo.anaconda.com/miniconda/$INSTALLER"
    
    echo "Downloading from: $DOWNLOAD_URL"
    echo ""
    
    if command -v wget &> /dev/null; then
        wget -q --show-progress "$DOWNLOAD_URL"
    elif command -v curl &> /dev/null; then
        curl -L -o "$INSTALLER" "$DOWNLOAD_URL"
    else
        print_error "Neither wget nor curl available"
        exit 1
    fi
    
    if [[ ! -f "$INSTALLER" ]]; then
        print_error "Failed to download installer"
        exit 1
    fi
    
    # Verify download
    INSTALLER_SIZE=$(du -h "$INSTALLER" | cut -f1)
    print_success "Downloaded $INSTALLER ($INSTALLER_SIZE)"
}

install_miniconda() {
    print_header "Step 4: Installing Miniconda"
    
    cd "$TMPDIR_CONDA"
    
    echo "Installation path: $CONDA_PREFIX"
    echo ""
    
    # Check if already installed
    if [[ -d "$CONDA_PREFIX" ]]; then
        print_warning "Conda already installed at $CONDA_PREFIX"
        read -p "Reinstall? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_error "Installation cancelled"
            return 1
        fi
        rm -rf "$CONDA_PREFIX"
    fi
    
    # Run installer
    chmod +x "$INSTALLER"
    echo "Running installer (this may take a few minutes)..."
    
    if bash "$INSTALLER" -b -p "$CONDA_PREFIX"; then
        print_success "Miniconda installed successfully"
        return 0
    else
        print_error "Installation failed"
        return 1
    fi
}

initialize_conda() {
    print_header "Step 5: Initializing Conda"
    
    # Detect shell
    SHELL_NAME=$(basename "$SHELL")
    
    echo "Detected shell: $SHELL_NAME"
    echo ""
    
    # Initialize conda
    case "$SHELL_NAME" in
        bash)
            "$CONDA_PREFIX/bin/conda" init bash
            RC_FILE="$HOME/.bashrc"
            ;;
        zsh)
            "$CONDA_PREFIX/bin/conda" init zsh
            RC_FILE="$HOME/.zshrc"
            ;;
        fish)
            "$CONDA_PREFIX/bin/conda" init fish
            RC_FILE="$HOME/.config/fish/config.fish"
            ;;
        *)
            print_warning "Unknown shell: $SHELL_NAME"
            print_warning "Manually run: $CONDA_PREFIX/bin/conda init $SHELL_NAME"
            RC_FILE=""
            ;;
    esac
    
    if [[ -n "$RC_FILE" ]]; then
        print_success "Conda initialized in $RC_FILE"
        echo "Sourcing configuration..."
        source "$RC_FILE" 2>/dev/null || true
    fi
    
    # Verify conda works
    if "$CONDA_PREFIX/bin/conda" --version > /dev/null 2>&1; then
        print_success "Conda verified working"
    else
        print_error "Conda verification failed"
        return 1
    fi
}

install_mamba() {
    print_header "Step 6: Installing Mamba (Optional but Recommended)"
    
    read -p "Install Mamba for faster package management? (y/n) " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Skipping Mamba installation"
        return 0
    fi
    
    echo "Installing Mamba..."
    echo ""
    
    # Source conda for this shell session
    source "$CONDA_PREFIX/etc/profile.d/conda.sh"
    
    # Install mamba in base environment
    if "$CONDA_PREFIX/bin/conda" install -y -c conda-forge mamba; then
        print_success "Mamba installed successfully"
        
        # Verify mamba
        if "$CONDA_PREFIX/bin/mamba" --version > /dev/null 2>&1; then
            print_success "Mamba verified working"
        fi
    else
        print_warning "Mamba installation failed, but conda is still functional"
    fi
}

configure_channels() {
    print_header "Step 7: Configuring Conda Channels"
    
    source "$CONDA_PREFIX/etc/profile.d/conda.sh"
    
    echo "Adding bioconda and conda-forge channels..."
    echo ""
    
    conda config --add channels conda-forge
    conda config --add channels bioconda
    conda config --set channel_priority strict
    
    print_success "Channels configured"
    echo ""
    echo "Current configuration:"
    conda config --show channels
}

configure_hpc_settings() {
    print_header "Step 8: HPC-Specific Configuration (Optional)"
    
    read -p "Apply HPC optimizations (TMPDIR, disable auto-activation)? (y/n) " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return 0
    fi
    
    # Disable auto-activation of base
    conda config --set auto_activate_base false
    print_success "Disabled auto-activation of base environment"
    
    # Set TMPDIR in shell RC
    SHELL_NAME=$(basename "$SHELL")
    
    case "$SHELL_NAME" in
        bash)
            RC_FILE="$HOME/.bashrc"
            ;;
        zsh)
            RC_FILE="$HOME/.zshrc"
            ;;
        *)
            RC_FILE="$HOME/.profile"
            ;;
    esac
    
    echo "" >> "$RC_FILE"
    echo "# Conda temporary directory (for HPC)" >> "$RC_FILE"
    echo "export TMPDIR=/tmp/\$USER" >> "$RC_FILE"
    echo "mkdir -p \$TMPDIR" >> "$RC_FILE"
    
    print_success "Added TMPDIR configuration to $RC_FILE"
}

cleanup() {
    print_header "Step 9: Cleanup"
    
    # Remove temporary directory
    rm -rf "$TMPDIR_CONDA"
    print_success "Temporary files cleaned up"
}

verify_installation() {
    print_header "Step 10: Verification"
    
    echo "Testing conda installation..."
    echo ""
    
    # Source conda
    source "$CONDA_PREFIX/etc/profile.d/conda.sh"
    
    # Check conda version
    echo "Conda version:"
    conda --version
    echo ""
    
    # Check Python version
    echo "Python version:"
    python --version
    echo ""
    
    # Check mamba (if installed)
    if command -v mamba &> /dev/null; then
        echo "Mamba version:"
        mamba --version
        echo ""
    fi
    
    # Check channels
    echo "Configured channels:"
    conda config --show channels
    echo ""
    
    print_success "Installation verified successfully!"
}

print_next_steps() {
    print_header "Next Steps"
    
    cat << 'EOF'
1. Close and reopen your terminal, or run:
   source ~/.bashrc  (or ~/.zshrc for zsh)

2. Create your first environment:
   conda create -n myenv python=3.11
   
3. Activate environment:
   conda activate myenv

4. Install bioinformatics packages:
   mamba install -c bioconda samtools bcftools biopython

5. Check documentation:
   https://docs.conda.io/
   https://mamba.readthedocs.io/

For HPC SLURM scripts, add to your script:
   source ~/miniconda3/etc/profile.d/conda.sh
   conda activate myenv

Questions or issues? Check HPC_CONDA_INSTALLATION_GUIDE.md

EOF
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Automated Miniconda + Mamba Installation for HPC                ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    check_system
    check_disk_space
    download_miniconda
    install_miniconda || exit 1
    initialize_conda || exit 1
    install_mamba
    configure_channels
    configure_hpc_settings
    cleanup
    verify_installation
    print_next_steps
}

# Run main function
main
