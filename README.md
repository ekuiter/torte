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

To run torte, you need a Linux system with [curl](https://curl.se/), [Git](https://git-scm.com/), [GNU Make](https://www.gnu.org/software/make/), and [Docker](https://docs.docker.com/get-docker/)(use [rootless mode](https://docs.docker.com/engine/security/rootless/) to avoid permission issues with created files).
Windows/WSL and macOS should also work, but are untested.

Experiment files in torte are self-executing - so, you can just download an experiment file (e.g., from the `experiments` directory) and run it:

```
curl -sS https://raw.githubusercontent.com/ekuiter/torte/main/experiments/default.sh > experiment.sh && bash experiment.sh
```

By default, this will install torte into the `torte` directory; all experiment data will be stored in the directories `input` and `output` in your working directory.

**Advanced Usage**

- As an alternative to the self-extracting installer shown above, you can clone this repository and run experiments with `./torte.sh <experiment-file>`.
- A running experiment can be stopped with `Ctrl+C`.
  If this does not respond, try `Ctrl+Z`, then `./torte.sh stop`.
- Run `./torte.sh help` to get further usage information.
- Developers are recommended to use [ShellCheck](https://www.shellcheck.net/) to improve code quality.

## Bundled Tools

The following tools are bundled with torte and can be used in experiments.
Most tools are not included in this repository, but cloned and built with tool-specific Docker files in the `scripts` directory.

For transparency, we document the changes we make to these tools and known limitations. There are also some general known limitations of torte [^1] [^2].

| Tool | Version | Date | Changes and Limitations |
| - | - | - | - |
| [ckaestne/kconfigreader](https://github.com/ckaestne/kconfigreader) | 913bf31 | 2016-07-01 | [^3] [^4] [^5] [^6] [^9] |
| [ekuiter/SATGraf](https://github.com/ekuiter/SATGraf) | 2677015 | 2023-04-05 | [^11] |
| [FeatureIDE/FeatJAR](https://github.com/FeatureIDE/FeatJAR) | latest | | [^12] [^14] [^15] |
| [FeatureIDE/FeatureIDE](https://github.com/FeatureIDE/FeatureIDE) | 3.9.1 | 2022-12-06 | [^13] [^15] |
| [paulgazz/kmax](https://github.com/paulgazz/kmax) | 5a8780d | 2023-03-19 | [^4] [^5] [^6] [^7] [^8] |
| [Z3Prover/z3](https://github.com/Z3Prover/z3) | 4.11.2 | 2022-09-04 | [^10] |

[^1]: Currently, non-Boolean variability (e.g., constraints on numerical features) is only partially supported (e.g., encoded naively into Boolean constraints).
It is recommended to check manually whether non-Boolean variability is correctly represented in generated files.

[^2]: Support for different Linux architectures is currently limited to a single Linux architecture (given in the `ARCH` environment variable) in a given experiment.

[^3]: We added the class `TransformIntoDIMACS.scala` to kconfigreader to decouple the extraction and transformation of feature models, so kconfigreader can also transform feature models extracted with other tools (e.g., kmax).

[^4]: We majorly revised the native C bindings `dumpconf.c` (kconfigreader) and `kextractor.c` (kmax), which are intended to be compiled against a system's Kconfig parser to get accurate feature models.
Our improved versions adapt to the KConfig constructs actually used in a system, which is important to extract evolution histories with evolving KConfig parsers.
Our changes are generalizations of the original versions of `dumpconf.c` and `kextractor.c` and should pose no threat to validity.

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

`todo`

## Supported Subject Systems

`todo`