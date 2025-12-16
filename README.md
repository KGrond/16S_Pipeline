# 16S rRNA Amplicon Processing Pipeline

This repository contains a set of scripts for preprocessing and analyzing 16S rRNA amplicon sequencing data using **Cutadapt**, **FastQC**, and **QIIME 2**. The pipeline performs primer removal, quality assessment, truncation parameter calculation, DADA2 denoising, feature table construction, taxonomy assignment, and phylogenetic tree generation.  

*Note: If you use a computer with the Apple Silicon M4 chip, qiime installation can be challenging. [This document](Qiime2_install_Apple%20M4.md) outlines the steps that worked for a MacBook Pro M4 running Tahoe v.26.1*


---
---

# 🐚 Running the pipeline via Bash
---
---

## Prerequisites
- QIIME2: https://library.qiime2.org/quickstart/amplicon
- Bash Shell: The scripts are designed to be run in a Unix-like environment (Linux, macOS, or WSL).
- Miniconda: https://www.anaconda.com/docs/getting-started/miniconda/install#macos
- Download Utilities: The system must have either wget or curl installed for downloading the Miniconda installer.
- QIIME2 classifier: (see [qiime2.org/data-resources](https://library.qiime2.org/data-resources))

---

## Required Files
The pipeline requires the following files:
- **Demultiplexed paired-end FASTQ files** (`*_R1.fastq` and `*_R2.fastq`)  
- **Metadata file** (`metadata.csv`)  
- **QIIME 2 manifest file** (`manifest.tsv`)  
- **Pre-trained Naive Bayes classifier** (`.qza` file, e.g., SILVA 138)  
---


## 🧬 Pipeline Overview

The pipeline executes in the following four sequential steps. All tools are installed and run from the single shared Conda environment: qiime2-amplicon-2025.7-test.

| **Step** | **Script** | **Tools Used** | **Purpose** |
|---------|------------|----------------|-------------|
| **1. 🛠️ Environment Setup** | [`installs.sh`](installs.sh) |  • Cutadapt • FastQC • unzip | activates the conda environment, and installs all required workflow dependencies. |
| **2. ✂️ Primer Trimming** | [`remove_primers.sh`](remove_primers.sh) | Cutadapt | Removes forward and reverse primers from raw FASTQ files using Cutadapt. |
| **3. 📊 Quality Check & Truncation Calculation** | [`run_fastqc.sh`](run_fastqc.sh) | FastQC • unzip • awk | Generates FastQC quality reports and calculates optimal QIIME 2 DADA2 truncation lengths. |
| **4. 🔍 Core Analysis** | [`qiime2_pipeline.sh`](qiime2_pipeline.sh) | QIIME 2 | Runs DADA2 denoising, builds phylogenetic trees, assigns taxonomy, and generates key QIIME 2 artifacts. |

## 🧩 Scripts Used

| Script | Description |
|-------|-------------|
| [`installs.sh`](installs.sh) | Installs all required dependencies (Cutadapt, FastQC, unzip). |
| [`remove_primers.sh`](remove_primers.sh) | Removes forward and reverse primers using Cutadapt. |
| [`run_fastqc.sh`](run_fastqc.sh) | Runs FastQC and computes read-quality-based truncation parameters. |
| [`qiime2_pipeline.sh`](qiime2_pipeline.sh) | Executes full QIIME 2 workflow: denoising, taxonomy, phylogeny, and summaries. |

---

## 🛠️ Tools Used

| Tool | Purpose |
|------|---------|
| **Conda** | Environment + dependency management |
| **QIIME 2** | Core amplicon processing + taxonomic assignment |
| **Cutadapt** | Primer trimming |
| **FastQC** | Read quality QC |
| **unzip** | Extracts FastQC output archives |

---

## 📂 Recommended Directory Structure

This project uses three main Bash scripts to process 16S amplicon sequencing data from raw FASTQ files through primer trimming, quality control, and final QIIME 2 analysis.

The structure below shows the required input locations and the generated output directories for a successful pipeline run. The entire analysis is designed to be executed from the project_root/ directory.

```bash
project_root/
|
|-- remove_primers.sh           # 1. Script for primer removal (Cutadapt)
|-- run_fastqc.sh               # 2. Script for quality control and DADA2 parameter calculation
|-- qiime2_pipeline.sh          # 3. Main script for QIIME 2 analysis
|-- sample-metadata.tsv         # REQUIRED: QIIME 2 metadata file for diversity
|-- silva-138-99-nb-classifier.qza 
|
|-- demultiplexed_seq/          # INPUT_DIR for Script 1 (Raw Data)
|   |
|   |-- R1/
|   |   |-- sampleA_R1.fastq.gz
|   |   |-- (etc...)
|   |
|   |-- R2/
|   |   |-- sampleA_R2.fastq.gz
|   |   |-- (etc...)
|
|-- trimmed_sequences/          # OUTPUT_DIR for Script 1 / INPUT_DIR for Scripts 2 & 3
|   |-- sampleA_R1_trimmed.fastq.gz
|   |-- (etc...)
|
|-- fastqc_reports_trimmed/     # OUTPUT_DIR for Script 2 (QC & DADA2 parameters)
|   |-- sampleA_R1_trimmed_fastqc.zip
|   |-- qiime2_trunc_params.txt # Contains R1_AVG and R2_AVG
|
|-- qiime2_analysis/            # OUTPUT_DIR for Script 3 (QIIME 2 Artifacts)
    |-- 01_demultiplexed_seqs.qza
    |-- 03_feature_table.qza
    |-- (etc... all QZA/QZV files)
    |-- diversity-core-metrics-phylogenetic/
        |-- (Final diversity analysis output)
```


### ⚠️ Critical File Cautions

| File/Directory | Location Requirement | Purpose |
| :--- | :--- | :--- |
| sample-metadata.tsv | MUST be in `project_root/` | Mandatory metadata file for QIIME 2 diversity analysis (Step 7). |
| silva-138-99-nb-classifier.qza | MUST be in `project_root/` | The taxonomic classifier (Script 3). (The script attempts to download this if missing). |
| qiime2_trunc_params.txt | Generated in **`fastqc_reports_trimmed/` | Contains the calculated R1\_AVG and R2\_AVG. Must be present before running Script 3. |
| Raw FASTQ Files | MUST be in `demultiplexed_seq/R1/` and `demultiplexed_seq/R2/` | Primer removal (Script 1) will fail if files are not nested in these R1/R2 folders. |



## 1. 🛠️ Software Installs ([installs.sh](installs.sh))

**Purpose**
Activates the conda environment, and installs all dependencies.

**Key Features:**  
- Activates a Conda environment (`qiime2-amplicon-2025.10`) to install the necessary dependencies in.  
- Checks for existing dependencies, and if missing installs **Cutadapt** and **FastQC**.
- Tests the installation of dependencies. 

---


## 2. ✂️ Primer Removal ([remove_primers.sh](remove_primers.sh))

**Purpose:**  
Removes 16S V4 region primers from paired-end FASTQ files using **Cutadapt**.  

**Key Features:**  
- Activates a dedicated Conda environment (`qiime2-amplicon-2025.10`) and installs dependencies if missing.  
- Removes both forward (515F) and reverse (806R) primers.  
- Saves trimmed FASTQ files to a specified output directory.  

**Dependencies:**  
- Conda  
- QIIME 2 (installed via Conda)  
- Cutadapt  

---

## 3. 📊 Quality Control and Truncation Calculation ([run_fastqc.sh](run_fastqc.sh))

**Purpose:**  
Performs quality assessment of trimmed sequences using **FastQC** and calculates recommended truncation lengths for DADA2 denoising.  

**Key Features:**  
- Activates the conda environment that contains the installed software (`qiime2-amplicon-2025.10`).  
- Generates per-sample quality reports.  
- Calculates the first base where the mean quality drops below a specified threshold (default Q20).  
- Saves recommended truncation lengths for forward and reverse reads in a persistent parameters file (`qiime2_trunc_params.txt`).  

**Dependencies:**  
- Conda  
- FastQC  
- Unzip  

**Quality Parameters:**  
- Minimum acceptable mean quality score: Q20 (adjustable in script)  

---

## 4. 🔍 QIIME 2 Core Analysis ([qiime2_pipeline.sh](qiime2_pipeline.sh))

**Purpose:**  
Processes the trimmed sequences in **QIIME 2** to generate feature tables, representative sequences, phylogenetic trees, and taxonomy assignments. In addition, we included exploratory analyses including alpha and beta diversity visualizations and taxonomic barplots. 

**Key Features:**  
- Activates a dedicated Conda environment (`qiime2-amplicon-2025.10`).  
- Imports paired-end sequences into QIIME 2 format.  
- Performs DADA2 denoising using truncation lengths from ([`run_fastqc.sh`](run_fastqc.sh)).  
- Generates feature table and representative sequence summaries.  
- Builds a phylogenetic tree using MAFFT and FastTree.  
- Assigns taxonomy using a pre-trained Naive Bayes classifier (e.g., SILVA 138).  

**Dependencies:**  
- Conda  
- QIIME 2  
- Pre-trained Naive Bayes classifier (`.qza`)  

**Classifier Example:**  
- SILVA 138 99% OTUs Naive Bayes classifier (`silva-138-99-nb-classifier.qza`)  

---

## Recommended Execution Order

To ensure the pipeline runs correctly, execute the scripts in the following order:

1. **Software Installs**  
   ```bash
   bash installs.sh
   ```

2. **Primer Removal**  
   ```bash
   bash remove_primers.sh
   ```

3. **Quality Control and Truncation Parameter Calculation**  
   ```bash
   bash run_fastqc.sh
   ```

4. **QIIME 2 Processing**  
   ```bash
   bash qiime2_pipeline.sh
   ```


---

## Notes

- Ensure Conda is properly installed and available in your shell environment.  
- All output directories will be created automatically if they do not exist.  
- If the average truncation lengths calculated by FastQC are too short for your target region, manual inspection of the HTML reports is recommended.  
- The pipeline is designed for 16S V4 amplicon data but can be adapted to other regions by modifying the primer sequences.  

---

## References

- **Cutadapt:** https://cutadapt.readthedocs.io  
- **FastQC:** https://www.bioinformatics.babraham.ac.uk/projects/fastqc/  
- **QIIME 2:** https://qiime2.org


---

# 🐳 Running the Pipeline via Docker
---


This guide details how to execute the complete three-stage 16S bioinformatics pipeline using a reproducible Docker container.

Prerequisites
Docker Desktop must be installed and running on your system.

Your local repository directory must contain the raw data (in demultiplexed_seq/) and the manifest.tsv file in the root.

1. 🚢 Pull the Pre-Built Image (Recommended)
To quickly get the working environment without needing to run the long installation process, pull the pre-built image from the public registry.

Replace your_dockerhub_username with the actual username where the image was published.

Run the pull command:

```bash
docker pull your_dockerhub_username/16s-pipeline:latest
```

2. 🚀 Run the Pipeline
The command below executes the entire pipeline (Primer Removal, FastQC, DADA2/QIIME 2) by mounting your local data and output folders to the corresponding paths inside the Docker container.

IMPORTANT: You must replace the placeholder /path/to/your/repo/16s-pipeline with the absolute path to your local project folder.

Run Command
Bash

docker run -it --rm \
    -v /path/to/your/repo/16s-pipeline/demultiplexed_seq:/app/demultiplexed_seq \
    -v /path/to/your/repo/16s-pipeline/trimmed_sequences:/app/trimmed_sequences \
    -v /path/to/your/repo/16s-pipeline/fastqc_reports_trimmed:/app/fastqc_reports_trimmed \
    -v /path/to/your/repo/16s-pipeline/qiime2_analysis:/app/qiime2_analysis \
    -v /path/to/your/repo/16s-pipeline/manifest.tsv:/app/manifest.tsv \
    your_dockerhub_username/16s-pipeline:latest
3. Key Outputs
The pipeline automatically creates the necessary output directories and saves results directly back to your local machine:

trimmed_sequences/: Cutadapt output files.

fastqc_reports_trimmed/: FastQC reports and the calculated truncation parameters (qiime2_trunc_params.txt).

qiime2_analysis/: All QIIME 2 artifacts (.qza and visualization .qzv files).



**Author:** Kirsten Grond (https://github.com/KGrond)  
**Affiliation:** Alaska INBRE Data Science Core, University of Alaska Fairbanks, USA

## License
This project is licensed under the [Creative Commons Attribution (CC BY-NC-SA)](LICENSE).
