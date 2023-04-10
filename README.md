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

For transparency, we document the changes we make to these tools and known limitations.

| Tool | Version | Date | Changes | Limitations |
| - | - | - | - | - |
| [ckaestne/kconfigreader](https://github.com/ckaestne/kconfigreader) | 913bf31 | 2016-07-01 | [^1] [^2] | [^3] [^4] [^5] [^6] |
| [ekuiter/SATGraf](https://github.com/ekuiter/SATGraf) | latest | |
| [FeatureIDE/FeatJAR](https://github.com/FeatureIDE/FeatJAR) | latest | |
| [FeatureIDE/FeatureIDE](https://github.com/FeatureIDE/FeatureIDE) | 3.9.1 | 2022-12-06 |
| [paulgazz/kmax](https://github.com/paulgazz/kmax) | 5a8780d | 2023-03-19 |
| [Z3Prover/z3](https://github.com/Z3Prover/z3) | 4.11.2 | 2022-09-04 |

[^1]: We added the script `TransformIntoDIMACS.scala` to kconfigreader to decouple the extraction and transformation of feature models, so kconfigreader can also transform feature models extracted with other tools (e.g., kmax).

[^2]: We majorly revised kconfigreader's native C binding `dumpconf.c`, which is intended to be compiled against a project's Kconfig parser to get accurate feature models.
Our improved version adapts to the KConfig constructs actually used in a project, which is important to extract evolution histories with evolving KConfig parsers.

[^3]: Non-Boolean variability (e.g., constraints on numerical features) is only partially extracted and encoded in extracted feature models.

[^4]: Compiling the native C binding is not possible for all KConfig-based projects (e.g., if the Python-based [Kconfiglib](https://github.com/ulfalizer/Kconfiglib) parser is used).
In that case, you can try to reuse a C binding from an existing project with similar KConfig files; however, this may limit the extracted model's accuracy.

[^5]: Extraction of Linux >= v4.18 currently yields incorrect models.

[^6]: It is currently only possible to extract a feature model for a single Linux architecture (given in the `ARCH` environment variable) in a given experiment.

## Predefined Experiments

todo

Here is a simple footnote With some additional text after it.