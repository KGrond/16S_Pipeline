# Install Qiime2 on Apple M4

Installing QIIM2 can present some package conflict issues on Macs with the Apple M4 Silicon chip. Below is a solution that worked for me on a MacBook Pro with Tahoe v.26.1. 

Before installing QIIME2, you will need to set your terminal to open with the Rosetta 2 mode using the following steps:
1. Find the "Terminal" application in your "Applications" folder.
2. Right-click it and select "Get Info."
3. Check the box for "Open using Rosetta".
4. Close and reopen your terminal.


## 1. Channel Configuration Initialization

This step establishes a clean configuration baseline by systematically removing any existing channel entries. This prevents the introduction of package conflicts or violation of the required dependency hierarchy during the installation process.


```bash
conda config --remove channels conda-forge
conda config --remove channels bioconda
conda config --remove channels defaults
conda config --remove channels qiime2/label/r2025.10
```

## 2. Establishing Channel Priority Order
The channels are added in the required sequence (lowest to highest priority). Configuring the QIIME 2-specific channel (`qiime2/label/r2025.10`) as the highest priority ensures that the Conda solver preferentially selects package versions explicitly compatible with the QIIME 2 distribution.

```bash
conda config --add channels defaults 
conda config --add channels bioconda 
conda config --add channels conda-forge 
conda config --add channels qiime2/label/r2025.10
```

## 3. Initial Environment Creation Attempt and Architecture Override
This command initiates environment creation, incorporating the architectural compatibility fix essential for Apple Silicon systems.

CONDA_SUBDIR=osx-64: This prefix is required on M-series chips to compel the installation of packages compiled for the Intel architecture (osx-64), facilitating execution via the Rosetta 2 translation layer.

Note: This initial attempt may encounter dependency resolution failures.

```bash
CONDA_SUBDIR=osx-64 conda env create -n qiime2-2025.10 --file https://raw.githubusercontent.com/qiime2/distributions/refs/heads/dev/2025.10/amplicon/released/qiime2-amplicon-macos-latest-conda.yml
```

## 4. Configuring Flexible Channel Priority
To address complex inter-channel dependency conflicts (e.g., LibMambaUnsatisfiableError), the channel priority setting is adjusted to flexible. This configures the solver to employ a broader, more permissive strategy for combining package versions across the prioritized channels.
```bash
conda config --set channel_priority flexible
```

## 5. Final Environment Creation Attempt
The environment creation command is re-executed. With the established flexible channel priority, the Conda solver is subsequently capable of resolving the full dependency graph and successfully completing the QIIME 2 environment installation.
```bash
CONDA_SUBDIR=osx-64 conda env create -n qiime2-2025.10 --file https://raw.githubusercontent.com/qiime2/distributions/refs/heads/dev/2025.10/amplicon/released/qiime2-amplicon-macos-latest-conda.yml
```

## 6. Post-Installation Environment Configuration
Following successful installation, the environment must be persistently configured to default to the Intel architecture, guaranteeing consistent functionality across all subsequent activations.

### Activate the new environment
`conda activate qiime2-2025.10`

### Persistently set the osx-64 architecture preference within this environment
`conda config --env --set subdir osx-64`

### Deactivate conda environment
`conda deactivate`