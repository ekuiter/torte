FROM rust:1.90-trixie
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    bc \
    bison \
    build-essential \
    flex \
    git \
    libelf-dev \
    libssl-dev \
    parallel \
    perl \
    pkg-config \
    python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /home
RUN git clone https://github.com/julianbraha/kconfirm.git \
    && cd kconfirm \
    && git checkout 455504cca93ff591aab0fd2ddb541ed2b487e38d \
    && cargo build --locked --release -p kconfirm-smt

RUN git config --global --add safe.directory '*' \
    && git config --global user.email "anon@example.com" \
    && git config --global user.name "anon" \
    && git config --global init.defaultBranch main

WORKDIR /home
