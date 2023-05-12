FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    parallel \
    && python3 -mpip install z3-solver==4.11.2

WORKDIR /home
COPY *.py ./