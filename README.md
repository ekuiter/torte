# torte

**t**seitin **or** not **t**s**e**itin, **t**ransf**or**ma**t**ion workb**e**nch

- Install [Docker](https://docs.docker.com/get-docker/) on a Linux system.
  To avoid permission issues with created files, use [rootless mode](https://docs.docker.com/engine/security/rootless/).
- Define an experiment in `input/config.sh` or change an existing experiment's parameters.
- Run the experiment with `./torte.sh`. Stop it with `Ctrl+Z`, then `./torte.sh stop`.