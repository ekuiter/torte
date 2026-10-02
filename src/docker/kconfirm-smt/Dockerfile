FROM rust:1.85-bookworm

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
# "error[E0658]: `let` expressions in this position are unstable" in the rust:1.85-bookworm image
RUN git clone https://github.com/julianbraha/kconfirm.git \
    && cd kconfirm \
    && git checkout 176c5495234e48c3907d78f955f09d76e310dd90 \
    && perl -0pi -e 's/if let Ok\(arch\) = std::env::var\("ARCH"\)\n        && !arch\.is_empty\(\)\n    \{\n        return arch;\n    \}/if let Ok(arch) = std::env::var("ARCH") {\n        if !arch.is_empty() {\n            return arch;\n        }\n    }/' kconfirm-linux/src/lib.rs \
    && cargo build --release -p kconfirm-smt

RUN git config --global --add safe.directory '*' \
    && git config --global user.email "anon@example.com" \
    && git config --global user.name "anon" \
    && git config --global init.defaultBranch main

WORKDIR /home
