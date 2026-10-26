FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

ARG Z3_VERSION=5.3.2
ARG Z3_BUILD_JOBS=2

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    python3 \
    parallel \
    cmake \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch "z3-${Z3_VERSION}" https://github.com/Z3Prover/z3.git /tmp/z3 \
    && cmake -S /tmp/z3 -B /tmp/z3/build \
        -DCMAKE_BUILD_TYPE=Release \
        -DZ3_BUILD_PYTHON_BINDINGS=ON \
        -DPython3_EXECUTABLE=/usr/bin/python3 \
        -DCMAKE_INSTALL_PYTHON_PKG_DIR=/usr/local/lib/python3.12/dist-packages \
    && cmake --build /tmp/z3/build --parallel "${Z3_BUILD_JOBS}" \
    && cmake --install /tmp/z3/build \
    && ldconfig \
    && python3 -c "import z3; assert z3.get_version_string() == '${Z3_VERSION}'; assert z3.Solver().check() == z3.sat" \
    && rm -rf /tmp/z3

WORKDIR /home
COPY *.py ./
