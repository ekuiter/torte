# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

### Changed

- Revised export of Docker images, allowing to easily create GitHub releases with all images
- Renamed analysis to solving

### Removed

### Fixed

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