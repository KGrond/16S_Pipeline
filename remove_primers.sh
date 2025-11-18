#!/bin/bash

# --- 16S Primer Removal Script using Cutadapt ---

# 0. Configuration
# IMPORTANT: Adjust these variables based on your data location and desired primer sequences.

# Define Input/Output Directories and Metadata File
# These paths MUST be adjusted to match your system configuration.
INPUT_DIR="/Users/kgrond/Desktop/INBRE-DataScience/16S_pipeline/test_data/demultiplexed_seq"
# The OUTPUT_DIR is defined as an absolute path for stability.
OUTPUT_DIR="/Users/kgrond/Desktop/INBRE-DataScience/16S_pipeline/test_data/01_trimmed_sequences"
METADATA_FILE="/Users/kgrond/Desktop/INBRE-DataScience/16S_pipeline/test_data/metadata.csv"

# --- PRIMER SEQUENCES ---
# V4 Region Primers (515F/806R)
FWD_PRIMER="GTGCCAGCMGCCGCGGTAA"
REV_PRIMER="GGACTACHVGGGTWTCTAAT"

# --- 1. Conda Environment Setup and Activation ---
CONDA_ENV="qiime2-amplicon-2025.7"

# Check if environment exists (Run setup only if missing)
if ! conda info --envs | grep -q "$CONDA_ENV"; then
    echo "--- Conda Environment Setup: $CONDA_ENV is missing. Running setup now. ---"

    # Create and install packages
    echo "Creating and installing QIIME 2 (2025.7) and Cutadapt..."
    
    # Create environment
    conda create -n $CONDA_ENV python=3.10 -y
    
    # Install packages into the newly created environment
    conda install -n $CONDA_ENV -c conda-forge -c bioconda -c defaults qiime2=2025.7 -y
    conda install -n $CONDA_ENV -c conda-forge cutadapt -y
    
    if [ $? -ne 0 ]; then
        echo "ERROR: Conda package installation failed during setup. Exiting."
        exit 1
    fi
else
    echo "Environment '$CONDA_ENV' already exists. Skipping setup."
fi

# Activate the environment (ALWAYS necessary to ensure PATH is set correctly)
echo "Activating Conda environment: $CONDA_ENV"
source activate $CONDA_ENV
if [ $? -ne 0 ]; then
    echo "ERROR: Could not activate Conda environment. Please check your Conda installation."
    exit 1
fi
echo "Environment activated."

# --- 2. Create Output Directory ---
mkdir -p "$OUTPUT_DIR"
echo "Output will be saved to: $OUTPUT_DIR"

# 3. Primer Removal Loop
# Looking for non-compressed .fastq files
echo "Starting primer trimming with Cutadapt..."
# Change CWD to the input directory for simplified input paths inside the loop
cd "$INPUT_DIR/R1"

# Find all R1 files (Forward reads), checking for the non-compressed .fastq extension
R1_FILES=$(ls *R1*.fastq 2>/dev/null)
if [ -z "$R1_FILES" ]; then
    echo "ERROR: No R1 (Forward) FASTQ files found in $INPUT_DIR/R1. Check your path and file naming. Expecting *.fastq"
    cd -
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
    BASE_NAME=$(basename "$R1_FILE" | sed -E 's/(_R1|_R2).*\.fastq//')
    
    echo "Processing $BASE_NAME..."

    # Cutadapt command (The output reports are no longer captured, removing the source of the error):
    cutadapt \
        -g "$FWD_PRIMER" \
        -G "$REV_PRIMER" \
        -a "$(echo "$REV_PRIMER" | tr 'ATGCatgc' 'TACGtacg' | rev)" \
        -G "$(echo "$FWD_PRIMER" | tr 'ATGCatgc' 'TACGtacg' | rev)" \
        --minimum-length 1 \
        --cores 4 \
        -o "$OUTPUT_DIR/${BASE_NAME}_R1_trimmed.fastq" \
        -p "$OUTPUT_DIR/${BASE_NAME}_R2_trimmed.fastq" \
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
echo "Next step: Run quality_check.sh"