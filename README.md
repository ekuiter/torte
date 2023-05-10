# torte: feature-model experiments à la carte 🍰

**torte is a declarative workbench for reproducible experiments in feature-model analysis research.**

Why **torte**?
Take your pick:

- "**T**seitin **or** not **T**seitin?" **E**valuator
- CNF **T**ransf**or**ma**t**ion Workb**e**nch
- KConfig Extrac**tor** that **T**ackles **E**volution
- **To**wards **R**eproducible Feature-Model **T**ransformation and **E**xtraction
- **T**he **O**bviously **R**everse-Engineered **T**ool Nam**e**

torte can currently be used to

- **extract feature models** from KConfig-based configurable software systems (e.g., the [Linux kernel](https://github.com/torvalds/linux)),
- **transform feature models** between various formats (e.g., [FeatureIDE](https://featureide.github.io), [UVL](https://github.com/Universal-Variability-Language), and [DIMACS](https://www.domagoj-babic.com/uploads/ResearchProjects/Spear/dimacs-cnf.pdf)), and
- **analyze feature models** with solvers to evaluate the extraction and transformation impact,

all in a fully declarative and reproducible fashion backed by reusable Docker containers.
This way, you can

- **draft experiments** for selected feature models first, then generalize them to a larger corpus later,
- **execute experiments** on a remote machine without having to bother with technical setup,
- **distribute fully-automated replication packages** when an experiment is ready for publication, and
- **adapt and update existing experiments** without needing to resort to clone-and-own practices.

This one-liner will get you started (Docker required):
```
curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/main/experiments/default.sh -o experiment.sh && bash experiment.sh
```
Read on if you want to know more details.

## Getting Started

To run torte, you need:

- a Linux system or Windows with [WSL](https://learn.microsoft.com/windows/wsl/install) (macOS is currently not supported)
- [curl](https://curl.se/), [Git](https://git-scm.com/), and [GNU Make](https://www.gnu.org/software/make/)
- [Docker](https://docs.docker.com/get-docker/) ([rootless mode](https://docs.docker.com/engine/security/rootless/) recommended to avoid permission issues with created files)

Experiment files in torte are self-executing - so, you can just create or download an experiment file (e.g., from the `experiments` directory) and run it.

The following should get you started on a fresh Ubuntu 22.04 installation:

```
# install and set up dependencies
sudo apt-get install -y curl git make uidmap dbus-user-session
curl -fsSL https://get.docker.com | sh
dockerd-rootless-setuptool.sh install

# run the default experiment with torte
curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/main/experiments/default.sh -o experiment.sh && bash experiment.sh
```

By default, this will install torte into the `torte` directory; all experiment data will be stored in the directories `input` and `output` in your working directory.

The above command runs the default experiment, which extracts, transforms, and analyzes the feature model of BusyBox 1.36.0 as a demonstration.
For other predefined experiments, see [here](#predefined-experiments); you can also write your own by adapting `experiment.sh`.

**Further Tips**

- As an alternative to the self-extracting installer shown above, you can clone this repository and run experiments with `./torte.sh <experiment-file>`.
- A running experiment can be stopped with `Ctrl+C`.
  If this does not respond, try `Ctrl+Z`, then `./torte.sh stop`.
- Run `./torte.sh help` to get further usage information (e.g., running an experiment over SSH and im-/export of Docker containers).
- Developers are recommended to use [ShellCheck](https://www.shellcheck.net/) to improve code quality.
- If you encounter the error message `cannot delete ...: Permission denied`, try to switch to Docker rootless mode.
- The first execution of torte can take a while (~30 minutes), as several complex Docker containers need to be built.
This can be avoided by loading a replication package that includes Docker images (built by `./torte.sh export`).

## Supported Subject Systems

This is a list of all subject systems for which feature-model extraction has been tested and confirmed to work for at least one extraction tool.
Other systems or revisions may also be supported.
Detailed system-specific information on potential threats to validity is available in the `scripts/subjects` directory.

| System | Revisions | Notes |
| - | - | - |
| [axtls](scripts/subjects/axtls.sh) | 1.0.0 - 2.0.0 | |
| [buildroot](scripts/subjects/buildroot.sh) | 2009.02 - 2022.05 | |
| [busybox](scripts/subjects/busybox.sh) | 1.3.0 - 1.36.0 | |
| [embtoolkit](scripts/subjects/embtoolkit.sh) | 1.0.0 - 1.8.0 | |
| [fiasco](scripts/subjects/fiasco.sh) | 5eed420 (2023-04-18) | [^23] |
| [freetz-ng](scripts/subjects/freetz-ng.sh) | d57a38e (2023-04-18) | [^23] |
| [linux](scripts/subjects/linux.sh) | 2.5.45 - 6.3 | [^21] | |
| [toybox](scripts/subjects/toybox.sh) | 0.4.5 - 0.8.9 | [^22] | |
| [uclibc-ng](scripts/subjects/uclibc-ng.sh) | 1.0.2 - 1.0.40 | |

[^21]: Most architectures of Linux can be extracted successfully.
The user-mode architecture `um` is currently not supported, as it requires setting an additional sub-architecture.

[^22]: Feature models for this system are currently likely to be incomplete due to an inaccurate extraction.

[^23]: This system does not regularly release tagged revisions, so only a single revision has been tested.

## Bundled Tools

### Extraction, Transformation, and Analysis

The following tools are bundled with torte and can be used in experiments for extracting, transforming, and analyzing feature models.
Most tools are not included in this repository, but cloned and built with tool-specific Docker files in the `docker` directory.
The bundled solvers are listed in a separate table [below](#solvers).

For transparency, we document the changes we make to these tools and known limitations. There are also some general known limitations of torte [^1] [^2].

| Tool | Version | Date | Notes |
| - | - | - | - |
| [ckaestne/kconfigreader](https://github.com/ckaestne/kconfigreader) | 913bf31 | 2016-07-01 | [^3] [^4] [^5] [^9] [^16] |
| [ekuiter/SATGraf](https://github.com/ekuiter/SATGraf) | 2677015 | 2023-04-05 | [^11] |
| [FeatureIDE/FeatJAR](https://github.com/FeatureIDE/FeatJAR) | e27aea7 | 2023-04-11 | [^12] [^15] |
| [FeatureIDE/FeatureIDE](https://github.com/FeatureIDE/FeatureIDE) | 3.9.1 | 2022-12-06 | [^13] [^14] [^15] |
| [paulgazz/kmax](https://github.com/paulgazz/kmax) | 5a8780d | 2023-03-19 | [^4] [^5] [^6] [^7] [^8] |
| [Z3Prover/z3](https://github.com/Z3Prover/z3) | 4.11.2 | 2022-09-04 | [^10] |

[^1]: Currently, non-Boolean variability (e.g., constraints on numerical features) is only partially supported (e.g., encoded naively into Boolean constraints).
It is recommended to check manually whether non-Boolean variability is correctly represented in generated files.

[^2]: Support for different Linux architectures is currently limited to a single Linux architecture (given in the `ARCH` environment variable) in a given experiment.

[^3]: We added the class `TransformIntoDIMACS.scala` to kconfigreader to decouple the extraction and transformation of feature models, so kconfigreader can also transform feature models extracted with other tools (e.g., kmax).

[^4]: We majorly revised the native C bindings `dumpconf.c` (kconfigreader) and `kextractor.c` (kmax), which are intended to be compiled against a system's Kconfig parser to get accurate feature models.
Our improved versions adapt to the KConfig constructs actually used in a system, which is important to extract evolution histories with evolving KConfig parsers.
Our changes are generalizations of the original versions of `dumpconf.c` and `kextractor.c` and should pose no threat to validity.
Specifically, we added support for `E_CHOICE` (treated as `E_LIST`), `P_IMPLY` (treated as `P_SELECT`, see [smba/kconfigreader](https://github.com/smba/kconfigreader)), and `E_NONE`, `E_LTH`, `E_LEQ`, `E_GTH`, `E_GEQ` (ignored).

[^5]: Compiling the native C bindings of kconfigreader and kmax is not possible for all KConfig-based systems (e.g., if the Python-based [Kconfiglib](https://github.com/ulfalizer/Kconfiglib) parser is used).
In that case, you can try to reuse a C binding from an existing system with similar KConfig files; however, this may limit the extracted model's accuracy.

[^7]: We added the script `kclause2model.py` to kmax to translate kclause's pickle files into the kconfigreader's feature-model format.
This file translates Boolean variability correctly, but non-Boolean variability is not supported.

[^8]: We do not use kmax's `kclause_to_dimacs.py` script for CNF transformation, as it has had [some issues](https://github.com/paulgazz/kmax/issues/226) in the past.
Instead, we have a separate Docker container for Z3.

[^9]: The DIMACS files produced by kconfigreader may contain additional variables due to Plaisted-Greenbaum transformation (i.e., satisfiability is preserved, model counts are not).
Currently, this behavior is not configurable.

[^10]: The DIMACS files produced by Z3 may contain additional variables due to Tseitin transformation (i.e., satisfiability and model counts are preserved).
Currently, this behavior is not configurable.

[^11]: We forked the original [SATGraf](https://bitbucket.org/znewsham/satgraf/) tool and migrated it to Gradle.
We also added a new feature for exporting the community structure visualization as a JPG file, avoiding the graphical user interface.

[^12]: FeatJAR is still in an experimental stage and its results should generally be cross-validated with FeatureIDE.

[^13]: We perform all transformations with FeatureIDE from within a FeatJAR instance, which does not affect the results.

[^14]: Transformations with FeatureIDE into XML and UVL currently only encode a flat feature hierarchy, no feature-modeling notation is reverse-engineered.

[^15]: DIMACS files produced by FeatJAR and FeatureIDE do not contain additional variables (i.e., equivalence is preserved).
Currently, this behavior is not configurable.

[^16]: Feature models and formulas produced by kconfigreader have nondeterministic clause order.
This does not impact semantics, but it possibly influences the efficiency of solvers.

### Solvers

The following solvers are bundled with torte and can be used in experiments for analyzing feature-model formulas.
The bundled solver binaries are available in the `docker/solver` directory.
Solvers are grouped in collections to allow several versions of the same solver to be used.

In addition to the solvers listed below, `z3` (already listed above) can be used as a satisfiability and SMT solver.

#### Collection: emse-2023

These #SAT solvers (available [here](https://github.com/SoftVarE-Group/emse-evaluation-sharpsat/tree/main/solvers)) were used in the evaluations of several papers:

* [Evaluating State-of-the-Art #SAT Solvers on Industrial Configuration Spaces](https://raw.githubusercontent.com/SoftVarE-Group/Papers/main/2023/2023-EMSE-Sundermann.pdf) (EMSE 2023)
* [Tseitin or not Tseitin? The Impact of CNF Transformations on Feature-Model Analyses](https://raw.githubusercontent.com/SoftVarE-Group/Papers/main/2022/2022-ASE-Kuiter.pdf) (ASE 2022)

The #SAT solvers from the collection `model-counting-competition-2022` should be preferred for new experiments.

| Solver | Version | Date | Notes |
| - | - | - | - |
| countAntom | 1.0 | 2015-05-11 | [^18] |
| d4 | ? | ? | |
| dSharp | ? | ? | |
| Ganak | ? | ? | |
| sharpSAT | ? | ? | |

#### Collection: model-counting-competition-2022

These #SAT solvers (available [here](https://cloudstore.zih.tu-dresden.de/index.php/s/pXFAfnJffKyNA77)) were used in the [model-counting competition 2022](https://mccompetition.org/past_iterations).
Not all evaluated solvers are included here, as some solver binaries (i.e., for MTMC and ExactMC) have not been disclosed.

| Solver | Version | Date | Notes |
| - | - | - | - |
| c2d | ? | ? | |
| d4 | ? | ? | |
| DPMC | ? | ? | |
| gpmc | ? | ? | |
| TwG | ? | ? | [^17] |
| SharpSAT-TD | ? | ? | [^18] |
| SharpSAT-td+Arjun | ? | ? | [^18] [^19] |

#### Collection: other

These are miscellaneous solvers from various sources.

| Solver | Version | Date | Class | Notes |
| - | - | - | - | - |
| [d4v2](https://github.com/SoftVarE-Group/d4v2) | c1f6842 | 2023-02-15 | #SAT Solver, d-DNNF compiler, PMC |
| SAT4J | 2.3.6 | 2020-12-14 | SAT Solver |

#### Collection: sat-competition

These SAT solvers (binaries copied/compiled from [here](http://www.satcompetition.org/)) were used in the evaluation of the paper [Tseitin or not Tseitin? The Impact of CNF Transformations on Feature-Model Analyses](https://raw.githubusercontent.com/SoftVarE-Group/Papers/main/2022/2022-ASE-Kuiter.pdf) (ASE 2022).
Each solver is the gold medal winner in the main track (SAT+UNSAT) of the SAT competition in the year encoded in its file name.
We were unable to obtain binaries for the winning solvers in 2008 and 2015.

| Year | Solver | Version | Date | Notes |
| - | - | - | - | - |
| 2002 | zchaff | ? | ? | |
| 2003 | Forklift | ? | ? | |
| 2004 | zchaff | ? | ? | |
| 2005 | SatELiteGTI | ? | ? | |
| 2006 | MiniSat | ? | ? | |
| 2007 | RSat | ? | ? | |
| 2009 | precosat | ? | ? | |
| 2010 | CryptoMiniSat | ? | ? | |
| 2011 | glucose | ? | ? | |
| 2012 | glucose | ? | ? | |
| 2013 | lingeling-aqw | ? | ? | |
| 2014 | lingeling-ayv | ? | ? | |
| 2016 | MapleCOMSPS_DRUP | ? | ? | |
| 2017 | Maple_LCM_Dist | ? | ? | |
| 2018 | MapleLCMDistChronoBT | ? | ? | |
| 2019 | MapleLCMDiscChronoBT-DL-v3 | ? | ? | |
| 2020 | Kissat-sc2020-sat | ? | ? | |
| 2021 | Kissat_MAB | ? | ? | |

[^17]: For TwG, two configurations were provided by the model-counting competition (`TwG1` and `TwG2`).
As there was no indication as to which configuration was used in the competition, we arbitrarily chose `TwG1`.

[^18]: This solver currently crashes on some or all inputs.

[^19]: For SharpSAT-td+Arjun, two configurations were provided by the model-counting competition (`conf1` and `conf2`).
As only the second configuration actually runs SharpSAT-td, we chose `conf2`.

## Predefined Experiments

This is a list of all predefined experiments in the `experiments` directory and their purposes.
Please create a pull request if you want to publish your own experiment.
Experiments starting with `draft-` are experimental.

| Experiment | Purpose |
| - | - |
| `default.sh` | "Hello-world" experiment that extracts and transforms a single feature model |
| `draft-ase-2022-tseitin-or-not-tseitin.sh` | Evaluation for the paper [Tseitin or not Tseitin? The Impact of CNF Transformations on Feature-Model Analyses](https://raw.githubusercontent.com/SoftVarE-Group/Papers/main/2022/2022-ASE-Kuiter.pdf) (ASE 2022) |
| `draft-linux.sh` | Extraction, transformation, and analysis of Linux feature models |
| `feature-model-collection.sh` | Extracts and transforms a collection of feature models |

## Project History

This project has evolved through several stages and intends to replace them all:

[kmax-vm](https://github.com/ekuiter/kmax-vm) > [feature-model-repository-pipeline](https://github.com/ekuiter/feature-model-repository-pipeline) > [tseitin-or-not-tseitin](https://github.com/ekuiter/tseitin-or-not-tseitin) > [torte](https://github.com/ekuiter/torte)

- [kmax-vm](https://github.com/ekuiter/kmax-vm) was intended to provide an easy-to-use environment for integrating kmax with [PCLocator](https://github.com/ekuiter/PCLocator) in a virtual machine using Vagrant/VirtualBox.
  It is now obsolete due to our Docker integration of kmax.
- [feature-model-repository-pipeline](https://github.com/ekuiter/feature-model-repository-pipeline) extended [kmax-vm](https://github.com/ekuiter/kmax-vm) and could be used to extract feature models from Kconfig-based software systems with kconfigreader and kmax.
  The results were stored in the [feature-model-repository](https://github.com/ekuiter/feature-model-repository).
  Its functionality is completely subsumed by torte and more efficient and reliable due to our Docker integration.
- [tseitin-or-not-tseitin](https://github.com/ekuiter/tseitin-or-not-tseitin) extended the [feature-model-repository-pipeline](https://github.com/ekuiter/feature-model-repository-pipeline) to allow for transformation and analysis of feature models.
  It was mostly intended as a replication package for a single academic paper.
  Its functionality is almost completely subsumed by torte, which can be used to create replication packages for many different experiments.

If you are looking for a curated collection of feature models from various domains, have a look at our [feature-model-benchmark](https://github.com/SoftVarE-Group/feature-model-benchmark).

If you have any feedback, please contact me at [kuiter@ovgu.de](mailto:kuiter@ovgu.de).
New issues, pull requests, or any other kinds of feedback are always welcome.

## License

The source code of this project is released under the [LGPL v3 license](LICENSE.txt).
To ensure reproducibility, we also provide binaries (e.g., for solvers) in this repository.
These binaries have been collected or compiled from public sources.
Their usage is subject to each binaries' respective license - please contact me if you perceive any licensing issues.