# torte

**torte is a declarative experimentation workbench for fully automated and reproducible evaluations in feature-model analysis research.**

Why **torte**?
Take your pick:

- "**T**seitin **or** not **T**seitin?" **E**valuator
- CNF **T**ransf**or**ma**t**ion Workb**e**nch
- KConfig Extrac**tor** that **T**ackles **E**volution

## Getting Started

There are two ways to set up torte:
If you just want to run an experiment (e.g., for reproduction), use the one-liner below.
If you want to make changes to torte or define your own experiments, read the "install manually" section below.

### One-Liner

To run torte, you need to install **curl**, **git**, **make**, and **docker** (in rootless mode).

Then, just download some experiment file (see `experiments` directory for others) and run it:

```
curl -sS https://raw.githubusercontent.com/ekuiter/torte/main/experiments/default.sh > experiment.sh && bash experiment.sh
```

By default, this will install torte into the `torte` directory; all experiment data will be stored in the directories `input` and `output` in your working directory.

### Install Manually

- Download or clone this repository onto a Linux system (on Windows, usage via WSL should be possible, but is untested).
- Install [GNU Make](https://www.gnu.org/software/make/) and [Docker](https://docs.docker.com/get-docker/).
  To avoid permission issues with created files, use [rootless mode](https://docs.docker.com/engine/security/rootless/).
- Change the experiment in `experiments/default.sh` or define a new experiment in the `experiments` directory.
- Run the experiment with `./torte.sh <experiment-file>`.
  Stop a running experiment with `Ctrl+Z`, then `./torte.sh stop`.
  Run `./torte.sh help` to get usage information.

## Bundled Tools

| Tool | Version | Date | Changes | Limitations |
| - | - | - | - | - |
| [ckaestne/kconfigreader](https://github.com/ckaestne/kconfigreader) | 913bf31 | 2016-07-01 |
| [ekuiter/SATGraf](https://github.com/ekuiter/SATGraf) | latest | |
| [FeatureIDE/FeatJAR](https://github.com/FeatureIDE/FeatJAR) | latest | |
| [FeatureIDE/FeatureIDE](https://github.com/FeatureIDE/FeatureIDE) | 3.9.1 | 2022-12-06 |
| [paulgazz/kmax](https://github.com/paulgazz/kmax) | 5a8780d | 2023-03-19 |
| [Z3Prover/z3](https://github.com/Z3Prover/z3) | 4.11.2 | 2022-09-04 |