FROM ubuntu:24.04

# kmax and system (e.g., Linux) dependencies
ENV DEBIAN_FRONTEND=noninteractive
ARG Z3_VERSION=5.3.2.0
RUN apt-get update && apt-get install -y --no-install-recommends \
  ca-certificates \
  git \
  python3-venv \
  python3-dev \
  flex \
  bison \
  bc \
  gawk \
  libssl-dev \
  libelf-dev \
  wget \
  parallel \
  cmake \
  build-essential \
  && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/kmax
ENV PATH="/opt/kmax/bin:${PATH}"

# install (the tested version of) kmax
WORKDIR /home
RUN git clone https://github.com/paulgazz/kmax.git \
  && cd kmax \
  && git checkout 2880e6c99cecb828761e65e53cb9752cd74a8ada \
  && sed -i "s/z3-solver/z3-solver==${Z3_VERSION}/" setup.py \
  && python3 -m pip install --no-cache-dir . \
  && python3 -m pip check \
  && python3 -c "import z3; assert z3.get_version()[:3] == tuple(map(int, '${Z3_VERSION}'.split('.')[:3])); assert z3.Solver().check() == z3.sat"

# copy and set up
# - kextractor (which is compiled against the projects' Kconfig implementations)
# - IO scripts
COPY *.sh *.py kextractor.c ./
RUN git config --global --add safe.directory '*' \
    && git config --global user.email "anon@example.com" \
    && git config --global user.name "anon" \
    && git config --global init.defaultBranch main
RUN chmod +x *.sh
