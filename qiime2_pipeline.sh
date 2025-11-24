#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status. This helps catch errors early.
set -e

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Input Directory (where the FASTQ files are located, same as FastQC script)
INPUT_DIR="${SCRIPT_DIR}/trimmed_sequences"

# Output Directory for DADA2 parameters from FastQC script
PARAMS_DIR="${SCRIPT_DIR}/fastqc_reports_trimmed"
PARAMS_FILE="${PARAMS_DIR}/qiime2_trunc_params.txt"

# Output Directory for all QIIME 2 artifacts
OUTPUT_DIR="${SCRIPT_DIR}/qiime2_analysis"

# Directory where the classifier should be stored (relative to this script's location if not absolute)
CLASSIFIER_DIR="${SCRIPT_DIR}"
CLASSIFIER_NAME="silva-138-99-nb-classifier.qza"
CLASSIFIER_PATH="${CLASSIFIER_DIR}/silva-138-99-nb-classifier.qza"
CLASSIFIER_URL="https://data.qiime2.org/2022.2/common/silva-138-99-nb-classifier.qza" # Using a stable QIIME 2 release URL

# --- 1. Conda Environment Setup and Activation ---
CONDA_ENV="qiime2-2025.10"
# Activate the environment (ALWAYS necessary to ensure PATH is set correctly)
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


# Define the QIIME command prefix using 'conda run'.
QIIME_COMMAND="conda run -n ${CONDA_ENV} qiime"
echo "QIIME commands will be executed using: ${QIIME_COMMAND}"
echo "Assuming Conda environment '${CONDA_ENV}' exists and is properly configured."

# --- Classifier Download Check ---
echo "--- Checking for Taxonomy Classifier ---"
if [ ! -f "${CLASSIFIER_PATH}" ]; then
    echo "❌ Classifier not found at ${CLASSIFIER_PATH}. Attempting to download..."
    
    mkdir -p "${CLASSIFIER_DIR}"
    
    # Use wget if available, otherwise use curl
    if command -v wget &> /dev/null; then
        echo "Using wget to download classifier..."
        wget -O "${CLASSIFIER_PATH}" "${CLASSIFIER_URL}"
    elif command -v curl &> /dev/null; then
        echo "Using curl to download classifier..."
        curl -L "${CLASSIFIER_URL}" -o "${CLASSIFIER_PATH}"
    else
        echo "FATAL ERROR: Neither wget nor curl is installed. Cannot download classifier."
        echo "Please install one of these utilities or manually download the file from: ${CLASSIFIER_URL}"
        exit 1
    fi
    
    if [ $? -ne 0 ]; then
        echo "❌ FATAL ERROR: Download failed. Check the URL and network connection."
        exit 1
    fi
    echo "✅ Successfully downloaded classifier to ${CLASSIFIER_PATH}."
else
    echo "✅ Classifier found at ${CLASSIFIER_PATH}. Skipping download."
fi


# --- Parameter Extraction ---

if [ ! -f "${PARAMS_FILE}" ]; then
    echo "Error: Truncation parameter file not found: ${PARAMS_FILE}"
    echo "Please run 'run_fastqc.sh' first to calculate and save the optimal truncation lengths."
    exit 1
fi

# Load R1_AVG and R2_AVG from the parameters file
source "${PARAMS_FILE}"
echo "Loaded truncation parameters: R1=${R1_AVG} bp, R2=${R2_AVG} bp"

# Check if values are sensible (non-zero)
if [ "${R1_AVG}" -eq 0 ] && [ "${R2_AVG}" -eq 0 ]; then
    echo "Error: Both R1 and R2 truncation lengths are 0. Check FastQC reports or input files."
    exit 1
fi

# Create output directories
mkdir -p "${OUTPUT_DIR}"
echo "Created QIIME 2 output directory: ${OUTPUT_DIR}"

# --- Reusable Checkpoint Function ---
# $1: Output file path
# $2...: Command to execute if file does not exist
run_qiime_step() {
    local output_file="$1"
    shift # Remove the first argument (output file) from the list of arguments
    
    if [ -f "$output_file" ]; then
        echo "✅ Checkpoint: $output_file already exists. Skipping step."
    else
        echo "⏳ Running command to create $output_file..."
        # Execute the remaining arguments as the command
        "$@"
        if [ $? -ne 0 ]; then 
            echo "❌ Error encountered creating $output_file. Exiting." 
            exit 1
        fi
        echo "✅ $output_file successfully created."
    fi
}
# ------------------------------------

# --- QIIME 2 Pipeline Steps ---
echo "--- Starting QIIME 2 Pipeline (DADA2) ---"

# 1. Import Data
QZA_DEMUX="${OUTPUT_DIR}/01_demultiplexed_seqs.qza"
echo "1. Importing paired-end FASTQ data using Manifest File..."
run_qiime_step "${QZA_DEMUX}" \
  ${QIIME_COMMAND} tools import \
    --type 'SampleData[PairedEndSequencesWithQuality]' \
    --input-path "/Users/kgrond/Desktop/INBRE-DataScience/16S_pipeline/16S_pipeline_repo/manifest.tsv" \
    --output-path "${QZA_DEMUX}" \
    --input-format PairedEndFastqManifestPhred33V2


# 2. Visualize Demultiplexed Sequences (Optional)
QZV_DEMUX="${OUTPUT_DIR}/02_demux_summary.qzv"
echo "2. Visualizing demultiplexed sequences..."
# We allow visualization to fail gracefully, so we skip the strict run_qiime_step error check
if [ ! -f "${QZV_DEMUX}" ]; then
    ${QIIME_COMMAND} demux summarize \
      --i-data "${QZA_DEMUX}" \
      --o-visualization "${QZV_DEMUX}"
    if [ $? -ne 0 ]; then echo "Warning: Demux visualization failed. Continuing..."; fi
else
    echo "✅ Checkpoint: ${QZV_DEMUX} already exists. Skipping step."
fi


# 3. Denoise and Dereplicate using DADA2
QZA_TABLE="${OUTPUT_DIR}/03_feature_table.qza"
QZA_REP_SEQS="${OUTPUT_DIR}/04_rep_seqs.qza"
QZA_DADA2_STATS="${OUTPUT_DIR}/05_dada2_stats.qza"

echo "3. Running DADA2 denoising with trunc-len-f ${R1_AVG} and trunc-len-r ${R2_AVG}..."
# We only check for the existence of the table; DADA2 creates all three files simultaneously
if [ ! -f "${QZA_TABLE}" ]; then
    ${QIIME_COMMAND} dada2 denoise-paired \
      --i-demultiplexed-seqs "${QZA_DEMUX}" \
      --p-trunc-len-f "${R1_AVG}" \
      --p-trunc-len-r "${R2_AVG}" \
      --o-table "${QZA_TABLE}" \
      --o-representative-sequences "${QZA_REP_SEQS}" \
      --o-denoising-stats "${QZA_DADA2_STATS}" \
      --verbose
    if [ $? -ne 0 ]; then echo "❌ Error in DADA2 Denoising. Exiting."; exit 1; fi
    echo "✅ DADA2 artifacts successfully created."
else
    echo "✅ Checkpoint: ${QZA_TABLE} already exists. Skipping DADA2 step."
fi


# 4. Generate Summaries for Review
echo "4. Generating Feature Table and Representative Sequences summaries..."

# 4a. Feature Table Summary
QZV_TABLE_SUMMARY="${OUTPUT_DIR}/06_feature_table_summary.qzv"
run_qiime_step "${QZV_TABLE_SUMMARY}" \
  ${QIIME_COMMAND} feature-table summarize \
    --i-table "${QZA_TABLE}" \
    --o-visualization "${QZV_TABLE_SUMMARY}"

# 4b. Representative Sequences Summary
QZV_REP_SEQS_SUMMARY="${OUTPUT_DIR}/07_rep_seqs_summary.qzv"
run_qiime_step "${QZV_REP_SEQS_SUMMARY}" \
  ${QIIME_COMMAND} feature-table tabulate-seqs \
    --i-data "${QZA_REP_SEQS}" \
    --o-visualization "${QZV_REP_SEQS_SUMMARY}"


# 5. Build Phylogenetic Tree
echo "--- 5. Building Phylogenetic Tree ---"

# 5a. Aligning representative sequences (MAFFT)
QZA_ALIGNMENT="${OUTPUT_DIR}/08_aligned_rep_seqs.qza"
echo "5a. Aligning representative sequences (MAFFT)..."
run_qiime_step "${QZA_ALIGNMENT}" \
  ${QIIME_COMMAND} alignment mafft \
    --i-sequences "${QZA_REP_SEQS}" \
    --o-alignment "${QZA_ALIGNMENT}"

# 5b. Masking alignment
QZA_MASKED_ALIGNMENT="${OUTPUT_DIR}/09_masked_aligned_rep_seqs.qza"
echo "5b. Masking alignment..."
run_qiime_step "${QZA_MASKED_ALIGNMENT}" \
  ${QIIME_COMMAND} alignment mask \
    --i-alignment "${QZA_ALIGNMENT}" \
    --o-masked-alignment "${QZA_MASKED_ALIGNMENT}"

# 5c. Building phylogenetic tree (FastTree)
QZA_UNROOTED_TREE="${OUTPUT_DIR}/10_unrooted_tree.qza"
echo "5c. Building phylogenetic tree (FastTree)..."
run_qiime_step "${QZA_UNROOTED_TREE}" \
  ${QIIME_COMMAND} phylogeny fasttree \
    --i-alignment "${QZA_MASKED_ALIGNMENT}" \
    --o-tree "${QZA_UNROOTED_TREE}"

# 5d. Rooting the tree
QZA_ROOTED_TREE="${OUTPUT_DIR}/11_rooted_tree.qza"
echo "5d. Rooting the tree..."
run_qiime_step "${QZA_ROOTED_TREE}" \
  ${QIIME_COMMAND} phylogeny midpoint-root \
    --i-tree "${QZA_UNROOTED_TREE}" \
    --o-rooted-tree "${QZA_ROOTED_TREE}"


# 6. Taxonomy Assignment
echo "--- 6. Taxonomy Assignment ---"

# The CLASSIFIER_PATH is now guaranteed to exist or the script will have exited
# gracefully after attempting the download.

# 6a. Assigning taxonomy
QZA_TAXONOMY="${OUTPUT_DIR}/12_taxonomy.qza"
echo "6a. Assigning taxonomy to representative sequences (Naive Bayes)..."
run_qiime_step "${QZA_TAXONOMY}" \
  ${QIIME_COMMAND} feature-classifier classify-sklearn \
    --i-reads "${QZA_REP_SEQS}" \
    --i-classifier "${CLASSIFIER_PATH}" \
    --o-classification "${QZA_TAXONOMY}"

# 6b. Generating Taxonomy visualization
QZV_TAXONOMY_TABULATED="${OUTPUT_DIR}/13_taxonomy_tabulated.qzv"
echo "6b. Generating Taxonomy visualization (Tabular view)..."
run_qiime_step "${QZV_TAXONOMY_TABULATED}" \
  ${QIIME_COMMAND} metadata tabulate \
    --m-input-file "${QZA_TAXONOMY}" \
    --o-visualization "${QZV_TAXONOMY_TABULATED}"

# 6c. Generating Taxa Barplots
QZV_TAXA_BARPLOTS="${OUTPUT_DIR}/14_taxa_barplots.qzv"
echo "6c. Generating Taxa Barplots (Overview of community composition)..."
# We allow barplot visualization to fail gracefully
if [ ! -f "${QZV_TAXA_BARPLOTS}" ]; then
    ${QIIME_COMMAND} taxa barplot \
        --i-table "${QZA_TABLE}" \
        --i-taxonomy "${QZA_TAXONOMY}" \
        --o-visualization "${QZV_TAXA_BARPLOTS}"
    if [ $? -ne 0 ]; then echo "Warning: Taxa barplot generation failed. Continuing..."; fi
else
    echo "✅ Checkpoint: ${QZV_TAXA_BARPLOTS} already exists. Skipping step."
fi


echo "---"
echo "QIIME 2 Pipeline Complete (Up to Taxonomy and Phylogeny)."
echo "Results saved in the '${OUTPUT_DIR}' directory."
echo "Next Steps:"
echo "1. Inspect the DADA2 stats: qiime tools view ${OUTPUT_DIR}/05_dada2_stats.qzv"
echo "2. Check Taxonomy Barplots: qiime tools view ${OUTPUT_DIR}/14_taxa_barplots.qzv"
echo "3. Continue with Diversity analysis (Alpha and Beta)."