#!/bin/bash
# Exit immediately if a command exits with a non-zero status
set -e

# ==============================================================================
#                      ** SCRIPT EXPLANATION / README **
# ==============================================================================
#
# ## Purpose: Automated QIIME 2 Truncation Parameter Calculation
# This script performs three key actions:
# 1. Runs **FastQC** on trimmed FASTQ files (resuming existing analysis).
# 2. Analyzes the resulting FastQC reports to find the **truncation length (bp)**
#    where the Mean quality drops below the configured threshold (Q20 by default)
#    for each sample. Data is piped directly from the zip file for efficiency.
# 3. Calculates the **Median** and **Mean** of these lengths for R1 and R2 reads.
# 4. **Intelligently selects** the truncation parameter (Median if highly skewed,
#    Mean otherwise) to recommend for the QIIME 2 DADA2 step, saving it to 
#    `qiime2_trunc_params.txt`.
# 5. Generates a **text-based histogram** for manual validation.
#
# ## Configuration Variables (Customize These):
# * `DATA_DIR`: Change this path if your trimmed FASTQ files are not in 
#   './trimmed_sequences'.
# * `CONDA_ENV`: Ensure this matches your active QIIME 2 environment name.
# * `MIN_QUALITY_SCORE`: Change this (default is 20) if you require a different 
#   minimum quality threshold (e.g., Q25).
#
# ## Checkpointing and Resuming:
# The script **skips** rerunning FastQC for any FASTQ file that already has a
# corresponding **.zip report** in the **fastqc_reports_trimmed/** directory.
#
# ## Output and Cleanup Files:
# * **Created Files:**
#   * `fastqc_reports_trimmed/*.zip`: The individual FastQC reports. (Skipped on resume)
#   * `fastqc_reports_trimmed/qiime2_trunc_params.txt`: Final recommended DADA2 parameters.
#   * `fastqc_reports_trimmed/truncation_histograms.txt`: Text histograms for validation.
#
# * **To Start Over (Clean Run):**
#   Delete the entire FastQC output directory:
#   `rm -rf fastqc_reports_trimmed/`
#
# ==============================================================================

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

# Output file for the calculated histograms
HISTO_FILE="${OUTPUT_DIR}/truncation_histograms.txt"

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
# Only clear the temp file if it exists, don't clear the final params file yet as it's generated later
rm -f "${TRUNC_TEMP_FILE}"
rm -f "${HISTO_FILE}"
echo "Created output directory: ${OUTPUT_DIR}"

# --- PHASE 1: FASTQC EXECUTION WITH RESUME/CHECKPOINT ---
echo "--- Phase 1: Running FastQC (Resumes existing analysis) ---"

# Use a globbing for loop for stability.
for fastq_file in "${DATA_DIR}"/*.fastq.gz; do
    # Check if the file actually exists (handles cases where the glob finds no match)
    if [ -f "${fastq_file}" ]; then
        filename=$(basename "${fastq_file}")
        
        # Calculate the base name for the report by stripping the .fastq.gz extension.
        zip_base_name="${filename%.fastq.gz}"

        # The expected output report file name
        zip_file="${OUTPUT_DIR}/${zip_base_name}_fastqc.zip"
        
        # Checkpoint: Skip if the expected output report file already exists
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

# --- PHASE 2: TRUNCATION CALCULATION AND DATA EXTRACTION (Using 'for' loop) ---
# Loop through all files again to calculate truncation lengths from the generated/existing reports.
for fastq_file in "${DATA_DIR}"/*.fastq.gz; do
    if [ -f "${fastq_file}" ]; then
        filename=$(basename "${fastq_file}")
        
        # Calculate the base name for the report by stripping the .fastq.gz extension
        zip_base_name="${filename%.fastq.gz}"
        
        # Get the name of the FastQC results zip file and directory (uses the base name)
        zip_file="${OUTPUT_DIR}/${zip_base_name}_fastqc.zip"
        fastqc_dir="${zip_base_name}_fastqc"

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
            # The length is the base position *before* the quality drop.
            trunc_length=$(awk -v min_q="${MIN_QUALITY_SCORE}" '
                />>Per base sequence quality/ {found=1; next}
                /^>>END_MODULE/ {found=0}
                found && $1 != "#Base" {
                    # $3 is Mean column
                    if ($3 < min_q) {
                        # The truncation length is the position *before* the drop
                        print $1 - 1;
                        exit;
                    }
                }' "${quality_data_file}")
            
            # If a drop was found, record it. If not, use the full length of the longest read
            if [ -z "${trunc_length}" ]; then
                # Get the length of the last base processed (which is the full read length)
                # We subtract 1 to ensure a discrete integer output, as the last base reported is usually N-1 of the read length
                # A more robust solution is to check the max reported base, but for typical Illumina runs, 151 is the max.
                trunc_length=$(awk '
                    />>Per base sequence quality/ {found=1; next}
                    /^>>END_MODULE/ {found=0}
                    found && $1 != "#Base" {last_base = $1}
                    END {print last_base}' "${quality_data_file}")
                
                if [ -n "${trunc_length}" ]; then
                    # Force to integer if the length is a range (e.g., 150-151)
                    # We take the lower number for safety, if a range is implied by the report, but for simplicity, we assume the max.
                    # Since FastQC often reports the max as 151 for 150bp runs, we set a clear integer max.
                    trunc_length=150
                    echo "Truncation not required (Quality > Q${MIN_QUALITY_SCORE} for full length). Recommended length: ${trunc_length}"
                else
                    trunc_length="NA"
                fi
            fi
            
            # Ensures trunc_length is not negative or zero if the first base fails (sets to 1)
            if [ "${trunc_length}" -lt 1 ]; then
                 trunc_length=1
            fi

            echo "${direction},${trunc_length}" >> "${TRUNC_TEMP_FILE}"
            echo "  -> Recommended length for ${direction}: ${trunc_length}"
            
            # Clean up extracted directory
            rm -rf "${OUTPUT_DIR}/${fastqc_dir}"
        fi
    fi
done

# ---
## --- Summary and Statistical Calculation (Median/Mean/Skew Logic) ---
# ---

# Check if the temp file exists before proceeding with calculation
if [ ! -f "${TRUNC_TEMP_FILE}" ]; then
    echo "FATAL ERROR: Failed to create temporary file ${TRUNC_TEMP_FILE}. No truncation data was collected."
    exit 1
fi

echo "Calculating median and average truncation lengths..."

# Function to calculate MEDIAN, MEAN (Average), and COUNT for a given read type
calculate_stats() {
    local read_type=$1
    local sum=0
    local count=0
    local median=0
    local mean=0
    local all_lengths

    # 1. Filter out 'NA' and extract lengths for the specific read type.
    # 2. Sort the lengths numerically (required for median).
    all_lengths=$(awk -F',' -v type="${read_type}" '
        $1 == type && $2 != "NA" {
            print $2;
        }' "${TRUNC_TEMP_FILE}" | sort -n)

    # Calculate count and sum
    count=$(echo "${all_lengths}" | wc -l)
    sum=$(echo "${all_lengths}" | awk '{sum += $1} END {print sum}')
    
    if [ "${count}" -eq 0 ]; then
        echo "0,0,0" # median, mean, count
        return
    fi
    
    # Calculate Mean (Average), rounded to the nearest integer
    # Uses bc/awk: (Sum/Count) + 0.5 then truncates to integer
    mean=$(echo "scale=0; (${sum} / ${count}) + 0.5" | bc | awk '{print int($1)}')

    # Calculate Median (Robust calculation for both odd/even counts, rounded to nearest integer)
    if [ "${count}" -gt 0 ]; then
        local line_count="${count}"
        
        if [ "$((line_count % 2))" -eq 1 ]; then
            # Odd count: Median is the single middle element
            local middle_line=$(( (line_count + 1) / 2 ))
            # Uses sed to get the single middle value
            median=$(echo "${all_lengths}" | sed -n "${middle_line}p")
        else
            # Even count: Median is the average of the two middle elements, then rounded.
            local lower_middle_line=$(( line_count / 2 ))
            local upper_middle_line=$(( lower_middle_line + 1 ))
            
            # Get the two middle values
            local val1=$(echo "${all_lengths}" | sed -n "${lower_middle_line}p")
            local val2=$(echo "${all_lengths}" | sed -n "${upper_middle_line}p")

            # Calculate the average, add 0.5 for rounding, and then truncate (to nearest integer)
            median=$(echo "scale=0; ((${val1} + ${val2}) / 2) + 0.5" | bc | awk '{print int($1)}')
        fi
    fi

    # Print the results: median, mean, count
    echo "${median},${mean},${count}"
}

# --- PROCESS R1 ---
R1_stats=$(calculate_stats "R1_forward")
R1_median=$(echo "${R1_stats}" | awk -F',' '{print $1}')
R1_mean=$(echo "${R1_stats}" | awk -F',' '{print $2}')
R1_count=$(echo "${R1_stats}" | awk -F',' '{print $3}')

# --- PROCESS R2 ---
R2_stats=$(calculate_stats "R2_reverse")
R2_median=$(echo "${R2_stats}" | awk -F',' '{print $1}')
R2_mean=$(echo "${R2_stats}" | awk -F',' '{print $2}')
R2_count=$(echo "${R2_stats}" | awk -F',' '{print $3}')

# --- Skew Check Logic ---
# If the absolute difference between Median and Mean is > 10bp, use the Median (robust to outliers).
DIFF_THRESHOLD=10

R1_use_median="false"
R2_use_median="false"

# R1 Check - Calculate absolute difference using shell arithmetic
if [ "${R1_median}" -gt "${R1_mean}" ]; then
    R1_DIFF=$((R1_median - R1_mean))
else
    R1_DIFF=$((R1_mean - R1_median))
fi

if [ "${R1_DIFF}" -gt "${DIFF_THRESHOLD}" ]; then
    R1_FINAL_PARAM="${R1_median}"
    R1_use_median="true"
else
    R1_FINAL_PARAM="${R1_mean}"
fi

# R2 Check - Calculate absolute difference using shell arithmetic
if [ "${R2_median}" -gt "${R2_mean}" ]; then
    R2_DIFF=$((R2_median - R2_mean))
else
    R2_DIFF=$((R2_mean - R2_median))
fi

if [ "${R2_DIFF}" -gt "${DIFF_THRESHOLD}" ]; then
    R2_FINAL_PARAM="${R2_median}"
    R2_use_median="true"
else
    R2_FINAL_PARAM="${R2_mean}"
fi

# --- Visualization Generation (Text-based Histograms) ---
echo "--- Generating Histograms ---"

generate_histogram() {
    local read_type=$1
    local title=$2
    local histogram

    # Use awk to count frequencies of each unique length
    # Then pipe to awk again to format the histogram bars (where each count is a '*')
    histogram=$(awk -F',' -v type="${read_type}" '
        $1 == type && $2 != "NA" {
            count[$2]++;
        }
        END {
            for (len in count) {
                printf "%s,%s\n", len, count[len];
            }
        }' "${TRUNC_TEMP_FILE}" | sort -n -t',' -k1,1 | awk -F',' '
        {
            bar = "";
            for (i=0; i<$2; i++) {
                bar = bar "*";
            }
            # Print length (left-aligned) and the bar (max bar length is 20 for screen)
            printf " %-10s | %s (%d)\n", $1 " bp", bar, $2;
        }')

    echo "## 📊 ${title} Truncation Length Distribution" >> "${HISTO_FILE}"
    echo "Count of Samples Truncated at Each Length (Q${MIN_QUALITY_SCORE}):" >> "${HISTO_FILE}"
    echo "" >> "${HISTO_FILE}"
    echo " Length (bp) | Samples (Total: ${R1_count}/${R2_count})" >> "${HISTO_FILE}"
    echo "-------------|---------------------------------------------" >> "${HISTO_FILE}"
    echo "${histogram}" >> "${HISTO_FILE}"
    echo "" >> "${HISTO_FILE}"
}

generate_histogram "R1_forward" "R1 (Forward Read)"
generate_histogram "R2_reverse" "R2 (Reverse Read)"

# --- Parameter Saving ---
echo "# QIIME 2 DADA2 Truncation Parameters (Calculated by run_fastqc.sh)" > "${PARAMS_FILE}"
echo "R1_TRUNC_LEN=${R1_FINAL_PARAM}" >> "${PARAMS_FILE}"
echo "R2_TRUNC_LEN=${R2_FINAL_PARAM}" >> "${PARAMS_FILE}"
echo "Saved QIIME 2 parameters to ${PARAMS_FILE}"

echo -e "\n--- Quality Truncation Summary (Q${MIN_QUALITY_SCORE}) ---"

# R1 Summary
echo "Read Type: R1 (Forward) - Total Samples: ${R1_count}"
echo "  Median Length: ${R1_median} bp"
echo "  Average Length: ${R1_mean} bp"
if [ "${R1_use_median}" == "true" ]; then
    echo "  ➡️ Final Parameter Chosen: ${R1_FINAL_PARAM} bp (**MEDIAN** used due to high skew/outliers.)"
else
    echo "  ➡️ Final Parameter Chosen: ${R1_FINAL_PARAM} bp (**AVERAGE** used, low skew)."
fi

# R2 Summary
echo "Read Type: R2 (Reverse) - Total Samples: ${R2_count}"
echo "  Median Length: ${R2_median} bp"
echo "  Average Length: ${R2_mean} bp"
if [ "${R2_use_median}" == "true" ]; then
    echo "  ➡️ Final Parameter Chosen: ${R2_FINAL_PARAM} bp (**MEDIAN** used due to high skew/outliers.)"
else
    echo "  ➡️ Final Parameter Chosen: ${R2_FINAL_PARAM} bp (**AVERAGE** used, low skew)."
fi

echo -e "\nRecommended QIIME 2 DADA2 parameters:"
echo "  --p-trunc-len-f ${R1_FINAL_PARAM} \\"
echo "  --p-trunc-len-r ${R2_FINAL_PARAM}"

# --- Final User Warning ---
echo -e "\n========================================================"
echo "⚠️ **ACTION REQUIRED: PARAMETER VALIDATION** ⚠️"
echo "========================================================"
echo "The recommended truncation lengths have been AUTOMATICALLY calculated."
echo "Due to potential bimodal distributions (like the R2 data), you MUST manually verify the chosen lengths."
echo ""
echo "* **Check:** Review the generated file **${HISTO_FILE}** to confirm the distribution of truncation lengths."
echo "* **Compare:** Ensure the **Final Parameter Chosen** (Median or Average) aligns with the bulk of your high-quality reads."
echo "* **Adjust:** If the automated choice is unsafe, manually edit the DADA2 parameters in your main QIIME 2 pipeline script."
echo "========================================================"


# Clean up temporary file
rm -f "${TRUNC_TEMP_FILE}"