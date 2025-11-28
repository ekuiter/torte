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
    bison
WORKDIR /home

# the most recent version of configfix requires picosat to be built separately as a shared library
# we use the same version (965) as older configfix versions: https://github.com/delta-one/linux/commit/b4c4746c261ad0cae58b00807fe828782397904b
COPY picosat-965.tar.gz .
RUN tar -xvf picosat-965.tar.gz && \
    cd picosat-965 && \
    ./configure.sh && \
    make libpicosat.so && \
    cp libpicosat.so libpicosat-trace.so
ENV LD_LIBRARY_PATH=/home/picosat-965

# install (the tested version of) configfix
RUN git clone https://github.com/ekuiter/torte-ConfigFix.git \
    && cd torte-ConfigFix \
    && git checkout 0312ab71e49a55163f82f70a84b7e46790e11794 \
    && make scripts/kconfig/cfoutconfig

# COPY *.py /tools/