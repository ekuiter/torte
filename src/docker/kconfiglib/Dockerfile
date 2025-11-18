FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    git \
    python3 \
    build-essential
WORKDIR /home
RUN git clone https://github.com/zephyrproject-rtos/Kconfiglib.git
WORKDIR /home/Kconfiglib
RUN git checkout 601f63d035ba355fefb69387de1a9bc5cc2201ab
COPY *.py ./
WORKDIR /home