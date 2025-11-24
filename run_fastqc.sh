#!/bin/bash
# Exit immediately if a command exits with a non-zero status
set -e

# --- Configuration ---
# Data Directory: Path to the directory containing the FASTQ files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/trimmed_sequences"

# Set the output directory for FastQC reports
OUTPUT_DIR="fastqc_reports_trimmed"

# Define the Conda environment name (Make sure this matches your installs.sh script)
CONDA_ENV="qiime2-2025.10" 

# Define the minimum quality score threshold for truncation (Q20 is standard)
MIN_QUALITY_SCORE=20

# Temporary file to store individual read truncation lengths
TRUNC_TEMP_FILE="${OUTPUT_DIR}/truncation_lengths_temp.txt"

# Persistent file to store final average truncation parameters for QIIME 2
PARAMS_FILE="${OUTPUT_DIR}/qiime2_trunc_params.txt"

# --- Conda Initialization and Activation ---

# Check if conda is available at all
if command -v conda &> /dev/null
then
    echo "Conda detected. Initializing shell and activating environment..."
    # Initialize conda by sourcing the relevant script (necessary for non-interactive shell sessions)
    CONDA_BASE=$(conda info --base)
    if [ -f "${CONDA_BASE}/etc/profile.d/conda.sh" ]; then
        source "${CONDA_BASE}/etc/profile.d/conda.sh"
    else
        echo "Error: Conda initialization script not found. Please ensure Conda is installed correctly."
        exit 1
    fi

    # Activate the target environment
    conda activate "${CONDA_ENV}"

    if [ $? -ne 0 ]; then
        echo "Error: Failed to activate Conda environment '${CONDA_ENV}'. Did you run installs.sh?"
        exit 1
    fi
    echo "Conda environment '${CONDA_ENV}' activated."
else
    echo "Error: 'conda' command not found. Cannot proceed."
    exit 1
fi

# --- Tool Execution Checks (Runs after environment is active) ---
echo "--- Verifying required tools in environment ---"

if ! command -v fastqc &> /dev/null
then
    echo "❌ Error: **FastQC** not found in the active environment ('${CONDA_ENV}'). Please run **installs.sh**."
    exit 1
fi

if ! command -v unzip &> /dev/null
then
    echo "❌ Error: **unzip** utility not found in the active environment ('${CONDA_ENV}'). Please run **installs.sh**."
    exit 1
fi
echo "✅ FastQC and unzip verified."

# Create the output directory if it doesn't exist and clear temp file and params file
mkdir -p "${OUTPUT_DIR}"
rm -f "${TRUNC_TEMP_FILE}"
rm -f "${PARAMS_FILE}"
echo "Created output directory: ${OUTPUT_DIR}"

# --- PHASE 1: FASTQC EXECUTION WITH RESUME/CHECKPOINT ---
echo "--- Phase 1: Running FastQC (Resumes existing analysis) ---"

# Find all .fastq.gz files and run FastQC only if the report doesn't exist.
find "${DATA_DIR}" -maxdepth 1 -name "*.fastq.gz" | while read fastq_file; do
    if [ -f "${fastq_file}" ]; then
        filename=$(basename "${fastq_file}")
        
        # CORRECTED: FastQC appends _fastqc.zip to the full input filename (e.g., file.fastq.gz_fastqc.zip)
        zip_file="${OUTPUT_DIR}/${filename}_fastqc.zip"
        
        if [ -f "${zip_file}" ]; then
            echo "Skipping: ${filename} (FastQC report already exists: ${zip_file})"
            continue # Skip to the next file if report is found
        fi
        
        echo "Processing: ${filename}"
        # Run FastQC
        fastqc "${fastq_file}" -o "${OUTPUT_DIR}"
    fi
done

echo "---"
echo "--- Phase 2: Truncation Length Calculation (Q${MIN_QUALITY_SCORE}) ---"

# --- PHASE 2: TRUNCATION CALCULATION AND DATA EXTRACTION ---
# Loop through all files again to calculate truncation lengths from the generated/existing reports.
find "${DATA_DIR}" -maxdepth 1 -name "*.fastq.gz" | while read fastq_file; do
    if [ -f "${fastq_file}" ]; then
        filename=$(basename "${fastq_file}")
        
        # CORRECTED: Get the name of the FastQC results zip file and directory (uses full filename)
        zip_file="${OUTPUT_DIR}/${filename}_fastqc.zip"
        fastqc_dir="${filename}_fastqc"

        # Check if the report file exists before proceeding to extraction
        if [ ! -f "${zip_file}" ]; then
            echo "Warning: No FastQC report found for ${filename}. Skipping truncation calculation."
            continue
        fi

        # Determine read direction (R1/R2)
        if [[ "${filename}" =~ "_R1_" ]]; then
            direction="R1_forward"
        elif [[ "${filename}" =~ "_R2_" ]]; then
            direction="R2_reverse"
        else
            direction="unknown"
        fi

        echo "Extracting data for: ${filename}"
        
        # 1. Extract Per Base Sequence Quality file
        unzip -o -qq "${zip_file}" "${fastqc_dir}/fastqc_data.txt" -d "${OUTPUT_DIR}"
        
        # Check if the quality data file exists after extraction
        quality_data_file="${OUTPUT_DIR}/${fastqc_dir}/fastqc_data.txt"

        if [ -f "${quality_data_file}" ]; then
            # 2. Find the minimum truncation length (first position where Mean Quality drops below MIN_QUALITY_SCORE)
            trunc_length=$(awk -v min_q="${MIN_QUALITY_SCORE}" '
                />>Per base sequence quality/ {found=1; next}
                /^>>END_MODULE/ {found=0}
                found && $1 != "#Base" {
                    # $3 is Mean column
                    if ($3 < min_q) {
                        print $1;
                        exit;
                    }
                }' "${quality_data_file}")
            
            # If a drop was found, record it. If not, use the full length of the longest read (reported in $1 of the last line)
            if [ -z "${trunc_length}" ]; then
                # Get the length of the last base processed
                trunc_length=$(awk '
                    />>Per base sequence quality/ {found=1; next}
                    /^>>END_MODULE/ {found=0}
                    found && $1 != "#Base" {last_base = $1}
                    END {print last_base}' "${quality_data_file}")
                
                if [ -n "${trunc_length}" ]; then
                    echo "Truncation not required (Quality > Q${MIN_QUALITY_SCORE} for full length). Recommended length: ${trunc_length}"
                else
                    trunc_length="NA"
                fi
            fi
            
            echo "${direction},${trunc_length}" >> "${TRUNC_TEMP_FILE}"
            echo "  -> Recommended length for ${direction}: ${trunc_length}"
            
            # Clean up extracted directory
            rm -rf "${OUTPUT_DIR}/${fastqc_dir}"
        fi
    fi
done

echo "---"
echo "FastQC analysis complete. Generating summary and parameters file..."

# --- SUMMARY AND AVERAGE CALCULATION ---

# Initialize variables to prevent issues if grep/awk finds nothing
R1_avg=0
R2_avg=0

# Check if the temp file exists before proceeding with grep/awk
if [ ! -f "${TRUNC_TEMP_FILE}" ]; then
    echo "FATAL ERROR: Failed to create temporary file ${TRUNC_TEMP_FILE}. No truncation data was collected."
    exit 1
fi

# Calculate the average truncation length for R1 (forward) reads
R1_lengths=$(grep "R1_forward" "${TRUNC_TEMP_FILE}" | awk -F',' '{print $2}' | grep -v 'NA')
R1_count=$(echo "${R1_lengths}" | wc -l | tr -d '[:space:]')
if [ "${R1_count}" -gt 0 ]; then
    R1_sum=$(echo "${R1_lengths}" | awk '{sum += $1} END {print sum}')
    R1_avg=$(echo "scale=0; ${R1_sum} / ${R1_count}" | bc)
fi

# Calculate the average truncation length for R2 (reverse) reads
R2_lengths=$(grep "R2_reverse" "${TRUNC_TEMP_FILE}" | awk -F',' '{print $2}' | grep -v 'NA')
R2_count=$(echo "${R2_lengths}" | wc -l | tr -d '[:space:]')
if [ "${R2_count}" -gt 0 ]; then
    R2_sum=$(echo "${R2_lengths}" | awk '{sum += $1} END {print sum}')
    R2_avg=$(echo "scale=0; ${R2_sum} / ${R2_count}" | bc)
fi

# --- Parameter Saving ---
echo "# QIIME 2 DADA2 Truncation Parameters (Calculated by run_fastqc.sh)" > "${PARAMS_FILE}"
echo "R1_AVG=${R1_avg}" >> "${PARAMS_FILE}"
echo "R2_AVG=${R2_avg}" >> "${PARAMS_FILE}"
echo "Saved QIIME 2 parameters to ${PARAMS_FILE}"

echo -e "\n--- Quality Truncation Summary (Q${MIN_QUALITY_SCORE}) ---"
echo "Read Type,Recommended Truncation Lengths"
echo "R1 (Forward) - Total Samples: ${R1_count}, Average Length: ${R1_avg} bp"
echo "R2 (Reverse) - Total Samples: ${R2_count}, Average Length: ${R2_avg} bp"

echo -e "\nRecommended QIIME 2 DADA2 parameters (using integer average):"
echo "  --p-trunc-len-f ${R1_avg} \\"
echo "  --p-trunc-len-r ${R2_avg}"
echo "Note: If the average is too short (e.g., less than 150bp for 16S V4), manually inspect the HTML reports for a balance between quality and read retention."
echo "Final truncation lengths are the *shortest* length needed to maintain good quality across all samples."

# Clean up temporary file
rm -f "${TRUNC_TEMP_FILE}"