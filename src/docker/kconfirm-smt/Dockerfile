FROM rust:1.85-bookworm

# kconfirm-smt builds its Z3 binding against the system library and evaluates
# Linux Kconfig preprocessor macros with the host compiler.
RUN apt-get update && apt-get install -y \
    bc \
    bison \
    build-essential \
    flex \
    git \
    libelf-dev \
    libssl-dev \
    libz3-dev \
    parallel \
    perl \
    pkg-config \
    python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /home
RUN git clone https://github.com/julianbraha/kconfirm.git \
    && cd kconfirm \
    && git checkout 176c5495234e48c3907d78f955f09d76e310dd90 \
    && cargo build --release -p kconfirm-smt

RUN git config --global --add safe.directory '*' \
    && git config --global user.email "anon@example.com" \
    && git config --global user.name "anon" \
    && git config --global init.defaultBranch main

WORKDIR /home
