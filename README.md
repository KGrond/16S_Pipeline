# 16S rRNA Amplicon Processing Pipeline

This repository contains a set of scripts for preprocessing and analyzing 16S rRNA amplicon sequencing data using **Cutadapt**, **FastQC**, and **QIIME 2**. The pipeline performs primer removal, quality assessment, truncation parameter calculation, DADA2 denoising, feature table construction, taxonomy assignment, and phylogenetic tree generation.  

*Note: If you use a computer with the Apple Silicon M4 chip, qiime installation can be challenging. [This document](Qiime2_install_Apple%20M4.md) outlines the steps that worked for a MacBook Pro M4 running Tahoe v.26.1*


## Prerequisites
- QIIME2: https://library.qiime2.org/quickstart/amplicon
- Bash Shell: The scripts are designed to be run in a Unix-like environment (Linux, macOS, or WSL).
- Miniconda: https://www.anaconda.com/docs/getting-started/miniconda/install#macos
- Download Utilities: The system must have either wget or curl installed for downloading the Miniconda installer.
- QIIME2 classifier: (see [qiime2.org/data-resources](https://library.qiime2.org/data-resources))

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

## 1. 🛠️ Software Installs ([installs.sh](installs.sh))

**Purpose**
Activates the conda environment, and installs all dependencies.

**Key Features:**  
- Activates a Conda environment (`qiime2-amplicon-2025.7`) to install the necessary dependencies in.  
- Checks for existing dependencies, and if missing installs **Cutadapt** and **FastQC**.
- Tests the installation of dependencies. 

---


## 2. ✂️ Primer Removal ([remove_primers.sh](remove_primers.sh))

**Purpose:**  
Removes 16S V4 region primers from paired-end FASTQ files using **Cutadapt**.  

**Key Features:**  
- Activates a dedicated Conda environment (`qiime2-amplicon-2025.7`) and installs dependencies if missing.  
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
Processes the trimmed sequences in **QIIME 2** to generate feature tables, representative sequences, phylogenetic trees, and taxonomy assignments.  

**Key Features:**  
- Activates a dedicated Conda environment (`qiime2-amplicon-2025.7`).  
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

## Required Input Files

The pipeline requires the following input files:

- **Demultiplexed paired-end FASTQ files** (`*_R1.fastq` and `*_R2.fastq`)  
- **Metadata file** (`metadata.csv`)  
- **QIIME 2 manifest file** (`manifest.tsv`)  
- **Pre-trained Naive Bayes classifier** (`.qza` file, e.g., SILVA 138)  

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

**Author:** Kirsten Grond (https://github.com/KGrond)  
**Affiliation:** Alaska INBRE Data Science Core, University of Alaska Fairbanks, USA

## License
This project is licensed under the [Creative Commons Attribution (CC BY-NC-SA)](LICENSE).
