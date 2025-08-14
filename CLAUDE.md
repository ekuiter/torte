# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

torte is a declarative workbench for reproducible experiments in feature-model analysis research. It provides tools to extract feature models from KConfig-based configurable software systems, transform them between various formats, and analyze them with solvers.

## Key Commands

### Running Experiments
- `./torte.sh` - Run the default experiment (BusyBox demo)
- `./torte.sh <experiment>` - Run a specific experiment from the experiments/ directory
- `./torte.sh clean` - Remove all output files for the experiment
- `./torte.sh stop` - Stop the current experiment
- `./torte.sh reset` - Remove all Docker containers and images

### Remote Operations
- `./torte.sh run-remote [host]` - Run experiment on remote server
- `./torte.sh copy-remote [host]` - Download results from remote server
- `./torte.sh install-remote [host] [image]` - Install Docker image on remote server

### Development and Analysis
- `./torte.sh export` - Prepare a reproduction package
- `./torte.sh browse` - Start web server for browsing output files
- `./torte.sh help` - Show help information

## Architecture

### Core Structure
- **torte.sh**: Main entry point script that handles installation and routing
- **src/main.sh**: Primary command dispatcher and initialization
- **src/lib/**: Core library functions for experiments, analysis, transformation
- **src/docker/**: Docker containers for various tools and solvers
- **src/systems/**: System-specific extraction scripts (Linux, BusyBox, etc.)
- **experiments/**: Predefined experiment configurations

### Key Components
- **Extraction Tools**: KConfigReader, KClause for feature model extraction
- **Transformation Tools**: FeatJAR, FeatureIDE for format conversion (DIMACS, UVL, XML)
- **Analysis Tools**: Z3, various SAT/SMT solvers for model analysis
- **Systems Support**: Linux kernel, BusyBox, BuildRoot, and other KConfig-based systems

### Docker-Based Architecture
torte uses Docker containers extensively to ensure reproducibility. Each tool (extractors, transformers, solvers) runs in its own containerized environment. The system automatically builds required Docker images on first use.

## Experiment Structure

### Creating Experiments
Experiments are Bash scripts that define:
- `experiment-systems()`: Which systems/revisions to analyze
- `experiment-stages()`: Pipeline of extraction, transformation, and analysis steps

### Common Stages
- `clone-systems`: Download and prepare source systems
- `extract-kconfig-models`: Extract feature models from KConfig files
- `transform-models-*`: Convert between formats (DIMACS, UVL, XML)
- `solve-*`: Run analysis (satisfiability, model counting, backbone computation)
- `join-into`: Combine results from multiple stages

## Configuration

### Global Variables
- `OUTPUT_DIRECTORY=output`: Where experiment results are stored
- `FORCE_RUN=`: Set to 'y' to force re-running completed stages
- `VERBOSE=`: Set to 'y' for detailed console output
- `TIMEOUT=`: Default timeout for operations
- `JOBS=`: Number of parallel jobs for analysis

### Docker Configuration
- `DOCKER_RUN=y`: Enable Docker container execution
- `MEMORY_LIMIT=`: Automatically determined if unset

## Development Notes

- The codebase uses Docker extensively for tool isolation and reproducibility
- Experiments are fully declarative and can be distributed as reproduction packages  
- The system supports both local and remote execution
- Results are stored in CSV format for easy analysis
- Jupyter notebooks can be integrated for result visualization
- is written fully in bash to leverage the composition effects of pipes and bash's ease of use
- uses a bash dialect specified in `src/bootstrap.sh` to allow for python-like passing of arguments (either just positional with `<value>`, or named with `--<arg> <value>`)
- make sure to, whenever you update a signature of a function, also update all occurrences of that change in that function's body
- DO NOT attempt to run any file directly, because they need the bash dialect preprocessor
- to run and test any given function, it can just be executed with `./torte.sh <function> <args>`

## Important Files to Understand

- `torte.sh`: Main entry point and installer
- `src/main.sh`: Core dispatcher logic
- `src/lib/experiment.sh`: Experiment management functions
- `experiments/default/experiment.sh`: Simple demo experiment
- `src/docker/*/Dockerfile`: Tool-specific containers

## 🛑 DO NOT TOUCH 🛑

**CRITICAL: Under no circumstances should you ever modify the following:**

- `output*/*`