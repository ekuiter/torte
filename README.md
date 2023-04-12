# torte

**torte is a declarative experimentation workbench for fully automated and reproducible evaluations in feature-model analysis research.**

Why **torte**?
Take your pick:

- "**T**seitin **or** not **T**seitin?" **E**valuator
- CNF **T**ransf**or**ma**t**ion Workb**e**nch
- KConfig Extrac**tor** that **T**ackles **E**volution

torte can currently be used to

- extract feature models from KConfig-based configurable software systems (e.g., the [Linux kernel](https://github.com/torvalds/linux)),
- transform feature models between various formats (e.g., [FeatureIDE](https://featureide.github.io), [UVL](https://github.com/Universal-Variability-Language), and [DIMACS](https://www.domagoj-babic.com/uploads/ResearchProjects/Spear/dimacs-cnf.pdf)), and
- evaluate the impacts of such extractions and transformations on feature-model analyses,

all in a declarative and reproducible fashion backed by reusable Docker containers.

## Getting Started

To run torte, you need

- a Linux system or Windows with [WSL](https://learn.microsoft.com/windows/wsl/install) (macOS is currently not supported)
- [curl](https://curl.se/), [Git](https://git-scm.com/), and [GNU Make](https://www.gnu.org/software/make/)
- [Docker](https://docs.docker.com/get-docker/) ([rootless mode](https://docs.docker.com/engine/security/rootless/) recommended to avoid permission issues with created files).

Experiment files in torte are self-executing - so, you can just download an experiment file (e.g., from the `experiments` directory) and run it.

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

**Advanced Usage**

- As an alternative to the self-extracting installer shown above, you can clone this repository and run experiments with `./torte.sh <experiment-file>`.
- A running experiment can be stopped with `Ctrl+C`.
  If this does not respond, try `Ctrl+Z`, then `./torte.sh stop`.
- Run `./torte.sh help` to get further usage information (e.g., running an experiment over SSH and im-/export of Docker containers).
- Developers are recommended to use [ShellCheck](https://www.shellcheck.net/) to improve code quality.

## Supported Subject Systems

This is a list of all subject systems for which feature-model extraction has been confirmed to work.
Other systems or revisions may also be supported.

| System | Revisions | Notes |
| - | - | - |
| [busybox](https://github.com/mirror/busybox) | 1.3.0 - 1.36.0 | |
| [linux](https://github.com/torvalds/linux) | 2.6.12 - 4.17 | only x86 architecture tested, => 4.18 currently not supported |

## Bundled Tools

The following tools are bundled with torte and can be used in experiments.
Most tools are not included in this repository, but cloned and built with tool-specific Docker files in the `scripts` directory.

For transparency, we document the changes we make to these tools and known limitations. There are also some general known limitations of torte [^1] [^2].

| Tool | Version | Date | Changes and Limitations |
| - | - | - | - |
| [ckaestne/kconfigreader](https://github.com/ckaestne/kconfigreader) | 913bf31 | 2016-07-01 | [^3] [^4] [^5] [^6] [^9] |
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
Specifically, we added support for `E_CHOICE` (treated as `E_LIST`), `P_IMPLY` (treated as `P_SELECT`), and `E_NONE`, `E_LTH`, `E_LEQ`, `E_GTH`, `E_GEQ` (ignored).

[^5]: Compiling the native C bindings of kconfigreader and kmax is not possible for all KConfig-based systems (e.g., if the Python-based [Kconfiglib](https://github.com/ulfalizer/Kconfiglib) parser is used).
In that case, you can try to reuse a C binding from an existing system with similar KConfig files; however, this may limit the extracted model's accuracy.

[^6]: Extraction of Linux >= v4.18 currently yields incorrect models for both kconfigreader and kmax.

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

## Predefined Experiments

This is a list of all predefined experiments in the `experiments` directory and their purposes.
Please create a pull request if you want to publish your own experiment.

| Experiment | Purpose |
| - | - |
| `default.sh` | "Hello-world" experiment that extracts and transforms a single feature model |
| `ase-2022-tseitin-or-not-tseitin.sh` | Evaluation for our ASE'22 paper "Tseitin or not Tseitin? The Impact of CNF Transformations on Feature-Model Analyses" |
| `splc-2023-benchmark.sh` | Evaluation for our SPLC'23 paper draft |

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