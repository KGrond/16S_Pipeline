#!/bin/bash

# Activates a specific Conda environment and verifies tool installation.

# Exit immediately on error
set -eo pipefail

# --- Configuration ---
CONDA_ENV="qiime2-2025.10"
TOOLS_TO_VERIFY="cutadapt fastqc unzip"

# --- Initialization and Activation ---

# 1. Source Conda initialization and activate environment
CONDA_BASE=$(conda info --base 2>/dev/null || echo "$HOME/miniconda3")
source "${CONDA_BASE}/etc/profile.d/conda.sh" || { echo "FATAL: Conda init failed."; exit 1; }

conda activate "${CONDA_ENV}" || { echo "FATAL: Environment '${CONDA_ENV}' not found."; exit 1; }
echo "✅ Activated environment: ${CONDA_ENV}"

# 2. Configure Subdir (M-series Mac compatibility)
if [[ "$(uname)" == "Darwin" ]]; then
    conda config --env --set subdir osx-64
    FORCE_SUBDIR="yes"
    echo "⚙️ Configured for osx-64 binaries."
else
    FORCE_SUBDIR="no"
fi

# 3. Fix Missing Tools (Install FastQC)
echo "⏳ Installing/Updating FastQC..."
INSTALL_CMD="conda install fastqc -c bioconda -c conda-forge -y"

if [[ "${FORCE_SUBDIR}" == "yes" ]]; then
    CONDA_SUBDIR=osx-64 ${INSTALL_CMD}
else
    ${INSTALL_CMD}
fi

# --- Verification ---
echo "--- Verifying Tools ---"

# Function to test a command
test_command() {
    local command_name="$1"
    
    echo -n "Testing ${command_name}... "
    if "${command_name}" --version &> /dev/null || "${command_name}" -v &> /dev/null; then
        echo "✅ PASS"
    else
        echo "❌ FAIL"
    fi
}

# Run the tests
test_command "cutadapt"
test_command "fastqc"
test_command "unzip"

echo "--- Verification complete. Run remove_primers.sh"