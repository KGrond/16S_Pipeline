# 16S rRNA Amplicon Processing Pipeline

This repository contains a set of scripts for preprocessing and analyzing 16S rRNA amplicon sequencing data using **Cutadapt**, **FastQC**, and **QIIME 2**. The pipeline performs primer removal, quality assessment, truncation parameter calculation, DADA2 denoising, feature table construction, taxonomy assignment, and phylogenetic tree generation.  

## Pipeline Overview

The pipeline consists of three main scripts, which should be executed sequentially:

1. **Primer Removal (`remove_primers.sh`)**  
2. **Quality Control and Truncation Parameter Calculation (`run_fastqc.sh`)**  
3. **QIIME 2 Processing (`qiime2_pipeline.sh`)**

---

## 1. Primer Removal (`remove_primers.sh`)

**Purpose:**  
Removes 16S V4 region primers from paired-end FASTQ files using **Cutadapt**.  

**Key Features:**  
- Activates a dedicated Conda environment (`qiime2-16s-pipeline`) and installs dependencies if missing.  
- Removes both forward (515F) and reverse (806R) primers.  
- Saves trimmed FASTQ files to a specified output directory.  

**Dependencies:**  
- Conda  
- QIIME 2 (installed via Conda)  
- Cutadapt  

---

## 2. Quality Control and Truncation Calculation (`run_fastqc.sh`)

**Purpose:**  
Performs quality assessment of trimmed sequences using **FastQC** and calculates recommended truncation lengths for DADA2 denoising.  

**Key Features:**  
- Activates the Conda environment (`qiime2-16s-pipeline`).  
- Installs **FastQC** and **unzip** if not already present.  
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

## 3. QIIME 2 Processing (`qiime2_pipeline.sh`)

**Purpose:**  
Processes the trimmed sequences in **QIIME 2** to generate feature tables, representative sequences, phylogenetic trees, and taxonomy assignments.  

**Key Features:**  
- Activates a dedicated Conda environment (`qiime2-amplicon-2025.7`).  
- Imports paired-end sequences into QIIME 2 format.  
- Performs DADA2 denoising using truncation lengths from `run_fastqc.sh`.  
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

1. **Primer Removal**  
   ```bash
   bash remove_primers.sh
   ```

2. **Quality Control and Truncation Parameter Calculation**  
   ```bash
   bash run_fastqc.sh
   ```

3. **QIIME 2 Processing**  
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

- **Cutadapt:** [https://cutadapt.readthedocs.io](https://cutadapt.readthedocs.io)  
- **FastQC:** [https://www.bioinformatics.babraham.ac.uk/projects/fastqc/](https://www.bioinformatics.babraham.ac.uk/projects/fastqc/)  
- **QIIME 2:** [https://qiime2.org](https://qiime2.org)  

---

