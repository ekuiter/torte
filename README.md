# torte

**torte is a declarative experimentation workbench for fully automated and reproducible evaluations in feature-model analysis research.**

Why **torte**?
Take your pick:

- "**T**seitin **or** not **T**seitin?" **E**valuator
- CNF **T**ransf**or**ma**t**ion Workb**e**nch
- KConfig Extrac**tor** that **T**ames **E**volution

## Getting Started

- Install [GNU Make](https://www.gnu.org/software/make/) and [Docker](https://docs.docker.com/get-docker/) on a Linux system. On Windows, usage via WSL should be possible (but is untested).
  To avoid permission issues with created files, use [rootless mode](https://docs.docker.com/engine/security/rootless/).
- Define an experiment in `input/experiment.sh` or change an existing experiment's parameters.
- Run the experiment with `./torte.sh`. Stop a running experiment with `Ctrl+Z`, then `./torte.sh stop`.