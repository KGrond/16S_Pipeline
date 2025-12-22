!/usr/bin/env bash
# Exit immediately if a command exits with a non-zero status.
set -e

# ==============================================================================
#                 ** AUTOMATED QIIME 2 MASTER PIPELINE **
# ==============================================================================
# Purpose: Full 16S Workflow with Smart Resuming and Detailed Error Guidance.
# ==============================================================================

# --- 1. Configuration & User Variables ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==============================================================================
# --- USER-FILLABLE VARIABLES ---
# ==============================================================================
PROJECT_NAME="Project_Name" 
CONDA_ENV="qiime2-2025.10" 
FWD_PRIMER="GTGCCAGCMGCCGCGGTAA" 
REV_PRIMER="GGACTACHVGGGTWTCTAAT"

# Input/Output Paths
INPUT_DIR="${SCRIPT_DIR}/${PROJECT_NAME}_demultiplexed_data" 
MANIFEST_FILE="${SCRIPT_DIR}/${PROJECT_NAME}_manifest.tsv"
METADATA_FILE="${SCRIPT_DIR}/${PROJECT_NAME}_metadata.tsv"
OUTPUT_DIR="${SCRIPT_DIR}/${PROJECT_NAME}_qiime2_output"

# Classifier Configuration (SILVA 138)
CLASSIFIER_DIR="${SCRIPT_DIR}"
CLASSIFIER_PATH="${CLASSIFIER_DIR}/silva-138-99-nb-classifier.qza"
CLASSIFIER_URL="https://data.qiime2.org/classifiers/sklearn-1.4.2/silva/silva-138-99-nb-classifier.qza" 

# ------------------------------------------------------------------------------
# --- 2. Tool & Environment Verification ---
# ------------------------------------------------------------------------------

# A. realpath check
if ! command -v realpath &> /dev/null; then
    echo "------------------------------------------------------------------"
    echo "❌ FATAL ERROR: The 'realpath' command is not installed."
    echo "------------------------------------------------------------------"
    echo "This script requires 'realpath' to generate absolute file paths."
    echo "Please install 'coreutils' for your operating system:"
    echo ""
    echo "  🍎 macOS (Homebrew):      brew install coreutils"
    echo "  🐧 Ubuntu / Debian:       sudo apt-get install coreutils"
    echo "  🤠 CentOS / Fedora / RHEL: sudo dnf install coreutils"
    echo "  🐚 Arch Linux:            sudo pacman -S coreutils"
    echo "------------------------------------------------------------------"
    exit 1
fi

# B. Conda installation check
if ! command -v conda &> /dev/null; then
    echo "------------------------------------------------------------------"
    echo "❌ FATAL ERROR: 'conda' command not found."
    echo "------------------------------------------------------------------"
    echo "Conda is required to manage the QIIME 2 environment."
    echo "Please install Miniconda (recommended) or Anaconda:"
    echo ""
    echo "  🌐 Download Link: https://docs.conda.io/en/latest/miniconda.html"
    echo "  💻 Quick Command (Linux):"
    echo "     curl -O https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh"
    echo "     bash Miniconda3-latest-Linux-x86_64.sh"
    echo "------------------------------------------------------------------"
    exit 1
fi

# Locate Conda base and source profile to allow activation in a script
CONDA_BASE=$(conda info --base)
source "${CONDA_BASE}/etc/profile.d/conda.sh"

# C. Environment check
if ! conda info --envs | grep -qE "(^|[[:space:]])${CONDA_ENV}([[:space:]]|$)"; then
    echo "------------------------------------------------------------------"
    echo "❌ FATAL ERROR: Conda environment '${CONDA_ENV}' not found."
    echo "------------------------------------------------------------------"
    echo "Please check the 'CONDA_ENV' variable at the top of this script."
    echo "If you have not created this environment yet, run:"
    echo ""
    echo "  1. wget https://data.qiime2.org/distro/amplicon/qiime2-amplicon-2024.10-py310-linux-conda.yml"
    echo "  2. conda env create -n ${CONDA_ENV} --file qiime2-amplicon-2024.10-py310-linux-conda.yml"
    echo ""
    echo "Note: Ensure the environment name matches exactly: ${CONDA_ENV}"
    echo "------------------------------------------------------------------"
    exit 1
fi

echo "✅ Environment '$CONDA_ENV' verified. Activating..."
conda activate "$CONDA_ENV"
QIIME_COMMAND="qiime"

# ------------------------------------------------------------------------------
# --- 3. Classifier Management  ---
# ------------------------------------------------------------------------------
if [ ! -f "${CLASSIFIER_PATH}" ]; then
    echo "------------------------------------------------------------------"
    echo "🔍 Classifier not found. Attempting automated download..."
    echo "------------------------------------------------------------------"
    
    if curl -L "${CLASSIFIER_URL}" -o "${CLASSIFIER_PATH}"; then
        echo "✅ Successfully downloaded: $(basename "${CLASSIFIER_PATH}")"
    else
        echo "------------------------------------------------------------------"
        echo "❌ FATAL ERROR: Classifier download failed."
        echo "------------------------------------------------------------------"
        echo "You must manually provide a compatible Naive Bayes classifier."
        echo ""
        echo "1. Find the correct classifier for your QIIME 2 version at:"
        echo "   ➡️  https://data.qiime2.org/distro/amplicon/sample-resources"
        echo ""
        echo "2. Look for 'Silva 138 99% OTUs from 515F/806R region' (or your region)."
        echo ""
        echo "3. Download the .qza file and place it in this directory:"
        echo "   📂 ${CLASSIFIER_DIR}"
        echo ""
        echo "4. Ensure the filename matches: $(basename "${CLASSIFIER_PATH}")"
        echo "------------------------------------------------------------------"
        exit 1
    fi
else
    echo "✅ Checkpoint: Compatible classifier found."
fi

# ------------------------------------------------------------------------------
# --- 4. Internal Helpers & Directory Setup ---
# ------------------------------------------------------------------------------
mkdir -p "${OUTPUT_DIR}"

run_qiime_step() {
    local output_file="$1"
    shift 
    if [ -f "$output_file" ] || [ -d "$output_file" ]; then
        echo "✅ Checkpoint: $(basename "$output_file") already exists. Skipping."
    else
        echo "⏳ Running: $(basename "$output_file")..."
        "$@"
        echo "✅ Success: $(basename "$output_file") created."
    fi
}

# ------------------------------------------------------------------------------
# --- 5. Manifest Generation (SRA/Illumina Compatible) ---
# ------------------------------------------------------------------------------
if [ ! -f "${MANIFEST_FILE}" ]; then
    echo "--- Generating QIIME 2 Manifest File ---"
    printf "sample-id\tforward-absolute-filepath\treverse-absolute-filepath\n" > "${MANIFEST_FILE}"

    find "${INPUT_DIR}" -type f \( -name "*_R1.*" -o -name "*_1.*" \) \
        \( -name "*.fastq*" -o -name "*.fq*" \) | sort -u | while IFS= read -r R1_PATH; do
        
        R1_FILENAME=$(basename "${R1_PATH}")
        
        if [[ "${R1_FILENAME}" == *"_R1."* ]]; then
            FWD_SUFFIX="_R1."; REV_SUFFIX="_R2."
        elif [[ "${R1_FILENAME}" == *"_1."* ]]; then
            FWD_SUFFIX="_1."; REV_SUFFIX="_2."
        else
            continue 
        fi

        SAMPLE_ID=$(echo "${R1_FILENAME}" | sed "s/${FWD_SUFFIX/./\\.}.*//")
        R2_FILENAME=$(echo "${R1_FILENAME}" | sed "s/${FWD_SUFFIX/./\\.}/${REV_SUFFIX/./\\.}/")
        R2_PATH=$(find "${INPUT_DIR}" -type f -name "${R2_FILENAME}" -print -quit)

        if [ -n "${R2_PATH}" ]; then
            R1_ABS_PATH=$(realpath "${R1_PATH}")
            R2_ABS_PATH=$(realpath "${R2_PATH}")
            printf "%s\t%s\t%s\n" "${SAMPLE_ID}" "${R1_ABS_PATH}" "${R2_ABS_PATH}" >> "${MANIFEST_FILE}"
        fi
    done
    echo "✅ Manifest created with $(($(wc -l < "${MANIFEST_FILE}") - 1)) samples."
else
    echo "✅ Checkpoint: Manifest file already exists."
fi

# ------------------------------------------------------------------------------
## 6. Parameter Extraction and Setup 🔬
# ------------------------------------------------------------------------------
if [ ! -f "${PARAMS_FILE}" ]; then
    echo "Error: Truncation parameter file not found: ${PARAMS_FILE}"
    echo "Please run 'run_fastqc.sh' first."
    exit 1
fi

# Load R1_TRUNC_LEN and R2_TRUNC_LEN from the parameters file
source "${PARAMS_FILE}"
echo "Loaded truncation parameters: R1=${R1_TRUNC_LEN} bp, R2=${R2_TRUNC_LEN} bp"

# Check if values are sensible (non-zero)
if [ "${R1_TRUNC_LEN}" -eq 0 ] && [ "${R2_TRUNC_LEN}" -eq 0 ]; then
    echo "Error: Both R1 and R2 truncation lengths are 0. Check FastQC reports."
    exit 1
fi

# Create output directories
mkdir -p "${OUTPUT_DIR}"
echo "Created QIIME 2 output directory: ${OUTPUT_DIR}"


# ------------------------------------------------------------------------------
# --- 7. Core QIIME 2 Workflow ---
# ------------------------------------------------------------------------------

echo "--- Starting QIIME 2 Pipeline (DADA2) ---"

# 7.1 Import Data
QZA_DEMUX="${OUTPUT_DIR}/01_demultiplexed_seqs.qza"
echo "1. Importing paired-end FASTQ data..."
run_qiime_step "${QZA_DEMUX}" \
  ${QIIME_COMMAND} tools import \
    --type 'SampleData[PairedEndSequencesWithQuality]' \
    --input-path "${MANIFEST_FILE}" \
    --output-path "${QZA_DEMUX}" \
    --input-format PairedEndFastqManifestPhred33V2

# 7.2 Trim Primers
QZA_PRIMER_TRIMMED="${OUTPUT_DIR}/02_primer_trimmed_seqs.qza"
run_qiime_step "${QZA_PRIMER_TRIMMED}" \
  ${QIIME_COMMAND} cutadapt trim-paired \
    --i-demultiplexed-sequences "${QZA_DEMUX}" \
    --p-adapter-f "${REV_PRIMER}" \
    --p-adapter-r "${FWD_PRIMER}" \
    --o-trimmed-sequences "${QZA_PRIMER_TRIMMED}"

# 7.3 Visualize Demultiplexed Sequences
QZV_DEMUX="${OUTPUT_DIR}/02_demux_summary.qzv"
echo "2. Visualizing demultiplexed sequences..."
if [ ! -f "${QZV_DEMUX}" ]; then
    ${QIIME_COMMAND} demux summarize \
      --i-data "${QZA_DEMUX}" \
      --o-visualization "${QZV_DEMUX}" || echo "Warning: Demux visualization failed. Continuing..."
else
    echo "✅ Checkpoint: $(basename "${QZV_DEMUX}") already exists. Skipping step."
fi

# 7.4 Denoise and Dereplicate using DADA2
QZA_TABLE="${OUTPUT_DIR}/03_feature_table.qza"
QZA_REP_SEQS="${OUTPUT_DIR}/04_rep_seqs.qza"
QZA_DADA2_STATS="${OUTPUT_DIR}/05_dada2_stats.qza"

echo "Running DADA2 denoising with trunc-len-f ${R1_TRUNC_LEN} and trunc-len-r ${R2_TRUNC_LEN}..."
if [ ! -f "${QZA_TABLE}" ]; then
    ${QIIME_COMMAND} dada2 denoise-paired \
      --i-demultiplexed-seqs "${QZA_DEMUX}" \
      --p-trunc-len-f "${R1_TRUNC_LEN}" \
      --p-trunc-len-r "${R2_TRUNC_LEN}" \
      --o-table "${QZA_TABLE}" \
      --o-representative-sequences "${QZA_REP_SEQS}" \
      --o-denoising-stats "${QZA_DADA2_STATS}" \
      --o-base-transition-stats "${OUTPUT_DIR}/06_dada2_stats.qza" \
      --verbose
    if [ $? -ne 0 ]; then echo "❌ Error in DADA2 Denoising. Exiting."; exit 1; fi
    echo "✅ DADA2 artifacts successfully created."
else
    echo "✅ Checkpoint: $(basename "${QZA_TABLE}") already exists. Skipping DADA2 step."
fi

# 7.5 Generate Summaries for Review
echo "Generating Feature Table and Representative Sequences summaries..."

QZV_TABLE_SUMMARY="${OUTPUT_DIR}/07_feature_table_summary.qzv"
run_qiime_step "${QZV_TABLE_SUMMARY}" \
  ${QIIME_COMMAND} feature-table summarize \
    --i-table "${QZA_TABLE}" \
    --o-visualization "${QZV_TABLE_SUMMARY}"

QZV_REP_SEQS_SUMMARY="${OUTPUT_DIR}/08_rep_seqs_summary.qzv"
run_qiime_step "${QZV_REP_SEQS_SUMMARY}" \
  ${QIIME_COMMAND} feature-table tabulate-seqs \
    --i-data "${QZA_REP_SEQS}" \
    --o-visualization "${QZV_REP_SEQS_SUMMARY}"


# 7.6 Build Phylogenetic Tree
echo "--- Building Phylogenetic Tree ---"

QZA_ROOTED_TREE="${OUTPUT_DIR}/09_rooted_tree.qza"
if [ ! -f "${QZA_ROOTED_TREE}" ]; then
    echo "⏳ Building Phylogenetic Tree..."
    ${QIIME_COMMAND} phylogeny align-to-tree-mafft-fasttree \
      --i-sequences "${QZA_REP_SEQS}" \
      --o-alignment "${OUTPUT_DIR}/temp_aln.qza" \
      --o-masked-alignment "${OUTPUT_DIR}/temp_mask.qza" \
      --o-tree "${OUTPUT_DIR}/temp_tree.qza" \
      --o-rooted-tree "${QZA_ROOTED_TREE}"
    rm "${OUTPUT_DIR}/temp_aln.qza" "${OUTPUT_DIR}/temp_mask.qza" "${OUTPUT_DIR}/temp_tree.qza"
fi

# 7.7 Taxonomy Assignment
echo "--- 6. Taxonomy Assignment ---"

# 7.7a. Assigning taxonomy
QZA_TAXONOMY="${OUTPUT_DIR}/10_taxonomy.qza"
run_qiime_step "${QZA_TAXONOMY}" \
  ${QIIME_COMMAND} feature-classifier classify-sklearn \
    --i-reads "${QZA_REP_SEQS}" \
    --i-classifier "${CLASSIFIER_PATH}" \
    --o-classification "${QZA_TAXONOMY}"

# 7.7b. Generating Taxonomy visualization
QZV_TAXONOMY_TABULATED="${OUTPUT_DIR}/11_taxonomy_tabulated.qzv"
run_qiime_step "${QZV_TAXONOMY_TABULATED}" \
  ${QIIME_COMMAND} metadata tabulate \
    --m-input-file "${QZA_TAXONOMY}" \
    --o-visualization "${QZV_TAXONOMY_TABULATED}"

# 7.7c. Generating Taxa Barplots
QZV_TAXA_BARPLOTS="${OUTPUT_DIR}/12_taxa_barplots.qzv"
echo "6c. Generating Taxa Barplots..."

if [ ! -f "${METADATA_FILE}" ]; then
    echo "❌ WARNING: Metadata file not found: ${METADATA_FILE}. Skipping Taxa Barplots."
else
    # We check the checkpoint file for 6c
    if [ ! -f "${QZV_TAXA_BARPLOTS}" ]; then
        ${QIIME_COMMAND} taxa barplot \
            --i-table "${QZA_TABLE}" \
            --i-taxonomy "${QZA_TAXONOMY}" \
            --m-metadata-file "${METADATA_FILE}" \
            --o-visualization "${QZV_TAXA_BARPLOTS}"
        if [ $? -ne 0 ]; then echo "❌ Error: Taxa barplot generation failed. Continuing..."; fi
    else
        echo "✅ Checkpoint: $(basename "${QZV_TAXA_BARPLOTS}") already exists. Skipping step."
    fi
fi

#---
## 8. Alpha and Beta Diversity Analysis 📊
#---
echo "--- 7. Alpha and Beta Diversity Analysis ---"

ALPHA_BETA_DIV="${OUTPUT_DIR}/diversity-core-metrics-phylogenetic"
SAMPLE_READ_COUNTS_FILE="${OUTPUT_DIR}/03_sample_read_counts.tsv"

# Temporary variables for generating the read counts file
TEMP_EXPORT_DIR="${OUTPUT_DIR}/temp_export_dir_export"
TEMP_BIOM_FILE="${TEMP_EXPORT_DIR}/feature-table.biom"
SAMPLING_DEPTH=0 # Initialized to 0, will be set by user input

# --- 6a. Create Sample Read Counts File (Fixed for reliable parsing) ---
echo "6a. Exporting feature table and calculating total reads per sample..."

if [ ! -f "${SAMPLE_READ_COUNTS_FILE}" ]; then
    echo "⏳ Exporting feature table artifact to BIOM format..."
    mkdir -p "${TEMP_EXPORT_DIR}"

    # Export QIIME 2 table to BIOM format
    ${QIIME_COMMAND} tools export \
        --input-path "${QZA_TABLE}" \
        --output-path "${TEMP_EXPORT_DIR}"

    if [ ! -f "${TEMP_BIOM_FILE}" ]; then
        echo "❌ ERROR: QIIME tools export failed. The BIOM file was not created. Cannot proceed."
        rm -rf "${TEMP_EXPORT_DIR}"
        exit 1
    fi

    echo "⏳ Summarizing BIOM table to generate sample read count file..."
    
    # Use the reliable '--output-counts' flag from biom summarize-table
    conda run -n ${CONDA_ENV} biom summarize-table \
        -i "${TEMP_BIOM_FILE}" \
        --output-counts \
        > "${SAMPLE_READ_COUNTS_FILE}.temp" 2>&1

    # Format the output file: replace first line, and rename columns
    echo -e "sample-id\tTotal_Reads" > "${SAMPLE_READ_COUNTS_FILE}"
    tail -n +2 "${SAMPLE_READ_COUNTS_FILE}.temp" >> "${SAMPLE_READ_COUNTS_FILE}"
    
    rm -f "${SAMPLE_READ_COUNTS_FILE}.temp"
    rm -rf "${TEMP_EXPORT_DIR}"

    if [ $(wc -l < "${SAMPLE_READ_COUNTS_FILE}") -le 1 ]; then
        echo "❌ FATAL ERROR: Read counts file is still empty or contains only the header after creation."
        echo "Please manually inspect the BIOM file for sample counts."
        exit 1
    fi

    echo "✅ Sample read counts saved to: ${SAMPLE_READ_COUNTS_FILE}"
else
    echo "✅ Sample read counts file already exists: ${SAMPLE_READ_COUNTS_FILE}. Skipping creation."
fi


# --- 6b. Interactive Sampling Depth Prompt ---
echo -e "\n-------------------------------------------------"
echo "### ACTION REQUIRED: DETERMINE SAMPLING DEPTH ###"
echo "Please review the total read counts per sample saved in:"
echo "➡️ ${SAMPLE_READ_COUNTS_FILE}"
echo "Use this file to determine the appropriate **sampling depth** for your diversity analysis."


echo -e "\nℹ️ QIIME 2 requires a sampling depth for diversity analysis."
read -r -p "Enter the desired sampling depth: " SAMPLING_DEPTH

if ! [[ "$SAMPLING_DEPTH" =~ ^[0-9]+$ ]] || [ "$SAMPLING_DEPTH" -le 0 ]; then
    echo "❌ Invalid sampling depth entered. Exiting."
    exit 1
fi

# --- 6c. Run Core Metrics ---
if [ ! -f "${METADATA_FILE}" ]; then
    echo "❌ FATAL ERROR: Metadata file required for diversity analysis not found: ${METADATA_FILE}"
    echo "Please create a valid QIIME 2 sample-metadata.tsv file."
    exit 1
fi

# Use a guaranteed QIIME 2 output artifact as the checkpoint
RAREFIED_TABLE_QZA="${ALPHA_BETA_DIV}/rarefied_table.qza"

echo -e "\nRunning Core Metrics with user-defined sampling depth: ${SAMPLING_DEPTH}"
run_qiime_step "${RAREFIED_TABLE_QZA}" \
  ${QIIME_COMMAND} diversity core-metrics-phylogenetic \
    --i-phylogeny "${QZA_ROOTED_TREE}" \
    --i-table "${QZA_TABLE}" \
    --p-sampling-depth "${SAMPLING_DEPTH}" \
    --m-metadata-file "${METADATA_FILE}" \
    --output-dir "${ALPHA_BETA_DIV}"

# --- Final Summary ---
echo "---"
echo "QIIME 2 Pipeline Complete."
echo "Results saved in the '${OUTPUT_DIR}' directory."
echo "Next Steps: View your results by opening the .qzv files in a browser using:"
echo "➡️ qiime tools view <path_to_qzv_file>"