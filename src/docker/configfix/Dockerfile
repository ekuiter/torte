FROM ubuntu:24.04

# dependencies for building systems and configfix
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --allow-unauthenticated \
    pkg-config \
    g++ \
    qtbase5-dev \
    wget \
    build-essential \
    libncurses-dev \
    libssl-dev \
    libelf-dev \
    bc \
    git \
    flex \
    bison \
    xz-utils
WORKDIR /home

# the most recent version of configfix requires picosat to be built separately as a shared library
# we use the same version (965) as older configfix versions: https://github.com/delta-one/linux/commit/b4c4746c261ad0cae58b00807fe828782397904b
COPY picosat-965.tar.gz .
RUN tar -xvf picosat-965.tar.gz && \
    cd picosat-965 && \
    ./configure.sh --trace --shared && \
    make libpicosat.so && \
    cp libpicosat.so libpicosat-trace.so
ENV LD_LIBRARY_PATH=/home/picosat-965

# ConfigFix v7.3 is a copy-patch payload that must be built against Linux 7.3
RUN wget -q https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.3.tar.xz \
    && echo "87363c24f10e06321eb362765521094e94471f6bff8bce2d6b3e40f39f004953  linux-7.3.tar.xz" | sha256sum -c - \
    && mkdir linux \
    && tar -xf linux-7.3.tar.xz --strip-components=1 -C linux \
    && rm linux-7.3.tar.xz
RUN git clone --branch v7.3 --depth 1 https://github.com/isselab/configfix.git \
    && cd configfix \
    && git checkout 35f5e8b2535c9b4cbc1908f2875dcaf8911baf1c \
    && ./copy_files.sh /home/linux \
    && cd /home/linux \
    # Export into the working directory, including for non-Linux systems.
    && sed -i 's|\./scripts/kconfig/cfout_constraints|cfout_constraints|g' scripts/kconfig/cfoutconfig.c \
    && make build_cfoutconfig

COPY *.sh .
RUN chmod +x *.sh
