FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    git \
    gawk \
    python3 \
    build-essential
WORKDIR /home
RUN git clone https://github.com/zephyrproject-rtos/Kconfiglib.git
WORKDIR /home/Kconfiglib
RUN git checkout b8535af53f0650a69e52db4bf8585c09d55852e7
COPY *.py ./
WORKDIR /home
