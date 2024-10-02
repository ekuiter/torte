# torte: feature-model experiments à la carte 🍰

**torte is a declarative workbench for reproducible experiments in feature-model analysis research.**

Why **torte**?
Take your pick:

- "**T**seitin **or** not **T**seitin?" **E**valuator
- CNF **T**ransf**or**ma**t**ion Workb**e**nch
- KConfig Extrac**tor** that **T**ackles **E**volution
- **To**wards **R**eproducible Feature-Model **T**ransformation and **E**xtraction
- **T**hat's an **O**bviously **R**everse-Engineered **T**ool Nam**e**
- KConfig = 🍰 config ∧ 🍰 = torte ∎

torte can be used to

- **extract feature models** from KConfig-based configurable software systems (e.g., the [Linux kernel](https://github.com/torvalds/linux)),
- **transform feature models** between various formats (e.g., [FeatureIDE](https://featureide.github.io), [UVL](https://github.com/Universal-Variability-Language), and [DIMACS](https://www.domagoj-babic.com/uploads/ResearchProjects/Spear/dimacs-cnf.pdf)), and
- **analyze feature models** with solvers to evaluate the extraction and transformation impact,

all in a fully declarative and reproducible fashion backed by reusable Docker containers.
This way, you can

- **draft experiments** for selected feature models first, then generalize them to a larger corpus later,
- **execute experiments** on a remote machine without having to bother with technical setup,
- **distribute fully-automated reproduction packages** when an experiment is ready for publication, and
- **adapt and update existing experiments** without needing to resort to clone-and-own practices.

## Getting Started: The Quick Way

This one-liner will get you started with the [default experiment](experiments/default.sh) ([Docker](https://docs.docker.com/get-docker/) required).
```
curl -s https://ekuiter.github.io/torte/ | sh
```
Read on if you want to know more details.

## Getting Started: In Detail

To run torte, you need:

- an `x86_64` or `arm64` system [^28] with Linux, macOS, or Windows with [WSL](https://learn.microsoft.com/windows/wsl/install)
- [Git](https://git-scm.com/), [curl](https://curl.se/), GNU tools ([bash](https://www.gnu.org/software/bash/), [coreutils](https://www.gnu.org/software/coreutils/), [make](https://www.gnu.org/software/make/), [grep](https://www.gnu.org/software/grep/), and [sed](https://www.gnu.org/software/sed/))
- [Docker](https://docs.docker.com/get-docker/) (preferably in [rootless mode](https://docs.docker.com/engine/security/rootless/) on Linux)

[^28]: On `arm64` systems (e.g., Windows tablets and Apple Silicon Macs), torte cross-compiles some Docker images to ensure that precompiled binaries (e.g., JavaSMT, Z3, and all solvers) function correctly.
This may negatively impact performance on some systems (e.g., ARM-based Windows tablets), although recent Macs should not be affected due to [Rosetta](https://en.wikipedia.org/wiki/Rosetta_(software)).
(If you encounter errors like [this one](https://github.com/docker/for-mac/issues/7006), try to disable "Use Rosetta for x86_64/amd64 emulation on Apple Silicon" in the Docker settings. This setting can be re-enabled after the Docker images have been built.)
Executing torte from within a virtual machine has only been confirmed to work with Linux guest systems on `x86_64` host systems.
Despite our efforts, some functionality involving precompiled binaries is still known to cause problems on `arm64` systems.
If such functionality is required, the easiest solution is to switch to an `x86_64` system (e.g., with SSH).

Experiment files in torte are self-executing - so, you can just create or download an experiment file (e.g., from the `experiments` directory) and run it.

The following instructions will get you started on a fresh system.
By default, each of these instruction sets will install torte into the `torte` directory.
All experiment data will then be stored in the directories `input` and `output` in your working directory.

### Ubuntu 22.04

```
# install and set up dependencies
sudo apt-get update
sudo apt-get install -y curl git make uidmap dbus-user-session

# install Docker (see https://docs.docker.com/desktop/install/linux-install/)
curl -fsSL https://get.docker.com | sh
dockerd-rootless-setuptool.sh install

# download and run the default experiment
curl -s https://ekuiter.github.io/torte/ | sh
```

### macOS 14

```
# install and set up dependencies (this will replace macOS' built-in bash with a newer version)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
(echo; echo 'eval "$(/opt/homebrew/bin/brew shellenv)"') >> $HOME/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
brew install bash coreutils gnu-sed grep

# install Docker (see https://docs.docker.com/desktop/install/mac-install/)
curl -o Docker.dmg https://desktop.docker.com/mac/main/arm64/149282/Docker.dmg
sudo hdiutil attach Docker.dmg
sudo /Volumes/Docker/Docker.app/Contents/MacOS/install --accept-license
sudo hdiutil detach /Volumes/Docker
rm Docker.dmg
open /Applications/Docker.app

# download and run the default experiment
curl -s https://ekuiter.github.io/torte/ | sh
```

### Windows 11

```
# install WSL (see https://learn.microsoft.com/windows/wsl/install)
powershell
wsl --install

# install Docker (see https://docs.docker.com/desktop/install/windows-install/)
Invoke-WebRequest https://desktop.docker.com/win/main/amd64/149282/Docker%20Desktop%20Installer.exe -OutFile Docker.exe
Start-Process Docker.exe -Wait -ArgumentList 'install', '--accept-license'
Remove-Item Docker.exe

# restart your computer, start Docker, then install and set up dependencies
wsl
sudo apt-get update
sudo apt-get install -y curl git make

# download and run the default experiment
curl -s https://ekuiter.github.io/torte/ | sh
```

Above, we run the [default experiment](experiments/default.sh), which extracts, transforms, and analyzes the feature model of BusyBox 1.36.0 as a demonstration.
To execute another experiment, run `curl -s https://ekuiter.github.io/torte/ | sh -s - <experiment>` (a list of predefined experiments is available [here](#predefined-experiments)).
You can also write your own experiments by adapting an existing experiment file.

**Further Tips**

- As an alternative to the self-extracting installer shown above, you can clone this repository and run experiments with `./torte.sh <experiment-file>`.
- A running experiment can be stopped with `Ctrl+C`.
  If this does not respond, try `Ctrl+Z`, then `./torte.sh stop`.
- Run `./torte.sh help` to get further usage information (e.g., running an experiment over SSH and im-/export of Docker containers).
- Developers are recommended to use [ShellCheck](https://www.shellcheck.net/) to improve code quality.
- If Docker is running in rootless mode, experiments must not be run as `sudo`. Otherwise, experiments must be run as `sudo`.
- The first execution of torte can take a while (~30 minutes), as several complex Docker containers need to be built.
This can be avoided by loading a reproduction package that includes Docker images (built by `./torte.sh export`).

## Supported Subject Systems

This is a list of all subject systems for which feature-model extraction has been tested and confirmed to work for at least one extraction tool.
Other systems or revisions may also be supported.
Detailed system-specific information on potential threats to validity is available in the `scripts/subjects` directory.

| System | Revisions | Notes |
| - | - | - |
| [axtls](scripts/subjects/axtls.sh) | 1.0.0 - 2.0.0 | |
| [buildroot](scripts/subjects/buildroot.sh) | 2009.02 - 2024.05 | |
| [busybox](scripts/subjects/busybox.sh) | 1.3.0 - 1.36.0 | |
| [embtoolkit](scripts/subjects/embtoolkit.sh) | 1.0.0 - 1.8.0 | |
| [fiasco](scripts/subjects/fiasco.sh) | 5eed420 (2023-04-18) | [^23] |
| [freetz-ng](scripts/subjects/freetz-ng.sh) | d57a38e (2023-04-18) | [^23] |
| [linux](scripts/subjects/linux.sh) | 2.5.45 - 6.7 | [^21] [^25] [^26] [^29] | |
| [toybox](scripts/subjects/toybox.sh) | 0.4.5 - 0.8.9 | [^22] | |
| [uclibc-ng](scripts/subjects/uclibc-ng.sh) | 1.0.2 - 1.0.47 | |

[^21]: Most revisions and architectures of Linux (since the introduction of KConfig) can be extracted successfully.
The user-mode architecture `um` is currently not supported, as it requires setting an additional sub-architecture.

[^25]: Due to extractor limitations, we ignore the more recently introduced KConfig constructs defined in Linux' `scripts/Kconfig.include`.
Most of these only add machine specific-default values or dependencies (affecting about 100 features in the kernel's history up to `v6.3`).
However, these constructs do not affect our feature-model extraction, as we want to ignore machine-dependent restrictions.

[^26]: Currently, we use the KConfig parser of Linux 2.6.9 for all revisions of Linux up to Linux 2.6.9, as older versions of the parser cannot be compiled.
We suspect that this does not substantially affect the extracted formula.

[^29]: For Linux, specifying arbitrary commit hashes is not enabled by default, because we must perform a complete Git history rewrite (resetting the commit hashes in the process) in order to ensure that checking out the repository also succeeds cross-platform on case-insensitive file systems (e.g., APFS).
To specify arbitrary and up-to-date commit hashes, use `LINUX_CLONE_MODE=original|filter` (see `scripts/subject/linux.sh#post-clone-hook-linux`: `original` only works on case-sensitive file systems, while `filter` is cross-platform, but takes several hours to run).
This does not affect typical use cases that involve tag and branch identifiers.

[^22]: Feature models for this system are currently likely to be incomplete due to an inaccurate extraction.

[^23]: This system does not regularly release tagged revisions, so only a single revision has been tested.

## Bundled Tools

### Extraction, Transformation, and Analysis

The following tools are bundled with torte and can be used in experiments for extracting, transforming, and analyzing feature models.
Most tools are not included in this repository, but cloned and built with tool-specific Docker files in the `docker` directory.
The bundled solvers are listed in a separate table [below](#solvers).

For transparency, we document the changes we make to these tools and known limitations. There are also some general known limitations of torte. [^1]

| Tool | Version | Date | Notes |
| - | - | - | - |
| [arminbiere/cadiback](https://github.com/arminbiere/cadiback) | 2e912fb | 2023-07-21 | |
| [ckaestne/kconfigreader](https://github.com/ckaestne/kconfigreader) | 913bf31 | 2016-07-01 | [^3] [^4] [^5] [^9] [^16] [^24] |
| [ekuiter/clausy](https://github.com/ekuiter/clausy) | 6b816a9 | 2024-01-15 | |
| [ekuiter/SATGraf](https://github.com/ekuiter/SATGraf) | 2677015 | 2023-04-05 | [^11] |
| [FeatureIDE/FeatJAR](https://github.com/FeatureIDE/FeatJAR) | e27aea7 | 2023-04-11 | [^12] [^15] |
| [FeatureIDE/FeatureIDE](https://github.com/FeatureIDE/FeatureIDE) | 3.9.1 | 2022-12-06 | [^13] [^14] [^15] |
| [paulgazz/kmax](https://github.com/paulgazz/kmax) | 4.5.2 | 2023-12-20 | [^4] [^5] [^7] [^8] [^24] |
| [Z3Prover/z3](https://github.com/Z3Prover/z3) | 4.11.2 | 2022-09-04 | [^10] |

[^1]: Currently, non-Boolean variability (e.g., constraints on numerical features) is only partially supported (e.g., encoded naively into Boolean constraints).
It is recommended to check manually whether non-Boolean variability is represented as desired in generated files.

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

[^24]: The formulas produced by kconfigreader and kmax do not explicitly mention unconstrained features (i.e., features that do not occur in any constraints). However, for many analyses that depend on knowing the entire feature set (e.g., simply listing all configurable features or calculating model counts), this is a threat to validity. We do not modify the extracted formulas, to preserve the original output of kconfigreader and kmax. To address this threat, we instead offer the transformation stage `transform-into-unconstrained-features`, which explicitly computes these features.

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
| dSharp | ? | ? | [^20] |
| Ganak | ? | ? | |
| sharpSAT | ? | ? | |

#### Collection: model-counting-competition-2022

These #SAT solvers (available [here](https://cloudstore.zih.tu-dresden.de/index.php/s/pXFAfnJffKyNA77)) were used in the [model-counting competition 2022](https://mccompetition.org/past_iterations).
Not all evaluated solvers are included here, as some solver binaries (i.e., for MTMC and ExactMC) have not been disclosed.

| Solver | Notes |
| - | - |
| c2d | |
| d4 | |
| DPMC | |
| gpmc | |
| TwG | [^17] |
| SharpSAT-TD | [^18] |
| SharpSAT-td+Arjun | [^18] [^19] |

#### Collection: other

These are miscellaneous solvers from various sources.

| Solver | Version | Date | Class | Notes |
| - | - | - | - | - |
| [ApproxMC](https://github.com/meelgroup/approxmc) | 4.1.9 | 2023-02-22 | Approximate #SAT Solver |
| backbone_kissat.py | - | - | Backbone Extractor |
| [d4v2](https://github.com/SoftVarE-Group/d4v2) | c1f6842 | 2023-02-15 | #SAT Solver, d-DNNF compiler, PMC |
| [kissat_MAB-HyWalk](https://satcompetition.github.io/2022/downloads/sequential-solvers.zip) | ? | ? | SAT Solver |
| SAT4J | 2.3.6 | 2020-12-14 | SAT Solver |

#### Collection: sat-competition

A subset of these SAT solvers was used in the evaluation of the paper [Tseitin or not Tseitin? The Impact of CNF Transformations on Feature-Model Analyses](https://raw.githubusercontent.com/SoftVarE-Group/Papers/main/2022/2022-ASE-Kuiter.pdf) (ASE 2022).
Each solver is the gold medal winner in the main track (SAT+UNSAT) of the SAT competition in the year encoded in its file name.
These binaries were obtained from the [SAT competition](http://www.satcompetition.org/), [SAT heritage](https://github.com/sat-heritage/docker-images), and [SAT museum](https://cca.informatik.uni-freiburg.de/satmuseum/) initiatives.

| Year | Solver |
| - | - |
| 2002 | zchaff |
| 2003 | Forklift |
| 2004 | zchaff |
| 2005 | SatELiteGTI |
| 2006 | MiniSat |
| 2007 | RSat |
| 2008 | MiniSat |
| 2009 | precosat |
| 2010 | CryptoMiniSat |
| 2011 | glucose |
| 2012 | glucose |
| 2013 | lingeling-aqw |
| 2014 | lingeling-ayv |
| 2015 | abcdSAT |
| 2016 | MapleCOMSPS_DRUP |
| 2017 | Maple_LCM_Dist |
| 2018 | MapleLCMDistChronoBT |
| 2019 | MapleLCMDiscChronoBT-DL-v3 |
| 2020 | Kissat-sc2020-sat |
| 2021 | Kissat_MAB |
| 2022 | Kissat_MAB-HyWalk |
| 2023 | sbva_cadical |

[^17]: For TwG, two configurations were provided by the model-counting competition (`TwG1` and `TwG2`).
As there was no indication as to which configuration was used in the competition, we arbitrarily chose `TwG1`.

[^18]: This solver currently crashes on some or all inputs.

[^19]: For SharpSAT-td+Arjun, two configurations were provided by the model-counting competition (`conf1` and `conf2`).
As only the second configuration actually runs SharpSAT-td, we chose `conf2` (`conf1` probably implements the approximate counter `SharpSAT-td-Arjun+ApproxMC`).

[^20]: This version of dSharp is [known](https://doi.org/10.4230/LIPIcs.SAT.2022.30) to produce inaccurate results for some inputs, so use it with caution.

## Predefined Experiments

This is a list of all predefined experiments in the `experiments` directory and their purposes.
Please create a pull request if you want to publish your own experiment.
Experiments starting with `draft-` are experimental.

| Experiment | Purpose |
| - | - |
| `busybox-history-full` | Extraction of all feature models of BusyBox (for every commit that touches the feature model) [^27] |
| `default` | "Hello-world" experiment that extracts and transforms a single feature model |
| `feature-model-collection` | Extraction, transformation, and analysis of several feature-model histories |
| `feature-model-collection-learning` | Learning from feature-model histories |
| `feature-model-differences` | Extraction and comparison of all feature models of several feature-model histories |
| `linux-history-releases` | Extraction, transformation, and analysis of a history of Linux feature models |
| `linux-history-weekly` | Extraction of a weekly history of Linux feature models |
| `linux-recent-release` | Extraction and transformation of a recent Linux feature model |
| `prepare-linux-fork` | Clones and rewrites the Linux Git repository to avoid issues with case-insensitive file systems |
| `tseitin-or-not-tseitin` | Evaluation for the paper [Tseitin or not Tseitin? The Impact of CNF Transformations on Feature-Model Analyses](https://raw.githubusercontent.com/SoftVarE-Group/Papers/main/2022/2022-ASE-Kuiter.pdf) (ASE 2022) |

[^27]: As noted by [Kröher et al. 2023](https://www.sciencedirect.com/science/article/abs/pii/S0164121223001322), the feature model of BusyBox is scattered across its `.c` source code files in special comments and therefore not trivial to extract. We solve this problem by iterating over all commits to generate all feature models, committing them to a new `busybox-models` repository, in which each commit represents one version of the feature model.

## Project History

This project has evolved through several stages and intends to replace them all:

[kmax-vm](https://github.com/ekuiter/kmax-vm) > [feature-model-repository-pipeline](https://github.com/ekuiter/feature-model-repository-pipeline) > [tseitin-or-not-tseitin](https://github.com/ekuiter/tseitin-or-not-tseitin) > [torte](https://github.com/ekuiter/torte)

- [kmax-vm](https://github.com/ekuiter/kmax-vm) was intended to provide an easy-to-use environment for integrating kmax with [PCLocator](https://github.com/ekuiter/PCLocator) in a virtual machine using Vagrant/VirtualBox.
  It is now obsolete due to our Docker integration of kmax.
- [feature-model-repository-pipeline](https://github.com/ekuiter/feature-model-repository-pipeline) extended [kmax-vm](https://github.com/ekuiter/kmax-vm) and could be used to extract feature models from Kconfig-based software systems with kconfigreader and kmax.
  The results were stored in the [feature-model-repository](https://github.com/ekuiter/feature-model-repository).
  Its functionality is completely subsumed by torte and more efficient and reliable due to our Docker integration.
- [tseitin-or-not-tseitin](https://github.com/ekuiter/tseitin-or-not-tseitin) extended the [feature-model-repository-pipeline](https://github.com/ekuiter/feature-model-repository-pipeline) to allow for transformation and analysis of feature models.
  It was mostly intended as a reproduction package for a single academic paper.
  Its functionality is almost completely subsumed by torte, which can be used to create reproduction packages for many different experiments.

If you are looking for a curated collection of feature models from various domains, have a look at our [feature-model-benchmark](https://github.com/SoftVarE-Group/feature-model-benchmark).

If you have any feedback, please contact me at [kuiter@ovgu.de](mailto:kuiter@ovgu.de).
New issues, pull requests, or any other kinds of feedback are always welcome.

## License

The source code of this project is released under the [LGPL v3 license](LICENSE.txt).
To ensure reproducibility, we also provide binaries (e.g., for solvers) in this repository.
These binaries have been collected or compiled from public sources.
Their usage is subject to each binaries' respective license - please contact me if you perceive any licensing issues.
