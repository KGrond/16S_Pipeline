#!/bin/bash

# --- 16S Primer Removal Script using Cutadapt (Execution Only) ---

# 0. Configuration
# This script assumes the environment 'qiime2-amplicon-2025.7' is already installed
# and contains cutadapt.

# Define Input/Output Directories and Metadata File
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Input Directory (where the raw demultiplexed FASTQ files are located)
INPUT_DIR="${SCRIPT_DIR}/demultiplexed_seq"

# Output Directory for trimmed sequences
OUTPUT_DIR="${SCRIPT_DIR}/trimmed_sequences"

# Metadata file (relative to the script)
METADATA_FILE="${SCRIPT_DIR}/metadata.csv"

# --- PRIMER SEQUENCES ---
# V4 Region Primers (515F/806R)
FWD_PRIMER="GTGCCAGCMGCCGCGGTAA"
REV_PRIMER="GGACTACHVGGGTWTCTAAT"

# --- 1. Conda Environment Activation ---
CONDA_ENV="qiime2-2025.10"

echo "Activating Conda environment: $CONDA_ENV"
# Check if conda is available and activate the environment
if command -v conda &> /dev/null; then
    CONDA_BASE=$(conda info --base)
    if [ -f "${CONDA_BASE}/etc/profile.d/conda.sh" ]; then
        source "${CONDA_BASE}/etc/profile.d/conda.sh"
    fi
    source activate $CONDA_ENV
    
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to activate Conda environment '${CONDA_ENV}'. Did you run installs.sh?"
        exit 1
    fi
    echo "Environment activated."
else
    echo "ERROR: 'conda' command not found. Cannot proceed."
    exit 1
fi

# Define the Cutadapt command prefix using 'conda run' for maximum reliability
CUTADAPT_COMMAND="conda run -n ${CONDA_ENV} cutadapt"
echo "Cutadapt commands will be executed using: ${CUTADAPT_COMMAND}"

# --- 2. Create Output Directory ---
mkdir -p "$OUTPUT_DIR"
echo "Output will be saved to: $OUTPUT_DIR"

# 3. Primer Removal Loop
# Looking for non-compressed .fastq files
echo "Starting primer trimming with Cutadapt..."
# Change CWD to the input directory for simplified input paths inside the loop
# We assume the directory structure is $INPUT_DIR/R1 and $INPUT_DIR/R2
cd "$INPUT_DIR/R1"

# Find all R1 files (Forward reads), checking for the non-compressed .fastq extension
R1_FILES=$(ls *R1*.fastq.gz 2>/dev/null)
if [ -z "$R1_FILES" ]; then
    echo "ERROR: No R1 (Forward) FASTQ files found in $INPUT_DIR/R1. Check your path and file naming. Expecting *.fastq.gz"
    # Go back to the original directory before exiting
    cd - > /dev/null
    exit 1
fi

for R1_FILE in $R1_FILES; do
    # Derive the corresponding R2 file name
    R2_FILE=${R1_FILE/R1/R2}
    
    # Check if the R2 file exists
    if [ ! -f "../R2/$R2_FILE" ]; then
        echo "WARNING: Corresponding R2 file not found for $R1_FILE in ../R2/. Skipping this pair."
        continue
    fi

    # Extract the base name (remove R1/R2 suffix and .fastq)
    BASE_NAME=$(basename "$R1_FILE" | sed -E 's/(_R1|_R2).*\.fastq.gz//')
    
    echo "Processing $BASE_NAME..."

    # Cutadapt command execution
    ${CUTADAPT_COMMAND} \
        -g "$FWD_PRIMER" \
        -G "$REV_PRIMER" \
        -a "$(echo "$REV_PRIMER" | tr 'ATGCatgc' 'TACGtacg' | rev)" \
        -G "$(echo "$FWD_PRIMER" | tr 'ATGCatgc' 'TACGtacg' | rev)" \
        --minimum-length 1 \
        --cores 4 \
        -o "$OUTPUT_DIR/${BASE_NAME}_R1_trimmed.fastq.gz" \
        -p "$OUTPUT_DIR/${BASE_NAME}_R2_trimmed.fastq.gz" \
        "$R1_FILE" \
        "../R2/$R2_FILE"

    if [ $? -ne 0 ]; then
        echo "FATAL ERROR: Cutadapt failed for $BASE_NAME. Please check the console output for any error messages."
    else
        echo "Successfully trimmed and saved files for $BASE_NAME."
    fi

done

# 4. Cleanup and Summary
cd - > /dev/null # Go back to the original directory
echo "Primer removal complete. Trimmed files are located in: $OUTPUT_DIR"
echo "Next step: Run run-fastqc.sh."
