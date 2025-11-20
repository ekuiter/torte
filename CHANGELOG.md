# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

This release significantly revises the extraction mechanism, which means we can now extract almost fully complete feature-model histories not only for Linux, but every supported system.

### Added

- Podman support
- System: uClibc
- Solver collection: SAT heritage
- Solvers: IsaSAT, MergeSat
- Resumable stages for extraction, transformation, and solving
- Flexible solver queries for void, backbone, and partial configuration analysis
- Experimental hierarchy extraction for flat UVL models
- Support for parsing UVL files in FeatJAR
- Support for extracting standalone KConfig files for testing purposes
- Integration with non-KConfig repositories like feature-model benchmark and UVLHub
- Added more flexible and consistent stage helpers for extraction and CNF transformation

### Changed

- Revised export of Docker images, allowing to easily create GitHub releases with all images
- Renamed analysis to solving and architecture to context
- Significantly improved extraction by replacing and compiling LKC's `conf.c` in place
- Revisited, checked, and improved feature-model extraction of every existing system
- Revised terminology (LKC to denote the KConfig parser implementation of the Linux kernel)
- Improved solver error handling
- Unified feature set computation
- Significantly increased performance of lambda and hook functions
- Updated KClause binding kextractor, which enables tristate encoding in KClause-extracted formulas
- Extracted FeatJAR module into dedicated repository, which simplifies building and testing it standalone
- Updated FeatJAR to latest version
- Simplified transformation stage naming

### Removed

- System-specific code clones, which are to be reintegrated into the shared codebase

### Fixed

- Several bugs
- Improved exit on Ctrl+C
- Proper locking of CSV files during parallelized jobs
- Improved encoding of logical equivalences in KClause

## [1.0.0] - 2025-08-27

### Added

#### Core Architecture
- **Declarative experiment framework** with bash-based experiment definitions
- **Multi-stage pipeline architecture** with automatic stage numbering and dependency tracking
- **Multi-pass experiments** supporting different configurations in a single experiment
- **Docker-based tool isolation** ensuring reproducible execution environments
- **Modified bash language** with Python-like named parameter passing (`--param value`)
- **Stage aggregation and joining** for combining results from multiple stages

#### System Support
- **Linux kernel** feature model extraction across architectures and versions
- **BusyBox** with complete revision history and KConfig model generation
- **Additional KConfig systems**: BuildRoot, uClibc-ng, toybox, axTLS, embtoolkit, Fiasco
- **Test systems** for lightweight CI/CD integration

#### Feature Model Extraction
- **KConfigReader + KClause** integration for direct KConfig extraction
- **Multi-architecture support** for Linux (x86, ARM, openrisc, arc, etc.)
- **Version management** with automated Git integration

#### Model Transformation
- **FeatJAR integration** with multiple transformation backends
- **FeatureIDE transformations** for format conversion (UVL, XML, DIMACS, SMT)
- **Backbone extraction** using Kissat and CadiBack
- **Format standardization** across different feature model representations

#### Analysis and Solving
- **40+ SAT solvers** from competition archives and historical collections
- **13+ #SAT solvers** including d4, sharpSAT, DPMC, ganak
- **Community structure analysis** with SatGraf integration
- **Satisfiability analysis** with timeout and parallelization support

#### Development and Operations
- **Bootstrap installer** with one-line installation from GitHub
- **Performance profiling system** with speedscope integration and function-level timing
- **Automated testing framework** with CI integration and experiment validation
- **Remote execution support** via SSH with result synchronization
- **Web-based file browser** for exploring experiment outputs
- **CSV-based result storage** with structured data export

#### Data Management
- **Stage directory management** with automatic numbering and cleanup
- **File collection utilities** with timestamp-based organization
- **Git integration** for revision tracking and statistics
- **Reproduction package export** for sharing complete experiments
- **Result aggregation** across multiple experimental configurations

#### Quality Assurance
- **Comprehensive error handling** with structured logging
- **Memory and timeout management** for long-running analyses
- **Parallel job execution** with configurable worker limits
- **Stage completion tracking** with dependency validation